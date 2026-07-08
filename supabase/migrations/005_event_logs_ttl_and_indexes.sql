-- =========================================================
-- ReliefNote: event_logs の TTL と case_data の複合インデックス
-- =========================================================
-- 背景:
--  - event_logs は追記専用で増える一方。100K ユーザー × 50 イベント/月で
--    3 日以内に無料枠を圧迫する試算。180 日 TTL を pg_cron で回す。
--  - case_data は (case_id) 単独インデックスしか無く、最新同期の取り出しで
--    フルスキャンになる恐れがあるため (case_id, synced_at DESC) を追加。

-- 1. event_logs の created_at インデックス (TTL DELETE の高速化)
CREATE INDEX IF NOT EXISTS event_logs_created_at_idx
    ON public.event_logs (created_at);

-- 2. 180 日より古いイベントを削除する関数
CREATE OR REPLACE FUNCTION public.purge_old_event_logs() RETURNS INTEGER
    LANGUAGE plpgsql AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.event_logs
        WHERE created_at < now() - interval '180 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- 3. pg_cron で毎日 03:10 JST (= 18:10 UTC) に実行
-- Supabase では pg_cron は拡張として用意済み (要: pg_cron schema が存在)。
-- 既に同名ジョブがある場合はスキップ (再実行耐性)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'pg_cron extension の作成権限がありません。Supabase Dashboard → Database → Extensions から手動で有効化してください';
END $$;

DO $$
BEGIN
    PERFORM cron.schedule(
        'reliefnote_event_logs_purge',
        '10 18 * * *',
        $cron$SELECT public.purge_old_event_logs();$cron$
    );
EXCEPTION WHEN undefined_table OR undefined_function THEN
    RAISE NOTICE 'cron.schedule が利用できません。無料プランの場合は pg_cron を Dashboard から有効化後、本ブロックだけ再実行してください';
END $$;

-- 4. case_data に (case_id, synced_at DESC) 複合インデックス
-- 既存の case_data_case_id_idx / case_data_synced_at_idx と重複するが、
-- 「ケース内で新しい順」という実クエリに合致する複合を追加する。
CREATE INDEX IF NOT EXISTS case_data_case_synced_idx
    ON public.case_data (case_id, synced_at DESC);

-- =========================================================
-- 手動運用メモ
-- =========================================================
-- パージ関数の手動実行:
--   SELECT public.purge_old_event_logs();
--
-- スケジュール確認:
--   SELECT * FROM cron.job WHERE jobname = 'reliefnote_event_logs_purge';
--
-- スケジュール解除:
--   SELECT cron.unschedule('reliefnote_event_logs_purge');
