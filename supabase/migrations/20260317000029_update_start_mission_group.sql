-- =================================================================
-- start_mission RPC: 그룹 기반 일일 중복 참여 체크
--
-- 변경 내용:
--   1. 일일 참여 제한 체크 기준 변경:
--      기존: (user_id, campaign_id, 오늘 날짜)
--      변경: campaigns에서 group_id 조회 → (user_id, group_id, 오늘 날짜)
--      효과: 서브키워드 A로 참여했으면 동일 그룹의 서브키워드 B도 당일 차단
--   2. mission_logs INSERT 시 group_id 컬럼 추가 저장
--      (추후 중복 체크 인덱스 활용)
--
-- 하위 호환:
--   group_id가 NULL인 캠페인(기존 데이터)은 campaign_id 기준 체크로 폴백.
--   단, migration 0027에서 기존 데이터에 모두 고유 group_id가 부여되면
--   폴백 분기는 사실상 미사용.
--
-- 일일 슬롯 체크 기준(step 5):
--   유지 — campaign별 daily_target 기준. 서브키워드 독립 관리.
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
  v_tag_index  INTEGER;
  v_campaign   public.campaigns%ROWTYPE;
  v_group_id   UUID;    -- 해당 캠페인의 그룹 식별자
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
  --      FOR UPDATE 잠금 전 별도 조회 (group_id는 불변값이므로 안전)
  SELECT group_id INTO v_group_id
  FROM public.campaigns
  WHERE id = p_campaign_id;

  -- ── 4. 그룹 기반 일일 참여 제한 ──────────────────────────────
  IF v_group_id IS NOT NULL THEN
    -- 신규: group_id 기준 — 동일 그룹의 다른 서브키워드 포함 차단
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
    -- 폴백: group_id NULL인 기존 캠페인은 campaign_id 기준 체크
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
  WHERE id             = p_campaign_id
    AND status         = 'ACTIVE'
    AND expires_at     > NOW()
    AND remaining_slots > 0
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'CAMPAIGN_UNAVAILABLE');
  END IF;

  -- ── 6. 캠페인 일일 슬롯 초과 차단 ────────────────────────────
  --      서브키워드별 daily_target 독립 관리 (그룹 합산 아님)
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

  -- ── 8. 정답 태그 할당 (is_answer=true 태그 선택) ──────────────
  --      tag_word 응답에 절대 포함 금지!
  --      sort_order를 tag_index로 반환 (유저 안내용)
  SELECT id, sort_order INTO v_tag_id, v_tag_index
  FROM public.campaign_tags
  WHERE campaign_id = p_campaign_id
    AND is_answer   = true
  LIMIT 1;

  IF v_tag_id IS NULL THEN
    -- 정답 태그 없으면 슬롯 복구 후 오류 반환
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

  -- ── 10. 성공 응답 ─────────────────────────────────────────────
  --       keyword + started_at + tag_index 반환
  --       tag_word / assigned_tag_id 절대 포함 금지
  RETURN json_build_object(
    'success',    true,
    'log_id',     v_log_id,
    'keyword',    v_campaign.keyword,
    'started_at', v_started_at,
    'tag_index',  v_tag_index
  );

END;
$$;
