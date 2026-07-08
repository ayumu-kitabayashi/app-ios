# 家族共有 (Family Sharing) 設計書

**ステータス**: 設計ドラフト (未実装)
**前提**: Step 1〜3 完了後に着手
**工期見積**: 3 週間 (設計 1 週 + 実装 1.5 週 + テスト 0.5 週)

---

## 1. コンセプト

### 「データは故人に帰属する」

従来の共有サービスは「ユーザーのデータを他ユーザーと共有する」設計。
ReliefNote では「故人の手続き・記録を、遺族チームで管理する」という発想。

- データの主語は **故人 (GriefCase)** であり、個人ユーザーではない
- 家族メンバーはその GriefCase に参加する
- メンバーが離脱しても GriefCase は存続する

### なぜ暗号化が必要か

- 死亡診断書の情報、相続関連、金融口座情報が含まれる
- B2B2C モデルのため、葬儀社も ReliefNote 運営者もデータを読めてはいけない
- 「プライバシーが武器」を技術的に担保する

---

## 2. データモデル

### GriefCase (ケース)

```typescript
interface GriefCase {
    case_id: string;           // UUID v4
    deceased_name: string;     // 暗号化対象
    death_date: string;        // YYYY-MM-DD (暗号化対象)
    created_at: string;        // ISO 8601
    owner_id: string;          // 作成者の member_id
    members: CaseMember[];
    encryption_key_check: string; // AES-GCM で暗号化した固定文字列 (鍵照合用)
}

interface CaseMember {
    member_id: string;         // UUID v4
    display_name: string;      // 暗号化対象 (ケース内でのみ復号)
    role: 'owner' | 'editor' | 'viewer';
    joined_at: string;
    last_seen_at: string;
}
```

### 暗号化対象データ

| データ | 暗号化 | 理由 |
|---|---|---|
| deceased_name | AES-GCM | 故人の名前は個人情報 |
| death_date | AES-GCM | 死亡日 |
| answers (Q-DOD-01 等) | AES-GCM | 手続きに関わる全回答 |
| tasks + taskStatuses | AES-GCM | タスク進捗 |
| grief_logs | AES-GCM | 感情記録 (最もセンシティブ) |
| grief_waves | AES-GCM | 波の記録 |
| member display_name | AES-GCM | メンバー名 |
| case_id | 平文 | ルーティングに必要 |
| created_at | 平文 | ソートに必要 |
| role | 平文 | 権限判定に必要 |

### 暗号化しないデータ (サーバー側で見える)

| データ | 用途 |
|---|---|
| case_id | ルーティング |
| member_id | 認証 |
| role | 権限チェック |
| partner_id | コブランド |
| last_sync_at | 同期タイミング |
| total_tasks (数のみ) | 匿名統計 |
| completed_tasks (数のみ) | 匿名統計 |

---

## 3. 暗号化アーキテクチャ

### 鍵の生成と管理

```
[ケース作成]
  → AES-256-GCM 鍵 (case_key) をブラウザで生成
  → case_key を Base64 エンコード
  → QR コードに case_id + case_key を埋め込む
  → ケース作成者は case_key を localStorage に保存

[メンバー招待]
  → QR コードを見せる (対面) or 暗号化リンクを送る
  → 新メンバーは QR から case_id + case_key を取得
  → 新メンバーの localStorage に case_key を保存
  → サーバーは case_key を知らない
```

### QR コードのフォーマット

```
reliefnote://join?c={case_id}&k={base64_case_key}
```

- URL スキーム `reliefnote://` はウェブアプリでは `https://reliefnote.jp/join?c=...&k=...` にフォールバック
- QR スキャン後、パラメータの `k` を localStorage に保存し、URL からは即座に削除
- QR 画像はスキャン後に破棄 (カメラロールに保存しない)

### 暗号化・復号フロー

```javascript
// 暗号化
async function encryptData(plaintext, caseKey) {
    var keyBytes = base64ToArrayBuffer(caseKey);
    var cryptoKey = await crypto.subtle.importKey(
        'raw', keyBytes, 'AES-GCM', false, ['encrypt']
    );
    var iv = crypto.getRandomValues(new Uint8Array(12));
    var encoded = new TextEncoder().encode(plaintext);
    var ciphertext = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv: iv },
        cryptoKey,
        encoded
    );
    // iv (12 bytes) + ciphertext を結合して Base64
    var combined = new Uint8Array(iv.length + ciphertext.byteLength);
    combined.set(iv);
    combined.set(new Uint8Array(ciphertext), iv.length);
    return arrayBufferToBase64(combined);
}

// 復号
async function decryptData(encrypted, caseKey) {
    var keyBytes = base64ToArrayBuffer(caseKey);
    var cryptoKey = await crypto.subtle.importKey(
        'raw', keyBytes, 'AES-GCM', false, ['decrypt']
    );
    var combined = base64ToArrayBuffer(encrypted);
    var iv = combined.slice(0, 12);
    var ciphertext = combined.slice(12);
    var decrypted = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: new Uint8Array(iv) },
        cryptoKey,
        ciphertext
    );
    return new TextDecoder().decode(decrypted);
}
```

