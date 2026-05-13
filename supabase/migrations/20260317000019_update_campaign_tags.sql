-- =================================================================
-- campaign_tags: is_answer + sort_order 컬럼 추가
-- register_campaign RPC: p_answer_index 추가, 태그 2개 이상 필수
-- start_mission RPC: is_answer=true 태그 할당 + tag_index 반환
--
-- 배경:
--   태그 자동 크롤링 방식을 폐기하고 광고주가 직접 태그를 입력하는 방식으로 변경.
--   광고주가 정답 태그를 지정하면 (is_answer=true),
--   미션 시작 시 유저에게 "N번째 태그를 입력하세요" 안내를 제공.
--
-- 변경 사항:
--   1. campaign_tags.is_answer BOOLEAN (정답 태그 여부)
--   2. campaign_tags.sort_order INTEGER (태그 입력 순서, 1-based)
--   3. register_campaign RPC:
--      - p_answer_index INT 파라미터 추가 (정답 태그 위치, 1-based)
--      - 태그 2개 이상 필수 (기존 1개 → 2개 이상)
--      - sort_order, is_answer 컬럼 INSERT 포함
--   4. start_mission RPC:
--      - RANDOM() 대신 is_answer=true 태그 선택
--      - 응답에 tag_index (sort_order 값) 포함
-- =================================================================

-- ── 1. campaign_tags 컬럼 추가 ──────────────────────────────────
ALTER TABLE public.campaign_tags
  ADD COLUMN IF NOT EXISTS is_answer  BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;


-- ── 2. register_campaign RPC 업데이트 ────────────────────────────
--      현재 최신 버전 (migration 0009 + 0018 통합):
--        p_start_date / p_end_date 기반 기간 계산
--        p_seed_keyword 순위 추적용 시드 키워드
--      이번 추가:
--        p_answer_index 정답 태그 인덱스 (1-based)
-- =================================================================
CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id       UUID,
  p_product_url   TEXT,
  p_keyword       TEXT,
  p_daily_target  INTEGER,
  p_start_date    DATE,
  p_end_date      DATE,
  p_tags          TEXT[],
  p_answer_index  INTEGER,           -- 정답 태그 인덱스 (1-based, 필수)
  p_seed_keyword  TEXT DEFAULT NULL  -- 시드 키워드 (순위 추적용, NULL이면 p_keyword 사용)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_duration_days INTEGER;
  v_budget        INTEGER;
  v_wallet_id     UUID;
  v_campaign_id   UUID;
  v_tag           TEXT;
  v_tag_idx       INTEGER := 0;
  v_seed_keyword  TEXT;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 파라미터 유효성 검증 ──────────────────────────────────
  IF p_daily_target <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_product_url = '' OR p_keyword = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  -- 태그 2개 이상 필수
  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 2 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;

  -- 정답 인덱스 범위 검증 (1 ≤ p_answer_index ≤ 태그 수)
  IF p_answer_index IS NULL
  OR p_answer_index < 1
  OR p_answer_index > array_length(p_tags, 1) THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_ANSWER_INDEX');
  END IF;

  -- ── 3. 기간 계산 및 최소 7일 검증 ────────────────────────────
  v_duration_days := p_end_date - p_start_date + 1;

  IF v_duration_days < 7 THEN
    RETURN json_build_object(
      'success', false,
      'error',   'DURATION_TOO_SHORT',
      'minimum', 7
    );
  END IF;

  -- seed_keyword: 빈 문자열이면 NULL 저장 (하위 호환)
  v_seed_keyword := NULLIF(TRIM(COALESCE(p_seed_keyword, '')), '');

  -- ── 4. 예산 계산: 일일 유입 × 기간(일) × 50원 ───────────────
  v_budget := p_daily_target * v_duration_days * 50;

  -- ── 5. 잔액 확인 + 지갑 잠금 (SELECT FOR UPDATE) ─────────────
  SELECT id INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = p_user_id
    AND balance >= v_budget
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success',  false,
      'error',    'INSUFFICIENT_BALANCE',
      'required', v_budget
    );
  END IF;

  -- ── 6. 예산 즉시 차감 ────────────────────────────────────────
  UPDATE public.wallets
  SET balance    = balance - v_budget,
      updated_at = NOW()
  WHERE id = v_wallet_id;

  -- ── 7. SPEND 거래 내역 INSERT ─────────────────────────────────
  INSERT INTO public.transactions (user_id, type, amount, status, description)
  VALUES (
    p_user_id,
    'SPEND',
    v_budget,
    'COMPLETED',
    FORMAT(
      '캠페인 등록 — 키워드: %s | %s ~ %s (%s일) × 일 %s명 × 50P',
      p_keyword,
      TO_CHAR(p_start_date, 'YYYY-MM-DD'),
      TO_CHAR(p_end_date,   'YYYY-MM-DD'),
      v_duration_days,
      p_daily_target
    )
  );

  -- ── 8. 캠페인 INSERT ──────────────────────────────────────────
  INSERT INTO public.campaigns (
    user_id, product_url, keyword, seed_keyword,
    daily_target, duration_days, budget,
    remaining_slots, status,
    start_date, end_date, expires_at
  )
  VALUES (
    p_user_id, p_product_url, p_keyword, v_seed_keyword,
    p_daily_target, v_duration_days, v_budget,
    p_daily_target * v_duration_days,
    'ACTIVE',
    p_start_date,
    p_end_date,
    p_end_date::TIMESTAMPTZ + INTERVAL '1 day'
  )
  RETURNING id INTO v_campaign_id;

  -- ── 9. 태그 INSERT (sort_order + is_answer 포함) ───────────────
  --      p_answer_index 번째 태그에만 is_answer=true 설정
  FOREACH v_tag IN ARRAY p_tags LOOP
    v_tag_idx := v_tag_idx + 1;
    INSERT INTO public.campaign_tags (campaign_id, tag_word, sort_order, is_answer)
    VALUES (v_campaign_id, TRIM(v_tag), v_tag_idx, (v_tag_idx = p_answer_index));
  END LOOP;

  -- ── 10. 성공 응답 ─────────────────────────────────────────────
  RETURN json_build_object(
    'success',     true,
    'campaign_id', v_campaign_id,
    'budget',      v_budget,
    'duration',    v_duration_days
  );

END;
$$;


-- ── 3. start_mission RPC 업데이트 ────────────────────────────────
--      is_answer=true 태그 선택 + tag_index(sort_order) 응답 추가
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
