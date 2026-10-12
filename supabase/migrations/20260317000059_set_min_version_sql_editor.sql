-- =================================================================
-- Phase 35-1: set_min_app_version — SQL Editor 에서도 쓸 수 있게
--
-- 0058 에서 ADMIN 검증을 넣자 SQL Editor 에서도 FORBIDDEN 이 났다.
-- SQL Editor 는 로그인 세션이 아니라 auth.uid() 가 NULL 이고,
-- is_admin() 은 그 값으로 판단하기 때문이다.
--
-- 구분 방법:
--   session_user 는 SECURITY DEFINER 안에서도 '실제 접속한 역할'이
--   그대로 남는다 (current_user 는 함수 소유자로 바뀌므로 쓰면 안 된다).
--     SQL Editor  → postgres / supabase_admin
--     앱·웹(PostgREST) → authenticator
--
--   그래서 앱에서 온 호출은 기존대로 ADMIN 만 통과하고,
--   SQL Editor 는 운영자 콘솔이므로 허용한다.
-- =================================================================

CREATE OR REPLACE FUNCTION public.set_min_app_version(
  p_min_version_code INTEGER,
  p_force            BOOLEAN DEFAULT FALSE,
  p_message          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_value JSONB;
BEGIN
  -- 앱·웹에서 온 호출은 ADMIN 만. SQL Editor(운영자 콘솔)는 허용.
  IF NOT public.is_admin()
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT value INTO v_value FROM public.app_config WHERE key = 'android_version';

  v_value := COALESCE(v_value, '{}'::JSONB)
    || jsonb_build_object(
         'min_version_code', GREATEST(p_min_version_code, 0),
         'force',            p_force
       );

  IF p_message IS NOT NULL AND TRIM(p_message) <> '' THEN
    v_value := v_value || jsonb_build_object('message', p_message);
  END IF;

  INSERT INTO public.app_config (key, value, updated_at)
  VALUES ('android_version', v_value, NOW())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = NOW();

  RETURN v_value;
END;
$fn$;

REVOKE ALL ON FUNCTION public.set_min_app_version(INTEGER, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_min_app_version(INTEGER, BOOLEAN, TEXT) TO authenticated;


-- ── 강제 업데이트 켜기 — 46 미만은 업데이트 안내 ────────────────
--    force = false (건너뛰기 가능). 완전히 막으려면 true 로 다시 실행.
SELECT public.set_min_app_version(
  46,
  FALSE,
  '새 버전이 나왔습니다. 업데이트 후 이용해 주세요.'
);

-- 적용 결과 확인
SELECT value FROM public.app_config WHERE key = 'android_version';
