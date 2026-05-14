-- =================================================================
-- register_campaign RPC: 태그 최소 입력 개수 2개 → 1개로 변경
--
-- 배경:
--   migration 0019, 0023에서 "태그 최소 2개" 검증이 적용되어 있음.
--   운영 중 태그 1개만 입력하는 케이스 허용 요청 → 최소 1개로 완화.
--
-- 수정:
--   line: IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 2
--   → IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 1
--
--   (array_length는 빈 배열/NULL일 때 NULL 반환 → IS NULL 조건이 핵심)
--   (< 1 조건은 안전망 역할 — 사실상 IS NULL로만 TAGS_REQUIRED 트리거됨)
--
-- Flutter 변경:
--   campaign_new_screen.dart 에서도 동일하게 최소 1개로 변경 완료
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

  -- 태그 최소 1개 필수 (migration 0025: 2개 → 1개로 완화)
  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 1 THEN
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
