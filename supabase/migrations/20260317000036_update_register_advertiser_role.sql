-- =================================================================
-- register_advertiser RPC — 사업자 등록 완료 시 role을 ADVERTISER로 고정
--
-- 변경: business_info INSERT 직후, 같은 함수(=같은 트랜잭션) 내에서
-- public.users.role을 'ADVERTISER'로 UPDATE한다. 둘 중 하나라도 실패하면
-- 전체가 롤백되어 "사업자정보는 등록됐는데 role은 USER로 남는" 불일치를
-- 방지한다. 그 외 로직(인증/파라미터 검증/예외 처리)은 migration 0007과 동일.
--
-- 전제: migration 0035에서 role CHECK 제약에 ADVERTISER가 추가되어 있어야 함.
-- =================================================================

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

  -- ── 계정 타입 확정 (사업자 등록 완료 = ADVERTISER) ───────────
  --    business_info INSERT와 같은 트랜잭션 — 함께 커밋/롤백됨
  UPDATE public.users SET role = 'ADVERTISER' WHERE id = v_user_id;

  RETURN json_build_object('success', true);

EXCEPTION
  WHEN unique_violation THEN
    -- 동일 user_id로 이미 business_info가 존재하는 경우
    RETURN json_build_object('success', false, 'error', 'ALREADY_REGISTERED');
  WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;
