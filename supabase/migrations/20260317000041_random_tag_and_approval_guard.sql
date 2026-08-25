-- =================================================================
-- Phase 22: 랜덤 정답 태그 출제 + 승인 캠페인만 미션 허용
--
-- 변경 내용:
--   1. start_mission
--      - 캠페인 유효성 조건에 approval_status = 'APPROVED' 추가
--        (승인 전 캠페인은 어떤 경로로도 미션 시작 불가)
--      - 정답 태그 선택: is_answer=true 고정 1건 → 등록된 태그 중 ORDER BY RANDOM() 1건
--        → 매 미션마다 "몇 번째 태그"가 랜덤으로 출제된다.
--   2. verify_mission
--      - 제출 태그 비교를 normalize_tag() 기준으로 통일
--        (앱 유저가 '#'을 붙여 입력하거나 공백을 섞어도 정상 매칭)
--
-- 응답 규약 유지:
--   tag_word / assigned_tag_id 는 절대 응답에 포함하지 않는다.
--   유저에게는 tag_index(sort_order)만 전달된다.
-- =================================================================

-- ── 1. start_mission ────────────────────────────────────────────
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

  -- ── 4. 그룹 기반 일일 참여 제한 ──────────────────────────────
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
  --      승인 완료(APPROVED) 캠페인만 미션 시작 가능
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
  --      어드민이 등록한 태그 풀에서 매번 무작위로 1개 선택.
  --      tag_word 응답 포함 금지 — sort_order만 tag_index로 반환.
  SELECT id, sort_order INTO v_tag_id, v_tag_index
  FROM public.campaign_tags
  WHERE campaign_id = p_campaign_id
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_tag_id IS NULL THEN
    -- 태그가 없으면 슬롯 복구 후 오류 반환 (승인 절차상 발생하지 않아야 정상)
    UPDATE public.campaigns
    SET remaining_slots = remaining_slots + 1
    WHERE id = p_campaign_id;
    RETURN json_build_object('success', false, 'error', 'NO_TAGS_AVAILABLE');
  END IF;

  -- ── 9. mission_log INSERT (group_id 포함) ────────────────────
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
$$;


-- ── 2. verify_mission — 태그 비교를 normalize_tag 기준으로 통일 ──
CREATE OR REPLACE FUNCTION public.verify_mission(
  p_log_id        UUID,
  p_user_id       UUID,
  p_submitted_tag TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log       mission_logs%ROWTYPE;
  v_tag_word  TEXT;
  v_reward    INTEGER := 7;
  v_wallet_id UUID;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  SELECT * INTO v_log FROM public.mission_logs
    WHERE id = p_log_id AND user_id = p_user_id AND status = 'IN_PROGRESS'
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  -- 10분 타임아웃 블록 없음 (migration 0034에서 의도적으로 제거)

  SELECT tag_word INTO v_tag_word FROM public.campaign_tags
    WHERE id = v_log.assigned_tag_id;

  IF v_tag_word IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  -- '#' / 공백 / 대소문자 차이를 무시하고 비교
  IF public.normalize_tag(p_submitted_tag) <> public.normalize_tag(v_tag_word) THEN
    RETURN json_build_object('success', false, 'error', 'WRONG_TAG');
  END IF;

  SELECT id INTO v_wallet_id FROM public.wallets
    WHERE user_id = p_user_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  UPDATE public.wallets
    SET balance = balance + v_reward, updated_at = NOW()
    WHERE id = v_wallet_id;

  INSERT INTO public.transactions (user_id, type, amount, status, description)
    VALUES (p_user_id, 'EARN', v_reward, 'COMPLETED', '미션 성공 리워드');

  UPDATE public.mission_logs
    SET status = 'SUCCESS', completed_at = NOW()
    WHERE id = p_log_id;

  RETURN json_build_object('success', true, 'earned', v_reward);
END;
$$;
