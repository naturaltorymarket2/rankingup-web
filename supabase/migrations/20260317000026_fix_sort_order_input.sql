-- =================================================================
-- register_campaign RPC: p_sort_orders 파라미터 추가
-- 태그 순서를 광고주가 직접 입력한 실제 네이버 상품 페이지 순서로 저장
--
-- 배경:
--   기존: sort_order = 루프 카운터 (태그 추가 순서 1,2,3... — 의미 없는 값)
--         p_answer_index = p_tags 배열 내 정답 태그의 위치(1-based 인덱스)
--
--   변경: p_sort_orders INTEGER[] 파라미터 추가 (p_tags와 1:1 대응)
--         sort_order = p_sort_orders[i] (광고주가 직접 입력한 실제 네이버 태그 순서)
--         p_answer_index = 정답 태그의 실제 순서값 (p_sort_orders 배열의 값 중 하나)
--
-- 효과:
--   start_mission이 반환하는 tag_index = sort_order(is_answer=true 태그)
--   = 광고주가 입력한 실제 네이버 상품 페이지 태그 순서
--   → 앱 유저에게 "N번째 태그를 입력하세요" 안내가 실제 정확한 순서로 표시됨
--
-- 태그 최소 개수: 1개 (migration 0025 기준 유지)
-- is_answer 판별: p_sort_orders[i] = p_answer_index 인 태그만 true
-- =================================================================

CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id       UUID,
  p_product_url   TEXT,
  p_keyword       TEXT,
  p_daily_target  INTEGER,
  p_start_date    DATE,
  p_end_date      DATE,
  p_tags          TEXT[],
  p_sort_orders   INTEGER[],         -- 각 태그의 실제 순서값 (p_tags와 1:1 대응, 광고주 직접 입력)
  p_answer_index  INTEGER,           -- 정답 태그의 실제 순서값 (p_sort_orders 배열의 값 중 하나)
  p_seed_keyword  TEXT DEFAULT NULL  -- 시드 키워드 (순위 추적용). NULL이면 p_keyword 사용
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
  v_tag_count     INTEGER;
  v_i             INTEGER;
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

  -- 태그 최소 1개 필수 (migration 0025 기준 유지)
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

  -- ── 9. 태그 INSERT (sort_order = 광고주 입력 실제 순서값) ────────
  --      is_answer: p_sort_orders[i] = p_answer_index 인 태그만 true
  --      변경 전: sort_order = v_tag_idx (루프 카운터, 의미 없음)
  --      변경 후: sort_order = p_sort_orders[v_i] (광고주 직접 입력값)
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

  -- ── 10. 성공 응답 ─────────────────────────────────────────────
  RETURN json_build_object(
    'success',     true,
    'campaign_id', v_campaign_id,
    'budget',      v_budget,
    'duration',    v_duration_days
  );

END;
$$;
