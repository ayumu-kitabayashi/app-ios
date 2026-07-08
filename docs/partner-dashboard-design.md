# 葬儀社向けダッシュボード MVP 設計書

**ステータス**: 設計ドラフト (未実装)
**前提**: Step 1〜4 完了後に着手
**工期見積**: 1 週間 (設計 2 日 + 実装 3 日 + テスト 2 日)

---

## 1. コンセプト

### 「匿名統計だけ」のダッシュボード

葬儀社がリアルタイムに見られるのは **完全匿名化された統計のみ**。
個々の遺族の名前・タスク内容・感情記録は一切表示しない。

### 何を知りたいか (葬儀社のニーズ)

1. **導入効果**: 「うちの QR カード、使われてるの？」
2. **活用度**: 「遺族はどの機能を使ってるの？」
3. **改善ヒント**: 「遺族が困っているポイントはどこ？」
4. **報告材料**: 「経営会議で報告するための数字がほしい」

---

## 2. ダッシュボード画面設計

### アクセス方法

- Cloudflare Worker or Supabase Edge Function で提供
- URL: `https://reliefnote.jp/partner/{partner_id}/dashboard`
- 認証: パートナー登録時に発行するアクセストークン (Bearer token)
- レスポンシブ: PC / タブレットで閲覧想定

### 画面構成

```
[ヘッダー]
  ◯◯葬儀社 ダッシュボード | 期間: [今月 ▼]

[KPI カード 4 枚]
  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
  │利用者数   │ │タスク完了率│ │OCR利用率  │ │ケア利用率 │
  │   23人   │ │   42%   │ │   68%   │ │   31%   │
  │  +5 先月比│ │  +8pp   │ │  -2pp   │ │  +12pp  │
  └─────────┘ └─────────┘ └─────────┘ └─────────┘

[利用者数の推移]
  棒グラフ (月別、過去 6 ヶ月)

[よく使われている機能 TOP 5]
  1. タスクリスト閲覧   456 回
  2. 死亡日 OCR 撮影      89 回
  3. こころのケア記録      78 回
  4. AI 質問             45 回
  5. 呼吸ガイド           23 回

[タスク完了率の分布]
  0-25%: ██████ 8 人
  25-50%: ████████████ 12 人
  50-75%: ████████ 6 人
  75-100%: ████ 3 人

[月次レポート]
  [2026年3月 PDF ▼] [2026年2月 PDF ▼]
```

---

## 3. 集計クエリ (Supabase)

### 前提

- `event_logs` テーブルに全イベントが記録されている
- `partner` フィールドでパートナーごとにフィルタ
- 集計は Edge Function でサーバーサイド実行 (service_role_key 使用)

### KPI 集計 SQL

```sql
-- 月間ユニーク利用者数
SELECT COUNT(DISTINCT user_id)
FROM public.event_logs
WHERE event_data->>'channel' = 'funeral'
  AND event_data->>'partner' = $1
  AND created_at >= date_trunc('month', CURRENT_DATE)
  AND created_at < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month';

-- タスク完了率 (全ユーザーの平均)
-- event_type = 'task_status_changed' で status = 'DONE' のカウント
SELECT
    user_id,
    COUNT(*) FILTER (WHERE event_data->>'new_status' = 'DONE') AS done_count,
    COUNT(*) FILTER (WHERE event_data->>'new_status' IS NOT NULL) AS total_changes
FROM public.event_logs
WHERE event_data->>'partner' = $1
  AND event_type = 'task_status_changed'
  AND created_at >= date_trunc('month', CURRENT_DATE)
GROUP BY user_id;

-- OCR 利用率
SELECT
    COUNT(*) FILTER (WHERE event_type = 'ocr_run_finished') AS ocr_attempts,
    COUNT(*) FILTER (WHERE event_type = 'ocr_result_confirmed') AS ocr_confirmed,
    COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'ocr_capture_opened') AS ocr_users
FROM public.event_logs
WHERE event_data->>'partner' = $1
  AND created_at >= date_trunc('month', CURRENT_DATE);

-- 機能別利用回数 TOP 5
SELECT
    event_type,
    COUNT(*) AS usage_count
FROM public.event_logs
WHERE event_data->>'partner' = $1
  AND created_at >= date_trunc('month', CURRENT_DATE)
  AND event_type NOT IN ('page_view', 'session_start') -- ノイズ除外
GROUP BY event_type
ORDER BY usage_count DESC
LIMIT 5;
```

---

## 4. 月次 PDF レポート

### 生成方法

- Supabase Edge Function (Deno) で HTML テンプレートを生成
- Puppeteer / Playwright で PDF 化 (ヘッドレスブラウザ)
- または: サーバーサイドで HTML を生成し、クライアント側で `window.print()` する簡易版 (MVP)

### レポート構成 (A4 2 ページ)

**1 ページ目: サマリ**
```
┌──────────────────────────────────────┐
│ ReliefNote 月次レポート              │
│ ◯◯葬儀社 様                        │
│ 2026年3月                           │
├──────────────────────────────────────┤
│                                      │
│ [KPI 4 枚]                          │
│ 利用者数 | タスク完了率 | OCR | ケア  │
│                                      │
│ [利用者数の推移グラフ]               │
│                                      │
│ [よく使われた機能 TOP 5]             │
│                                      │
└──────────────────────────────────────┘
```

