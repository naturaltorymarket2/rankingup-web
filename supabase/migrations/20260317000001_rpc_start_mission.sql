-- =================================================================
-- RPC: start_mission(p_campaign_id, p_user_id, p_device_id)
-- 호출: 앱 유저 (B2C)
-- 역할: 미션 시작 + 정답 태그 랜덤 할당
--
-- 어뷰징 방지 (서버에서만 처리):
--   1. 호출자 = p_user_id 일치 검증
--   2. 동일 device_id 중복 계정 차단
--   3. 동일 유저 하루 1회 미션 제한 (캠페인별)
--   4. 캠페인 일일 슬롯 초과 차단
--   5. remaining_slots SELECT FOR UPDATE (동시성 제어)
--   6. 정답 태그 랜덤 할당 — tag_word 응답에 절대 포함 금지
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
AS $$
DECLARE
  v_log_id     UUID;
  v_started_at TIMESTAMPTZ;
  v_tag_id     UUID;
  v_campaign   public.campaigns%ROWTYPE;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 동일 device_id 중복 계정 차단 ────────────────────────
  --      같은 기기에서 다른 계정으로 참여 시도 차단
  IF EXISTS (
    SELECT 1 FROM public.users
    WHERE device_id = p_device_id
      AND id != p_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'DEVICE_ALREADY_REGISTERED');
  END IF;

  -- ── 3. 동일 유저 하루 1회 미션 제한 (캠페인별) ───────────────
  -- ⚠️ 테스트용 임시 비활성화 — 운영 전 반드시 주석 해제!
  -- IF EXISTS (
  --   SELECT 1 FROM public.mission_logs
  --   WHERE campaign_id = p_campaign_id
  --     AND user_id     = p_user_id
  --     AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
  --         = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
  --     AND status IN ('IN_PROGRESS', 'SUCCESS')
  -- ) THEN
  --   RETURN json_build_object('success', false, 'error', 'ALREADY_PARTICIPATED_TODAY');
  -- END IF;

  -- ── 4. 캠페인 유효성 + remaining_slots SELECT FOR UPDATE ─────
  SELECT * INTO v_campaign
  FROM public.campaigns
  WHERE id             = p_campaign_id
    AND status         = 'ACTIVE'
    AND expires_at     > NOW()
    AND remaining_slots > 0
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'CAMPAIGN_UNAVAILABLE');
  END IF;

  -- ── 5. 캠페인 일일 슬롯 초과 차단 ────────────────────────────
  IF (
    SELECT COUNT(*) FROM public.mission_logs
    WHERE campaign_id = p_campaign_id
      AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
          = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
      AND status IN ('IN_PROGRESS', 'SUCCESS')
  ) >= v_campaign.daily_target THEN
    RETURN json_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED');
  END IF;

  -- ── 6. remaining_slots 차감 ──────────────────────────────────
  UPDATE public.campaigns
  SET remaining_slots = remaining_slots - 1
  WHERE id = p_campaign_id;

  -- ── 7. 정답 태그 랜덤 할당 (tag_word 응답에 절대 포함 금지!) ──
  SELECT id INTO v_tag_id
  FROM public.campaign_tags
  WHERE campaign_id = p_campaign_id
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_tag_id IS NULL THEN
    -- 태그 없으면 슬롯 복구 후 오류 반환
    UPDATE public.campaigns
    SET remaining_slots = remaining_slots + 1
    WHERE id = p_campaign_id;
    RETURN json_build_object('success', false, 'error', 'NO_TAGS_AVAILABLE');
  END IF;

  -- ── 8. mission_log INSERT + started_at 회수 ──────────────────
  INSERT INTO public.mission_logs
    (campaign_id, user_id, device_id, assigned_tag_id, status, started_at)
  VALUES
    (p_campaign_id, p_user_id, p_device_id, v_tag_id, 'IN_PROGRESS', NOW())
  RETURNING id, started_at INTO v_log_id, v_started_at;

  -- ── 9. 성공 응답 ─────────────────────────────────────────────
  --      keyword + started_at 반환 | tag_word / assigned_tag_id 절대 포함 금지
  --      started_at: 클라이언트 타이머 기준값 (서버 UTC ISO 8601)
  RETURN json_build_object(
    'success',    true,
    'log_id',     v_log_id,
    'keyword',    v_campaign.keyword,
    'started_at', v_started_at
  );

END;
$$;
