-- =========================================================
-- ReliefNote: LP からの問い合わせ (reliefnote.jp/#contact) 受け皿
-- =========================================================
-- 背景:
--  - reliefnote.jp の LP に置く問い合わせフォームの保存先。
--  - mailto: はモバイルでメーラー未設定ユーザーに届かないため自前フォーム化。
--  - 既存の anon key + REST insert で完結する。
--
-- セキュリティ:
--  - anon は INSERT のみ。SELECT/UPDATE/DELETE は service_role のみ (Dashboard で閲覧)。
--  - email/name 等は本人入力なので「本人が同意した個人情報」として扱う。
--  - 簡易スパム対策として CHECK 制約で文字数/形式を制限。
--  - 180 日 TTL は付けない (問い合わせは履歴として残したい)。

CREATE TABLE IF NOT EXISTS public.contact_inquiries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role TEXT NOT NULL CHECK (role IN ('bereaved', 'government', 'funeral', 'media', 'other')),
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    email TEXT NOT NULL CHECK (char_length(email) BETWEEN 5 AND 200 AND email LIKE '%@%'),
    phone TEXT CHECK (phone IS NULL OR char_length(phone) BETWEEN 0 AND 30),
    organization TEXT CHECK (organization IS NULL OR char_length(organization) <= 120),
    message TEXT NOT NULL CHECK (char_length(message) BETWEEN 1 AND 2000),
    source TEXT,                              -- 流入元 (referrer 等)
    user_agent TEXT,                          -- 送信時のブラウザ情報
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS contact_inquiries_created_at_idx
    ON public.contact_inquiries (created_at DESC);
CREATE INDEX IF NOT EXISTS contact_inquiries_role_idx
    ON public.contact_inquiries (role);

ALTER TABLE public.contact_inquiries ENABLE ROW LEVEL SECURITY;

-- anon: INSERT のみ許可
DROP POLICY IF EXISTS "anon can insert contact_inquiries" ON public.contact_inquiries;
CREATE POLICY "anon can insert contact_inquiries"
    ON public.contact_inquiries
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- =========================================================
-- 動作確認 / 運用クエリ
-- =========================================================
-- 最近の問い合わせ:
--   SELECT created_at, role, name, email, message
--   FROM public.contact_inquiries ORDER BY created_at DESC LIMIT 50;
--
-- 立場別件数 (直近 30日):
--   SELECT role, COUNT(*) FROM public.contact_inquiries
--   WHERE created_at > now() - interval '30 days'
--   GROUP BY role ORDER BY count DESC;
