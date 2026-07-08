-- =========================================================
-- ReliefNote: event_logs / feedback の TTL を 180 日 → 365 日へ延長
-- =========================================================
-- 背景:
--  - 005 / 006 で 180 日 TTL を設定したが、季節要因 (法事シーズン等) や
--    前年同月比 / 1年コホートの分析を可能にするため 365 日へ延長する。
--  - pg_cron のジョブ自体 (毎日実行) はそのまま。purge 関数の WHERE 句のみ更新。
--  - 関数を CREATE OR REPLACE で差し替えるだけなので無停止で適用可能。

-- 1. event_logs purge 関数の差し替え
CREATE OR REPLACE FUNCTION public.purge_old_event_logs() RETURNS INTEGER
    LANGUAGE plpgsql AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.event_logs
        WHERE created_at < now() - interval '365 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- 2. feedback purge 関数の差し替え
CREATE OR REPLACE FUNCTION public.purge_old_feedback() RETURNS INTEGER
    LANGUAGE plpgsql AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.feedback
        WHERE created_at < now() - interval '365 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- =========================================================
-- 手動確認メモ
-- =========================================================
-- 関数が新しい 365 日定義に置き換わったか:
--   SELECT pg_get_functiondef('public.purge_old_event_logs'::regproc);
--   SELECT pg_get_functiondef('public.purge_old_feedback'::regproc);
--
-- pg_cron ジョブは 005 / 006 で登録済みのものをそのまま使う:
--   SELECT jobname, schedule, command FROM cron.job
--   WHERE jobname IN ('reliefnote_event_logs_purge', 'reliefnote_feedback_purge');
--
-- 即時パージ (テスト用):
--   SELECT public.purge_old_event_logs();
--   SELECT public.purge_old_feedback();
