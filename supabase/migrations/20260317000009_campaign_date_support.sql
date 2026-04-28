-- =================================================================
-- 캠페인 등록 개선 — start_date/end_date 컬럼 추가 + RPC 업데이트
--
-- 변경 사항:
--   1. campaigns 테이블에 start_date, end_date DATE 컬럼 추가
--   2. register_campaign RPC 파라미터 변경
--        p_duration_days INTEGER → p_start_date DATE, p_end_date DATE
--      (duration_days는 내부에서 end_date - start_date + 1 로 계산)
--   3. duration_days >= 7 최소 기간 검증 추가
-- =================================================================

-- -----------------------------------------------------------------
-- 1. campaigns 테이블 컬럼 추가
-- -----------------------------------------------------------------
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS end_date   DATE;

-- -----------------------------------------------------------------
-- 2. RPC: register_campaign (start_date / end_date 버전)
--
--    파라미터:
--      p_user_id      UUID
--      p_product_url  TEXT
--      p_keyword      TEXT
--      p_daily_target INTEGER
--      p_start_date   DATE    ← 신규 (기존 p_duration_days 대체)
--      p_end_date     DATE    ← 신규
--      p_tags         TEXT[]
--
--    처리 순서:
--      1. 호출자 본인 확인
--      2. 파라미터 유효성 + 기간 >= 7일
--      3. 예산 계산: daily_target × duration_days × 50P
--      4. 잔액 확인 (SELECT FOR UPDATE)
--      5. wallets.balance 차감
--      6. transactions INSERT (SPEND)
--      7. campaigns INSERT
--      8. campaign_tags INSERT (tag_words 순회)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id       UUID,
  p_product_url   TEXT,
  p_keyword       TEXT,
  p_daily_target  INTEGER,
  p_start_date    DATE,
  p_end_date      DATE,
  p_tags          TEXT[]
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

  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 1 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
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
    user_id, product_url, keyword,
    daily_target, duration_days, budget,
    remaining_slots, status,
    start_date, end_date, expires_at
  )
  VALUES (
    p_user_id, p_product_url, p_keyword,
    p_daily_target, v_duration_days, v_budget,
    p_daily_target * v_duration_days,
    'ACTIVE',
    p_start_date,
    p_end_date,
    p_end_date::TIMESTAMPTZ + INTERVAL '1 day'  -- 종료일 자정까지 유효
  )
  RETURNING id INTO v_campaign_id;

  -- ── 9. 정답 태그 INSERT (tag_word는 DB에만 저장) ─────────────
  FOREACH v_tag IN ARRAY p_tags LOOP
    INSERT INTO public.campaign_tags (campaign_id, tag_word)
    VALUES (v_campaign_id, TRIM(v_tag));
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
