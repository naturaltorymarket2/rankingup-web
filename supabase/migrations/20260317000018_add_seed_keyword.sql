-- =================================================================
-- campaigns.seed_keyword 컬럼 추가 + register_campaign RPC 업데이트
--
-- 배경:
--   Phase 5-2에서 다중 키워드 캠페인 등록 기능 도입 후,
--   동일 상품(product_url)에 대해 N개 캠페인이 생성됨.
--   스케줄러가 N개 키워드 전체를 추적하는 대신,
--   대표(시드) 키워드 1개만 추적하도록 변경하기 위해 seed_keyword 저장.
--
-- 변경 내용:
--   1. campaigns.seed_keyword TEXT (nullable) 컬럼 추가
--      - NULL: 기존 캠페인 (하위 호환 — keyword를 시드로 간주)
--      - 설정됨: 자동완성으로 등록된 캠페인의 원본 시드 키워드
--   2. register_campaign RPC에 p_seed_keyword 파라미터 추가 (DEFAULT NULL)
-- =================================================================

-- ── 1. 컬럼 추가 ─────────────────────────────────────────────────
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS seed_keyword TEXT;

-- ── 2. register_campaign RPC 업데이트 ────────────────────────────
CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id       UUID,
  p_product_url   TEXT,
  p_keyword       TEXT,
  p_daily_target  INTEGER,
  p_duration_days INTEGER,
  p_tags          TEXT[],
  p_seed_keyword  TEXT DEFAULT NULL  -- 시드 키워드 (순위 추적용). NULL이면 p_keyword 사용
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_budget        INTEGER;
  v_wallet_id     UUID;
  v_campaign_id   UUID;
  v_tag           TEXT;
  v_seed_keyword  TEXT;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 파라미터 유효성 검증 ──────────────────────────────────
  IF p_daily_target  <= 0
  OR p_duration_days <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_product_url = '' OR p_keyword = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 1 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;

  -- seed_keyword: 빈 문자열이면 NULL 저장 (하위 호환)
  v_seed_keyword := NULLIF(TRIM(COALESCE(p_seed_keyword, '')), '');

  -- ── 3. 예산 계산: 일일 유입 × 기간(일) × 50원 ───────────────
  v_budget := p_daily_target * p_duration_days * 50;

  -- ── 4. 잔액 확인 + 지갑 잠금 (SELECT FOR UPDATE) ─────────────
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

  -- ── 5. 예산 즉시 차감 ────────────────────────────────────────
  UPDATE public.wallets
  SET balance    = balance - v_budget,
      updated_at = NOW()
  WHERE id = v_wallet_id;

  -- ── 6. SPEND 거래 내역 INSERT ─────────────────────────────────
  INSERT INTO public.transactions (user_id, type, amount, status, description)
  VALUES (
    p_user_id,
    'SPEND',
    v_budget,
    'COMPLETED',
    FORMAT(
      '캠페인 등록 — 키워드: %s | %s일 × 일 %s명 × 50P',
      p_keyword, p_duration_days, p_daily_target
    )
  );

  -- ── 7. 캠페인 INSERT (seed_keyword 포함) ──────────────────────
  INSERT INTO public.campaigns (
    user_id, product_url, keyword, seed_keyword,
    daily_target, duration_days, budget,
    remaining_slots, status, expires_at
  )
  VALUES (
    p_user_id, p_product_url, p_keyword, v_seed_keyword,
    p_daily_target, p_duration_days, v_budget,
    p_daily_target * p_duration_days,
    'ACTIVE',
    NOW() + MAKE_INTERVAL(days => p_duration_days)
  )
  RETURNING id INTO v_campaign_id;

  -- ── 8. 정답 태그 INSERT (tag_word는 DB에만 저장) ─────────────
  FOREACH v_tag IN ARRAY p_tags LOOP
    INSERT INTO public.campaign_tags (campaign_id, tag_word)
    VALUES (v_campaign_id, TRIM(v_tag));
  END LOOP;

  -- ── 9. 성공 응답 ─────────────────────────────────────────────
  RETURN json_build_object(
    'success',     true,
    'campaign_id', v_campaign_id,
    'budget',      v_budget
  );

END;
$$;
