# データモデル仕様

**最終更新**: <!-- AUTO:last-updated -->
2026-07-08
<!-- /AUTO:last-updated --> / **対象読者**: DB 移行・スキーマ拡張・データインポート/エクスポート担当

CSV 行数とマイグレーション一覧は `npm run docs:update` で自動更新される。

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

ReliefNote のデータは大きく 2 種類に分かれる:
1. **コンテンツマスター** (CSV) — 制度知識・タスク定義・質問定義
2. **ユーザーデータ** (Supabase + localStorage) — 回答・進捗・家族共有データ

本書は両者のスキーマと相互関係を定義します。

---

## 1. CSV マスター (`data/*.csv`)

すべて UTF-8、ヘッダ行 1 行、`,` 区切り、ダブルクォート escape の標準 CSV。

### 1.1 `tasks_master.csv` (90 行)

| 列 | 型 | 説明 |
|---|---|---|
| `task_id` | TEXT | 主キー (例: RN-D7-06) |
| `title` | TEXT | タスクタイトル |
| `domain` | TEXT | カテゴリ (FUNERAL/ADMIN/FINANCE/PENSION/HEALTH/EMPLOYMENT/HOUSING/DIGITAL/INSURANCE/CONTRACTS) |
| `time_bucket` | TEXT | フェーズ識別子 (H24/D7/D14/M3/M4/M10/Y3) |
| `display_policy` | TEXT | ALWAYS / CONDITIONAL / REVIEW |
| `priority` | INTEGER | 0-100、優先度 |
| `depends_on` | TEXT | 先行タスクID (`;` 区切り) |
| `depends_logic` | TEXT | NONE / SINGLE / AND / OR |
| `onboarding_step` | INTEGER | 1-4、オンボーディング段階 |
| `legal_due_days_from_dod` | INTEGER? | 法定期限 (死亡日からの日数) |
| `legal_due_note` | TEXT? | 期限の注記 |
| `recommended_start_days_from_dod` | INTEGER | 推奨着手日 |
| `due_type` | TEXT | LEGAL / RECOMMENDED / EVENT_BASED / CLAIM_WINDOW |
| `urgency_tier` | TEXT | CRITICAL / HIGH / MEDIUM / LOW |

### 1.2 `rules_master.csv` (90 行)

`tasks_master.csv` と 1:1。タスク表示の判定ロジック。

| 列 | 型 | 説明 |
|---|---|---|
| `rule_id` | TEXT | 主キー (例: TR-7060) |
| `task_id` | TEXT | tasks_master への外部キー |
| `rule_type` | TEXT | DSL_V1 (現在の方式) |
| `required_questions` | TEXT | 評価に必要な質問IDリスト (`;` 区切り) |
| `applies_when` | TEXT | DSL: 該当条件 |
| `not_applicable_when` | TEXT? | DSL: 非該当条件 |
| `auto_done_when` | TEXT? | DSL: 自動完了条件 |
| `fallback_status` | TEXT | UNKNOWN 時の状態 (デフォルト NEED_CONFIRM) |

### 1.3 `questions_master.csv` (39 行)

| 列 | 型 | 説明 |
|---|---|---|
| `sort_order` | DECIMAL | 表示順 |
| `question_id` | TEXT | 主キー (例: Q-REL-01) |
| `time_bucket` | TEXT | この質問が活きるフェーズ |
| `onboarding_step` | INTEGER | 1-4 |
| `question_text` | TEXT | 質問文 |
| `answer_type` | TEXT | single_select / multi_select / date |
| `options_internal` | TEXT | 内部値 (`;` 区切り、例: SPOUSE;PARENT;CHILD) |
| `option_labels` | TEXT | 表示文言 (`;` 区切り) |
| `exclusive_options` | TEXT | 排他オプション (multi_select で「どれもない」等) |
| `nullable` | BOOLEAN | 「わからない」を許容するか |

### 1.4 `task_content_master.csv` (90 行 × 12 列)

タスクごとの詳細コンテンツ。すべての列を持つ完全構造。

| 列 | 説明 |
|---|---|
| `task_id` | tasks_master への外部キー |
| `action_summary` | 1 文要約 |
| `why_needed` | なぜ必要か |
| `destination` | 提出先 |
| `required_docs` | 必要書類 (`、` `・` `/` 区切りリスト) |
| `steps_short` | 手順 (短い) — `\n` 区切り、行頭に番号 |
| `steps_detail` | 手順 (詳細) — steps_short と同件数 |
| `office_hours` | 受付時間 |
| `address` | 住所 |
| `phone` | 電話番号 |
| `done_condition` | 完了条件 |
| `faq` | FAQ — `Q.質問→回答` の連結、`\n` 区切り |

### 1.5 `phase_master.csv` (8 行)

