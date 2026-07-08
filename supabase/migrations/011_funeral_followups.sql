-- =========================================================
-- ReliefNote: 葬儀社スタッフ CRM 用フォローアップテーブル
-- =========================================================
-- 背景:
--  - funeral_dashboard.html から、葬儀社スタッフが各ご遺族に対して
--    実施した「電話・メール・来店・メモ」をログ化したい
--  - 複数スタッフ運用での「対応被り・フォロー漏れ」を防ぐ
--  - ご遺族 (event_logs.user_id) と紐付けて履歴表示
--
-- スキーマ:
--  - id           : UUID
--  - channel      : 'funeral' / 'hokuryu' / 'direct'（葬儀社識別）
--  - user_id      : ご遺族の anon UUID（event_logs.user_id と同じ値）
--  - staff_name   : 葬儀社内の担当者名（事前相談員等、自由記述）
--  - action_type  : 'call' / 'email' / 'visit' / 'memo' / 'other'
--  - outcome      : 'completed' / 'callback_needed' / 'no_response' / 'rejected' / 'pending'
--  - note         : 自由記述（社内メモ、ご遺族との会話内容など）
--  - created_at   : 記録日時
--
-- セキュリティ:
--  - 実運用では葬儀社別の認証層を入れる前提
--  - デモ・初期パイロットでは anon SELECT/INSERT を許可
--  - 本番展開時は (channel, partner_id) ベースの RLS に強化する

CREATE TABLE IF NOT EXISTS public.funeral_followups (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel      TEXT NOT NULL,
    user_id      TEXT NOT NULL,
    staff_name   TEXT NOT NULL,
    action_type  TEXT NOT NULL CHECK (action_type IN ('call','email','visit','memo','other')),
    outcome      TEXT          CHECK (outcome IS NULL OR outcome IN ('completed','callback_needed','no_response','rejected','pending')),
    note         TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.funeral_followups IS '葬儀社スタッフがご遺族に対して実施した対応履歴';

-- インデックス
CREATE INDEX IF NOT EXISTS funeral_followups_user_idx
    ON public.funeral_followups (channel, user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS funeral_followups_staff_idx
    ON public.funeral_followups (channel, staff_name, created_at DESC);
CREATE INDEX IF NOT EXISTS funeral_followups_created_idx
    ON public.funeral_followups (channel, created_at DESC);

-- RLS
ALTER TABLE public.funeral_followups ENABLE ROW LEVEL SECURITY;

-- anon SELECT (葬儀社内の表示用)
DROP POLICY IF EXISTS "anon read funeral_followups" ON public.funeral_followups;
CREATE POLICY "anon read funeral_followups"
    ON public.funeral_followups
    FOR SELECT
    TO anon
    USING (true);

-- anon INSERT (葬儀社スタッフが記録)
DROP POLICY IF EXISTS "anon insert funeral_followups" ON public.funeral_followups;
CREATE POLICY "anon insert funeral_followups"
    ON public.funeral_followups
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- =========================================================
-- 動作確認 (SQL Editor で実行)
-- =========================================================
-- INSERT:
--   INSERT INTO public.funeral_followups (channel, user_id, staff_name, action_type, outcome, note)
--   VALUES ('funeral', 'test-uuid-1234', '田中', 'call', 'completed', '49日のご相談、本位牌のカタログ送付予定');
--
-- SELECT:
--   SELECT * FROM public.funeral_followups
--    WHERE channel = 'funeral'
--    ORDER BY created_at DESC LIMIT 20;
--
-- スタッフ別 集計:
--   SELECT staff_name, COUNT(*) AS actions, COUNT(DISTINCT user_id) AS families
--     FROM public.funeral_followups
--    WHERE channel = 'funeral' AND created_at >= now() - interval '30 days'
--    GROUP BY staff_name ORDER BY actions DESC;
