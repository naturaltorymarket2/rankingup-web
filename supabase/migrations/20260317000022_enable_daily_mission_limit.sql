-- =================================================================
-- start_mission: 일일 참여 제한 활성화
--
-- 배경:
--   migration 0001 및 0019에서 step 3 (동일 유저 하루 1회 미션 제한)이
--   테스트용으로 주석 처리되어 있음.
--   → 동일 유저가 같은 캠페인에 하루 여러 번 참여 가능 → 어뷰징 허용 상태
--
-- 수정:
--   step 3 주석 해제 → 일일 참여 제한 활성화
--   그 외 모든 로직은 migration 0019와 동일
--     (is_answer=true 태그 선택 + tag_index 응답 포함)
--
-- 전제 조건:
--   campaign_tags.is_answer, sort_order 컬럼 필요 (migration 0019에서 추가)
--   이 migration에서 IF NOT EXISTS로 안전하게 보장
-- =================================================================

-- Prerequisite: campaign_tags 컬럼 보장 (migration 0019 미적용 대비)
ALTER TABLE public.campaign_tags
  ADD COLUMN IF NOT EXISTS is_answer  BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;


-- =================================================================
-- start_mission RPC (일일 참여 제한 활성화 버전)
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
  v_tag_index  INTEGER;  -- 정답 태그 순서 (sort_order, 1-based)
  v_campaign   public.campaigns%ROWTYPE;
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

  -- ── 3. 동일 유저 하루 1회 미션 제한 (캠페인별) — 활성화 ──────
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

  -- ── 7. 정답 태그 할당 (is_answer=true 태그 선택) ──────────────
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

  -- ── 8. mission_log INSERT + started_at 회수 ──────────────────
  INSERT INTO public.mission_logs
    (campaign_id, user_id, device_id, assigned_tag_id, status, started_at)
  VALUES
    (p_campaign_id, p_user_id, p_device_id, v_tag_id, 'IN_PROGRESS', NOW())
  RETURNING id, started_at INTO v_log_id, v_started_at;

  -- ── 9. 성공 응답 ─────────────────────────────────────────────
  --      keyword + started_at + tag_index 반환
  --      tag_word / assigned_tag_id 절대 포함 금지
  RETURN json_build_object(
    'success',    true,
    'log_id',     v_log_id,
    'keyword',    v_campaign.keyword,
    'started_at', v_started_at,
    'tag_index',  v_tag_index
  );

END;
$$;
