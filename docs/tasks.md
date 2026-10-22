# Daily Concierge 実装タスク一覧・進行管理表

`Codex CLIとGit Hubをちゃんと使おう！.md` のタスク分解基準に基づき、1タスク＝1エージェント作業で完結・検証できる粒度に分解しています。

---

## フェーズ構成と進捗

### Phase 0: ポータブル開発基盤・Antigravity設定・Git初期化 (P0)
- [x] **T0-1: リポジトリ初期化とポータブル環境設定 (`AGENTS.md` / `GEMINI.md` / `.env.example`)**
- [x] **T0-2: Antigravity カスタムスキル定義 (`.agents/skills/`)**
- [x] **T0-3: Obsidian Sync用 引き継ぎノート作成 (`10_Projects/DailyConcierge_引き継ぎ.md`)**

### Phase 1: バックエンドコア ＆ Obsidian・予定・提案エンジン (P0〜P1)
- [ ] **T1-1: バックエンド基盤 ＆ ローカル/クラウド共通データモデル実装 (Python FastAPI + SQLite/Supabase互換)**
- [ ] **T1-2: Obsidian双方向パーサー＆ウォッチャー実装 (`やるメモ.md` / `趣味ガチャ` / Vaultプロファイル)**
- [ ] **T1-3: 天気API・Googleカレンダー連携・AIコンシェルジュ提案エンジン実装**

### Phase 2: SNS未読差分クローラー ＆ 柔軟なURLウォッチャー (P1)
- [ ] **T1-4: SNS差分収集（YouTube / Pixiv / X / RSS）＆ 自然言語URLルール生成エンジン**

### Phase 3: フロントエンド（PC Webダッシュボード ＆ Flutter Android/Desktopコード） (P1)
- [ ] **T2-1: PC/スマホ対応 レスポンシブWebダッシュボード実装（学校PCで即時動作確認用）**
- [ ] **T2-2: Flutter マルチプラットフォームアプリ実装（Androidネイティブ / Windows Desktop / Web）**
