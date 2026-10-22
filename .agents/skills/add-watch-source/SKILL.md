---
name: add-watch-source
description: ユーザーが指定したURLと自然言語の指示（「この公式サイトの最新イベント情報を取って」「このタグのイラストを追って」など）から、SNS・Web差分クローラーの監視ソース（抽出ルール）を解析・追加するスキル。
---

# URL＆自然言語指示からの監視ソース追加スキル (`add-watch-source`)

ユーザーが「このURLの〜の情報を取れるようにして」と指示した際、またはダッシュボードの「＋ソース追加」機能を拡張・実行する際は、以下の手順に従ってください。

## 実行手順

1. **対象URLの種別判定**
   - **YouTube**: チャンネルURL (`/@...` or `/channel/...`) または検索キーワード → RSSフィード (`https://www.youtube.com/feeds/videos.xml?channel_id=...`) または YouTube Data API / `yt-dlp` 抽出ルールとして登録。
   - **Pixiv**: ユーザーIDまたはタグ名 → Pixiv Ajax API (`/ajax/user/{id}/profile/all` または `/ajax/search/artworks/{tag}`) 抽出ルールとして登録。
   - **X (Twitter)**: `@username` または検索クエリ → ローカルワーカーのブラウザセッション / Nitter / RSS Bridge / API 抽出ルールとして登録。
   - **一般Webサイト（公式サイト・ニュース・セール情報等）**:
     1. ページのHTMLを取得し、RSS/Atomフィード (`<link rel="alternate" type="application/rss+xml">`) の有無を確認する。
     2. RSSがない場合、HTML構造を解析し、ユーザーの指示（例：「イベント更新情報だけ」「セール品だけ」）に合致する要素の **CSSセレクタ（アイテム一覧・タイトル・URL・日付・画像）** または **Gemini抽出プロンプト** を生成する。

2. **バックエンドへの登録と初回差分取得**
   - `backend/data/sources.json`（またはDBの `watch_sources` テーブル）にソース定義を追加する。
   - 初回クロールテストを実行し、少なくとも1件以上のアイテムが正しく抽出できることを確認する。

3. **ユーザーへの報告**
   - 抽出された最新アイテムのプレビュー（1〜3件）を提示し、意図通りの情報が取れているか確認する。
