-- =================================================================
-- RPC: register_campaign(p_user_id, p_product_url, p_keyword,
--                         p_daily_target, p_duration_days, p_tags)
-- 호출: 광고주 (웹)
-- 역할: 캠페인 등록 + 예산 포인트 즉시 차감
--
-- 예산 계산: daily_target × duration_days × 50원
--
-- 등록 전제 조건:
--   - 클라이언트에서 파이썬 랭킹 모듈로 키워드 순위 15위 이내 확인 후 호출
--   - 이 RPC는 순위 재검증 없이 포인트만 처리 (순위 검증은 앞 단계에서)
--
-- 어뷰징 방지:
--   1. 호출자 = p_user_id 일치 검증
--   2. 잔액 부족 시 등록 차단 (wallet SELECT FOR UPDATE)
--   3. 태그 1개 이상 필수 검증
-- =================================================================
CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id       UUID,
  p_product_url   TEXT,
  p_keyword       TEXT,
  p_daily_target  INTEGER,
  p_duration_days INTEGER,
  p_tags          TEXT[]   -- 정답 태그 목록 (1개 이상 필수)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_budget      INTEGER;
  v_wallet_id   UUID;
  v_campaign_id UUID;
  v_tag         TEXT;
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

  -- ── 7. 캠페인 INSERT ──────────────────────────────────────────
  INSERT INTO public.campaigns (
    user_id, product_url, keyword,
    daily_target, duration_days, budget,
    remaining_slots, status, expires_at
  )
  VALUES (
    p_user_id, p_product_url, p_keyword,
    p_daily_target, p_duration_days, v_budget,
    p_daily_target * p_duration_days,          -- 전체 슬롯 = 일 × 기간
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
