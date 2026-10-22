# 自宅PC・学校PC 引き継ぎ＆再開ガイド (`HANDOVER.md`)

このリポジトリには、**システム本体のコード**だけでなく、**Antigravity / Codex 用のルール (`GEMINI.md`, `AGENTS.md`)、カスタムスキル (`.agents/skills/`)、設計書 (`docs/implementation_plan.md`)、タスク管理表 (`docs/tasks.md`)** がすべて同梱されています。

---

## 1. 自宅PCで初めて作業を再開する手順

### Step 1: GitHubからクローンする
自宅PCのターミナル（PowerShell等）で任意の作業フォルダに移動し、以下を実行します：
```powershell
git clone <あなたのGitHubリポジトリURL> daily_concierge
cd daily_concierge
```

### Step 2: `.env` ファイルで自宅PCのObsidian Vaultパスを指定する
`.env.example` をコピーして `.env` を作り、自宅PCで同期している Obsidian Vault (`obs` フォルダ) のパスを設定します：
```powershell
cp .env.example .env
```
`.env` の中身：
```env
# 自宅PCのObsidian Vaultのパス（Obsidian Syncで同期されているフォルダ）
OBSIDIAN_VAULT_PATH=C:\Users\<あなたのユーザー名>\Documents\obs

# Gemini APIキー（任意：設定するとAI提案・URL自動解析・記事要約が本物のGeminiで動作します）
GEMINI_API_KEY=your_gemini_api_key_here

# Supabase設定（任意：外出先からスマホ同期する場合に設定。未設定でもローカルSQLite/JSONで完全動作します）
SUPABASE_URL=
SUPABASE_ANON_KEY=
```

### Step 3: Antigravity 2.0（または Codex）で開く
1. Antigravity 2.0 を起動し、左サイドバーの **「Projects」** から `daily_concierge` フォルダをワークスペースとして開きます。
2. 自動的に `GEMINI.md` と `.agents/skills/` が読み込まれます。
3. チャット欄で以下のように話しかけるだけで、すぐ続きから再開できます：
   > `docs/implementation_plan.md と docs/tasks.md を確認して、現在の進捗を把握してください。自宅PC環境に合わせて動作確認と次のタスクを進めたいです。`

---

## 2. 起動コマンド一覧

### A. バックエンド＆ブラウザWebダッシュボードを起動する（学校PC・自宅PC共通）
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```
→ ブラウザで `http://localhost:8000` を開くと、すぐにダッシュボードが使えます！

### B. Flutterアプリ（Android実機ビルド／Windowsデスクトップ）を起動する（自宅PC用）
```powershell
cd flutter_app
flutter pub get
# Windowsデスクトップアプリとして起動
flutter run -d windows
# Androidスマホ（USBデバッグ接続時）にインストール＆起動
flutter run -d android
# Androidインストール用APKファイルをビルド
flutter build apk --release
```