**2 ページ目: インサイト**
```
┌──────────────────────────────────────┐
│ 今月のインサイト                      │
├──────────────────────────────────────┤
│                                      │
│ ■ 遺族の傾向                        │
│   - タスク完了率が先月比 +8pp 改善    │
│   - OCR 利用率は 68%（目標 80%）     │
│   - こころのケア利用率が急増（+12pp） │
│                                      │
│ ■ 推奨アクション                     │
│   - QR カードの配布率を上げましょう    │
│   - OCR がうまくいかない報告が 3 件    │
│     → 撮影のコツを案内に追記推奨     │
│                                      │
│ ■ 次月のアップデート予定              │
│   - 家族共有機能(β)リリース          │
│   - AI 質問の回答精度向上             │
│                                      │
│ ──────────────────────────────────── │
│ ReliefNote | barcaak1011@gmail.com   │
└──────────────────────────────────────┘
```

### 配信

- 毎月 5 日に自動生成 → パートナーのメールアドレスに自動送信
- ダッシュボードからも過去分をダウンロード可能

---

## 5. 匿名化ルール

### 絶対に表示しないもの

| データ | 理由 |
|---|---|
| ユーザー名・ニックネーム | 個人特定リスク |
| 故人の名前 | プライバシー |
| 死亡日 (個別) | 組み合わせで個人特定 |
| タスクの詳細内容 | 手続き内容から個人特定 |
| 感情記録の本文 | 最もセンシティブ |
| AI チャットの会話内容 | プライバシー |

### 表示するもの (匿名集計)

| データ | 表示形式 |
|---|---|
| ユニーク利用者数 | 数値のみ |
| タスク完了率 | パーセンテージ |
| 機能別利用回数 | イベント名 + 回数 |
| OCR 成功率 | パーセンテージ |
| 利用者数の推移 | 月別の棒グラフ |
| タスク完了率の分布 | レンジ別の棒グラフ |

### 最低集計人数ルール

- **5 人未満** の場合、すべての集計値を「集計中」と表示し、具体的な数字は出さない
- これにより、少人数のケースで個人が特定されるリスクを回避

---

## 6. 認証

### MVP (シンプル版)

- パートナー登録時に 64 文字のランダムトークンを発行
- ダッシュボード URL にトークンを含める: `/partner/{id}/dashboard?token={token}`
- Edge Function でトークンを検証
- トークンは 90 日で期限切れ → 再発行 (手動)

### Phase 2 以降

- メールアドレス + パスワード認証 (Supabase Auth)
- 2FA (TOTP)
- 複数スタッフアカウント (管理者/閲覧者)

---

## 7. 技術スタック

| レイヤー | 技術 | 理由 |
|---|---|---|
| フロント | 静的 HTML + Vanilla JS | シンプルさ優先。ダッシュボードだけのために React は過剰 |
| グラフ | Chart.js (CDN) | 軽量、設定が少ない |
| API | Supabase Edge Function | service_role_key で集計クエリを実行 |
| PDF | HTML + `window.print()` (MVP) | サーバーサイド PDF 生成は Phase 2 |
| ホスティング | Cloudflare Pages or Supabase Storage | 静的ファイル配信 |

---

## 8. Supabase テーブル拡張

### partners テーブル (新規)

```sql
CREATE TABLE public.partners (
    partner_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    contact_email TEXT,
    dashboard_token TEXT NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
    token_expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '90 days',
    plan TEXT DEFAULT 'basic' CHECK (plan IN ('pilot', 'basic', 'standard', 'premium')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
-- anon からはアクセス不可 (Edge Function の service_role のみ)
```

### event_logs への partner フィールド追加

既存の `logEvent()` で `event_data` に `partner` を含める (既に `window.currentPartnerId` で設定済み)。

```javascript
// logEvent 内 (既存コード)
data.partner = window.currentPartnerId || '';
```

---

## 9. MVP 実装手順

1. `partners` テーブルを Supabase に作成
2. ダッシュボード HTML を `sales/partner-dashboard.html` として作成
3. Supabase Edge Function を 1 本作成 (GET `/api/partner-stats`)
4. Edge Function 内でトークン認証 + 集計クエリ実行
5. HTML 側で fetch → Chart.js でグラフ描画
6. 月次レポート: 同じ HTML の `?print=true` モードで `window.print()` → PDF

---

## 10. 今後の拡張

| 機能 | 時期 | 概要 |
|---|---|---|
| アラート通知 | Phase 2 | 「利用者が急減しています」のメール通知 |
| 比較 | Phase 2 | 「同規模の他社平均」との比較 (十分なデータが溜まった後) |
| CSV エクスポート | Phase 2 | 集計データの CSV ダウンロード |
| カスタムレポート | Phase 3 | パートナーが見たい指標を選択してレポート生成 |
| API | Phase 3 | パートナーの既存 CRM と連携 |
