-- =================================================================
-- Phase 28: 유입 분산(페이싱)
--
-- 배경:
--   승인된 광고가 한꺼번에 노출돼 유입이 몰린다. 짧은 기간에 몰아넣고
--   끊으면 순위가 반락하는 것이 실측으로 확인됐다(운영자 상품 3건).
--   광고주에게는 '유입 수'를 그대로 팔되, 언제 몇 명을 넣을지는
--   내부에서 곡선으로 설계한다.
--
-- 설계:
--   1) 승인 시 그룹별 '일자별 목표'를 만든다 (기본 3주, 주차별 70/20/10%)
--      1주차에 몰아서 순위를 끌어올리고, 이후는 유지에 필요한 만큼만 넣는다.
--   2) 하루 안에서도 운영 시간(09~22시)에 걸쳐 균등하게 푼다.
--      지금까지 허용된 누적치를 넘으면 그 광고는 잠시 노출되지 않는다.
--   3) 서버(start_mission)에서도 같은 기준으로 막는다 (클라이언트 우회 차단).
--
-- 판매 조건은 바뀌지 않는다. 총 유입 수는 그대로이고 소진 기간만 늘어난다.
-- =================================================================

-- ── 1. 일자별 목표 테이블 ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.campaign_pacing (
  group_id   UUID        NOT NULL,
  pace_date  DATE        NOT NULL,
  target     INTEGER     NOT NULL CHECK (target >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (group_id, pace_date)
);

-- 서버 함수(SECURITY DEFINER)로만 접근한다. 클라이언트 정책을 두지 않는다.
ALTER TABLE public.campaign_pacing ENABLE ROW LEVEL SECURITY;

-- ── 2. 설정값 한 곳 ─────────────────────────────────────────────
--     비율은 운영하면서 조정한다. 이 함수만 고치면 전체에 반영된다.
CREATE OR REPLACE FUNCTION public.pacing_config()
RETURNS TABLE (open_hour INTEGER, close_hour INTEGER, week_weights NUMERIC[])
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT 9, 22, ARRAY[0.70, 0.20, 0.10]::NUMERIC[];
$fn$;

-- ── 3. 승인 시 일자별 목표 생성 ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.build_campaign_pacing(p_group_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_cfg        RECORD;
  v_rep        RECORD;
  v_sold_days  INTEGER;
  v_total      INTEGER;
  v_base       DATE;
  v_week       INTEGER;
  v_week_total INTEGER;
  v_daily      INTEGER;
  v_remainder  INTEGER;
  v_day        INTEGER;
  v_target     INTEGER;
  v_last       DATE;
  v_rows       INTEGER := 0;
BEGIN
  -- 이미 만들어져 있으면 다시 만들지 않는다.
  -- (트리거가 그룹 내 캠페인 수만큼 호출되므로 첫 호출만 유효)
  IF EXISTS (SELECT 1 FROM public.campaign_pacing WHERE group_id = p_group_id) THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_cfg FROM public.pacing_config();

  -- 그룹 대표 캠페인 (등록 순서 기준 — 대시보드/크롤러와 동일한 기준)
  SELECT group_daily_target, start_date, end_date
    INTO v_rep
  FROM public.campaigns
  WHERE group_id = p_group_id
  ORDER BY created_at
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  -- 판매된 총 유입 수 = 일일 목표 × 판매 기간
  v_sold_days := GREATEST(1, (v_rep.end_date - v_rep.start_date) + 1);
  v_total     := COALESCE(v_rep.group_daily_target, 0) * v_sold_days;

  -- group_daily_target 이 없는 구 캠페인은 서브키워드 합으로 계산한다
  IF v_total <= 0 THEN
    SELECT COALESCE(SUM(daily_target), 0) * v_sold_days
      INTO v_total
    FROM public.campaigns
    WHERE group_id = p_group_id;
  END IF;

  IF v_total <= 0 THEN
    RETURN 0;
  END IF;

  -- 시작일이 지났으면 오늘부터 시작한다
  v_base := GREATEST(v_rep.start_date,
                     (NOW() AT TIME ZONE 'Asia/Seoul')::DATE);

  FOR v_week IN 1 .. array_length(v_cfg.week_weights, 1) LOOP
    v_week_total := ROUND(v_total * v_cfg.week_weights[v_week]);
    v_daily      := v_week_total / 7;
    v_remainder  := v_week_total - (v_daily * 7);

    FOR v_day IN 0 .. 6 LOOP
      -- 나머지는 주 초반에 붙인다 (앞쪽에 힘을 싣는 곡선)
      v_target := v_daily + (CASE WHEN v_day < v_remainder THEN 1 ELSE 0 END);

      INSERT INTO public.campaign_pacing (group_id, pace_date, target)
      VALUES (p_group_id, v_base + ((v_week - 1) * 7) + v_day, v_target)
      ON CONFLICT (group_id, pace_date) DO NOTHING;

      v_rows := v_rows + 1;
    END LOOP;
  END LOOP;

  -- 분산한 만큼 광고 기간을 늘린다 (총 유입 수는 그대로)
  v_last := v_base + (array_length(v_cfg.week_weights, 1) * 7) - 1;

  UPDATE public.campaigns
  SET end_date   = GREATEST(end_date, v_last),
      expires_at = GREATEST(
        expires_at,
        ((v_last + 1)::TIMESTAMP AT TIME ZONE 'Asia/Seoul')
      )
  WHERE group_id = p_group_id;

  RETURN v_rows;
END;
$fn$;

-- ── 4. 승인 트리거 ──────────────────────────────────────────────
--     approve_campaign 을 건드리지 않고 승인 시점에만 동작하게 한다.
CREATE OR REPLACE FUNCTION public.tg_build_campaign_pacing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NEW.approval_status = 'APPROVED'
     AND COALESCE(OLD.approval_status, '') <> 'APPROVED'
     AND NEW.group_id IS NOT NULL THEN
    PERFORM public.build_campaign_pacing(NEW.group_id);
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS campaigns_build_pacing ON public.campaigns;
CREATE TRIGGER campaigns_build_pacing
AFTER UPDATE ON public.campaigns
FOR EACH ROW
EXECUTE FUNCTION public.tg_build_campaign_pacing();

-- ── 5. 지금 이 시각까지 허용된 누적 유입 수 ─────────────────────
CREATE OR REPLACE FUNCTION public.pacing_allowed_now(p_group_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_cfg     RECORD;
  v_now     TIMESTAMP;
  v_target  INTEGER;
  v_now_min INTEGER;
  v_open    INTEGER;
  v_close   INTEGER;
  v_ratio   NUMERIC;
BEGIN
  IF p_group_id IS NULL THEN
    RETURN NULL;   -- 페이싱 대상이 아님 (구 캠페인)
  END IF;

  SELECT * INTO v_cfg FROM public.pacing_config();
  v_now := NOW() AT TIME ZONE 'Asia/Seoul';

  SELECT target INTO v_target
  FROM public.campaign_pacing
  WHERE group_id  = p_group_id
    AND pace_date = v_now::DATE;

  -- 오늘 배분이 없으면(기간 종료 등) 노출하지 않는다
  IF v_target IS NULL THEN
    RETURN 0;
  END IF;

  v_open    := v_cfg.open_hour  * 60;
  v_close   := v_cfg.close_hour * 60;
  v_now_min := EXTRACT(HOUR   FROM v_now)::INTEGER * 60
             + EXTRACT(MINUTE FROM v_now)::INTEGER;

  IF v_now_min <= v_open THEN
    v_ratio := 0;
  ELSIF v_now_min >= v_close THEN
    v_ratio := 1;
  ELSE
    v_ratio := (v_now_min - v_open)::NUMERIC / (v_close - v_open);
  END IF;

  RETURN CEIL(v_target * v_ratio)::INTEGER;
END;
$fn$;

-- ── 6. 오늘 그룹이 이미 사용한 수 ───────────────────────────────
CREATE OR REPLACE FUNCTION public.pacing_used_today(p_group_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT COUNT(*)::INTEGER
  FROM public.mission_logs
  WHERE group_id = p_group_id
    AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
        = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
    AND status IN ('IN_PROGRESS', 'SUCCESS');
$fn$;

-- ── 7. 지금 참여 가능한 그룹 목록 (앱 미션 보드용) ──────────────
CREATE OR REPLACE FUNCTION public.get_open_mission_groups()
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT COALESCE(json_agg(g.group_id), '[]'::JSON)
  FROM (
    SELECT DISTINCT c.group_id
    FROM public.campaigns c
    WHERE c.group_id        IS NOT NULL
      AND c.status          = 'ACTIVE'
      AND c.approval_status = 'APPROVED'
  ) g
  WHERE public.pacing_used_today(g.group_id) < public.pacing_allowed_now(g.group_id);
$fn$;

GRANT EXECUTE ON FUNCTION public.get_open_mission_groups() TO authenticated;

-- ── 8. start_mission — 페이싱 한도를 서버에서도 검사 ────────────
--     6번 단계(캠페인 일일 슬롯)를 그룹 페이싱 기준으로 교체한다.
--     나머지 로직은 migration 0041 과 동일하다.
CREATE OR REPLACE FUNCTION public.start_mission(
  p_campaign_id  UUID,
  p_user_id      UUID,
  p_device_id    TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_log_id     UUID;
  v_started_at TIMESTAMPTZ;
  v_tag_id     UUID;
  v_tag_index  INTEGER;
  v_campaign   public.campaigns%ROWTYPE;
  v_group_id   UUID;
  v_allowed    INTEGER;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 동일 device_id 중복 계정 차단 ────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.users
    WHERE device_id = p_device_id
      AND id != p_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'DEVICE_ALREADY_REGISTERED');
  END IF;

  -- ── 3. 대상 캠페인의 group_id 조회 ───────────────────────────
  SELECT group_id INTO v_group_id
  FROM public.campaigns
  WHERE id = p_campaign_id;

  -- ── 4. 그룹 기반 일일 참여 제한 (상품당 하루 1회) ───────────
  IF v_group_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.mission_logs
      WHERE group_id = v_group_id
        AND user_id  = p_user_id
        AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
            = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
        AND status IN ('IN_PROGRESS', 'SUCCESS')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_PARTICIPATED_TODAY');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.mission_logs
      WHERE campaign_id = p_campaign_id
        AND user_id     = p_user_id
        AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
            = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
        AND status IN ('IN_PROGRESS', 'SUCCESS')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_PARTICIPATED_TODAY');
    END IF;
  END IF;

  -- ── 5. 캠페인 유효성 + remaining_slots SELECT FOR UPDATE ─────
  SELECT * INTO v_campaign
  FROM public.campaigns
  WHERE id              = p_campaign_id
    AND status          = 'ACTIVE'
    AND approval_status = 'APPROVED'
    AND expires_at      > NOW()
    AND remaining_slots > 0
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'CAMPAIGN_UNAVAILABLE');
  END IF;

  -- ── 6. 페이싱 한도 검사 ──────────────────────────────────────
  --      그룹 단위로 '지금 시각까지 허용된 누적치'를 넘으면 차단한다.
  --      시간이 지나면 다시 열리므로 유입이 한꺼번에 몰리지 않는다.
  IF v_group_id IS NOT NULL THEN
    v_allowed := public.pacing_allowed_now(v_group_id);

    IF v_allowed IS NOT NULL
       AND public.pacing_used_today(v_group_id) >= v_allowed THEN
      RETURN json_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED');
    END IF;
  ELSE
    -- 구 캠페인(그룹 없음)은 기존 일일 목표 기준을 유지한다
    IF (
      SELECT COUNT(*) FROM public.mission_logs
      WHERE campaign_id = p_campaign_id
        AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
            = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
        AND status IN ('IN_PROGRESS', 'SUCCESS')
    ) >= v_campaign.daily_target THEN
      RETURN json_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED');
    END IF;
  END IF;

  -- ── 7. remaining_slots 차감 ──────────────────────────────────
  UPDATE public.campaigns
  SET remaining_slots = remaining_slots - 1
  WHERE id = p_campaign_id;

  -- ── 8. 정답 태그 랜덤 할당 ───────────────────────────────────
  --      tag_word 응답 포함 금지 — sort_order만 tag_index로 반환한다.
  SELECT id, sort_order INTO v_tag_id, v_tag_index
  FROM public.campaign_tags
  WHERE campaign_id = p_campaign_id
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_tag_id IS NULL THEN
    UPDATE public.campaigns
    SET remaining_slots = remaining_slots + 1
    WHERE id = p_campaign_id;
    RETURN json_build_object('success', false, 'error', 'NO_TAGS_AVAILABLE');
  END IF;

  -- ── 9. mission_log INSERT ────────────────────────────────────
  INSERT INTO public.mission_logs
    (campaign_id, user_id, device_id, assigned_tag_id, status, started_at, group_id)
  VALUES
    (p_campaign_id, p_user_id, p_device_id, v_tag_id, 'IN_PROGRESS', NOW(), v_group_id)
  RETURNING id, started_at INTO v_log_id, v_started_at;

  -- ── 10. 성공 응답 ────────────────────────────────────────────
  RETURN json_build_object(
    'success',    true,
    'log_id',     v_log_id,
    'keyword',    v_campaign.keyword,
    'started_at', v_started_at,
    'tag_index',  v_tag_index
  );

END;
$fn$;

-- ── 9. 이미 승인된 광고에도 배분표를 만들어 준다 ────────────────
DO $do$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT group_id
    FROM public.campaigns
    WHERE group_id        IS NOT NULL
      AND status          = 'ACTIVE'
      AND approval_status = 'APPROVED'
  LOOP
    PERFORM public.build_campaign_pacing(r.group_id);
  END LOOP;
END;
$do$;
