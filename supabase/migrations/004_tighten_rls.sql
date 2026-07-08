-- =========================================================
-- ReliefNote: 003 の RLS を所有証明 (x-key-hash) ベースに強化
-- =========================================================
-- 背景: 003_family_sharing.sql は MVP として全アクセスを USING(true) で
-- 許可しており、case_id を知っていれば誰でも家族共有データを読めた。
-- 本マイグレーションは、クライアントが caseKey から導出した SHA-256
-- ハッシュを x-key-hash リクエストヘッダで送り、cases.key_hash と
-- 一致した場合のみ case_members / case_data へアクセスできるようにする。
--
-- 経過措置: 既存の cases 行は key_hash が NULL のままになる。
-- クライアントは初回アクセス時に UPDATE で key_hash を埋める。
-- バックフィル UPDATE は key_hash IS NULL の場合のみ許可される。

-- 1. cases に key_hash カラム追加
ALTER TABLE public.cases
    ADD COLUMN IF NOT EXISTS key_hash TEXT;

CREATE INDEX IF NOT EXISTS cases_key_hash_idx ON public.cases (key_hash);

-- 2. ヘッダ取得 / アクセス検証ヘルパー
CREATE OR REPLACE FUNCTION public._req_key_hash() RETURNS TEXT
    LANGUAGE sql STABLE AS $$
    SELECT current_setting('request.headers', true)::json->>'x-key-hash'
$$;

CREATE OR REPLACE FUNCTION public._has_case_access(target_case_id UUID) RETURNS BOOLEAN
    LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.cases
        WHERE case_id = target_case_id
          AND key_hash IS NOT NULL
          AND key_hash = public._req_key_hash()
    )
$$;

-- 3. cases ポリシーの差し替え
-- joinCase() は招待された側が encryption_key_check を取得する必要があるため、
-- SELECT は引き続き許可する。key_check は AES-GCM 暗号文で鍵を漏らさない。
DROP POLICY IF EXISTS "anon can read own case" ON public.cases;
CREATE POLICY "anon can lookup case for join"
    ON public.cases
    FOR SELECT
    TO anon
    USING (true);

-- 既存ケース (key_hash IS NULL) のバックフィルだけを許可する UPDATE
DROP POLICY IF EXISTS "anon can backfill key_hash" ON public.cases;
CREATE POLICY "anon can backfill key_hash"
    ON public.cases
    FOR UPDATE
    TO anon
    USING (key_hash IS NULL)
    WITH CHECK (key_hash IS NOT NULL);

-- 新規ケース作成時は key_hash 必須に格上げ
DROP POLICY IF EXISTS "anon can create case" ON public.cases;
CREATE POLICY "anon can create case"
    ON public.cases
    FOR INSERT
    TO anon
    WITH CHECK (key_hash IS NOT NULL);

-- 4. case_members ポリシー差し替え (所有証明必須)
DROP POLICY IF EXISTS "anon can read case members" ON public.case_members;
CREATE POLICY "members can read case members"
    ON public.case_members
    FOR SELECT
    TO anon
    USING (public._has_case_access(case_id));

DROP POLICY IF EXISTS "anon can join case" ON public.case_members;
CREATE POLICY "members can join case"
    ON public.case_members
    FOR INSERT
    TO anon
    WITH CHECK (public._has_case_access(case_id));

-- 5. case_data ポリシー差し替え (所有証明必須)
DROP POLICY IF EXISTS "anon can read case data" ON public.case_data;
CREATE POLICY "members can read case data"
    ON public.case_data
    FOR SELECT
    TO anon
    USING (public._has_case_access(case_id));

DROP POLICY IF EXISTS "anon can write case data" ON public.case_data;
CREATE POLICY "members can write case data"
    ON public.case_data
    FOR INSERT
    TO anon
    WITH CHECK (public._has_case_access(case_id));

DROP POLICY IF EXISTS "anon can update case data" ON public.case_data;
CREATE POLICY "members can update case data"
    ON public.case_data
    FOR UPDATE
    TO anon
    USING (public._has_case_access(case_id))
    WITH CHECK (public._has_case_access(case_id));

-- =========================================================
-- 動作確認
-- =========================================================
-- -- ヘッダ無しで case_data を SELECT → 0 件 (RLS で弾かれる)
-- SET ROLE anon;
-- SELECT * FROM public.case_data;
--
-- -- ヘッダ有り (PostgREST 経由想定) で SELECT
-- SELECT set_config('request.headers', '{"x-key-hash":"abc..."}', true);
-- SELECT * FROM public.case_data WHERE case_id = '...';
--
-- RESET ROLE;

-- =========================================================
-- ロールバック手順
-- =========================================================
-- 万が一クライアント側ロールアウトに失敗した場合、以下で 003 の状態に戻せる
--
-- DROP POLICY "members can read case members" ON public.case_members;
-- DROP POLICY "members can join case" ON public.case_members;
-- DROP POLICY "members can read case data" ON public.case_data;
-- DROP POLICY "members can write case data" ON public.case_data;
-- DROP POLICY "members can update case data" ON public.case_data;
-- DROP POLICY "anon can backfill key_hash" ON public.cases;
-- DROP POLICY "anon can create case" ON public.cases;
-- CREATE POLICY "anon can read case members" ON public.case_members FOR SELECT TO anon USING (true);
-- CREATE POLICY "anon can join case" ON public.case_members FOR INSERT TO anon WITH CHECK (true);
-- CREATE POLICY "anon can read case data" ON public.case_data FOR SELECT TO anon USING (true);
-- CREATE POLICY "anon can write case data" ON public.case_data FOR INSERT TO anon WITH CHECK (true);
-- CREATE POLICY "anon can update case data" ON public.case_data FOR UPDATE TO anon USING (true);
-- CREATE POLICY "anon can create case" ON public.cases FOR INSERT TO anon WITH CHECK (true);
