-- =================================================================
-- Phase 36: 어드민 임시 비밀번호 발급
--
-- 배경:
--   "회원 비밀번호를 어드민에서 보여 달라"는 요청이 있었다.
--   불가능하다 — 비밀번호는 복호화할 수 없는 해시로만 저장되고
--   원문은 어디에도 남지 않는다(Supabase/GoTrue 설계).
--
--   필요한 것은 '비밀번호를 아는 것'이 아니라 **즉시 접속하게 해 주는 것**이다.
--   메일을 받지 못하는 상황(테스트 계정, 메일 접근 불가)에서 운영자가
--   임시 비밀번호를 발급해 알려주면 같은 목적이 해결된다.
--
-- 동작:
--   auth.users.encrypted_password 를 bcrypt 해시로 덮어쓴다.
--   GoTrue 가 쓰는 방식과 같아 즉시 로그인된다.
--
-- 주의:
--   - 발급 시점에 기존 비밀번호는 무효가 된다
--   - 평문은 저장하지 않는다. 화면에 한 번 보여줄 뿐이다
--   - 사용자가 로그인한 뒤 비밀번호 찾기로 본인 것을 다시 정하게 안내한다
-- =================================================================

CREATE OR REPLACE FUNCTION public.admin_set_temp_password(
  p_user_id  UUID,
  p_password TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
-- crypt() / gen_salt() 는 extensions 스키마의 pgcrypto 에 있다
SET search_path = public, extensions
AS $fn$
DECLARE
  v_email TEXT;
BEGIN
  -- 앱·웹에서 온 호출은 ADMIN 만. SQL Editor(운영자 콘솔)는 허용.
  IF NOT public.is_admin()
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  IF p_password IS NULL OR char_length(p_password) < 6 THEN
    RETURN json_build_object('success', false, 'error', 'PASSWORD_TOO_SHORT');
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  UPDATE auth.users
     SET encrypted_password = crypt(p_password, gen_salt('bf')),
         updated_at         = NOW()
   WHERE id = p_user_id;

  RETURN json_build_object('success', true, 'email', v_email);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_set_temp_password(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_set_temp_password(UUID, TEXT) TO authenticated;
