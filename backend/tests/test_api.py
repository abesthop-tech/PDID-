import shutil
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient

from backend.main import app
from backend.services.obsidian_service import ObsidianService, obsidian_service
from backend.services.feed_service import FeedService, feed_service


class TestDailyConciergeBackend(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        # 実際のObsidian Vaultの読み取り互換テストを行いつつ、
        # 書き込みテスト（チェックボックス更新・追記・ガチャ移動）は一時ディレクトリのクローンVaultで安全に検証する
        cls.real_vault_path = obsidian_service.vault_path
        cls.temp_dir = Path(tempfile.mkdtemp(prefix="concierge_test_"))
        cls.test_vault = cls.temp_dir / "obs"
        (cls.test_vault / "01_Inbox").mkdir(parents=True, exist_ok=True)

        # 実Vaultの 01_Inbox 対象ノートをテスト用一時Vaultへコピー（実ファイルを汚さない）
        target_files = [
            "やるメモ.md",
            "したいゲーム.md",
            "見たい物語.md",
            "単発 やりたいリスト.md",
            "いまやってる・見てるもの.md",
            "趣味ガチャ_log.md",
            "10月26日までに完成させる.md",
        ]
        for fname in target_files:
            src = cls.real_vault_path / "01_Inbox" / fname
            dst = cls.test_vault / "01_Inbox" / fname
            if src.exists():
                shutil.copy2(src, dst)
            else:
                dst.write_text(f"- [ ] テスト項目 ({fname})\n", encoding="utf-8")

        # テスト中はシングルトンの vault_path と db_path を一時領域に差し替える
        obsidian_service._vault_path_override = cls.test_vault
        feed_service._db_path_override = cls.temp_dir / "test_concierge.db"
        feed_service._init_db()
        feed_service._seed_initial_data()

        cls.client = TestClient(app)

    @classmethod
    def tearDownClass(cls) -> None:
        obsidian_service._vault_path_override = None
        feed_service._db_path_override = None
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def test_01_read_real_vault_non_destructive(self) -> None:
        """実Vaultのやるメモ.md・趣味ガチャプールがエラーなく構造化パースできること"""
        real_svc = ObsidianService(vault_path=self.real_vault_path)
        parsed = real_svc.parse_yaru_memo()
        self.assertIn("sections", parsed)
        self.assertTrue(len(parsed["sections"]["morning_routine"]) >= 3)
        self.assertTrue(len(parsed["vacation_plan"]["prep_items"]) >= 3)

        pool = real_svc.get_gacha_pool("ALL")
        self.assertGreater(pool["counts"]["GAME"], 50)
        self.assertGreater(pool["counts"]["STORY"], 20)
        self.assertGreater(pool["counts"]["SINGLE"], 5)

    def test_02_dashboard_and_status_endpoints(self) -> None:
        """/api/status および /api/dashboard と Web UI (/) が正常に応答すること"""
        res_root = self.client.get("/")
        self.assertEqual(res_root.status_code, 200)
        self.assertIn("Daily Concierge", res_root.text)

        res_status = self.client.get("/api/status")
        self.assertEqual(res_status.status_code, 200)
        self.assertTrue(res_status.json()["ok"])

        res_dash = self.client.get("/api/dashboard")
        self.assertEqual(res_dash.status_code, 200)
        body = res_dash.json()
        self.assertTrue(body["ok"])
        self.assertIn("weather", body)
        self.assertIn("suggestions", body)
        self.assertEqual(len(body["suggestions"]["proposals"]), 3)

    def test_03_toggle_task_and_quick_memo_safety(self) -> None:
        """やるメモ.md のチェックボックスON/OFFと短文メモ追記がコールアウト等を壊さず動作すること"""
        before_text = (self.test_vault / "01_Inbox" / "やるメモ.md").read_text(encoding="utf-8")
        self.assertIn("> [!NOTE]- 休暇", before_text)

        # 朝ルーチンの「お神体に一礼1拍手」をONに切り替え
        res_toggle = self.client.post(
            "/api/obsidian/toggle-task",
            json={"text_match": "お神体に一礼1拍手", "checked": True},
        )
        self.assertEqual(res_toggle.status_code, 200)
        self.assertTrue(res_toggle.json()["checked"])

        # クイック短文メモ追記
        res_memo = self.client.post(
            "/api/obsidian/quick-memo",
            json={"text": "帰ったらQuest 3の価格チェックする", "target_section": "auto", "as_checkbox": True},
        )
        self.assertEqual(res_memo.status_code, 200)
        self.assertEqual(res_memo.json()["section"], "after_return")

        after_text = (self.test_vault / "01_Inbox" / "やるメモ.md").read_text(encoding="utf-8")
        self.assertIn("- [x] お神体に一礼1拍手", after_text)
        self.assertIn("- [ ] 帰ったらQuest 3の価格チェックする", after_text)
        # 既存のコールアウトやDataviewブロックが一切破損していないことを確認
        self.assertIn("> [!NOTE]- 休暇", after_text)
        self.assertIn("```dataview", after_text)

    def test_04_shumi_gacha_draw_and_actions(self) -> None:
        """趣味ガチャの抽選（GAME/STORY/SINGLE）および『よかった』『もう興味ない』のファイル移動が動作すること"""
        res_draw = self.client.post("/api/obsidian/gacha/draw", json={"category": "GAME"})
        self.assertEqual(res_draw.status_code, 200)
        draw_data = res_draw.json()
        self.assertFalse(draw_data["empty"])
        picked = draw_data["item"]
        self.assertEqual(picked["source"], "GAME")

        # 「よかった」アクション -> いまやってる・見てるもの.md に追加されること
        res_good = self.client.post(
            "/api/obsidian/gacha/action",
            json={
                "action": "good",
                "title": picked["title"],
                "source": "GAME",
                "raw_line": picked["raw"],
            },
        )
        self.assertEqual(res_good.status_code, 200)
        doing_content = (self.test_vault / "01_Inbox" / "いまやってる・見てるもの.md").read_text(encoding="utf-8")
        self.assertIn(f"[[{picked['title']}]]", doing_content)

        # 別のアイテムを抽選して「もう興味ない(drop)」 -> 趣味ガチャ_log.md に記録されること
        res_draw2 = self.client.post("/api/obsidian/gacha/draw", json={"category": "STORY"})
        picked2 = res_draw2.json()["item"]
        res_drop = self.client.post(
            "/api/obsidian/gacha/action",
            json={
                "action": "drop",
                "title": picked2["title"],
                "source": "STORY",
                "raw_line": picked2["raw"],
            },
        )
        self.assertEqual(res_drop.status_code, 200)
        log_content = (self.test_vault / "01_Inbox" / "趣味ガチャ_log.md").read_text(encoding="utf-8")
        self.assertIn(f"[STORY] [削除] {picked2['title']}", log_content)

    def test_05_sns_feeds_and_natural_language_url_watcher(self) -> None:
        """SNS未読差分フィードの取得・既読化・ブックマーク（Obsidianクリップ）・URL＋自然言語指示追加が動作すること"""
        res_feeds = self.client.get("/api/feeds?unread_only=true")
        self.assertEqual(res_feeds.status_code, 200)
        feeds = res_feeds.json()
        self.assertGreater(feeds["total_unread"], 0)
        first_item_id = feeds["items"][0]["id"]

        # ブックマーク＆Obsidianクリップ
        res_bm = self.client.post(
            "/api/feeds/bookmark",
            json={"item_id": first_item_id, "clip_to_vault": True},
        )
        self.assertEqual(res_bm.status_code, 200)
        self.assertTrue(res_bm.json()["is_bookmarked"])

        # 個別既読化
        res_read = self.client.post(
            "/api/feeds/mark-read",
            json={"item_ids": [first_item_id]},
        )
        self.assertEqual(res_read.status_code, 200)
        self.assertEqual(res_read.json()["updated_count"], 1)

        # URL＋自然言語指示での監視ソース追加
        res_add = self.client.post(
            "/api/sources/analyze",
            json={
                "url": "https://www.pixiv.net/tags/%E5%89%B5%E4%BD%9C/artworks",
                "instruction": "創作タグの新着イラスト差分だけを取って",
                "category": "sns_diff",
                "save": True,
            },
        )
        self.assertEqual(res_add.status_code, 200)
        add_data = res_add.json()
        self.assertTrue(add_data["ok"])
        self.assertEqual(add_data["source_type"], "pixiv")
        self.assertGreaterEqual(len(add_data["preview_items"]), 1)


if __name__ == "__main__":
    unittest.main()
