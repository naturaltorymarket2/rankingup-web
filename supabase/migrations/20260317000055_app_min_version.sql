-- =================================================================
-- Phase 32: 앱 강제 업데이트 (최소 버전 지정)
--
-- 배경:
--   새 버전을 올려도 기기마다 Play 스토어에 뜨는 시점이 다르다.
--   몇 시간에서 며칠까지 차이가 나고, 어떤 기기는 사용자가 직접
--   스토어에 들어가야 보인다. 그동안 구버전 사용자는 고쳐진 버그를
--   계속 겪는다.
--
--   서버가 '최소 버전'을 들고 있으면, 앱이 켜질 때 스스로 확인해서
--   낮으면 업데이트 화면을 띄운다. 앱 배포를 기다릴 필요 없이
--   운영자가 값만 바꾸면 즉시 적용된다.
--
-- 값 바꾸는 법 (SQL Editor):
--   SELECT public.set_min_app_version(42, false);   -- 권장(건너뛰기 가능)
--   SELECT public.set_min_app_version(42, true);    -- 강제(건너뛰기 불가)
--   SELECT public.set_min_app_version(0,  false);   -- 해제
--
-- 주의:
--   값을 올리면 그보다 낮은 버전은 **즉시** 막힌다. 스토어에 새 버전이
--   실제로 올라가 내려받을 수 있는지 확인한 뒤에 올릴 것.
-- =================================================================

-- ── 1. 설정 보관 ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_config (
  key        TEXT PRIMARY KEY,
  value      JSONB       NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.app_config IS
  '앱이 읽어가는 운영 설정. 앱 배포 없이 바꿀 수 있는 값만 둔다.';

INSERT INTO public.app_config (key, value)
VALUES (
  'android_version',
  jsonb_build_object(
    -- 이 값보다 낮은 versionCode 는 업데이트 안내를 받는다. 0 이면 해제.
    'min_version_code', 0,
    -- true 면 건너뛸 수 없다(닫기 버튼 없음)
    'force',            false,
    'store_url',        'https://play.google.com/store/apps/details?id=com.storetrafficbooster.app',
    'message',          '새 버전이 나왔습니다. 업데이트 후 이용해 주세요.'
  )
)
ON CONFLICT (key) DO NOTHING;

-- ── 2. RLS — 누구나 읽고, 쓰기는 어드민만 ───────────────────────
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_config_read  ON public.app_config;
DROP POLICY IF EXISTS app_config_write ON public.app_config;

-- 로그인 전(스플래시)에도 확인해야 하므로 anon 도 읽을 수 있어야 한다.
CREATE POLICY app_config_read ON public.app_config
  FOR SELECT USING (true);

CREATE POLICY app_config_write ON public.app_config
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── 3. 운영자가 값을 바꾸는 함수 ────────────────────────────────
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
