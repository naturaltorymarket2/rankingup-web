-- =================================================================
-- register_campaign RPC: 그룹 과금 구조 적용
--
-- 변경 내용:
--   1. 파라미터 추가:
--      - p_group_id UUID           : 클라이언트가 생성한 그룹 식별자
--      - p_group_daily_target INT  : 그룹 전체 일일 목표 (과금 기준)
--   2. 예산 계산 기준 변경:
--      기존: p_daily_target × 기간 × 50P (키워드마다 과금)
--      변경: p_group_daily_target × 기간 × 50P (그룹 단위 1회 과금)
--   3. 포인트 차감 조건:
--      동일 group_id를 가진 캠페인이 없을 때(첫 번째 서브키워드)만 차감.
--      두 번째 이후 서브키워드는 포인트 차감 없이 캠페인 행만 INSERT.
--   4. campaigns INSERT:
--      - daily_target: 서브키워드별 분배된 목표치 (p_daily_target)
--      - group_id, group_daily_target: 신규 컬럼 저장
--
-- 주의:
--   클라이언트는 동일 group_id로 순차(sequential) 호출해야 함.
--   동시 호출 시 group 카운트 체크가 경쟁 조건에 노출되나,
--   현재 _submit() 구현이 순차 호출을 보장하므로 허용 범위 내.
-- =================================================================

CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id            UUID,
  p_product_url        TEXT,
  p_keyword            TEXT,
  p_daily_target       INTEGER,            -- 서브키워드별 분배된 일일 목표
  p_group_daily_target INTEGER,            -- 그룹 전체 일일 목표 (과금 기준)
  p_start_date         DATE,
  p_end_date           DATE,
  p_tags               TEXT[],
  p_sort_orders        INTEGER[],
  p_answer_index       INTEGER,
  p_group_id           UUID,               -- 클라이언트가 생성·전달 (서브키워드 묶음 식별자)
  p_seed_keyword       TEXT DEFAULT NULL   -- 순위 추적 대표 키워드. NULL이면 p_keyword 사용
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_duration_days    INTEGER;
  v_budget           INTEGER;   -- 그룹 과금 예산 (첫 번째 서브키워드에만 실제 차감)
  v_wallet_id        UUID;
  v_campaign_id      UUID;
  v_tag_count        INTEGER;
  v_i                INTEGER;
  v_seed_keyword     TEXT;
  v_group_count      INTEGER;   -- 동일 group_id를 가진 기존 캠페인 수
  v_is_first         BOOLEAN;   -- 그룹 내 첫 번째 서브키워드 여부
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 파라미터 유효성 검증 ──────────────────────────────────
  IF p_daily_target <= 0 OR p_group_daily_target <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_product_url = '' OR p_keyword = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  -- 태그 최소 1개 필수
  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 1 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;

  -- p_sort_orders 배열 길이 = p_tags 배열 길이 검증
  IF array_length(p_sort_orders, 1) IS DISTINCT FROM array_length(p_tags, 1) THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  -- 정답 순서값이 p_sort_orders 배열 안에 존재하는지 검증
  IF NOT (p_answer_index = ANY(p_sort_orders)) THEN
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

  -- ── 4. 그룹 내 첫 번째 서브키워드 여부 확인 ─────────────────
  SELECT COUNT(*) INTO v_group_count
  FROM public.campaigns
  WHERE group_id = p_group_id;

  v_is_first := (v_group_count = 0);

  -- ── 5. 예산 계산: 그룹 일일 유입 × 기간(일) × 50P ───────────
  --      기존: p_daily_target × 기간 × 50  (키워드마다 부과)
  --      변경: p_group_daily_target × 기간 × 50  (그룹 1회 부과)
  v_budget := p_group_daily_target * v_duration_days * 50;

  -- ── 6. 잔액 확인 + 포인트 차감 (첫 번째 서브키워드만) ────────
  IF v_is_first THEN

    -- 잔액 확인 + 지갑 잠금 (SELECT FOR UPDATE)
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

    -- 예산 즉시 차감
    UPDATE public.wallets
    SET balance    = balance - v_budget,
        updated_at = NOW()
    WHERE id = v_wallet_id;

    -- SPEND 거래 내역 INSERT
    INSERT INTO public.transactions (user_id, type, amount, status, description)
    VALUES (
      p_user_id,
      'SPEND',
      v_budget,
      'COMPLETED',
      FORMAT(
        '캠페인 그룹 등록 — 메인키워드: %s | %s ~ %s (%s일) × 일 %s명 × 50P',
        COALESCE(v_seed_keyword, p_keyword),
        TO_CHAR(p_start_date, 'YYYY-MM-DD'),
        TO_CHAR(p_end_date,   'YYYY-MM-DD'),
        v_duration_days,
        p_group_daily_target
      )
    );

  END IF;

  -- ── 7. 캠페인 INSERT ──────────────────────────────────────────
  --      daily_target: 서브키워드별 분배 목표 (p_daily_target)
  --      group_daily_target: 그룹 전체 목표 (과금 기준)
  --      budget: 실제 차감된 금액 (첫 번째만 v_budget, 이후 0)
  INSERT INTO public.campaigns (
    user_id, product_url, keyword, seed_keyword,
    daily_target, group_daily_target, group_id,
    duration_days, budget,
    remaining_slots, status,
    start_date, end_date, expires_at
  )
  VALUES (
    p_user_id, p_product_url, p_keyword, v_seed_keyword,
    p_daily_target, p_group_daily_target, p_group_id,
    v_duration_days, CASE WHEN v_is_first THEN v_budget ELSE 0 END,
    p_daily_target * v_duration_days,
    'ACTIVE',
    p_start_date,
    p_end_date,
    p_end_date::TIMESTAMPTZ + INTERVAL '1 day'
  )
  RETURNING id INTO v_campaign_id;

  -- ── 8. 태그 INSERT (sort_order = 광고주 입력 실제 순서값) ─────
  v_tag_count := array_length(p_tags, 1);
  FOR v_i IN 1..v_tag_count LOOP
    INSERT INTO public.campaign_tags (campaign_id, tag_word, sort_order, is_answer)
    VALUES (
      v_campaign_id,
      TRIM(p_tags[v_i]),
      p_sort_orders[v_i],
      (p_sort_orders[v_i] = p_answer_index)
    );
  END LOOP;

  -- ── 9. 성공 응답 ─────────────────────────────────────────────
  RETURN json_build_object(
    'success',        true,
    'campaign_id',    v_campaign_id,
    'group_id',       p_group_id,
    'budget_charged', CASE WHEN v_is_first THEN v_budget ELSE 0 END,
    'is_first',       v_is_first,
    'duration',       v_duration_days
  );

END;
$$;
