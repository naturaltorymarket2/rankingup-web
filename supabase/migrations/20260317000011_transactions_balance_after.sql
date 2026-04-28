-- =================================================================
-- 포인트 내역 화면 지원 — balance_after 컬럼 추가 + RPC 업데이트
--
-- 변경 사항:
--   1. transactions 테이블에 balance_after INTEGER NULL 컬럼 추가
--      (과거 레코드 / PENDING 상태는 NULL 허용)
--   2. approve_charge RPC 업데이트
--      → COMPLETED 처리 시 balance_after 자동 기록
--   3. register_campaign RPC 업데이트
--      → SPEND INSERT 시 balance_after 자동 기록
-- =================================================================

-- -----------------------------------------------------------------
-- 1. balance_after 컬럼 추가
-- -----------------------------------------------------------------
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS balance_after INTEGER;

-- -----------------------------------------------------------------
-- 2. approve_charge — balance_after 기록 추가
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_charge(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx          public.transactions%ROWTYPE;
  v_wallet_id   UUID;
  v_new_balance INTEGER;
BEGIN

  -- ── 1. 어드민 권한 검증 ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. PENDING CHARGE 트랜잭션 조회 및 잠금 ──────────────────
  SELECT * INTO v_tx
  FROM public.transactions
  WHERE id     = p_tx_id
    AND type   = 'CHARGE'
    AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  -- ── 3. 지갑 잠금 ─────────────────────────────────────────────
  SELECT id INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = v_tx.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  -- ── 4. 포인트 지급 + 신규 잔액 취득 ──────────────────────────
  UPDATE public.wallets
  SET balance    = balance + v_tx.amount,
      updated_at = NOW()
  WHERE id = v_wallet_id
  RETURNING balance INTO v_new_balance;

  -- ── 5. 트랜잭션 완료 처리 + balance_after 기록 ───────────────
  UPDATE public.transactions
  SET status        = 'COMPLETED',
      balance_after = v_new_balance
  WHERE id = p_tx_id;

  RETURN json_build_object(
    'success', true,
    'user_id', v_tx.user_id,
    'amount',  v_tx.amount
  );

END;
$$;

-- -----------------------------------------------------------------
-- 3. register_campaign — balance_after 기록 추가 (v2: start/end date)
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
  v_new_balance   INTEGER;
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

  -- ── 4. 예산 계산 ─────────────────────────────────────────────
  v_budget := p_daily_target * v_duration_days * 50;

  -- ── 5. 잔액 확인 + 지갑 잠금 ─────────────────────────────────
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

  -- ── 6. 예산 차감 + 신규 잔액 취득 ────────────────────────────
  UPDATE public.wallets
  SET balance    = balance - v_budget,
      updated_at = NOW()
  WHERE id = v_wallet_id
  RETURNING balance INTO v_new_balance;

  -- ── 7. SPEND 거래 내역 INSERT (balance_after 포함) ─────────
  INSERT INTO public.transactions (
    user_id, type, amount, status, description, balance_after
  )
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
    ),
    v_new_balance
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
    p_end_date::TIMESTAMPTZ + INTERVAL '1 day'
  )
  RETURNING id INTO v_campaign_id;

  -- ── 9. 정답 태그 INSERT ───────────────────────────────────────
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
