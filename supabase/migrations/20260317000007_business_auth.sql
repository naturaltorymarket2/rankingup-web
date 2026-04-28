-- =================================================================
-- business_info 스키마 보완 + 광고주 회원가입 RPC
--
-- 변경 사항:
--   1. business_info.owner_name → nullable (회원가입 폼에 미포함)
--   2. business_info.tax_email 컬럼 추가 (세금계산서 이메일, 선택)
--   3. business_info RLS 정책 추가 (SELECT / INSERT)
--   4. RPC register_advertiser — 사업자 정보 등록
--
-- 호출 순서 (클라이언트):
--   supabase.auth.signUp(email, password)   ← handle_new_user 트리거: users + wallets 생성
--   → supabase.rpc('register_advertiser')   ← business_info 생성
-- =================================================================

-- -----------------------------------------------------------------
-- 1. owner_name: NOT NULL 해제 (폼에서 수집하지 않으므로 NULL 허용)
-- -----------------------------------------------------------------
ALTER TABLE public.business_info
  ALTER COLUMN owner_name DROP NOT NULL;

-- -----------------------------------------------------------------
-- 2. tax_email: 세금계산서 수신 이메일 컬럼 추가 (선택)
-- -----------------------------------------------------------------
ALTER TABLE public.business_info
  ADD COLUMN IF NOT EXISTS tax_email TEXT;

-- -----------------------------------------------------------------
-- 3. business_info RLS 정책
--    (기존 스키마에 누락 — 광고주가 본인 정보를 조회/등록 가능하도록)
-- -----------------------------------------------------------------
CREATE POLICY business_info_self_select ON public.business_info
  FOR SELECT USING (auth.uid() = user_id);

-- INSERT는 RPC(SECURITY DEFINER)에서만 실행되므로 별도 정책 불필요
-- (SECURITY DEFINER 함수는 RLS를 우회하여 직접 INSERT 수행)

-- -----------------------------------------------------------------
-- 4. RPC: register_advertiser
--    호출: 광고주 회원가입 직후 (세션 확보 후)
--    역할: business_info 레코드 생성
--
--    ⚠ Supabase 프로젝트 설정 권장:
--      Authentication → Providers → Email →
--      "Confirm email" 비활성화 시 회원가입과 동시에 세션 발급되어
--      즉시 RPC 호출 가능. 활성화 시 이메일 인증 후 로그인 필요.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_advertiser(
  p_company_name    TEXT,
  p_business_number TEXT,
  p_phone           TEXT,
  p_tax_email       TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN

  -- ── 인증 확인 ───────────────────────────────────────────────
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- ── 파라미터 유효성 검증 ────────────────────────────────────
  IF TRIM(p_company_name) = '' OR TRIM(p_business_number) = '' OR TRIM(p_phone) = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  -- ── business_info 등록 ─────────────────────────────────────
  INSERT INTO public.business_info (
    user_id,
    company_name,
    business_number,
    phone,
    tax_email
  ) VALUES (
    v_user_id,
    TRIM(p_company_name),
    TRIM(p_business_number),
    TRIM(p_phone),
    NULLIF(TRIM(COALESCE(p_tax_email, '')), '')
  );

  RETURN json_build_object('success', true);

EXCEPTION
  WHEN unique_violation THEN
    -- 동일 user_id로 이미 business_info가 존재하는 경우
    RETURN json_build_object('success', false, 'error', 'ALREADY_REGISTERED');
  WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;
