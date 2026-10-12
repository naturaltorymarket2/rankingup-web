-- =================================================================
-- Phase 33: 어드민 회원 관리
--
-- 배경:
--   가입한 회원을 볼 방법이 어드민에 없었다. 기기 중복(DEVICE_ALREADY_
--   REGISTERED)이 나면 매번 SQL Editor 를 열어 device_id 를 지웠고,
--   테스트 계정을 정리할 방법도 없었다.
--
--   get_users          회원 목록·검색 (잔액·미션 수·인증 여부 포함)
--   admin_update_user  역할 변경 / 기기 초기화
--   admin_delete_user  계정 삭제 (딸린 기록까지)
--
-- 삭제 안전장치:
--   - 본인 계정은 지울 수 없다
--   - ADMIN 계정은 지울 수 없다 (운영자가 자기 권한을 잃는 사고 방지)
--   - 광고를 가진 계정은 막는다 — 광고를 먼저 삭제하게 한다
--     (campaigns 는 ON DELETE CASCADE 가 아니라 그냥 두면 실패한다)
-- =================================================================

-- =================================================================
-- 1. get_users — 목록 / 검색
-- =================================================================
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
      u.id,
      u.email,
      u.role,
      u.device_id,
      u.created_at,
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


-- =================================================================
-- 2. admin_update_user — 역할 변경 / 기기 초기화
-- =================================================================
CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_user_id      UUID,
  p_role         TEXT    DEFAULT NULL,
  p_clear_device BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target public.users%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT * INTO v_target FROM public.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF p_role IS NOT NULL THEN
    IF p_role NOT IN ('USER', 'ADVERTISER', 'ADMIN') THEN
      RETURN json_build_object('success', false, 'error', 'INVALID_ROLE');
    END IF;
    -- 마지막 남은 어드민의 권한을 내리면 아무도 관리 못 하게 된다
    IF v_target.role = 'ADMIN' AND p_role <> 'ADMIN'
       AND (SELECT COUNT(*) FROM public.users WHERE role = 'ADMIN') <= 1 THEN
      RETURN json_build_object('success', false, 'error', 'LAST_ADMIN');
    END IF;

    UPDATE public.users SET role = p_role, updated_at = NOW()
    WHERE id = p_user_id;
  END IF;

  -- 기기 초기화 — 같은 기기로 다시 시작할 수 있게 한다.
  -- (기기 중복 차단에 걸린 사용자를 풀어줄 때 쓴다)
  IF p_clear_device THEN
    UPDATE public.users SET device_id = NULL, updated_at = NOW()
    WHERE id = p_user_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$fn$;


-- =================================================================
-- 3. admin_delete_user — 계정 삭제
-- =================================================================
CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_target    public.users%ROWTYPE;
  v_campaigns INTEGER;
  v_missions  INTEGER;
  v_tx        INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  IF p_user_id = auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'CANNOT_DELETE_SELF');
  END IF;

  SELECT * INTO v_target FROM public.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_target.role = 'ADMIN' THEN
    RETURN json_build_object('success', false, 'error', 'CANNOT_DELETE_ADMIN');
  END IF;

  -- 광고가 남아 있으면 막는다. campaigns 는 CASCADE 가 아니라 삭제가
  -- 실패하고, 승인·과금 이력이 얽혀 있어 조용히 지우면 안 된다.
  SELECT COUNT(*) INTO v_campaigns FROM public.campaigns WHERE user_id = p_user_id;
  IF v_campaigns > 0 THEN
    RETURN json_build_object(
      'success', false, 'error', 'HAS_CAMPAIGNS', 'count', v_campaigns
    );
  END IF;

  SELECT COUNT(*) INTO v_missions FROM public.mission_logs  WHERE user_id = p_user_id;
  SELECT COUNT(*) INTO v_tx       FROM public.transactions  WHERE user_id = p_user_id;

  -- CASCADE 가 걸려 있지 않은 것부터 직접 지운다
  DELETE FROM public.mission_logs WHERE user_id = p_user_id;
  DELETE FROM public.transactions WHERE user_id = p_user_id;

  -- auth.users 를 지우면 public.users → wallets / business_info /
  -- mission_events 까지 CASCADE 로 함께 지워진다
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN json_build_object(
    'success',       true,
    'email',         v_target.email,
    'mission_count', v_missions,
    'tx_count',      v_tx
  );
END;
$fn$;


REVOKE ALL ON FUNCTION public.get_users(TEXT, INTEGER)                  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_update_user(UUID, TEXT, BOOLEAN)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_delete_user(UUID)                   FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_users(TEXT, INTEGER)               TO authenticated;
GRANT  EXECUTE ON FUNCTION public.admin_update_user(UUID, TEXT, BOOLEAN) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.admin_delete_user(UUID)                TO authenticated;
