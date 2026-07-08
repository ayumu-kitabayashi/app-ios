# ReliefNote アーキテクチャ概要

**最終更新**: <!-- AUTO:last-updated -->
2026-07-08
<!-- /AUTO:last-updated --> / **対象読者**: 新規参加エンジニア・CTO 候補・技術アドバイザー

ReliefNote は日本の遺族向けに、葬儀後の手続きを案内する Web アプリケーションです。
本書はシステム全体の構成と各コンポーネントの責務をまとめます。

---

## 1. 全体構成図 (テキスト版)

```
[ユーザー (遺族)]
       │
       │ HTTPS
       ▼
┌──────────────────────────────────┐
│  GitHub Pages (静的配信)          │
│  reliefnote.github.io/app/         │
│   - index.html (約 28k 行)        │
│   - data/*.csv (9本)              │
│   - logo, favicon                 │
└──────────────┬───────────────────┘
               │
   ┌───────────┼───────────────────────┐
   │ (匿名ログ) │ (家族共有データ・E2E暗号化)│ (AI チャット)
   ▼           ▼                       ▼
┌───────────────────┐         ┌──────────────────────┐
│  Supabase         │         │  Cloudflare Workers  │
│  (Postgres + RLS) │         │  ai-chat-worker      │
│                   │         │  (TypeScript)        │
│  - event_logs     │         │                      │
│  - case_data      │         │  Anthropic API       │
│  - feedback       │         │  (Claude Haiku)      │
│  - contact_inq    │         └──────────────────────┘
│  - hokuryu_kpi    │
└───────────────────┘

[LP 別配信]
└── reliefnote-lp/  → GitHub Pages (別リポ・別ドメイン)
```

---

## 2. コンポーネント別責務

### 2.1 フロントエンド (`index.html`)

| 項目 | 内容 |
|---|---|
| 言語 | Vanilla JavaScript (ES2015+) |
| フレームワーク | **無し** |
| ビルドツール | **無し** (npm install 不要) |
| ファイル構成 | 単一 `index.html` (HTML/CSS/JS 内包、約 28k 行) |
| 配信 | GitHub Pages |
| 動作環境 | iOS Safari/Chrome、Android Chrome、Desktop ブラウザ全般 |
| オフライン動作 | `INLINE_CSV` フォールバックで `file://` でも起動可 |

**主な責務**:
- 画面遷移 (SPA: ホーム / ガイド / こころ / 相談 / 詳細 等)
- ルールエンジンの評価 (タスク状態判定)
- 質問回答の管理 (`localStorage`)
- AI チャット UI と Worker 呼び出し
- 家族共有データの暗号化と Supabase との同期
- イベントログ送信

**設計方針**:
- ビルドパイプラインを持たない (push = 本番反映)
- フレームワーク非依存で長期保守
- 古い端末・遅い回線の遺族層を想定し、JS バンドルを最小化

### 2.2 データマスター (`data/*.csv`)

行数は `npm run docs:update` で自動反映される (AUTO:csv-stats マーカー)。

<!-- AUTO:csv-stats -->
| ファイル | データ行数 |
|---|---|
| `tasks_master.csv` | 55 |
| `rules_master.csv` | 55 |
| `questions_master.csv` | 39 |
| `task_content_master.csv` | 57 |
| `phase_master.csv` | 7 |
| `message_master.csv` | 24 |
| `task_expert_map.csv` | 22 |
| `channel_override_master.csv` | 100 |
| `locale_override_master.csv` | 109 |
| `library_articles_master.csv` | 121 |
<!-- /AUTO:csv-stats -->

各 CSV の役割:
- `tasks_master`: 全タスク定義
- `rules_master`: 該当条件・自動完了条件 (DSL)
- `questions_master`: オンボーディング質問
- `task_content_master`: タスク詳細本文 (手順/書類/FAQ等)
- `phase_master`: 時間帯フェーズ (H24/D7/D14/M3/M4/M10/Y3 等)
- `message_master`: リマインドメッセージ
- `task_expert_map`: タスク↔専門家 (士業) マッピング
- `channel_override_master`: チャネル別の上書き (`?ch=hokuryu` 等)
- `locale_override_master`: 地域別の上書き (北竜町固有の窓口情報等)

**運用**: CSV は事業の核知識。エンジニア以外も編集可能なよう管理する。
変更は `data/` を編集 → push で反映。

### 2.3 バックエンド分離

#### 2.3.1 Supabase (Postgres + RLS)
- 役割: 永続データの保管 (家族共有データ・匿名ログ・フィードバック・問い合わせ)
- 認証: 匿名キー (`SUPABASE_ANON_KEY`) を HTML に直書き、**RLS で安全性を担保**
- RLS 戦略: 詳細は `docs/supabase-rls.md` 参照
- マイグレーション: `supabase/migrations/00X_*.sql` で管理

#### 2.3.2 Cloudflare Worker (`ai-chat-worker/`)
- 役割: Anthropic Claude API への proxy
- 言語: TypeScript
- 依存: `zod` のみ
- 機能: プロンプト構築・PII マスク・レート制限 (KV)・ログ
- デプロイ: `wrangler deploy`

