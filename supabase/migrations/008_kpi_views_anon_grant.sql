-- =========================================================
-- ReliefNote: KPI ダッシュボード用 anon SELECT 権限付与
-- =========================================================
-- 背景:
--  - 007 で作成した v_hokuryu_* ビュー群は event_logs / feedback を参照する。
--  - 現状 event_logs / feedback は anon に INSERT のみ許可、SELECT 不可なので
--    ダッシュボードから view を SELECT してもデータが返らない。
--  - 北竜町担当者向けダッシュボード (dashboard.html) からの読み取りを許可する。
--
-- セキュリティ的考察:
--  - event_logs.user_id は端末固有の匿名 UUID (rn_anon_id)。本名は含まれない。
--  - event_data.channel/screen_id/task_id 等は技術メタデータのみ。
--  - feedback.comment はユーザー自由記述。匿名だが文章自体は閲覧可能になる。
--  - 上記を踏まえて anon SELECT を許可する判断。
--  - より厳密にしたい場合は SECURITY DEFINER 関数でラップする選択肢あり。

-- 1. event_logs: anon SELECT 許可
DROP POLICY IF EXISTS "anon can read event_logs for kpi" ON public.event_logs;
CREATE POLICY "anon can read event_logs for kpi"
    ON public.event_logs
    FOR SELECT
    TO anon
    USING (true);

-- 2. feedback: anon SELECT 許可
DROP POLICY IF EXISTS "anon can read feedback for kpi" ON public.feedback;
CREATE POLICY "anon can read feedback for kpi"
    ON public.feedback
    FOR SELECT
    TO anon
    USING (true);

-- =========================================================
-- 動作確認 (SQL Editor で実行してデータが返ってくれば OK)
-- =========================================================
-- SELECT * FROM public.v_hokuryu_daily LIMIT 5;
-- SELECT * FROM public.v_hokuryu_feedback LIMIT 5;
