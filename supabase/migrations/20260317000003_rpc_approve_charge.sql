-- =================================================================
-- RPC: approve_charge(p_tx_id)
-- 호출: 어드민 (role = 'ADMIN')
-- 역할: PENDING 충전 트랜잭션 승인 → 광고주 포인트 지급
--
-- 충전 흐름:
--   1. 광고주가 충전 신청 → transactions (type=CHARGE, status=PENDING) INSERT
--   2. 어드민이 입금 확인 후 approve_charge 호출
--   3. wallets.balance += amount, status → COMPLETED
--
-- 어뷰징 방지:
--   1. 호출자 role = 'ADMIN' 검증
--   2. PENDING CHARGE 트랜잭션만 처리 (중복 승인 차단)
--   3. wallet SELECT FOR UPDATE (동시성 제어)
-- =================================================================
CREATE OR REPLACE FUNCTION public.approve_charge(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx        public.transactions%ROWTYPE;
  v_wallet_id UUID;
BEGIN

  -- ── 1. 어드민 권한 검증 ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. PENDING CHARGE 트랜잭션 조회 및 잠금 (FOR UPDATE) ─────
  SELECT * INTO v_tx
  FROM public.transactions
  WHERE id     = p_tx_id
    AND type   = 'CHARGE'
    AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  -- ── 3. 지갑 잠금 (SELECT FOR UPDATE) ─────────────────────────
  SELECT id INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = v_tx.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  -- ── 4. 포인트 지급 ────────────────────────────────────────────
  UPDATE public.wallets
  SET balance    = balance + v_tx.amount,
      updated_at = NOW()
  WHERE id = v_wallet_id;

  -- ── 5. 트랜잭션 완료 처리 ────────────────────────────────────
  UPDATE public.transactions
  SET status = 'COMPLETED'
  WHERE id = p_tx_id;

  RETURN json_build_object(
    'success', true,
    'user_id', v_tx.user_id,
    'amount',  v_tx.amount
  );

END;
$$;