### 2.4 LP (`reliefnote-lp/`)
- 別リポジトリ・別ドメインで配信
- 静的 HTML
- アプリ本体とは独立、デプロイサイクルも別

---

## 3. データフローの代表シナリオ

### 3.1 遺族がタスク詳細を開く
```
1. localStorage から answers (回答履歴) を読み込み
2. tasks/rules/questions の CSV から該当タスクを評価
3. taskStatuses[id] を determineTaskStatus() で算出 (OPEN/NEED_CONFIRM/AUTO_DONE/BLOCKED)
4. taskDetails[id] と taskStepsData[id] からコンテンツ表示
5. channel_override / locale_override を上書き適用
6. event_logs に screen_viewed をログ (本番のみ)
```

### 3.2 AI チャット
```
1. 遺族が質問入力 → PII マスク (PIIフィルタ)
2. タスクコンテキスト + 履歴 + 質問を Worker に POST
3. Worker が Anthropic API を呼び、回答を取得
4. レスポンス本文をフロントでストリーミング表示 (タイプライター演出)
5. 関連タスク/出典/フィードバック UI を構造化レンダリング
```

### 3.3 家族共有
```
1. 招待 URL/QR を生成 (caseKey を含む)
2. 招待された家族が URL を開く → caseKey をローカル取得
3. ローカルで Web Crypto により暗号化 → case_data へ POST
4. 取得時は case_data から取得 → ローカルで復号
5. RLS は cases.key_hash と x-key-hash ヘッダで所有証明
```

---

## 4. 依存サービス一覧

| サービス | 用途 | コスト | 障害時の挙動 |
|---|---|---|---|
| GitHub Pages | フロント配信 | 無料 | サービス停止時、アプリ自体が開けなくなる |
| Supabase | DB / RLS / pg_cron | 無料枠 | 家族共有/ログ/フィードバックが一時的に使えない (UI は動作継続) |
| Cloudflare Workers | AI proxy | 無料枠 | AI チャットのみ停止 |
| Anthropic API | LLM (Claude Haiku) | 従量課金 | AI チャット停止、UI からエラー表示 |
| Cloudflare KV | レート制限 | 無料枠 | 制限が無効化されるが Worker は動作継続 |

---

## 5. デプロイフロー

### フロント (アプリ本体)
```bash
# 編集 → コミット → push で本番即反映
git add data/ index.html
git commit -m "..."
git push origin main
```

### Worker (AI チャット)
```bash
cd ai-chat-worker
npm run typecheck   # 型チェック
npm run deploy      # wrangler でデプロイ
```

### DB マイグレーション
- Supabase ダッシュボード → SQL Editor で `supabase/migrations/00X_*.sql` を順次実行
- `IF NOT EXISTS` 等の冪等性付きで書かれているため、再実行は安全

現在のマイグレーション一覧 (自動生成):

<!-- AUTO:migrations-list -->
- `002_partners.sql`
- `003_family_sharing.sql`
- `004_tighten_rls.sql`
- `005_event_logs_ttl_and_indexes.sql`
- `006_feedback_table.sql`
- `007_hokuryu_kpi_views.sql`
- `008_kpi_views_anon_grant.sql`
- `009_contact_inquiries.sql`
- `010_extend_ttl_to_365_days.sql`
- `011_funeral_followups.sql`
<!-- /AUTO:migrations-list -->

---

## 6. セキュリティ概要

| 項目 | 対策 |
|---|---|
| 個人情報 | localStorage のみに保存、サーバー送信は家族共有時のみ (E2E 暗号化済み) |
| AI チャット入力 | PII (氏名/電話/メール等) を自動マスクして Worker へ送信 |
| Supabase | RLS 全テーブル有効、`key_hash` で所有証明 |
| API キー | `SUPABASE_ANON_KEY` は公開可、`ANTHROPIC_API_KEY` は Worker 内に隠蔽 |
| CORS | Worker は `ALLOWED_ORIGINS` allowlist 厳格運用 |
| TTL | event_logs / feedback は 365日後に pg_cron で自動削除 |

---

## 7. 既知の制約・技術的負債

<!-- AUTO:index-stats -->
- 行数: 約 41k 行 (実測 41,121 行)
- ファイルサイズ: 約 1807 KB
<!-- /AUTO:index-stats -->

- 単一 `index.html` が肥大化中。可読性は grep で耐えているが、機能ファイル分割の検討余地あり
- 自動テストは Playwright smoke 1ファイルのみ (rule engine の単体テスト不在)
- Worker のログは console.log のみ (D1 / KV への移行は Phase 2 Step 5 で予定)
- ネイティブアプリ未対応 (PWA で代用、iOS push は限定的)
- マルチテナント未対応 (パートナー別 DB 分離は将来課題)

---

## 8. 関連ドキュメント

- `docs/business-logic.md` — ルール DSL とタスク状態遷移の仕様
- `docs/data-model.md` — CSV と Supabase スキーマの対応関係
- `docs/migration-options.md` — CTO 引き継ぎ時の架構選択肢
- `docs/supabase-rls.md` — Supabase RLS 設計
- `docs/family-sharing-design.md` — 家族共有機能の設計詳細
- `docs/partner-dashboard-design.md` — 葬儀社向けダッシュボード設計案
