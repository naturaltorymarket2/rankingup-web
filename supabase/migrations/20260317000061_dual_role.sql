-- =================================================================
-- Phase 37: 광고주 ↔ 앱 유저 겸업 허용 (자동 승격 제거)
--
-- 문제:
--   계정 종류를 users.role 하나로 배타적으로 다뤘다(USER / ADVERTISER).
--   그런데 **광고주가 리워드 유저이기도 할 수 있다** — 실제로 운영자
--   본인 계정이 그렇다.
--
--   게다가 /web/login 에 로그인하면 role 을 ADVERTISER 로 '확정'했다.
--   오래된 계정(가입 경로 표시가 없는)은 그대로 승격돼, 앱 유저가
--   광고주 웹에 한 번 들어갔다는 이유로 **앱 로그인이 막혔다**.
--   실제 발생: naturaltorymarket@gmail.com (미션 기록·21P 보유).
--
--   실데이터 확인 — role=ADVERTISER 8건 중 광고 활동이 있는 계정은 2건뿐.
--   나머지 6건은 로그인만으로 승격된 것이다.
--
-- 바꾸는 것:
--   role          : USER / ADMIN  (앱·어드민 권한)
--   is_advertiser : 광고주 웹 접근 가능 여부 (겸업 가능)
--
--   두 값이 독립이라 '광고주이면서 앱 유저'가 자연스럽게 표현된다.
--   승격은 가입(또는 운영자 지정)으로만 일어난다 — 로그인은 아무것도 바꾸지 않는다.
-- =================================================================

-- ── 1. 컬럼 추가 ────────────────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_advertiser BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.users.is_advertiser IS
  '광고주 웹(/web/*) 접근 가능 여부. role 과 독립이라 앱 유저 겸업이 가능하다.';

-- ── 2. 기존 데이터 이관 ─────────────────────────────────────────
--     지금 광고주로 쓰고 있던 계정은 접근을 유지한다.
UPDATE public.users
   SET is_advertiser = TRUE
 WHERE role = 'ADVERTISER'
    OR id IN (SELECT user_id FROM public.business_info)
    OR id IN (SELECT DISTINCT user_id FROM public.campaigns);

--     role 은 USER / ADMIN 만 쓴다. ADVERTISER 였던 계정은 USER 로 내린다.
--     (is_advertiser 로 웹 접근은 유지되고, 이제 앱도 쓸 수 있다)
UPDATE public.users
   SET role = 'USER'
 WHERE role = 'ADVERTISER';

-- ── 3. register_advertiser — role 대신 플래그를 세운다 ──────────
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
AS $fn$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  INSERT INTO public.business_info
    (user_id, company_name, business_number, phone, tax_email)
  VALUES
    (v_user_id, p_company_name, p_business_number, p_phone, p_tax_email)
  ON CONFLICT (user_id) DO UPDATE
    SET company_name    = EXCLUDED.company_name,
        business_number = EXCLUDED.business_number,
        phone           = EXCLUDED.phone,
        tax_email       = EXCLUDED.tax_email;

  -- 광고주 자격만 켠다. role 은 건드리지 않는다(앱 유저 겸업 가능).
  UPDATE public.users
     SET is_advertiser = TRUE, updated_at = NOW()
   WHERE id = v_user_id;

  RETURN json_build_object('success', true);
END;
$fn$;

-- ── 4. 광고주 자격 켜기 (웹 가입이 끝난 시점에 본인이 호출) ─────
CREATE OR REPLACE FUNCTION public.mark_self_advertiser()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  UPDATE public.users
     SET is_advertiser = TRUE, updated_at = NOW()
   WHERE id = v_user_id;

  RETURN json_build_object('success', true);
END;
$fn$;

REVOKE ALL ON FUNCTION public.mark_self_advertiser() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_self_advertiser() TO authenticated;

-- ── 5. 어드민 회원 관리 — 광고주 자격 켜고 끄기 ─────────────────
CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_user_id       UUID,
  p_role          TEXT    DEFAULT NULL,
  p_clear_device  BOOLEAN DEFAULT FALSE,
  p_is_advertiser BOOLEAN DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target public.users%ROWTYPE;
BEGIN
  IF NOT public.is_admin()
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT * INTO v_target FROM public.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF p_role IS NOT NULL THEN
    IF p_role NOT IN ('USER', 'ADMIN') THEN
      RETURN json_build_object('success', false, 'error', 'INVALID_ROLE');
    END IF;
    IF v_target.role = 'ADMIN' AND p_role <> 'ADMIN'
       AND (SELECT COUNT(*) FROM public.users WHERE role = 'ADMIN') <= 1 THEN
      RETURN json_build_object('success', false, 'error', 'LAST_ADMIN');
    END IF;

    UPDATE public.users SET role = p_role, updated_at = NOW()
    WHERE id = p_user_id;
  END IF;

  IF p_is_advertiser IS NOT NULL THEN
    UPDATE public.users
       SET is_advertiser = p_is_advertiser, updated_at = NOW()
     WHERE id = p_user_id;
  END IF;

  IF p_clear_device THEN
    UPDATE public.users SET device_id = NULL, updated_at = NOW()
    WHERE id = p_user_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_update_user(UUID, TEXT, BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_update_user(UUID, TEXT, BOOLEAN, BOOLEAN) TO authenticated;

-- 인자 3개짜리 구버전은 지운다 (오버로드 모호성 방지)
DROP FUNCTION IF EXISTS public.admin_update_user(UUID, TEXT, BOOLEAN);

-- ── 6. 회원 목록에 광고주 여부 포함 ─────────────────────────────
CREATE OR REPLACE FUNCTION public.get_users(
  p_search TEXT    DEFAULT NULL,
  p_limit  INTEGER DEFAULT 50
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rows JSON;
  v_q    TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  v_q := NULLIF(TRIM(COALESCE(p_search, '')), '');

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::JSON)
  INTO v_rows
  FROM (
    SELECT
      u.id, u.email, u.role, u.device_id, u.created_at,
      u.is_advertiser,
      (au.email_confirmed_at IS NOT NULL)            AS email_confirmed,
      au.last_sign_in_at,
      COALESCE(w.balance, 0)                         AS balance,
      (SELECT COUNT(*) FROM public.mission_logs ml
        WHERE ml.user_id = u.id AND ml.status = 'SUCCESS')   AS success_count,
      (SELECT COUNT(*) FROM public.mission_logs ml
        WHERE ml.user_id = u.id)                             AS mission_count,
      (SELECT COUNT(*) FROM public.campaigns c
        WHERE c.user_id = u.id)                              AS campaign_count
    FROM public.users u
    LEFT JOIN auth.users     au ON au.id = u.id
    LEFT JOIN public.wallets w  ON w.user_id = u.id
    WHERE v_q IS NULL
       OR u.email ILIKE '%' || v_q || '%'
       OR u.device_id ILIKE '%' || v_q || '%'
    ORDER BY u.created_at DESC
    LIMIT GREATEST(LEAST(p_limit, 200), 1)
  ) t;

  RETURN json_build_object('success', true, 'users', v_rows);
END;
$fn$;
