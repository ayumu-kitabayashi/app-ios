-- =========================================================
-- ReliefNote: 家族共有 (GriefCase) テーブル
-- =========================================================
-- 使い方: Supabase Dashboard → SQL Editor で実行
-- 前提: 002_partners.sql の update_updated_at() 関数が存在すること

-- 1. cases テーブル
CREATE TABLE IF NOT EXISTS public.cases (
    case_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id TEXT,
    encryption_key_check TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

-- anon は INSERT のみ (新規ケース作成)
CREATE POLICY "anon can create case"
    ON public.cases
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- anon は自分が参加しているケースの key_check だけ SELECT 可能
-- (join 時の鍵照合に必要)
CREATE POLICY "anon can read own case"
    ON public.cases
    FOR SELECT
    TO anon
    USING (true);
    -- NOTE: 本番では case_members 経由の EXISTS チェックに変更すべき。
    -- MVP ではケース ID を知っている = 招待されている前提で SELECT を許可。

-- updated_at 自動更新
CREATE TRIGGER cases_updated_at
    BEFORE UPDATE ON public.cases
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at();

-- 2. case_members テーブル
CREATE TABLE IF NOT EXISTS public.case_members (
    case_id UUID NOT NULL REFERENCES public.cases(case_id) ON DELETE CASCADE,
    member_id UUID NOT NULL DEFAULT gen_random_uuid(),
    role TEXT NOT NULL DEFAULT 'viewer'
        CHECK (role IN ('owner', 'editor', 'viewer')),
    display_name_encrypted TEXT,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ,
    PRIMARY KEY (case_id, member_id)
);

ALTER TABLE public.case_members ENABLE ROW LEVEL SECURITY;

-- anon は INSERT (参加) のみ
CREATE POLICY "anon can join case"
    ON public.case_members
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- anon は同じケースのメンバー一覧を SELECT 可能
CREATE POLICY "anon can read case members"
    ON public.case_members
    FOR SELECT
    TO anon
    USING (true);

-- owner はメンバーを DELETE 可能 (除名)
-- NOTE: MVP ではクライアント側で role チェックする。
-- 本番では Edge Function 経由で owner 認証後に DELETE する。

-- 3. case_data テーブル (暗号化済みスナップショット)
CREATE TABLE IF NOT EXISTS public.case_data (
    case_id UUID NOT NULL REFERENCES public.cases(case_id) ON DELETE CASCADE,
    member_id UUID NOT NULL,
    encrypted_snapshot TEXT NOT NULL,
    field_timestamps JSONB NOT NULL DEFAULT '{}',
    synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (case_id, member_id)
);

ALTER TABLE public.case_data ENABLE ROW LEVEL SECURITY;

-- anon は INSERT / UPDATE (UPSERT) 可能
CREATE POLICY "anon can write case data"
    ON public.case_data
    FOR INSERT
    TO anon
    WITH CHECK (true);

CREATE POLICY "anon can update case data"
    ON public.case_data
    FOR UPDATE
    TO anon
    USING (true);

-- anon は同じケースのデータを SELECT 可能
CREATE POLICY "anon can read case data"
    ON public.case_data
    FOR SELECT
    TO anon
    USING (true);

-- 4. インデックス
CREATE INDEX IF NOT EXISTS case_members_case_id_idx
    ON public.case_members (case_id);

CREATE INDEX IF NOT EXISTS case_data_case_id_idx
    ON public.case_data (case_id);

CREATE INDEX IF NOT EXISTS case_data_synced_at_idx
    ON public.case_data (synced_at DESC);

-- =========================================================
-- 動作確認
-- =========================================================
--
-- -- anon としてケース作成
-- SET ROLE anon;
-- INSERT INTO public.cases (case_id, encryption_key_check)
--     VALUES ('11111111-1111-1111-1111-111111111111', 'test_check');
--
-- -- anon としてメンバー追加
-- INSERT INTO public.case_members (case_id, member_id, role)
--     VALUES ('11111111-1111-1111-1111-111111111111',
--             '22222222-2222-2222-2222-222222222222', 'owner');
--
-- -- anon として同期データ書き込み
-- INSERT INTO public.case_data (case_id, member_id, encrypted_snapshot, field_timestamps)
--     VALUES ('11111111-1111-1111-1111-111111111111',
--             '22222222-2222-2222-2222-222222222222',
--             'encrypted_blob_here', '{"answers": "2026-04-10T00:00:00Z"}');
--
-- -- クリーンアップ
-- RESET ROLE;
-- DELETE FROM public.cases WHERE case_id = '11111111-1111-1111-1111-111111111111';
