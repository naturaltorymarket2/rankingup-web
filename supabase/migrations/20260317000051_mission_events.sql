-- =================================================================
-- Phase 30: 미션 이탈 지점 측정
--
-- 배경:
--   지금은 '미션을 시작했다'와 '성공했다'만 안다. 시작하고 끝내지 않은
--   건이 어디서 멈췄는지 알 수 없어, 완주율이 낮게 나와도 원인을 못 찾는다.
--
--     미션을 눌러만 보고 나갔나?
--     네이버로 갔다가 안 돌아왔나?
--     돌아왔는데 태그를 못 찾아 포기했나?
--     오답을 내고 그만뒀나?
--
--   각 지점을 기록해 두면 어디를 고쳐야 하는지가 숫자로 드러난다.
--
-- 설계:
--   클라이언트가 직접 INSERT 하지 않고 RPC 를 통해서만 남긴다.
--   (user_id 를 auth.uid() 로 강제해 남의 이름으로 기록할 수 없게 한다)
--   조회는 어드민만 가능하다.
-- =================================================================

-- ── 1. 이벤트 테이블 ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mission_events (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  campaign_id UUID,
  log_id      UUID,
  step        TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS mission_events_created_idx
  ON public.mission_events (created_at DESC);
CREATE INDEX IF NOT EXISTS mission_events_step_idx
  ON public.mission_events (step, created_at DESC);
CREATE INDEX IF NOT EXISTS mission_events_log_idx
  ON public.mission_events (log_id);

-- 정책을 두지 않는다 = 클라이언트 직접 접근 불가.
-- 기록은 SECURITY DEFINER RPC, 조회는 어드민 RPC 로만 한다.
ALTER TABLE public.mission_events ENABLE ROW LEVEL SECURITY;

-- ── 2. 기록 RPC ────────────────────────────────────────────────
--     앱이 각 지점에서 호출한다. 실패해도 미션 진행에는 영향이 없도록
--     앱에서 결과를 기다리지 않고 오류도 무시한다.
CREATE OR REPLACE FUNCTION public.log_mission_event(
  p_step        TEXT,
  p_campaign_id UUID DEFAULT NULL,
  p_log_id      UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;   -- 비로그인 상태면 조용히 넘어간다
  END IF;

  -- 정해진 단계만 받는다. 오타나 임의 값으로 집계가 오염되지 않게 한다.
  IF p_step NOT IN (
    'VIEW_DETAIL',   -- 미션 상세 화면을 열었다
    'START',         -- 미션 시작(start_mission 성공)
    'LAUNCH_NAVER',  -- 네이버 앱으로 나갔다
    'RETURN_APP',    -- 앱으로 돌아와 태그 입력 화면을 봤다
    'SUBMIT',        -- 태그를 제출했다
    'WRONG_TAG',     -- 오답 판정을 받았다
    'SUCCESS'        -- 적립 완료
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.mission_events (user_id, campaign_id, log_id, step)
  VALUES (v_user_id, p_campaign_id, p_log_id, p_step);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.log_mission_event(TEXT, UUID, UUID) TO authenticated;

-- ── 3. 어드민 집계 RPC ──────────────────────────────────────────
--     최근 N일간 단계별 건수와 사람 수를 돌려준다.
CREATE OR REPLACE FUNCTION public.get_mission_funnel(p_days INTEGER DEFAULT 7)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_since TIMESTAMPTZ;
  v_rows  JSON;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  v_since := NOW() - (GREATEST(COALESCE(p_days, 7), 1) || ' days')::INTERVAL;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.sort_order), '[]'::JSON)
  INTO v_rows
  FROM (
    SELECT
      s.step,
      s.sort_order,
      COUNT(e.id)                        AS event_count,
      COUNT(DISTINCT e.log_id)           AS mission_count,
      COUNT(DISTINCT e.user_id)          AS user_count
    FROM (VALUES
      ('VIEW_DETAIL',  1),
      ('START',        2),
      ('LAUNCH_NAVER', 3),
      ('RETURN_APP',   4),
      ('SUBMIT',       5),
      ('SUCCESS',      6)
    ) AS s(step, sort_order)
    LEFT JOIN public.mission_events e
      ON e.step = s.step AND e.created_at >= v_since
    GROUP BY s.step, s.sort_order
  ) t;

  RETURN json_build_object(
    'success', true,
    'days',    GREATEST(COALESCE(p_days, 7), 1),
    'steps',   v_rows,
    -- 오답은 단계가 아니라 성격이 다른 지표라 따로 센다
    'wrong_tag_count', (
      SELECT COUNT(*) FROM public.mission_events
      WHERE step = 'WRONG_TAG' AND created_at >= v_since
    )
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.get_mission_funnel(INTEGER) TO authenticated;
