-- =================================================================
-- Phase 31: 미션 도중 뒤로가기 → 재참여 불가 문제 해결
--
-- 증상 (2026-10-10 실제 발생):
--   유저가 미션을 시작했다가 뒤로가기로 빠져나오면, 같은 상품에
--   다시 들어갈 수 없다. 그날 하루 내내 막힌다.
--
--   이탈 로그가 그대로 보여 준다 (user 64568224):
--     10:40:11 VIEW_DETAIL
--     10:40:12 START        ← 미션 시작 (mission_logs = IN_PROGRESS)
--     10:40:12 LAUNCH_NAVER
--     10:40:21 VIEW_DETAIL  ← 돌아와서 다시 눌렀지만
--     (START 없음)           ← ALREADY_PARTICIPATED_TODAY 로 거부됨
--
-- 원인:
--   start_mission 의 하루 1회 검사가 status IN ('IN_PROGRESS','SUCCESS')
--   를 본다. 뒤로가기로 나오면 로그가 IN_PROGRESS 로 남으므로 본인이
--   자기 자신에게 막힌다. IN_PROGRESS 를 정리하는 expire_stale_missions
--   는 '날짜가 지난' 건만 손대므로 당일에는 풀리지 않는다.
--   (어제 미션 2건이 모두 TIMEOUT 으로 끝난 것도 같은 이유다)
--
-- 해결:
--   진행 중인 미션이 있으면 거부하지 말고 **그 미션을 이어서 준다**.
--     - 새 로그를 만들지 않는다 → 하루 1회 제한은 그대로다
--     - remaining_slots 를 다시 깎지 않는다 → 광고주 유입 수가 줄지 않는다
--     - 출제된 태그(assigned_tag_id)도 그대로 → "N번째 태그" 안내가 바뀌지 않는다
--   이미 성공(SUCCESS)한 경우에만 ALREADY_PARTICIPATED_TODAY 로 막는다.
--
-- 앱 수정 불필요:
--   응답 모양이 같아서(log_id / keyword / started_at / tag_index)
--   이미 배포된 앱(versionCode 39)에서 그대로 동작한다.
-- =================================================================

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
  v_open       RECORD;
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

  -- ── 4. 오늘 이미 성공한 상품이면 차단 (하루 1회) ─────────────
  IF EXISTS (
    SELECT 1 FROM public.mission_logs
    WHERE user_id = p_user_id
      AND status  = 'SUCCESS'
      AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
          = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
      AND (
        (v_group_id IS NOT NULL AND group_id    = v_group_id)
        OR
        (v_group_id IS NULL     AND campaign_id = p_campaign_id)
      )
  ) THEN
    RETURN json_build_object('success', false, 'error', 'ALREADY_PARTICIPATED_TODAY');
  END IF;

  -- ── 5. 진행 중인 미션이 있으면 '이어서' 준다 ─────────────────
  --      뒤로가기로 빠져나온 경우가 여기에 해당한다.
  --      새 로그·슬롯 차감 없이 기존 로그를 그대로 돌려준다.
  SELECT ml.id, ml.started_at, c.keyword, ct.sort_order
    INTO v_open
  FROM public.mission_logs ml
  JOIN public.campaigns    c  ON c.id  = ml.campaign_id
  LEFT JOIN public.campaign_tags ct ON ct.id = ml.assigned_tag_id
  WHERE ml.user_id = p_user_id
    AND ml.status  = 'IN_PROGRESS'
    AND (ml.started_at AT TIME ZONE 'Asia/Seoul')::DATE
        = (NOW()       AT TIME ZONE 'Asia/Seoul')::DATE
    AND (
      (v_group_id IS NOT NULL AND ml.group_id    = v_group_id)
      OR
      (v_group_id IS NULL     AND ml.campaign_id = p_campaign_id)
    )
  ORDER BY ml.started_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN json_build_object(
      'success',    true,
      'log_id',     v_open.id,
      'keyword',    v_open.keyword,
      'started_at', v_open.started_at,
      'tag_index',  v_open.sort_order,
      'resumed',    true          -- 앱은 무시한다 (참고용)
    );
  END IF;

  -- ── 6. 캠페인 유효성 + remaining_slots SELECT FOR UPDATE ─────
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

  -- ── 7. 캠페인 일일 슬롯 초과 차단 ────────────────────────────
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

  -- ── 8. remaining_slots 차감 ──────────────────────────────────
  UPDATE public.campaigns
  SET remaining_slots = remaining_slots - 1
  WHERE id = p_campaign_id;

  -- ── 9. 정답 태그 랜덤 할당 ───────────────────────────────────
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

  -- ── 10. mission_log INSERT ───────────────────────────────────
  INSERT INTO public.mission_logs
    (campaign_id, user_id, device_id, assigned_tag_id, status, started_at, group_id)
  VALUES
    (p_campaign_id, p_user_id, p_device_id, v_tag_id, 'IN_PROGRESS', NOW(), v_group_id)
  RETURNING id, started_at INTO v_log_id, v_started_at;

  -- ── 11. 성공 응답 ────────────────────────────────────────────
  RETURN json_build_object(
    'success',    true,
    'log_id',     v_log_id,
    'keyword',    v_campaign.keyword,
    'started_at', v_started_at,
    'tag_index',  v_tag_index,
    'resumed',    false
  );

END;
$fn$;
