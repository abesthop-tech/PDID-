# Daily Concierge — Flutter マルチプラットフォームアプリ (`flutter_app/`)

**「余計なことを考える手間を減らし、今の私を明瞭にする」** パーソナル情報ハブ＆デイリーコンシェルジュの Android ネイティブ / Windows デスクトップ / Web 対応 Flutter アプリケーションです。

---

## 1. 主な機能と画面構成

1. **① Today & 提案 (`lib/screens/today_screen.dart`)**
   - 三軒茶屋・世田谷エリアの天気＆服装・傘アドバイス
   - Googleカレンダー予定タイムライン
   - Obsidian `01_Inbox/やるメモ.md` 双方向同期チェックリスト（朝ルーチン / 今日やるMust / 帰ったら・やりたいWant）
   - ラフに短文を投げ込める「クイック短文メモ追記」フォーム
   - AIコンシェルジュからの「今の空き時間・天気に合わせた具体的な行動提案」カード
   - **30分試食カウントダウンタイマー付き『趣味ガチャ』ウィジェット**（`したいゲーム.md` / `見たい物語.md` / `単発 やりたいリスト.md` 連動、「よかった→進行中へ」「興味ない→ログへ」「あとで」のワンタップ記録）
   - Vault全体から自動抽出した「今の私」プロファイルボード（進行中プロジェクト、関心トピック、予算・ルール）

2. **② SNS差分フィード (`lib/screens/sns_feed_screen.dart`)**
   - YouTube / Pixiv / X (Twitter) / RSS / カスタムWebサイトの「前回確認時からの未読差分のみ」を表示する Inbox Zero 型フィード
   - プラットフォーム・カテゴリ絞り込み、スワイプまたはワンタップでの既読化、「表示中をすべて既読にする」一括処理
   - タイムラインのノイズやおすすめ欄に時間を奪われない**アプリ内詳細プレビューモーダル**
   - 気になった記事や作品をワンタップで Obsidian (`やるメモ.md`) にクリップ保存

3. **③ AIニュース・お得情報・読み物 (`lib/screens/curation_screen.dart`)**
   - **ローカルAI・開発ツール解説**: ComfyUI / LLM / 個人開発ツールの最新動向と「なぜ今の自分に重要か」のAI解説
   - **お得情報・スポット**: Steamセール、Quest 3関連、三軒茶屋・都内の安くて良いスポット情報
   - **良記事・読み物**: 哲学・創作・ストーリー構造・エッセイなどの厳選解説

4. **④ ソース追加・設定 (`lib/screens/sources_settings_screen.dart`)**
   - **AI自然言語ウォッチャー追加**: URLを貼って「このページの最新イベント情報を取って」「このタグのイラストを追って」と指示するだけで監視ルールを自動生成・登録
   - 登録済み監視ソース一覧と手動クロール更新
   - **バックエンドサーバーURL / Supabaseクラウド同期 / オフラインキャッシュ設定**: 外出先やPCスリープ時でもクラッシュせずキャッシュ＆デモデータへ自動フォールバック

---

## 2. 自宅PCでのセットアップ＆実行手順

学校PCには Flutter SDK がインストールされていないため、自宅PCで以下の手順を実行してビルド・起動してください。

### 事前準備（初回のみ）
プロジェクト直下にプラットフォーム固有ランナーフォルダ（`android/`, `windows/`, `web/`）がまだ生成されていない場合は、`flutter_app/` ディレクトリ内で以下のコマンドを実行すると、既存の `lib/` や `pubspec.yaml` を上書きせずにネイティブランナー一式を生成できます：

```powershell
cd flutter_app
flutter create . --project-name daily_concierge --org com.dailyconcierge.app
flutter pub get
```

### A. Windows デスクトップアプリとして起動する
```powershell
cd flutter_app
flutter pub get
flutter run -d windows
```
- ウィンドウ幅 800px 以上では **PC用ワイドレイアウト（左 NavigationRail ＋ マルチカラム表示）** に自動切り替わりします。

### B. Android 実機でデバッグ起動する
1. Android スマホの「開発者向けオプション」で **USBデバッグ** を ON にし、PCにUSB接続します。
2. 以下のコマンドを実行します：
```powershell
cd flutter_app
flutter run -d android
```

### C. Android インストール用 APK をビルドする
スマホ単体でいつでも使えるようにリリース用 APK を作成する場合：
```powershell
cd flutter_app
flutter build apk --release
```
ビルド完了後、以下のパスに APK ファイルが出力されます：
`flutter_app/build/app/outputs/flutter-apk/app-release.apk`

これを Google ドライブや Discord、USB 経由で Android スマホに転送してインストールしてください。

---

## 3. バックエンドURL ＆ Supabase 接続設定手順

アプリ内の **「④ ソース・設定」タブ** から、いつでも接続先を変更・疎通テストできます。

### パターン1: 自宅Wi-Fi内で自宅PCのバックエンドと直接つなぐ
1. 自宅PCで `backend/main.py` を起動します（ポート `8000`）。
2. PCのローカルIPアドレス（例: `192.168.1.15`）を確認します（PowerShellで `ipconfig`）。
3. Androidアプリの「ソース・設定」画面で、バックエンドURLを `http://192.168.1.15:8000`（Windowsアプリの場合は `http://localhost:8000`）に設定して「保存＆接続テスト」を押します。

### パターン2: 外出先からスマホで使う（Supabase 連携 / ローカルキャッシュ）
- **Supabase連携**: `.env` およびアプリの「ソース・設定」画面に `SUPABASE_URL` と `SUPABASE_ANON_KEY` を設定すると、自宅PCがスリープ中でもクラウドDB経由で最新データの閲覧・タスクチェック・メモ追加が可能です。
- **オフライン自動フォールバック**: サーバーやSupabaseに接続できない環境（移動中など）でも、アプリ内の `SharedPreferences` キャッシュおよび内蔵デモデータへ自動的に切り替わり、エラーで止まることなく全画面を快適に操作できます。