### 鍵照合 (encryption_key_check)

ケース作成時に固定文字列 `"RELIEF_NOTE_KEY_CHECK"` を case_key で暗号化し、サーバーに保存。
新メンバーが参加時にこれを復号し、一致すれば鍵が正しいと判定。

---

## 4. 同期プロトコル

### 方式: Last-Write-Wins (LWW)

CRDT は実装コストが高く、この用途では同時編集が頻繁に起きない。
LWW をフィールドレベルで適用する。

```typescript
interface SyncPayload {
    case_id: string;
    member_id: string;
    timestamp: string;          // ISO 8601 (クライアント時刻)
    encrypted_snapshot: string; // AES-GCM 暗号化された全データ JSON
    field_timestamps: {         // フィールドごとの最終更新時刻
        [field_key: string]: string;
    };
}
```

### 同期フロー

```
[書き込み側]
  1. ローカルで変更
  2. field_timestamps の該当フィールドを更新
  3. 全データを case_key で暗号化
  4. Supabase に UPSERT (case_id + member_id)

[読み取り側]
  1. Supabase から全メンバーの最新 SyncPayload を取得
  2. 各フィールドについて field_timestamps が最新のものを採用
  3. マージ結果をローカルに反映
```

### コンフリクト解決ルール

| ケース | 解決方法 |
|---|---|
| 同じフィールドを同時更新 | timestamp が新しい方が勝つ (LWW) |
| メンバー A がタスク完了、B が未完了に戻す | timestamp 比較 (最新が勝つ) |
| オフライン中に変更 → オンライン復帰 | 復帰時に同期。timestamp が古いためサーバー側が優先される場合あり |
| 削除 vs 更新 | 削除を優先 (tombstone フラグ) |

### 同期タイミング

- **ページロード時**: 必ず同期
- **フォーカス復帰時** (visibilitychange): 同期
- **データ保存時**: debounce 3 秒後に同期
- **手動**: 「同期」ボタン (ヘッダーに配置)
- WebSocket / Realtime は Phase 2 以降

---

## 5. 権限モデル

| 操作 | owner | editor | viewer |
|---|---|---|---|
| タスクの閲覧 | O | O | O |
| タスクの完了/未完了切替 | O | O | X |
| 回答の入力・変更 | O | O | X |
| こころのケア (自分の記録) | O | O | O |
| こころのケア (他メンバーの閲覧) | O | O | X |
| メンバーの招待 | O | O | X |
| メンバーの削除 | O | X | X |
| ケースの削除 | O | X | X |
| 権限の変更 | O | X | X |

### 制約

- owner は常に 1 名。譲渡可能。
- owner がケースを離脱するには、先に別の owner を指名する必要がある。
- viewer は「見守り枠」。遠方の親族が状況を把握するためのロール。

---

## 6. QR 招待フロー (UI)

### 招待する側 (owner/editor)

```
[ケース設定画面]
  → 「家族を招待」ボタン
  → QR コード表示 (case_id + case_key をエンコード)
  → 「この QR を家族に見せてください」
  → QR の有効期限: 生成から 24 時間 (期限切れ時は再生成)
  → QR 画面のスクリーンショット禁止警告 (技術的強制はできない)
```

### 参加する側 (新メンバー)

```
[ReliefNote を開く]
  → 「家族のケースに参加」ボタン
  → カメラで QR をスキャン
  → case_key を localStorage に保存
  → 表示名を入力 (ケース内で使う名前)
  → サーバーに member 登録
  → encryption_key_check を復号して鍵照合
  → 成功 → ケース画面に遷移
  → 失敗 → 「QR が無効か期限切れです」エラー
```

### 法要・通夜での配布シナリオ

- 通夜/告別式の受付で、香典返しと一緒に QR カードを配布
- 1 枚の QR カードに「ReliefNote 参加用」QR を印刷
- 参加者はスマホで読み取り → 即日からタスクリストを家族で共有
- セキュリティ考慮: QR が漏れた場合は owner がメンバーを削除して鍵を再生成 (ケース全体の再暗号化)

---

## 7. Supabase テーブル設計

### cases テーブル

```sql
CREATE TABLE public.cases (
    case_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id TEXT,
    encryption_key_check TEXT NOT NULL,    -- 暗号化された鍵照合用文字列
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

-- anon は INSERT のみ (新規ケース作成)
CREATE POLICY "anon can create case"
    ON public.cases FOR INSERT TO anon WITH CHECK (true);

-- SELECT は member として登録されている場合のみ (Supabase Edge Function で認証)
```

### case_members テーブル

```sql
CREATE TABLE public.case_members (
    case_id UUID REFERENCES public.cases(case_id) ON DELETE CASCADE,
    member_id UUID NOT NULL DEFAULT gen_random_uuid(),
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('owner', 'editor', 'viewer')),
    display_name_encrypted TEXT,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ,
    PRIMARY KEY (case_id, member_id)
);

ALTER TABLE public.case_members ENABLE ROW LEVEL SECURITY;
```

