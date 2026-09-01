-- =================================================================
-- Phase 28 되돌리기: 유입 분산(페이싱) 제거
--
-- 배경:
--   0048 에서 승인 시 3주(70/20/10%)로 유입을 나누고 하루 안에서도
--   시간대별로 풀도록 했으나, 운영 방침상 되돌린다.
--   광고주가 구매한 일일 유입 수는 당일에 그대로 소진될 수 있어야 한다.
--
--   노출 순서 랜덤화(앱)는 유지한다 — 상단 광고 쏠림만 막는 것이라
--   유입량 자체에는 영향이 없다.
--
-- 되돌리는 것:
--   - campaign_pacing 테이블 및 관련 함수/트리거
--   - start_mission 의 페이싱 검사 → 캠페인 일일 목표(daily_target) 검사
--
-- 되돌리지 않는 것:
--   - 0048 이 늘려 둔 end_date / expires_at
--     되돌릴 원본 값을 남겨두지 않았고, 기간이 남아 있어도 remaining_slots
--     가 소진되면 광고는 종료된다. 판매한 유입 수에는 영향이 없다.
-- =================================================================

-- ── 1. 승인 트리거 제거 ─────────────────────────────────────────
DROP TRIGGER  IF EXISTS campaigns_build_pacing ON public.campaigns;
DROP FUNCTION IF EXISTS public.tg_build_campaign_pacing();

-- ── 2. start_mission — 일일 목표 검사로 원복 (migration 0041 기준) ──
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

  -- ── 6. 캠페인 일일 슬롯 초과 차단 ────────────────────────────
  --      구매한 일일 유입 수는 당일에 그대로 소진될 수 있다.
  IF (
    SELECT COUNT(*) FROM public.mission_logs
    WHERE campaign_id = p_campaign_id
      AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
          = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
      AND status IN ('IN_PROGRESS', 'SUCCESS')
  ) >= v_campaign.daily_target THEN
    RETURN json_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED');
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

-- ── 3. 페이싱 함수·테이블 제거 ──────────────────────────────────
DROP FUNCTION IF EXISTS public.get_open_mission_groups();
DROP FUNCTION IF EXISTS public.pacing_allowed_now(UUID);
DROP FUNCTION IF EXISTS public.pacing_used_today(UUID);
DROP FUNCTION IF EXISTS public.build_campaign_pacing(UUID);
DROP FUNCTION IF EXISTS public.pacing_config();
DROP TABLE    IF EXISTS public.campaign_pacing;
