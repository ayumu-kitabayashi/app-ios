# Supabase Row Level Security 推奨設定

ReliefNote は `SUPABASE_ANON_KEY` を HTML に直書きしているため、**誰でも anon キーで Supabase を呼べる**前提で設計する必要があります。テーブルには必ず RLS を有効化し、anon 権限でできることを最小限に絞り込んでください。

## 対象テーブル

| テーブル | 用途 | anon に許可するべき操作 |
|---|---|---|
| `event_logs` | フロントエンドから送るイベントログ (`logEvent()` で使用) | **INSERT のみ** |
| `frontend_errors` (任意) | エラーレポート専用に分ける場合 | **INSERT のみ** |

anon キーに `SELECT` / `UPDATE` / `DELETE` を許可すると、他のユーザーのログが読み放題・書き換え放題になります。**絶対に許可しないでください**。

## セットアップ手順

Supabase のダッシュボード → SQL Editor で以下を順に実行してください。

### 1. テーブル定義（まだ無ければ）

```sql
create table if not exists public.event_logs (
    id bigint generated always as identity primary key,
    user_id text,
    event_type text not null,
    event_data jsonb,
    created_at timestamptz not null default now()
);

-- created_at でよく検索するのでインデックス
create index if not exists event_logs_created_at_idx
    on public.event_logs (created_at desc);
create index if not exists event_logs_event_type_idx
    on public.event_logs (event_type);
```

### 2. RLS を有効化

```sql
alter table public.event_logs enable row level security;
```

### 3. anon に INSERT だけ許可

```sql
-- 既存の「全権許可」ポリシーがあれば先に削除
drop policy if exists "Enable all for anon" on public.event_logs;
drop policy if exists "Enable read for anon" on public.event_logs;

-- anon は INSERT のみ
create policy "anon can insert event logs"
    on public.event_logs
    for insert
    to anon
    with check (true);
```

### 4. SELECT / UPDATE / DELETE は service_role のみ

anon / authenticated からは読めないようにする。管理画面やダッシュボードで集計したい場合は、**必ずサーバー側（Supabase Edge Function / Cloudflare Worker）から `service_role_key` を使って** アクセスすること。ブラウザから service_role を使ってはいけない。

```sql
-- authenticated ロールでも読めないよう、明示的に policy を作らない
-- （何も作らなければ SELECT は拒否される）
```

### 5. 動作確認

```sql
-- anon として INSERT できるか
set role anon;
insert into public.event_logs (event_type, event_data)
    values ('test_event', '{"test": true}'::jsonb);
-- 成功するはず

-- anon として SELECT できないか
select count(*) from public.event_logs;
-- ERROR: permission denied for table event_logs  ← これが正しい動作

reset role;
```

## セキュリティ チェックリスト

運用開始前・機能追加後に以下を確認してください。

- [ ] `event_logs` テーブルで RLS が有効 (`select relname, relrowsecurity from pg_class where relname = 'event_logs';`)
- [ ] anon ロールに `SELECT` 権限がない（`Test` タブで anon として SELECT を実行しエラーになる）
- [ ] anon ロールに `INSERT` 権限がある（同様にテスト INSERT が成功する）
- [ ] anon ロールに `UPDATE` / `DELETE` 権限がない
- [ ] 自由記述（感情日記、波の note、AIチャット履歴など）が `event_logs` に含まれていない
- [ ] `user_id` カラムに実名やメアドではなく、匿名識別子（nickname またはハッシュ）だけが入っている
- [ ] Supabase ダッシュボードで `event_logs` のサイズを定期的にチェック（肥大化時はアーカイブ or TTL 設定）

## ログローテーション（任意）

`event_logs` は時間経過で肥大化します。古いデータを自動削除するには、Supabase の Scheduled Function か Postgres の拡張 `pg_cron` を使います。

```sql
-- 例: 180日より古いログを毎日削除
select cron.schedule(
    'delete_old_event_logs',
    '0 3 * * *',  -- 毎日 03:00 UTC
    $$ delete from public.event_logs where created_at < now() - interval '180 days' $$
);
```

## トラブルシュート

**「anon で INSERT したら 401 が返る」**
→ policy が `to anon` になっているか確認。`to public` だと認証ロール全員に適用されてしまう。

**「INSERT は成功するが Supabase ダッシュボードの Table Editor で見えない」**
→ ダッシュボードは `authenticated` ロールで動いていることがある。`service_role` に切り替えて確認。

**「fetch が CORS で失敗する」**
→ Supabase → Project Settings → API → CORS Allowed Origins に本番ドメイン、localhost:8080 などを追加。

## 参考リンク

- Supabase RLS 公式ドキュメント: https://supabase.com/docs/guides/auth/row-level-security
- Postgres policy 構文: https://www.postgresql.org/docs/current/sql-createpolicy.html
