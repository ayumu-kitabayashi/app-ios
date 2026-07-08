-- =========================================================
-- ReliefNote: feedback テーブル (ホーム画面のレビューカード保存先)
-- =========================================================
-- 背景:
--  - index.html の submitReview() は _supabaseInsert('feedback', ...) を
--    呼んでいるが、テーブルが未作成で 404 となり catch で握りつぶされていた。
--  - 25% マイルストーン到達後に出る 3 段階評価 + 任意コメント +
--    送信時の進捗メタを保存し、運営が Supabase Dashboard で閲覧する。
--
-- 設計方針:
--  - 匿名 (個人識別子は保存しない)。channel / 進捗メタデータのみ。
--  - anon から INSERT のみ許可。SELECT/UPDATE/DELETE は service_role のみ。
--  - 180 日より古いレコードは event_logs と同様に pg_cron で掃除。

-- 1. feedback テーブル
CREATE TABLE IF NOT EXISTS public.feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id TEXT NOT NULL DEFAULT 'direct',
    rating TEXT NOT NULL CHECK (rating IN ('positive', 'neutral', 'needs_improvement')),
    comment TEXT,
    milestone_pct INTEGER CHECK (milestone_pct BETWEEN 0 AND 100),
    days_since_death INTEGER,
    tasks_done INTEGER,
    tasks_total INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. 運営分析用インデックス
CREATE INDEX IF NOT EXISTS feedback_created_at_idx
    ON public.feedback (created_at DESC);
CREATE INDEX IF NOT EXISTS feedback_channel_rating_idx
    ON public.feedback (channel_id, rating);

-- 3. RLS 有効化
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

-- 4. anon は INSERT のみ。読み出し/更新/削除は不可 (service_role は RLS を bypass)
DROP POLICY IF EXISTS "anon can insert feedback" ON public.feedback;
CREATE POLICY "anon can insert feedback"
    ON public.feedback
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- 5. 180 日 TTL (event_logs と同方針)
CREATE OR REPLACE FUNCTION public.purge_old_feedback() RETURNS INTEGER
    LANGUAGE plpgsql AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.feedback
        WHERE created_at < now() - interval '180 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

DO $$
BEGIN
    PERFORM cron.schedule(
        'reliefnote_feedback_purge',
        '15 18 * * *',
        $cron$SELECT public.purge_old_feedback();$cron$
    );
EXCEPTION WHEN invalid_schema_name OR undefined_table OR undefined_function THEN
    RAISE NOTICE 'cron スキーマが未作成のためスキップ。Dashboard → Database → Extensions で pg_cron を有効化後に本ブロックのみ再実行してください';
END $$;

-- =========================================================
-- 手動運用メモ
-- =========================================================
-- 最近のレビュー閲覧:
--   SELECT created_at, channel_id, rating, comment, milestone_pct
--   FROM public.feedback ORDER BY created_at DESC LIMIT 50;
--
-- チャネル別満足度:
--   SELECT channel_id, rating, COUNT(*)
--   FROM public.feedback
--   WHERE created_at > now() - interval '30 days'
--   GROUP BY channel_id, rating
--   ORDER BY channel_id, rating;
--
-- 手動パージ:
--   SELECT public.purge_old_feedback();