| 列 | 説明 |
|---|---|
| `phase_id` | 主キー |
| `time_bucket` | H24/D7/D14/M3/M4/M10/Y3 |
| `sort_order` | 表示順 |
| `phase_title` | フェーズ名 |
| `tab_label` | タブ表示名 |
| `current_phase_start_day` | この時期に入る基準日数 |
| `current_phase_end_day` | この時期から抜ける基準日数 |
| `phase_message` | 遺族向けメッセージ |
| `phase_explanation` | 補足説明 |

### 1.6 `message_master.csv` (24 行)

リマインド・通知メッセージ。タスク詳細とは別チャネル。

| 列 | 説明 |
|---|---|
| `message_id`, `message_group`, `delivery_channel`, `surface`, `trigger_type`, `trigger_condition`, `title`, `body`, `priority`, `max_send`, `dedupe_scope` |

### 1.7 `task_expert_map.csv` (30 行)

タスクごとの推奨専門家。

| 列 | 説明 |
|---|---|
| `task_id` | tasks_master への外部キー |
| `profession` | 弁護士 / 司法書士 / 税理士 / 行政書士 / 社労士 / 遺品整理業者 |
| `fee_low`, `fee_high` | 費用レンジ (円) |
| `fee_unit` | 単位 (通常 "円") |
| `recommendation_note` | 推奨理由 |
| `necessity` | REQUIRED / RECOMMENDED / POSSIBLE |

### 1.8 `channel_override_master.csv` (131 行)

チャネル別の上書き (例: `?ch=funeral` で葬儀社向けの文言に差し替え)。

| 列 | 説明 |
|---|---|
| `override_id` | 主キー |
| `target_type` | task / question / global |
| `target_id` | 対象 ID |
| `field_name` | 上書きする列名 |
| `override_type` | REPLACE / HIDE / PREFILL / CLEAR |
| `override_value` | 新しい値 |

### 1.9 `locale_override_master.csv` (144 行)

地域別 (現状は北竜町のみ) の上書き。`?ch=hokuryu` のときだけ適用。

| 列 | 説明 |
|---|---|
| `override_id` | 主キー |
| `task_id` | 対象タスク ID |
| `field_name` | 上書きする列名 (task_content の列) |
| `override_value` | 新しい値 |

### 1.10 CSV を編集するときのルール

1. **task_id を変更しない** — 履歴データ・ルール・上書き全部が壊れる
2. **数字に `,` (3桁区切り) を入れない** — CSV パースが壊れる (例: ❌ `1,000円` ✅ `1000円`)
3. **改行を `\n` で表現** — 多くの列で 2 文字シーケンス `\n` を改行扱いする
4. **インライン CSV と同期する** — `index.html` 内の `INLINE_CSV` も同じ内容に保つこと (script で同期推奨)

---

## 2. Supabase テーブル

すべて RLS 有効。詳細は `docs/supabase-rls.md`。

### 2.1 `cases` (家族共有グループ)

```sql
CREATE TABLE public.cases (
    case_id UUID PRIMARY KEY,
    partner_id TEXT,
    encryption_key_check TEXT NOT NULL,
    key_hash TEXT,                 -- 004 で追加
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
```

- `key_hash`: ケース鍵の SHA-256 (`x-key-hash` ヘッダで照合)
- `encryption_key_check`: 鍵検証用の固定文字列を暗号化したもの (鍵照合)

### 2.2 `case_members`

```sql
CREATE TABLE public.case_members (
    case_id UUID,
    member_id UUID,
    role TEXT CHECK (role IN ('owner', 'editor', 'viewer')),
    display_name_encrypted TEXT,
    joined_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ,
    PRIMARY KEY (case_id, member_id)
);
```

`display_name_encrypted` はクライアント側で AES-GCM 暗号化して送信。

### 2.3 `case_data` (暗号化済みスナップショット)

```sql
CREATE TABLE public.case_data (
    case_id UUID,
    member_id UUID,
    encrypted_snapshot TEXT NOT NULL,
    field_timestamps JSONB NOT NULL DEFAULT '{}',
    synced_at TIMESTAMPTZ,
    PRIMARY KEY (case_id, member_id)
);
```

- `encrypted_snapshot`: タスク回答・進捗・ピン等の全状態を JSON で AES-GCM 暗号化
- `field_timestamps`: フィールド単位の最終更新時刻 (マージ衝突解決用)
- **TTL なし** (= ユーザーが解除するまで永続)

### 2.4 `event_logs` (匿名行動ログ)

