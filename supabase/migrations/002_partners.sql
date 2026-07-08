-- =========================================================
-- ReliefNote: パートナー (葬儀社) テーブル
-- =========================================================
-- 使い方: Supabase Dashboard → SQL Editor で実行

-- 1. partners テーブル
CREATE TABLE IF NOT EXISTS public.partners (
    partner_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    contact_email TEXT,
    tagline TEXT,
    color TEXT DEFAULT '#3A3F32',
    plan TEXT NOT NULL DEFAULT 'pilot'
        CHECK (plan IN ('pilot', 'basic', 'standard', 'premium')),
    dashboard_token TEXT NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
    token_expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '90 days',
    monthly_fee_yen INTEGER DEFAULT 0,
    pilot_start_date DATE,
    pilot_end_date DATE,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. RLS 有効化
ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;

-- anon / authenticated からはアクセス不可
-- (ダッシュボード API は service_role 経由でのみアクセス)
-- ポリシーを作成しないことで、全操作がデフォルト拒否される

-- 3. updated_at 自動更新トリガー
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER partners_updated_at
    BEFORE UPDATE ON public.partners
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at();

-- 4. event_logs にインデックス追加 (partner 検索用)
-- event_data は JSONB なので GIN インデックスが有効
CREATE INDEX IF NOT EXISTS event_logs_partner_idx
    ON public.event_logs USING GIN ((event_data -> 'partner'));

-- 5. デモパートナーを挿入
INSERT INTO public.partners (partner_id, name, tagline, plan, monthly_fee_yen)
VALUES ('demo', 'デモ葬儀社', '遺族のそばに、デモサービスから', 'pilot', 0)
ON CONFLICT (partner_id) DO NOTHING;

-- =========================================================
-- 動作確認
-- =========================================================
-- service_role で SELECT できるか:
--   SELECT * FROM public.partners;
--
-- anon で SELECT できないか:
--   SET ROLE anon;
--   SELECT * FROM public.partners;
--   -- ERROR: permission denied ← 正しい
--   RESET ROLE;
--
-- トークン確認:
--   SELECT partner_id, dashboard_token, token_expires_at FROM public.partners;