### case_data テーブル

```sql
CREATE TABLE public.case_data (
    case_id UUID REFERENCES public.cases(case_id) ON DELETE CASCADE,
    member_id UUID NOT NULL,
    encrypted_snapshot TEXT NOT NULL,       -- AES-GCM 暗号化された全データ JSON
    field_timestamps JSONB NOT NULL DEFAULT '{}',
    synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (case_id, member_id)
);

ALTER TABLE public.case_data ENABLE ROW LEVEL SECURITY;

-- case_members に登録されている member_id のみアクセス可能
CREATE POLICY "members can read case data"
    ON public.case_data FOR SELECT TO anon
    USING (
        EXISTS (
            SELECT 1 FROM public.case_members cm
            WHERE cm.case_id = case_data.case_id
            AND cm.member_id = case_data.member_id
        )
    );

CREATE POLICY "members can write case data"
    ON public.case_data FOR INSERT TO anon
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.case_members cm
            WHERE cm.case_id = case_data.case_id
            AND cm.member_id = case_data.member_id
            AND cm.role IN ('owner', 'editor')
        )
    );
```

---

## 8. オフラインサポート

### 方針

- ローカル (localStorage) を正とし、サーバーはバックアップ + 同期ハブ
- オフライン時もすべての操作が可能
- オンライン復帰時に自動同期
- 同期失敗時はリトライキュー (最大 5 回、指数バックオフ)

### localStorage キー構成 (家族共有モード)

```
relief_note_case_id       → UUID
relief_note_case_key      → Base64 (暗号化鍵)
relief_note_member_id     → UUID
relief_note_case_data     → JSON (復号済みローカルキャッシュ)
relief_note_sync_pending  → JSON (未同期の変更キュー)
```

---

## 9. セキュリティ考慮事項

### 脅威と対策

| 脅威 | 対策 |
|---|---|
| QR コードの漏洩 | owner がメンバーを削除 + 鍵ローテーション (全データ再暗号化) |
| localStorage の盗み読み | デバイスのパスコード/指紋が最終防衛線。追加で PIN ロック機能を検討 |
| MITM (通信盗聴) | HTTPS 必須。暗号化済みデータのみ通信するため、MITM されても復号不可 |
| Supabase 管理者による閲覧 | 暗号化済みデータのみ保存。case_key を知らない限り復号不可 |
| ブルートフォース (case_key) | AES-256-GCM: 2^256 の鍵空間。実質的に不可能 |
| メンバー離脱後のデータ保持 | 離脱時に localStorage からケースデータを削除。端末のバックアップに残る可能性は注意喚起で対応 |
| 相続トラブル (家族間対立) | owner がメンバーを削除可能。法的な判断は ReliefNote の責任範囲外 |

### 鍵ローテーション手順

1. owner が「鍵を再生成」を実行
2. 新しい case_key を生成
3. 既存の全 encrypted_snapshot を旧鍵で復号 → 新鍵で再暗号化
4. encryption_key_check を新鍵で再生成
5. 既存メンバーに新しい QR を配布 (対面推奨)
6. 旧鍵は破棄

---

## 10. 実装フェーズ

### Phase 1 (MVP: 3 週間)
- ケース作成 + QR 招待 + 参加
- タスク進捗の同期 (LWW)
- AES-GCM 暗号化/復号
- owner/editor/viewer 権限
- オフライン操作 + オンライン復帰時同期

### Phase 2 (改善: +2 週間)
- アクティビティフィード (「◯◯さんが △△ を完了しました」)
- タスクのアサイン (担当者フィールド追加)
- プッシュ通知 (Web Push API)
- PIN ロック

### Phase 3 (拡張: 将来)
- WebSocket Realtime 同期
- 鍵ローテーション UI
- ケースのエクスポート (PDF)
- 複数ケース管理 (複数の故人)

---

## 11. 既存コードへの影響

### 変更が必要な箇所

| 関数/領域 | 変更内容 |
|---|---|
| `saveData()` | ケースモードの場合、暗号化 + Supabase 同期を追加 |
| `loadData()` (初期化) | ケースモードの場合、Supabase から取得 + 復号 |
| `answers` オブジェクト | 平文のまま。暗号化は save/load レイヤーで透過的に行う |
| `taskStatuses` | 同上 |
| `localStorage.*grief*` | 同上 |
| `showScreen()` | ケース参加画面・ケース設定画面の追加 |
| タスクカード | アサイン UI (Phase 2) |
| ナビゲーション | 「家族」タブ or 設定内のケース管理メニュー |

### 変更しない箇所

- CSV マスターデータ (task_content_master, locale_override_master)
- AI チャット機能
- こころのケア (各メンバーが個別に記録。共有は Phase 2)
- logEvent() (匿名統計はケースモードでも同じ)