```sql
CREATE TABLE public.event_logs (
    id BIGSERIAL PRIMARY KEY,
    event_name TEXT NOT NULL,
    event_data JSONB,
    session_id TEXT,
    client_id TEXT,
    channel TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

- 識別子は完全匿名 (UUID, ハッシュ済み)
- TTL: **365 日** (`010_extend_ttl_to_365_days.sql` で 180→365 に延長)
- pg_cron で `purge_old_event_logs()` を毎日実行

### 2.5 `feedback`

```sql
CREATE TABLE public.feedback (
    id UUID PRIMARY KEY,
    channel_id TEXT,
    rating TEXT,
    comment TEXT,
    milestone_pct INTEGER,
    days_since_death INTEGER,
    tasks_done INTEGER,
    tasks_total INTEGER,
    created_at TIMESTAMPTZ
);
```

TTL: 365 日

### 2.6 `contact_inquiries`

```sql
CREATE TABLE public.contact_inquiries (
    id UUID PRIMARY KEY,
    channel TEXT,
    body TEXT NOT NULL,
    contact TEXT,
    created_at TIMESTAMPTZ
);
```

TTL: **なし** (履歴として保持)

### 2.7 `partners` (B2B パートナー管理 / 002)

```sql
CREATE TABLE public.partners (
    partner_id TEXT PRIMARY KEY,
    name TEXT,
    region TEXT,
    contract_status TEXT,
    created_at TIMESTAMPTZ
);
```

将来の B2B 契約管理用。現状は実利用なし。

### 2.8 KPI Views (`007_hokuryu_kpi_views.sql`)

| View 名 | 用途 |
|---|---|
| `v_hokuryu_user_retention` | ユーザー継続率 |
| `v_hokuryu_task_completion` | タスク完了率 |
| `v_hokuryu_funnel` | オンボーディングファネル |
| `v_hokuryu_daily_active` | DAU/WAU 計算 |

---

## 3. localStorage キー一覧

クライアント側に保存される情報。サーバーには (家族共有時を除き) 送信しない。

| キー | 内容 |
|---|---|
| `rn_answers` | 質問への回答 (JSON) |
| `rn_task_statuses` | タスク状態 (JSON) |
| `rn_step_progress` | ステップチェック状態 |
| `rn_pinned_tasks` | ピン留めタスク ID 配列 |
| `rn_task_memos` | タスクごとのメモ |
| `rn_onboarding_index` | オンボーディング進捗 |
| `rn_data_version` | データバージョン (マイグレーション用) |
| `rn_case_id` / `rn_case_key` / `rn_case_member_id` / `rn_case_role` / `rn_case_key_hash` | 家族共有関連 |
| `rn_ai_chat_config` | AI チャット設定 (provider 等) |
| `rn_ai_chat_history` | チャット履歴 (将来用、現状は DOM から取得) |
| `relief_note_channel` | チャネル ID |
| `relief_note_family_banner_dismissed` | 家族共有バナー dismiss 状態 |

---

## 4. CSV ↔ JSON 変換 (アプリ内データ構造)

`buildMasterData()` 関数 (index.html) で以下に変換:

```js
tasks = [
    {
        id, title, domain, phase, displayPolicy, priority,
        dependsOn: ['RN-XXX',...], dependsLogic,
        onboardingStep, legalDueDays, legalDueNote,
        appliesWhen, notApplicableWhen, autoDoneWhen, fallbackStatus,
        requiredQuestions: [...]
    }
]

questions = [
    {
        id, text, answerType,
        options: [{ value: 'YES', label: 'はい' }, ...],
        exclusiveOptions, nullable, timeBucket, onboardingStep
    }
]

taskDetails[id] = {
    actionSummary, whyNeeded, destination, address, phone,
    officeHours, requiredDocs, doneCondition, faq, steps
}

taskStepsData[id] = {
    steps_short: [...],
    steps_detail: [...]
}
```

---

## 5. データ移植ガイド (CSV → 別 DB)

PHP / Node / Python に移植する際:

1. **CSV はそのまま import** — ストレージは MySQL/PostgreSQL のテーブルに 1:1 対応させればよい
2. **DSL 列は TEXT のまま保存** — 評価エンジンを言語側で書き直す
3. **手順 / FAQ の `\n` 区切り** — DB 列は TEXT のまま保存し、表示時に分割
4. **三層オーバーライド** — 読み込み時にマージ済みのテーブル `task_content_resolved` を作って事前計算しておくと高速
5. **localStorage → サーバ側 user_state テーブル** — 認証ユーザーが必要な場合は ユーザーID + JSON カラムで保管

---

## 6. データ整合性チェック

`runIntegrityChecks()` (index.html) が起動時に検証:
- すべての `depends_on` が tasks に存在
- すべての `required_questions` が questions に存在
- すべての `locale_override.task_id` が tasks に存在
- すべての `taskDetails` の task_id が tasks に存在

CSV を編集したら必ずブラウザ console でエラー無しを確認すること。
