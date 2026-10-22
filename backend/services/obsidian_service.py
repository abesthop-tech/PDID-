import re
import random
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from backend.config import settings


class ObsidianService:
    """
    Obsidian Vault 双方向同期サービス
    - やるメモ.md の構造化パーサー＆行単位の安全なチェックボックス更新・短文メモ追記
    - 趣味ガチャ.md 完全互換＋SINGLE拡張ガチャ（GAME / STORY / SINGLE / ALL）
    - 「今の私」プロファイル＆コンテキスト抽出
    """

    CATEGORY_FILES = {
        "GAME": "01_Inbox/したいゲーム.md",
        "STORY": "01_Inbox/見たい物語.md",
        "SINGLE": "01_Inbox/単発 やりたいリスト.md",
    }
    CURRENT_FILE = "01_Inbox/いまやってる・見てるもの.md"
    LOG_FILE = "01_Inbox/趣味ガチャ_log.md"
    YARU_MEMO_FILE = "01_Inbox/やるメモ.md"
    OCTOBER_26_FILE = "01_Inbox/10月26日までに完成させる.md"

    def __init__(self, vault_path: Optional[Path] = None) -> None:
        self._vault_path_override = vault_path

    @property
    def vault_path(self) -> Path:
        return self._vault_path_override or settings.obsidian_vault_path

    def _resolve_file(self, rel_path: str) -> Path:
        return self.vault_path / rel_path

    def _backup_file(self, file_path: Path) -> None:
        """書き込み前に安全なバックアップを backend/data/vault_backups に保存する"""
        if not file_path.exists():
            return
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_name = f"{file_path.stem}_{timestamp}{file_path.suffix}"
            backup_target = settings.backup_dir / backup_name
            shutil.copy2(file_path, backup_target)
            # 古いバックアップが増えすぎないよう最新25件を残す
            backups = sorted(
                settings.backup_dir.glob(f"{file_path.stem}_*{file_path.suffix}"),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            )
            for old_b in backups[25:]:
                try:
                    old_b.unlink()
                except Exception:
                    pass
        except Exception:
            pass

    def _read_lines(self, rel_path: str) -> List[str]:
        path = self._resolve_file(rel_path)
        if not path.exists():
            return []
        content = path.read_text(encoding="utf-8")
        return content.splitlines()

    def _write_lines(self, rel_path: str, lines: List[str]) -> bool:
        path = self._resolve_file(rel_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self._backup_file(path)
        # Preserve LF newline and trailing newline safely
        text = "\n".join(lines) + "\n"
        path.write_text(text, encoding="utf-8")
        return True

    # ------------------------------------------------------------------
    # 1. やるメモ.md パーサー ＆ 双方向更新
    # ------------------------------------------------------------------
    def parse_yaru_memo(self) -> Dict[str, Any]:
        lines = self._read_lines(self.YARU_MEMO_FILE)
        sections: Dict[str, List[Dict[str, Any]]] = {
            "morning_routine": [],
            "today_and_home": [],
            "tomorrow_and_holiday": [],
            "maybe_want": [],
            "done_and_archive": [],
        }
        moc_links: List[str] = []
        vacation_plan: Dict[str, Any] = {
            "period": "10/29〜11/8 (11日間)",
            "prep_items": [],
            "casual_items": [],
            "fixed_events": [],
        }

        current_section = "morning_routine"
        in_dataview = False
        in_vacation_callout = False
        vacation_sub = ""

        for idx, raw_line in enumerate(lines):
            line_num = idx + 1
            stripped = raw_line.strip()

            # Dataview コードブロックのスキップ
            if stripped.startswith("```dataview"):
                in_dataview = True
                continue
            if in_dataview:
                if stripped.startswith("```"):
                    in_dataview = False
                continue

            # セクション判定
            if "***今とか今日とか" in stripped or "***帰ったら***" in stripped:
                current_section = "today_and_home"
                if "***帰ったら***" in stripped:
                    sections["today_and_home"].append({
                        "line_number": line_num,
                        "text": "【帰ったら】",
                        "raw": raw_line,
                        "is_checkbox": False,
                        "checked": False,
                        "is_header": True,
                        "sub_group": "after_return",
                    })
                continue
            elif "***明日やるための記録" in stripped or "***休み中にやりたいこと***" in stripped:
                current_section = "tomorrow_and_holiday"
                continue
            elif "***やりたいかもだけどやらなくてもいいやつ***" in stripped:
                current_section = "maybe_want"
                in_vacation_callout = False
                continue
            elif "***直近の考えに関する日常行為分析***" in stripped or "***残しとく***" in stripped:
                current_section = "notes_and_moc"
                in_vacation_callout = False
                continue
            elif stripped.startswith("## 消しといて"):
                current_section = "done_and_archive"
                in_vacation_callout = False
                continue

            # 休暇コールアウト内の解析 (`> [!NOTE]- 休暇`)
            if stripped.startswith("> [!NOTE]- 休暇"):
                in_vacation_callout = True
                continue
            if in_vacation_callout:
                if stripped.startswith(">"):
                    clean_q = re.sub(r"^>\s*", "", stripped).strip()
                    if clean_q.startswith("### 事前に準備必要なやつ"):
                        vacation_sub = "prep"
                    elif clean_q.startswith("### まあいい"):
                        vacation_sub = "casual"
                    elif clean_q.startswith("実施内容") or clean_q.startswith("重要事項"):
                        vacation_sub = "meta"
                    elif clean_q.startswith("- ") and vacation_sub in ("prep", "casual"):
                        item_title = clean_q[2:].strip()
                        entry = {
                            "line_number": line_num,
                            "text": item_title,
                            "category": "事前準備必要" if vacation_sub == "prep" else "自由・気軽",
                            "is_checkbox": False,
                            "checked": False,
                        }
                        if vacation_sub == "prep":
                            vacation_plan["prep_items"].append(entry)
                        else:
                            vacation_plan["casual_items"].append(entry)
                        sections["tomorrow_and_holiday"].append({
                            "line_number": line_num,
                            "text": f"[休暇:{entry['category']}] {item_title}",
                            "raw": raw_line,
                            "is_checkbox": False,
                            "checked": False,
                        })
                    continue
                else:
                    if stripped == "---":
                        in_vacation_callout = False

            # MOCリンク抽出
            if stripped.startswith("> - [[MOC "):
                m_moc = re.search(r"\[\[(MOC [^\]]+)\]\]", stripped)
                if m_moc:
                    moc_links.append(m_moc.group(1))
                continue

            # 空行・区切り線・空リンク `- [[]]` や他のコールアウトはスキップ
            if not stripped or stripped == "---" or stripped == "- [[]]":
                continue
            if stripped.startswith(">"):
                continue

            # チェックボックス判定
            m_cb = re.match(r"^(\s*)-\s*\[([ xX])\]\s*(.+)$", raw_line)
            if m_cb:
                checked = m_cb.group(2).lower() == "x"
                text_val = m_cb.group(3).strip()
                item_obj = {
                    "line_number": line_num,
                    "text": text_val,
                    "raw": raw_line,
                    "is_checkbox": True,
                    "checked": checked,
                }
                if current_section in sections:
                    sections[current_section].append(item_obj)
                else:
                    sections["done_and_archive"].append(item_obj)
                continue

            # 箇条書きまたはテキスト行の抽出
            if current_section in sections:
                clean_text = re.sub(r"^-\s*", "", stripped)
                sections[current_section].append({
                    "line_number": line_num,
                    "text": clean_text,
                    "raw": raw_line,
                    "is_checkbox": False,
                    "checked": False,
                })

        return {
            "vault_path": str(self.vault_path),
            "file": self.YARU_MEMO_FILE,
            "sections": sections,
            "vacation_plan": vacation_plan,
            "moc_links": moc_links,
            "updated_at": datetime.now().isoformat(),
        }

    def toggle_task(
        self,
        line_number: Optional[int] = None,
        text_match: Optional[str] = None,
        checked: Optional[bool] = None,
    ) -> Dict[str, Any]:
        """
        やるメモ.md 内の指定された行（またはテキスト一致行）の `- [ ]` ⇄ `- [x]` を安全に切り替える。
        コールアウトや他セクションを一切壊さず、対象行1行のみを書き換える。
        """
        lines = self._read_lines(self.YARU_MEMO_FILE)
        if not lines:
            return {"ok": False, "error": "やるメモ.md が見つからないか空です"}

        target_idx: Optional[int] = None

        # 1. 行番号が指定されており、かつチェックボックスまたはテキストが一致する場合
        if line_number is not None and 1 <= line_number <= len(lines):
            candidate = lines[line_number - 1]
            if re.match(r"^\s*-\s*\[[ xX]\]", candidate):
                if not text_match or text_match in candidate:
                    target_idx = line_number - 1

        # 2. text_match で検索
        if target_idx is None and text_match:
            for i, line in enumerate(lines):
                if re.match(r"^\s*-\s*\[[ xX]\]", line) and text_match in line:
                    target_idx = i
                    break

        if target_idx is None:
            return {"ok": False, "error": "対象のチェックボックス行が見つかりませんでした"}

        orig_line = lines[target_idx]
        m = re.match(r"^(\s*-\s*\[)([ xX])(\]\s*.+)$", orig_line)
        if not m:
            return {"ok": False, "error": "対象行がチェックボックス形式ではありません"}

        current_state = m.group(2).lower() == "x"
        new_state = (not current_state) if checked is None else checked
        mark = "x" if new_state else " "
        new_line = f"{m.group(1)}{mark}{m.group(3)}"
        lines[target_idx] = new_line

        self._write_lines(self.YARU_MEMO_FILE, lines)
        return {
            "ok": True,
            "line_number": target_idx + 1,
            "checked": new_state,
            "old_line": orig_line,
            "new_line": new_line,
        }

    def append_quick_memo(
        self,
        text: str,
        target_section: str = "auto",
        as_checkbox: bool = True,
    ) -> Dict[str, Any]:
        """
        クイック短文メモを `やるメモ.md` の適切なセクションへ安全に追記する。
        target_section:
          - "auto": 内容から自動判定（ルーチン/帰ったら/明日・休日/やりたいかも/今日）
          - "morning_routine"
          - "today" ("***今とか今日とか...")
          - "after_return" ("***帰ったら***→")
          - "tomorrow" ("***明日やるための記録...")
          - "maybe_want" ("***やりたいかもだけどやらなくてもいいやつ***")
        """
        clean = text.strip()
        if not clean:
            return {"ok": False, "error": "メモ内容が空です"}

        if target_section == "auto":
            if any(k in clean for k in ["帰ったら", "帰宅後", "夜に", "家で"]):
                target_section = "after_return"
            elif any(k in clean for k in ["明日", "週末", "休日", "休み", "来週"]):
                target_section = "tomorrow"
            elif any(k in clean for k in ["かも", "いつか", "気になる", "アイデア"]):
                target_section = "maybe_want"
            elif any(k in clean for k in ["毎朝", "ルーチン"]):
                target_section = "morning_routine"
            else:
                target_section = "today"

        # フォーマット整形
        if clean.startswith("- [ ]") or clean.startswith("- [x]") or clean.startswith("- "):
            formatted_line = clean
        elif as_checkbox:
            formatted_line = f"- [ ] {clean}"
        else:
            formatted_line = f"- {clean}"

        lines = self._read_lines(self.YARU_MEMO_FILE)
        if not lines:
            lines = [formatted_line]
            self._write_lines(self.YARU_MEMO_FILE, lines)
            return {
                "ok": True,
                "section": target_section,
                "inserted_line": formatted_line,
                "line_number": 1,
            }

        insert_idx = len(lines)
        markers = {
            "morning_routine": r"^- \[[ xX]\] ハンカチを持つ",
            "today": r"\*\*\*今とか今日とか",
            "after_return": r"\*\*\*帰ったら\*\*\*",
            "tomorrow": r"\*\*\*明日やるための記録",
            "maybe_want": r"\*\*\*やりたいかもだけどやらなくてもいいやつ\*\*\*",
        }
        pattern = markers.get(target_section, markers["today"])

        for i, line in enumerate(lines):
            if re.search(pattern, line):
                insert_idx = i + 1
                break

        lines.insert(insert_idx, formatted_line)
        self._write_lines(self.YARU_MEMO_FILE, lines)

        return {
            "ok": True,
            "section": target_section,
            "inserted_line": formatted_line,
            "line_number": insert_idx + 1,
        }

    # ------------------------------------------------------------------
    # 2. 趣味ガチャ (`趣味ガチャ.md` 完全互換 ＋ `SINGLE` 拡張)
    # ------------------------------------------------------------------
    def _read_gacha_category_items(self, category: str) -> List[Dict[str, str]]:
        rel_path = self.CATEGORY_FILES.get(category)
        if not rel_path:
            return []
        lines = self._read_lines(rel_path)
        items: List[Dict[str, str]] = []
        in_frontmatter = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            if i == 0 and stripped == "---":
                in_frontmatter = True
                continue
            if in_frontmatter:
                if stripped == "---":
                    in_frontmatter = False
                continue
            if not stripped:
                continue

            if category in ("GAME", "STORY"):
                m = re.match(r"^-\s*\[\[(.+?)\]\]\s*$", stripped)
                if m:
                    items.append({
                        "raw": line,
                        "title": m.group(1).strip(),
                        "source": category,
                    })
            elif category == "SINGLE":
                # 単発やりたいリストは `- 項目` またはプレーン行
                if stripped == "-":
                    continue
                if stripped.startswith("- "):
                    title_val = stripped[2:].strip()
                else:
                    title_val = stripped.rstrip("、,")
                if title_val:
                    items.append({
                        "raw": line,
                        "title": title_val,
                        "source": "SINGLE",
                    })
        return items

    def get_gacha_pool(self, category: str = "ALL") -> Dict[str, Any]:
        cat = category.upper()
        if cat in ("GAME", "STORY", "SINGLE"):
            pool = self._read_gacha_category_items(cat)
        elif cat == "ALL_WITH_SINGLE":
            pool = (
                self._read_gacha_category_items("GAME")
                + self._read_gacha_category_items("STORY")
                + self._read_gacha_category_items("SINGLE")
            )
        else:
            # 趣味ガチャ.md 互換の ALL (GAME + STORY) + SINGLE も選択可能
            pool = (
                self._read_gacha_category_items("GAME")
                + self._read_gacha_category_items("STORY")
                + self._read_gacha_category_items("SINGLE")
            )

        counts = {
            "GAME": len(self._read_gacha_category_items("GAME")),
            "STORY": len(self._read_gacha_category_items("STORY")),
            "SINGLE": len(self._read_gacha_category_items("SINGLE")),
        }
        counts["ALL"] = counts["GAME"] + counts["STORY"] + counts["SINGLE"]

        # いまやってる・見てるもの＆ログも返す
        current_doing = self.get_current_doing()
        recent_logs = self.get_gacha_logs(limit=10)

        return {
            "category": cat,
            "counts": counts,
            "pool_size": len(pool),
            "items": pool,
            "current_doing": current_doing,
            "recent_logs": recent_logs,
        }

    def draw_gacha(self, category: str = "ALL") -> Dict[str, Any]:
        data = self.get_gacha_pool(category)
        pool = data["items"]
        if not pool:
            return {
                "ok": True,
                "empty": True,
                "category": category.upper(),
                "item": None,
                "counts": data["counts"],
            }
        picked = random.choice(pool)
        return {
            "ok": True,
            "empty": False,
            "category": category.upper(),
            "item": picked,
            "trial_rule": "1話 / 1章 / 30分だけ試しましょう！",
            "counts": data["counts"],
        }

    def apply_gacha_action(
        self,
        action: str,
        title: str,
        source: str,
        raw_line: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        趣味ガチャのアクションを実行:
        - "good" ("よかった"): 元ファイルから削除し、`いまやってる・見てるもの.md` の `## やってるもの` に `- [[title]]` を追記
        - "drop" ("もう興味ない"): 元ファイルから削除し、`趣味ガチャ_log.md` に `- YYYY-MM-DD [SOURCE] [削除] title` を追記
        - "try" ("試す"): 30分タイマー開始状態を返す（ファイル変更なし）
        - "meh" ("あんまりだった"): そのまま戻す（ファイル変更なし）
        """
        act = action.lower()
        src = source.upper()
        today_str = datetime.now().strftime("%Y-%m-%d")

        if act in ("try", "meh", "skip"):
            return {
                "ok": True,
                "action": act,
                "title": title,
                "source": src,
                "timer_minutes": 30 if act == "try" else 0,
                "message": "30分タイマーを開始しました！" if act == "try" else "スキップしました",
            }

        rel_src = self.CATEGORY_FILES.get(src)
        if not rel_src:
            return {"ok": False, "error": f"不明なカテゴリです: {src}"}

        # 元ファイルから該当1行のみを削除
        src_lines = self._read_lines(rel_src)
        removed = False
        new_src_lines: List[str] = []
        for line in src_lines:
            if not removed:
                if raw_line and line.strip() == raw_line.strip():
                    removed = True
                    continue
                if f"[[{title}]]" in line or line.strip() == f"- {title}":
                    removed = True
                    continue
            new_src_lines.append(line)

        if removed:
            self._write_lines(rel_src, new_src_lines)

        if act == "good":
            # いまやってる・見てるもの.md に追記
            curr_lines = self._read_lines(self.CURRENT_FILE)
            entry_line = f"- [[{title}]]"
            if not curr_lines:
                curr_lines = [
                    "---",
                    f"created: {today_str} 00:00",
                    "---",
                    "## やってるもの",
                    entry_line,
                    "",
                    "---",
                    "## 完了",
                ]
            else:
                # `## やってるもの` の直後、または `---`（完了セクション前）に挿入
                inserted = False
                for i, l in enumerate(curr_lines):
                    if l.strip().startswith("## やってるもの"):
                        curr_lines.insert(i + 1, entry_line)
                        inserted = True
                        break
                if not inserted:
                    curr_lines.append(entry_line)
            self._write_lines(self.CURRENT_FILE, curr_lines)
            return {
                "ok": True,
                "action": "good",
                "removed_from_pool": removed,
                "added_to": self.CURRENT_FILE,
                "entry": entry_line,
            }

        if act == "drop":
            # 趣味ガチャ_log.md の末尾に追記
            log_lines = self._read_lines(self.LOG_FILE)
            log_entry = f"- {today_str} [{src}] [削除] {title}"
            # 末尾の空行を整理して追記
            while log_lines and not log_lines[-1].strip():
                log_lines.pop()
            log_lines.append(log_entry)
            self._write_lines(self.LOG_FILE, log_lines)
            return {
                "ok": True,
                "action": "drop",
                "removed_from_pool": removed,
                "added_to": self.LOG_FILE,
                "entry": log_entry,
            }

        return {"ok": False, "error": f"未対応のアクションです: {action}"}

    def get_current_doing(self) -> Dict[str, List[str]]:
        lines = self._read_lines(self.CURRENT_FILE)
        doing: List[str] = []
        done: List[str] = []
        mode = "doing"
        for line in lines:
            s = line.strip()
            if s.startswith("## やってるもの"):
                mode = "doing"
                continue
            elif s.startswith("## 完了"):
                mode = "done"
                continue
            m = re.match(r"^-\s*\[\[(.+?)\]\]", s)
            if m:
                if mode == "doing":
                    doing.append(m.group(1))
                else:
                    done.append(m.group(1))
            elif s.startswith("- ") and mode in ("doing", "done"):
                val = s[2:].strip()
                if val:
                    (doing if mode == "doing" else done).append(val)
        return {"doing": doing, "done": done}

    def get_gacha_logs(self, limit: int = 15) -> List[str]:
        lines = self._read_lines(self.LOG_FILE)
        logs = [l.strip() for l in lines if l.strip().startswith("- ")]
        return list(reversed(logs))[:limit]

    # ------------------------------------------------------------------
    # 3. 「今の私」プロファイル＆コンテキスト抽出
    # ------------------------------------------------------------------
    def get_profile_summary(self) -> Dict[str, Any]:
        """
        やるメモ.md、10月26日までに完成させる.md、MOC群から
        「現在の自分サマリー（目標・予算・進行中プロジェクト・関心タグ）」を抽出する。
        """
        oct26_lines = self._read_lines(self.OCTOBER_26_FILE)
        oct26_themes: List[str] = []
        capture_themes = False
        for line in oct26_lines:
            s = line.strip()
            if "書きたいものの見出し" in s:
                capture_themes = True
                continue
            if capture_themes and s.startswith("- "):
                val = s[2:].strip()
                if val and val != "[[]]":
                    oct26_themes.append(val)

        yaru_data = self.parse_yaru_memo()
        gacha_counts = self.get_gacha_pool("ALL")["counts"]
        doing_data = self.get_current_doing()

        return {
            "basic_info": {
                "age_milestone": "10月27日で20歳（誕生日）",
                "base_location": "三軒茶屋（実家在住・田園都市線起点）",
                "vacation_period": "2026年10月29日〜11月8日（11連休）",
            },
            "budget_and_finance": {
                "current_assets": "約6〜7万円",
                "expected_income": "来月バイト代 約4〜5万円（不足時は単発日雇い可）",
                "must_buy_goal": "Meta Quest 3（来月中に購入目標・分割も視野）",
                "living_cost_note": "食費は親負担でOK、交通費も旅行レベルでなければOK",
                "spending_policy": "普段の遊びは0円〜1,000円（ひとりカラオケ・平日科学館・散歩・自炊）で賢く楽しみ、Quest 3資金と札幌LCC旅費を確保する",
            },
            "active_projects": [
                {
                    "title": "『10月26日までに完成させる』執筆・統合プロジェクト",
                    "deadline": "2026-10-26",
                    "description": "これまで書いてきた様々な文章を統合し、「今の私」を最大限書き留める作品。",
                    "themes": oct26_themes or [
                        "中の上", "ゲーム", "苦しみは苦しみのなかでしか記述できない",
                        "超かぐや姫!", "評価", "母・父・姉への手紙", "人と私", "過去", "それでも、考えずにはいられない"
                    ],
                },
                {
                    "title": "Antigravity 2.0 & Codex CLI パーソナルシステム開発",
                    "deadline": "進行中",
                    "description": "スキル・サブエージェント・GitHubを活用し、学校PCと自宅PCをシームレスに繋ぐDaily Conciergeの構築。",
                    "themes": ["FastAPI", "Obsidian双方向同期", "SNS未読差分クローラー", "Flutter"],
                },
                {
                    "title": "10/29〜11/8 休暇11日間プランニング＆新しい起点づくり",
                    "deadline": "2026-10-29開始",
                    "description": "父とドライブ練習（2回）、ぬい裁縫、20歳のお酒（三茶）、ピアノ、作曲、ファインチューニング、鶏肉のソテー＆エッグベネディクト。",
                    "themes": ["ドライブ", "ぬい裁縫", "お酒解禁", "ピアノ・作曲", "LLMファインチューニング"],
                },
            ],
            "interest_tags": [
                "ローカルAI / ComfyUI / LLMファインチューニング",
                "Antigravity 2.0 / Codex CLI / Python",
                "超かぐや姫! / 物語考察・哲学",
                "Meta Quest 3 / Steamインディー＆名作ゲーム",
                "ピアノ / 短いフレーズ作曲 / 絵・ぬい裁縫",
                "三軒茶屋グルメ・お酒 / 料理（エッグベネディクト・鶏ソテー）",
                "LUUP散歩 / 平日科学館・夜の水族館・近場温泉",
            ],
            "vault_stats": {
                "gacha_counts": gacha_counts,
                "currently_doing": doing_data["doing"],
                "recently_completed": doing_data["done"],
                "moc_links": yaru_data["moc_links"],
            },
        }

    def clip_to_obsidian(
        self,
        title: str,
        url: str,
        summary: str = "",
        source_name: str = "",
    ) -> Dict[str, Any]:
        """
        SNS差分フィードやAIニュースのお気に入り記事を `やるメモ.md` の
        `***やりたいかもだけどやらなくてもいいやつ***` セクションへクリップ追記する。
        """
        clip_line = f"- [{title}]({url})"
        if source_name:
            clip_line += f" ({source_name})"
        if summary:
            short_sum = summary.replace("\n", " ").strip()[:80]
            clip_line += f" — {short_sum}"

        return self.append_quick_memo(
            text=clip_line,
            target_section="maybe_want",
            as_checkbox=False,
        )


obsidian_service = ObsidianService()
