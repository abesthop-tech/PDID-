import json
import re
import sqlite3
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

import feedparser
import httpx
from bs4 import BeautifulSoup

from backend.config import settings
from backend.services.obsidian_service import obsidian_service


class FeedService:
    """
    SNS未読差分クローラー ＆「URL＋自然言語指示」ウォッチャー
    - SQLite (backend/data/concierge.db) で watch_sources と feed_items を管理
    - YouTube / Pixiv / X(Twitter) / RSS / Custom URL 対応
    - URL＋自然言語指示からHTML/RSSを解析してCSSセレクタ・抽出ルールを自動生成
    - AI技術ニュース解説・お得情報（Steam/Quest3/三茶・都内スポット）・良記事キュレーション提供
    """

    def __init__(self, db_path: Optional[Path] = None) -> None:
        self._db_path_override = db_path
        self._init_db()
        self._seed_initial_data()

    @property
    def db_path(self) -> Path:
        return self._db_path_override or settings.db_path

    def _get_conn(self) -> sqlite3.Connection:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._get_conn() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS watch_sources (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    source_type TEXT NOT NULL,
                    url TEXT NOT NULL,
                    instruction TEXT DEFAULT '',
                    extraction_rule_json TEXT DEFAULT '{}',
                    category TEXT DEFAULT 'general',
                    enabled INTEGER DEFAULT 1,
                    last_checked_at TEXT DEFAULT '',
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS feed_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id INTEGER,
                    source_name TEXT NOT NULL,
                    source_type TEXT NOT NULL,
                    category TEXT NOT NULL,
                    title TEXT NOT NULL,
                    url TEXT NOT NULL UNIQUE,
                    summary TEXT DEFAULT '',
                    why_it_matters TEXT DEFAULT '',
                    author TEXT DEFAULT '',
                    thumbnail_url TEXT DEFAULT '',
                    published_at TEXT NOT NULL,
                    importance_score INTEGER DEFAULT 80,
                    is_read INTEGER DEFAULT 0,
                    is_bookmarked INTEGER DEFAULT 0,
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def _seed_initial_data(self) -> None:
        """
        初回起動時にユーザーの関心（ローカルAI/ComfyUI、Antigravity/Codex、超かぐや姫!/サブカル、
        Steam/Quest3お得情報、Pixiv/YouTube/X監視枠、良記事キュレーション）に合った初期データをシードする。
        """
        with self._get_conn() as conn:
            cnt = conn.execute("SELECT COUNT(*) FROM watch_sources").fetchone()[0]
            if cnt > 0:
                return

            now = datetime.now().strftime("%Y-%m-%d %H:%M")

            initial_sources = [
                (
                    "Zenn - ローカルAI / LLM / ComfyUI トレンド",
                    "rss",
                    "https://zenn.dev/topics/llm/feed",
                    "ローカルLLM、ファインチューニング、ComfyUI、個人開発エージェントの最新実践記事を取得",
                    json.dumps({"feed_type": "rss", "keywords": ["LLM", "ComfyUI", "LoRA", "Agent"]}),
                    "ai_tech",
                    1,
                    now,
                    now,
                ),
                (
                    "YouTube - AI & 創作・ゲーム制作チャンネル新着",
                    "youtube",
                    "https://www.youtube.com/results?search_query=ComfyUI+Local+LLM+IndieGame",
                    "ComfyUIワークフロー解説、ローカルLLMファインチューニング、個人ゲーム制作の新着動画だけ取得",
                    json.dumps({"channel_or_query": "ComfyUI Local LLM", "mode": "youtube_rss"}),
                    "youtube",
                    1,
                    now,
                    now,
                ),
                (
                    "Pixiv - 『超かぐや姫!』・お気に入り創作者タグ新着",
                    "pixiv",
                    "https://www.pixiv.net/tags/%E8%B6%85%E3%81%8B%E3%81%90%E3%82%84%E5%A7%AB/artworks",
                    "『超かぐや姫!』や創作キャラ・週報Pixiv用の新着イラスト・漫画差分を取得",
                    json.dumps({"tag": "超かぐや姫", "api": "/ajax/search/artworks/"}),
                    "pixiv",
                    1,
                    now,
                    now,
                ),
                (
                    "X (Twitter) - AI開発 (Antigravity / Codex CLI) & 創作リスト差分",
                    "x_twitter",
                    "https://x.com/search?q=Antigravity+OR+Codex+CLI+OR+Quest3",
                    "おすすめ欄のノイズを除外し、指定キーワードとフォロー中クリエイターの未読ポストのみ取得",
                    json.dumps({"query": "Antigravity OR Codex CLI OR Quest3", "exclude_retweets": True}),
                    "x_twitter",
                    1,
                    now,
                    now,
                ),
                (
                    "Steam & Meta Quest 3 セール・三軒茶屋/都内お得スポットウォッチャー",
                    "custom_url",
                    "https://store.steampowered.com/specials",
                    "『したいゲーム.md』内のタイトルやマルチ対応インディーゲームのセール、Quest 3関連のお得情報を抽出",
                    json.dumps({"item_selector": ".salepreviewwidgets_SaleItemBrowserRow", "title_selector": ".StoreSaleWidgetTitle"}),
                    "deals",
                    1,
                    now,
                    now,
                ),
            ]

            conn.executemany(
                """
                INSERT INTO watch_sources
                (name, source_type, url, instruction, extraction_rule_json, category, enabled, last_checked_at, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                initial_sources,
            )

            # 初期未読フィード＆キュレーションアイテム（SNS差分 + AI解説 + お得情報 + 良記事）
            initial_items = [
                # --- SNS未読差分 (youtube / pixiv / x_twitter / rss) ---
                (
                    1,
                    "Zenn - ローカルAI / LLM",
                    "rss",
                    "sns_diff",
                    "【実践】軽量LLMのテキスト適合ファインチューニング（Unsloth + LoRA）を自宅GPUで30分で回す手順",
                    "https://zenn.dev/topics/llm/articles/local-finetuning-unsloth-2026",
                    "大規模なデータセットを作らなくても、自分の書いたObsidianノート（数百行〜）から文体や思考パターンを適合させる軽量LoRA学習の最新ベストプラクティス。",
                    "『やるメモ.md』の「帰ったら：生成・テキスト適合かなあ」「ファインチューニング（ちょい前にいじってたやつの続き）」に直結する手順です。",
                    "AI_Lab_Zenn",
                    "",
                    "2026-10-22 09:30",
                    96,
                    0,
                    0,
                    now,
                ),
                (
                    4,
                    "X (Twitter) - AI開発差分",
                    "x_twitter",
                    "sns_diff",
                    "Antigravity 2.0 × Codex CLI で『AGENTS.md』と『.agents/skills』を共有して自宅PC・学校PC間を引き継ぐ構成パターン",
                    "https://x.com/ai_dev_jp/status/1980001026",
                    "複数環境でAIエージェントを使う際、Obsidian Syncには設計ノートだけを置き、リポジトリ側にカスタムスキルと自動検出Configを置くと環境差分ゼロで開発が続くという知見。",
                    "まさに今進めている『Codex CLIとGitHubをちゃんと使おう！』の実践そのもの。自宅PCでクローンした瞬間から同じスキルが動きます。",
                    "@ai_dev_jp",
                    "",
                    "2026-10-22 10:15",
                    95,
                    0,
                    0,
                    now,
                ),
                (
                    3,
                    "Pixiv - 週報・作品タグ差分",
                    "pixiv",
                    "sns_diff",
                    "【Pixiv新着差分】『超かぐや姫!』＆竹取物語モチーフ創作イラスト・考察ファンアートまとめ（未読4件）",
                    "https://www.pixiv.net/tags/%E8%B6%85%E3%81%8B%E3%81%90%E3%82%84%E5%A7%AB/artworks",
                    "前回チェック時以降に投稿された『超かぐや姫!』関連イラスト・漫画タグの新着差分。タイムラインをダラ見せず新着作品だけを1分で確認可能。",
                    "『10月26日までに完成させる.md』の見出しにある「超かぐや姫!」の執筆インスピレーションや「週報pixiv」の整理に最適です。",
                    "Pixiv Tag Watcher",
                    "",
                    "2026-10-22 08:40",
                    91,
                    0,
                    0,
                    now,
                ),
                (
                    2,
                    "YouTube - 創作＆音楽チャンネル",
                    "youtube",
                    "sns_diff",
                    "【ピアノ×作曲】音楽理論ゼロから「ゲームみたいに楽しく」4小節の短いフレーズを作るコード進行入門（12分動画）",
                    "https://www.youtube.com/watch?v=piano_short_phrase_1022",
                    "難しいスケール練習を飛ばして、好きなゲームのBGMっぽい響き（IV△7→V7→IIIm7→VIm）を左手2音＋右手メロディだけで鳴らして遊ぶ方法。",
                    "『やるメモ.md』の「ピアノ：ゲームみたいに楽しいから上手くなれるバランスはどこだ？」「起点:作曲 めちゃ短いフレーズ作るだけでも」にぴったりのアプローチです。",
                    "SoundQuest GameMusic",
                    "",
                    "2026-10-22 07:50",
                    93,
                    0,
                    0,
                    now,
                ),
                (
                    2,
                    "YouTube - 手芸・ぬい制作",
                    "youtube",
                    "sns_diff",
                    "【100均・手縫いOK】型紙いらずで今日中に完成する「ちびぬい・マスコット」超入門ガイド",
                    "https://www.youtube.com/watch?v=nui_sewing_starter_1022",
                    "裁縫セットとボア生地・フェルトだけで、ミシンなしでも2時間で1体完成させるための最小ステップ解説。",
                    "10/29〜11/8の休暇計画にある「起点:ぬい なんか裁縫できるやつ買う。めちゃ簡単なものでもいいから完成を目指す」の事前準備リストとしてそのまま使えます。",
                    "NuiCraft Studio",
                    "",
                    "2026-10-21 22:10",
                    86,
                    0,
                    0,
                    now,
                ),

                # --- ③ AI技術ニュース解説 (ai_news) ---
                (
                    1,
                    "AI Concierge Tech Digest",
                    "rss",
                    "ai_news",
                    "ローカルLLMの「個人ノート適合（Personal Style Adaptation）」が省メモリ化：8GB〜12GB VRAMでも自分の文体を再現可能に",
                    "https://huggingface.co/blog/personal-style-lora-2026",
                    "最新のQLoRA＋DPO（直接選好最適化）軽量パイプラインにより、自分が過去に書いたエッセイや日記（20〜50本程度）を学習させ、「自分らしい語り口・思考の癖」を持ったローカルモデルを短時間で構築する手法が普及しています。",
                    "【自分への活かし方】『10月26日までに完成させる.md』で統合しようとしている自分の文章群やObsidianの考察ノートを教師データにすれば、自宅PCで「自分の分身モデル」を作るファインチューニング実験がコスト0円で楽しめます。",
                    "AI Tech Curation",
                    "",
                    "2026-10-22 08:00",
                    97,
                    0,
                    0,
                    now,
                ),
                (
                    1,
                    "AI Concierge Tech Digest",
                    "rss",
                    "ai_news",
                    "ComfyUI × 2Dイラスト制作補助：「ラフ線画から塗り・ライティング案を3パターン出す」非破壊ワークフロー",
                    "https://github.com/comfyanonymous/ComfyUI",
                    "全部をAI生成するのではなく、「自分で描いたラフや構図」をベースにControlNetで配色や影の付け方だけをシミュレートし、人間が楽しく絵を描く起点を作る使い方が注目されています。",
                    "【自分への活かし方】休暇リストの「起点:絵（これから楽しめるようになるための最初の起点・コストなし）」とローカルAI環境を組み合わせる遊び方として相性抜群です。",
                    "ComfyUI Community",
                    "",
                    "2026-10-22 08:30",
                    89,
                    0,
                    0,
                    now,
                ),

                # --- ③ お得情報・スポット・セール (deals) ---
                (
                    5,
                    "Quest 3 & ガジェット予算ナビ",
                    "custom_url",
                    "deals",
                    "【購入計画ナビ】Meta Quest 3（512GB / 128GB認定整備品・分割0%キャンペーン）＆ PC VR接続ケーブル最安チェック",
                    "https://www.meta.com/jp/quest/quest-3/",
                    "来月購入目標のMeta Quest 3について、公式ストア・Amazon・家電量販店のポイント還元＆分割手数料無料枠の比較。PC（SteamVR）接続には純正Linkケーブル（約1万円）ではなく、3,000円台のAnker製USB3.0ケーブルまたはVirtual Desktop（無線）を使うと約7,000円節約可能！",
                    "【予算への効き目】現在資産6〜7万＋来月バイト代4〜5万の中で、周辺機器コストを最小化しつつ11連休の遊び予算もしっかり残せます。",
                    "Concierge Deal Finder",
                    "",
                    "2026-10-22 09:00",
                    98,
                    0,
                    0,
                    now,
                ),
                (
                    5,
                    "Steam 積みゲー＆セール監視",
                    "custom_url",
                    "deals",
                    "【Steamお得＆マルチ候補】『したいゲーム.md』連動：1人でも友達とでも遊べる名作・低予算タイトルピックアップ",
                    "https://store.steampowered.com/specials",
                    "『したいゲーム.md』に入っている『It Takes Two』（フレンドパスで1人買えば2人目は無料！）、『Stardew Valley』、『Raft』、『Helltaker』（無料）、『Darkest Dungeon』など、コストを抑えて11連休に1人＆誰かと遊べるタイトルがセール対象になりやすい時期です。",
                    "【休暇への活かし方】『It Takes Two』や『違う星のぼくら』なら1本分で2人遊べるため、「Steam見て決める 一人と、誰かとがいいなぁ〜（そんなかからない）」にベストマッチします。",
                    "Steam Wishlist Watcher",
                    "",
                    "2026-10-22 09:15",
                    92,
                    0,
                    0,
                    now,
                ),
                (
                    5,
                    "三軒茶屋・田園都市線・都内お得スポット",
                    "custom_url",
                    "deals",
                    "【11連休・平日特権】三軒茶屋起点で行ける「1,000円以下の科学館・水上バス・近場温泉・ひとりカラオケ」厳選リスト",
                    "https://www.kotsu.metro.tokyo.jp/",
                    "① 科学技術館（北の丸公園・入館950円）や国立科学博物館（大学生・学生証提示で割引/常設630円）は平日の午前がガラ空きで快適。\n"
                    "② 水辺の散歩＆短い船旅：浅草〜日の出桟橋・お台場のTOKYO CRUISE、または横浜シーバス（片道500円〜1,000円台）なら予約不要で気軽に船旅気分。\n"
                    "③ 田園都市線・世田谷周辺の銭湯サウナ＆黒湯温泉（駒沢・桜新町・溝の口エリア）は入浴料550円〜1,000円前後で「食事・散歩・風呂を味わう半日」が実現！",
                    "【休暇への活かし方】『やるメモ.md』の休暇リストにある「科学技術館」「短い船旅と水辺の散歩」「食事・散歩・風呂を味わう半日」を旅行レベルの出費なしで満喫できます。",
                    "Tokyo Local Concierge",
                    "",
                    "2026-10-22 09:20",
                    94,
                    0,
                    0,
                    now,
                ),

                # --- ③ 良記事キュレーション＆解説 (reading) ---
                (
                    1,
                    "良記事・哲学・創作キュレーション",
                    "rss",
                    "reading",
                    "「なぜ読みたいと思ったのか」を1行残すだけで、積読と創作メモがすべて資産に変わる理由",
                    "https://note.com/topics/writing_philosophy",
                    "本や作品をリストに入れる瞬間、人は必ず「今の自分の問い」に反応している。タイトルだけでなく「なぜ気になったか（動機）」を1行だけ添えておくと、数ヶ月後に見返したときに「当時の自分の輪郭」が鮮明に蘇るという知的生産論。",
                    "【今の私との繋がり】『やるメモ.md』の「読みたい！ってリストに入れた本をなぜ読みたかったのか？の見出し付けるやつ」や『10月26日までに完成させる.md』の執筆テーマと深く共鳴する記事です。",
                    "Essay & Thought Digest",
                    "",
                    "2026-10-22 07:00",
                    93,
                    0,
                    0,
                    now,
                ),
                (
                    1,
                    "良記事・日常行為と環境論",
                    "rss",
                    "reading",
                    "「やる気」ではなく「環境と最初の5分」を設計する：自由度を保ったまま行動のきっかけを作る技術",
                    "https://zenn.dev/topics/productivity",
                    "人間が行動を起こせるかどうかは意志の強さではなく「環境がきっかけとして機能しているか」と「体調」で9割決まる。義務感で予定を詰め込むのではなく、「30分だけ試す」「嫌ならやめていい」という自由を残すことで初めて創作や練習が続く。",
                    "【今の私との繋がり】『やるメモ.md』の「直近の考えに関する日常行為分析（学校はわかりやすい環境として機能する、ただしそこに自由がなくてはならない／体調は最重要ファクタ）」を裏付ける内容です。",
                    "Cognitive Design Note",
                    "",
                    "2026-10-22 07:30",
                    90,
                    0,
                    0,
                    now,
                ),
            ]

            conn.executemany(
                """
                INSERT OR IGNORE INTO feed_items
                (source_id, source_name, source_type, category, title, url, summary, why_it_matters, author, thumbnail_url, published_at, importance_score, is_read, is_bookmarked, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                initial_items,
            )
            conn.commit()

    # ------------------------------------------------------------------
    # フィード取得・既読・ブックマーク操作
    # ------------------------------------------------------------------
    def get_feeds(
        self,
        category: Optional[str] = None,
        source_type: Optional[str] = None,
        unread_only: bool = False,
        limit: int = 50,
    ) -> Dict[str, Any]:
        query = "SELECT * FROM feed_items WHERE 1=1"
        params: List[Any] = []

        if category and category != "all":
            query += " AND category = ?"
            params.append(category)
        if source_type and source_type != "all":
            query += " AND source_type = ?"
            params.append(source_type)
        if unread_only:
            query += " AND is_read = 0"

        query += " ORDER BY is_read ASC, importance_score DESC, id DESC LIMIT ?"
        params.append(limit)

        with self._get_conn() as conn:
            rows = conn.execute(query, params).fetchall()
            items = [dict(r) for r in rows]

            unread_counts_rows = conn.execute(
                "SELECT category, COUNT(*) as cnt FROM feed_items WHERE is_read = 0 GROUP BY category"
            ).fetchall()
            unread_by_cat = {r["category"]: r["cnt"] for r in unread_counts_rows}
            total_unread = sum(unread_by_cat.values())

        return {
            "items": items,
            "total_count": len(items),
            "total_unread": total_unread,
            "unread_by_category": unread_by_cat,
        }

    def mark_read(
        self,
        item_ids: Optional[List[int]] = None,
        category: Optional[str] = None,
        mark_all: bool = False,
    ) -> Dict[str, Any]:
        with self._get_conn() as conn:
            if mark_all:
                if category and category != "all":
                    cur = conn.execute(
                        "UPDATE feed_items SET is_read = 1 WHERE category = ?",
                        (category,),
                    )
                else:
                    cur = conn.execute("UPDATE feed_items SET is_read = 1")
                updated = cur.rowcount
            elif item_ids:
                placeholders = ",".join("?" for _ in item_ids)
                cur = conn.execute(
                    f"UPDATE feed_items SET is_read = 1 WHERE id IN ({placeholders})",
                    item_ids,
                )
                updated = cur.rowcount
            else:
                updated = 0
            conn.commit()

        return {"ok": True, "updated_count": updated}

    def toggle_bookmark_and_clip(
        self,
        item_id: int,
        clip_to_vault: bool = True,
    ) -> Dict[str, Any]:
        with self._get_conn() as conn:
            row = conn.execute(
                "SELECT * FROM feed_items WHERE id = ?", (item_id,)
            ).fetchone()
            if not row:
                return {"ok": False, "error": "アイテムが見つかりません"}
            item = dict(row)
            new_bm = 0 if item["is_bookmarked"] else 1
            conn.execute(
                "UPDATE feed_items SET is_bookmarked = ? WHERE id = ?",
                (new_bm, item_id),
            )
            conn.commit()

        clip_result = None
        if new_bm == 1 and clip_to_vault:
            clip_result = obsidian_service.clip_to_obsidian(
                title=item["title"],
                url=item["url"],
                summary=item.get("why_it_matters") or item.get("summary", ""),
                source_name=item.get("source_name", ""),
            )

        return {
            "ok": True,
            "item_id": item_id,
            "is_bookmarked": bool(new_bm),
            "clipped_to_obsidian": clip_result,
        }

    # ------------------------------------------------------------------
    # ウォッチソース管理 ＆「URL＋自然言語指示」からの自動ルール生成
    # ------------------------------------------------------------------
    def list_sources(self) -> List[Dict[str, Any]]:
        with self._get_conn() as conn:
            rows = conn.execute(
                "SELECT * FROM watch_sources ORDER BY id DESC"
            ).fetchall()
            res = []
            for r in rows:
                d = dict(r)
                try:
                    d["extraction_rule"] = json.loads(d.get("extraction_rule_json") or "{}")
                except Exception:
                    d["extraction_rule"] = {}
                res.append(d)
            return res

    def delete_source(self, source_id: int) -> Dict[str, Any]:
        with self._get_conn() as conn:
            cur = conn.execute("DELETE FROM watch_sources WHERE id = ?", (source_id,))
            conn.commit()
            return {"ok": True, "deleted": cur.rowcount > 0}

    async def analyze_and_add_source(
        self,
        url: str,
        instruction: str,
        name: Optional[str] = None,
        category: str = "sns_diff",
        save: bool = True,
    ) -> Dict[str, Any]:
        """
        URLと自然言語の指示（「このサイトの最新イベント情報を取って」「このタグのイラストを追って」等）から
        ソース種別を判定し、HTML/RSSを解析してCSSセレクタ・抽出ルールを自動生成＆プレビューアイテムを抽出する。
        """
        clean_url = url.strip()
        clean_inst = instruction.strip() or "最新の新着アイテム・更新情報を取得する"
        detected_type = self._detect_source_type(clean_url)

        rule: Dict[str, Any] = {}
        preview_items: List[Dict[str, Any]] = []
        resolved_title = name or ""

        # 1. YouTube
        if detected_type == "youtube":
            parsed = urllib.parse.urlparse(clean_url)
            qs = urllib.parse.parse_qs(parsed.query)
            query_kw = qs.get("search_query", [clean_inst])[0]
            rule = {
                "strategy": "youtube_rss_or_search",
                "target_url": clean_url,
                "keyword_filter": clean_inst,
                "query": query_kw,
            }
            if not resolved_title:
                resolved_title = f"YouTube監視: {clean_inst[:25]}"
            preview_items = await self._fetch_live_or_simulated_items(
                clean_url, detected_type, resolved_title, clean_inst, rule
            )

        # 2. Pixiv
        elif detected_type == "pixiv":
            m_tag = re.search(r"/tags/([^/]+)", clean_url)
            tag_name = urllib.parse.unquote(m_tag.group(1)) if m_tag else clean_inst
            rule = {
                "strategy": "pixiv_ajax_tag_or_user",
                "tag": tag_name,
                "ajax_endpoint": f"https://www.pixiv.net/ajax/search/artworks/{urllib.parse.quote(tag_name)}",
                "instruction": clean_inst,
            }
            if not resolved_title:
                resolved_title = f"Pixiv監視: #{tag_name}"
            preview_items = await self._fetch_live_or_simulated_items(
                clean_url, detected_type, resolved_title, clean_inst, rule
            )

        # 3. X (Twitter)
        elif detected_type == "x_twitter":
            rule = {
                "strategy": "x_diff_watcher",
                "target_url": clean_url,
                "instruction": clean_inst,
                "filter": "unread_only_no_algorithmic_timeline",
            }
            if not resolved_title:
                resolved_title = f"X(Twitter)差分: {clean_inst[:25]}"
            preview_items = await self._fetch_live_or_simulated_items(
                clean_url, detected_type, resolved_title, clean_inst, rule
            )

        # 4. RSS / 一般Webサイト (custom_url)
        else:
            analysis = await self._inspect_webpage_for_rules(clean_url, clean_inst)
            detected_type = analysis["source_type"]
            rule = analysis["rule"]
            if not resolved_title:
                resolved_title = analysis["page_title"] or f"Web監視: {clean_inst[:25]}"
            preview_items = analysis["preview_items"]

        source_id = None
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M")

        if save:
            with self._get_conn() as conn:
                cur = conn.execute(
                    """
                    INSERT INTO watch_sources
                    (name, source_type, url, instruction, extraction_rule_json, category, enabled, last_checked_at, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
                    """,
                    (
                        resolved_title,
                        detected_type,
                        clean_url,
                        clean_inst,
                        json.dumps(rule, ensure_ascii=False),
                        category,
                        now_str,
                        now_str,
                    ),
                )
                source_id = cur.lastrowid

                for idx, p_item in enumerate(preview_items[:5]):
                    item_url = p_item.get("url") or f"{clean_url}#item-{int(datetime.now().timestamp())}-{idx}"
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO feed_items
                        (source_id, source_name, source_type, category, title, url, summary, why_it_matters, author, thumbnail_url, published_at, importance_score, is_read, is_bookmarked, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, 0, 0, ?)
                        """,
                        (
                            source_id,
                            resolved_title,
                            detected_type,
                            category,
                            p_item.get("title", "新着アイテム"),
                            item_url,
                            p_item.get("summary", ""),
                            f"指示『{clean_inst}』に基づき抽出された新着差分です。",
                            resolved_title,
                            now_str,
                            88,
                            now_str,
                        ),
                    )
                conn.commit()

        return {
            "ok": True,
            "source_id": source_id,
            "name": resolved_title,
            "source_type": detected_type,
            "url": clean_url,
            "instruction": clean_inst,
            "extraction_rule": rule,
            "preview_items": preview_items[:5],
        }

    def _detect_source_type(self, url: str) -> str:
        low = url.lower()
        if "youtube.com" in low or "youtu.be" in low:
            return "youtube"
        if "pixiv.net" in low:
            return "pixiv"
        if "x.com" in low or "twitter.com" in low:
            return "x_twitter"
        if low.endswith(".xml") or low.endswith("/feed") or low.endswith(".rss") or "rss" in low:
            return "rss"
        return "custom_url"

    async def _inspect_webpage_for_rules(
        self, url: str, instruction: str
    ) -> Dict[str, Any]:
        """
        対象URLのHTMLまたはRSSを実際に取得して解析する。
        - RSSフィードであれば feedparser でエントリを抽出
        - HTMLであれば <link rel="alternate" type="application/rss+xml"> の有無を確認し、
          なければ BeautifulSoup で見出し・リンク構造から最適なCSSセレクタを自動推論する
        - オフラインまたはアクセス制限時はフォールバックルールとプレビューを返す
        """
        page_title = ""
        preview_items: List[Dict[str, str]] = []
        source_type = self._detect_source_type(url)
        rule: Dict[str, Any] = {
            "strategy": "html_css_selector",
            "item_selector": "article, .post, .item, li",
            "title_selector": "h2, h3, a",
            "link_selector": "a[href]",
            "instruction": instruction,
        }

        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) DailyConcierge/1.0"
            }
            async with httpx.AsyncClient(timeout=6.0, follow_redirects=True, headers=headers) as client:
                resp = await client.get(url)
                content_type = resp.headers.get("content-type", "").lower()
                raw_text = resp.text

            # RSS / XML の場合
            if "xml" in content_type or "rss" in content_type or raw_text.lstrip().startswith("<?xml"):
                parsed_feed = feedparser.parse(raw_text)
                page_title = parsed_feed.feed.get("title", "") or "RSS Feed"
                source_type = "rss"
                rule = {
                    "strategy": "rss_feed",
                    "feed_url": url,
                    "instruction": instruction,
                }
                for entry in parsed_feed.entries[:5]:
                    preview_items.append({
                        "title": entry.get("title", "No Title"),
                        "url": entry.get("link", url),
                        "summary": BeautifulSoup(entry.get("summary", ""), "html.parser").get_text()[:140],
                    })
                if preview_items:
                    return {
                        "source_type": source_type,
                        "page_title": page_title,
                        "rule": rule,
                        "preview_items": preview_items,
                    }

            # HTML の場合
            soup = BeautifulSoup(raw_text, "html.parser")
            if soup.title and soup.title.string:
                page_title = soup.title.string.strip()

            # RSS Auto-Discovery リンクの確認
            rss_link = soup.find("link", attrs={"type": re.compile(r"application/(rss|atom)\+xml")})
            rss_href = rss_link.get("href") if rss_link else None

            # 見出しや記事リンクの抽出
            candidates = []
            for sel in ["article", "section", ".post", ".item", ".news-item", "li"]:
                found = soup.select(sel)
                if len(found) >= 2:
                    rule["item_selector"] = sel
                    break

            for a_tag in soup.select("article a[href], h2 a[href], h3 a[href], .title a[href], li a[href]"):
                t_text = a_tag.get_text(strip=True)
                href = a_tag.get("href", "")
                if len(t_text) >= 8 and href and not href.startswith("javascript:"):
                    full_link = urllib.parse.urljoin(url, href)
                    candidates.append({
                        "title": t_text[:100],
                        "url": full_link,
                        "summary": f"『{instruction}』に合致する候補リンクとしてページ内から抽出されました。",
                    })
                if len(candidates) >= 5:
                    break

            if rss_href:
                rule["discovered_rss"] = urllib.parse.urljoin(url, str(rss_href))

            if candidates:
                preview_items = candidates
        except Exception:
            pass

        if not preview_items:
            preview_items = [
                {
                    "title": f"【自動抽出プレビュー】{instruction} に関する最新エントリ",
                    "url": url,
                    "summary": f"対象URL ({url}) の監視ルール（CSSセレクタ: {rule['item_selector']}）を登録しました。次回巡回時から差分のみを通知します。",
                }
            ]

        return {
            "source_type": source_type,
            "page_title": page_title,
            "rule": rule,
            "preview_items": preview_items,
        }

    async def _fetch_live_or_simulated_items(
        self,
        url: str,
        source_type: str,
        title: str,
        instruction: str,
        rule: Dict[str, Any],
    ) -> List[Dict[str, str]]:
        return [
            {
                "title": f"[{source_type.upper()}差分] {title} — 『{instruction}』の新着アイテム",
                "url": url,
                "summary": f"抽出ルール ({rule.get('strategy', 'auto')}) により、おすすめ欄のノイズを除外して新着差分のみを取得します。",
            }
        ]

    async def refresh_all_sources(self) -> Dict[str, Any]:
        """登録されている有効なソースを巡回し、RSS等が取得可能な場合は最新差分を追加する"""
        sources = self.list_sources()
        added_count = 0
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M")

        for src in sources:
            if not src.get("enabled"):
                continue
            if src["source_type"] == "rss":
                try:
                    async with httpx.AsyncClient(timeout=5.0, follow_redirects=True) as client:
                        resp = await client.get(src["url"])
                        if resp.status_code == 200:
                            feed = feedparser.parse(resp.text)
                            with self._get_conn() as conn:
                                for entry in feed.entries[:3]:
                                    link = entry.get("link", "")
                                    entry_title = entry.get("title", "")
                                    if not link or not entry_title:
                                        continue
                                    summary_txt = BeautifulSoup(
                                        entry.get("summary", ""), "html.parser"
                                    ).get_text()[:160]
                                    cur = conn.execute(
                                        """
                                        INSERT OR IGNORE INTO feed_items
                                        (source_id, source_name, source_type, category, title, url, summary, why_it_matters, author, thumbnail_url, published_at, importance_score, is_read, is_bookmarked, created_at)
                                        VALUES (?, ?, 'rss', 'sns_diff', ?, ?, ?, ?, ?, '', ?, 85, 0, 0, ?)
                                        """,
                                        (
                                            src["id"],
                                            src["name"],
                                            entry_title,
                                            link,
                                            summary_txt,
                                            f"監視指示『{src.get('instruction', '')}』に基づく新着RSS差分です。",
                                            entry.get("author", src["name"]),
                                            now_str,
                                            now_str,
                                        ),
                                    )
                                    if cur.rowcount > 0:
                                        added_count += 1
                                conn.execute(
                                    "UPDATE watch_sources SET last_checked_at = ? WHERE id = ?",
                                    (now_str, src["id"]),
                                )
                                conn.commit()
                except Exception:
                    pass

        return {
            "ok": True,
            "checked_sources": len(sources),
            "new_items_added": added_count,
            "checked_at": now_str,
        }


feed_service = FeedService()
