-- =================================================================
-- Phase 35: set_min_app_version 권한 구멍 수정 + 강제 업데이트 설정
--
-- 문제 (2026-10-12 실측):
--   0055 에서 만든 set_min_app_version 에 ADMIN 검증이 빠져 있었다.
--   SECURITY DEFINER 라 RLS 를 넘어서 실행되는데 authenticated 에게
--   EXECUTE 를 줬으므로, **로그인한 아무 앱 유저나** 최소 버전을
--   올려 전체 사용자의 앱을 잠글 수 있었다.
--   (일반 유저 세션으로 호출해 200 응답을 확인했다)
--
--   app_config 테이블 자체는 RLS 로 어드민만 쓰게 막아 뒀지만,
--   SECURITY DEFINER 함수는 그 RLS 를 통과한다 — 테이블만 막아서는
--   부족하고 함수 안에서 직접 확인해야 한다.
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
  -- 어드민만 바꿀 수 있다 (0055 에서 빠져 있던 검증)
  IF NOT public.is_admin() THEN
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


-- =================================================================
-- 강제 업데이트 켜기 — 46 미만은 업데이트 안내
--
--   46 이 프로덕션 전체 출시 완료(2026-10-12 14:08)된 것을 확인하고 켠다.
--   force = false 로 시작한다. 건너뛸 수 있어 혹시 스토어 반영이
--   늦은 기기가 있어도 앱을 못 쓰게 되지는 않는다.
--
--   하루 지켜본 뒤 완전히 막으려면:
--     SELECT public.set_min_app_version(46, true);
--   되돌리려면:
--     SELECT public.set_min_app_version(0, false);
--
--   주의: 42 이하에는 확인 코드 자체가 없어 이 안내가 뜨지 않는다.
--         (강제 업데이트는 43 부터 들어갔다)
-- =================================================================
SELECT public.set_min_app_version(
  46,
  FALSE,
  '새 버전이 나왔습니다. 업데이트 후 이용해 주세요.'
);
