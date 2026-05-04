-- ============================================================
-- process_withdraw / reject_withdraw 수정
--
-- 변경 이유:
--   submit_withdraw RPC(migration 15)에서 출금 신청 시 잔액을 즉시 차감하도록 변경됨.
--   따라서:
--   - process_withdraw: 잔액 차감 로직 제거 (이미 차감됨) → status=COMPLETED만 처리
--   - reject_withdraw:  잔액 복구 로직 추가 (신청 시 차감됐으므로 거절 시 환불)
-- ============================================================

-- -----------------------------------------------------------------
-- 1. process_withdraw — 출금 완료 처리 (잔액 차감 없음)
--    submit_withdraw에서 이미 차감했으므로 status=COMPLETED만 업데이트
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_withdraw(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx public.transactions%ROWTYPE;
BEGIN

  -- ── 1. 어드민 권한 검증 ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. PENDING WITHDRAW 트랜잭션 조회 및 잠금 ─────────────────
  SELECT * INTO v_tx
  FROM public.transactions
  WHERE id     = p_tx_id
    AND type   = 'WITHDRAW'
    AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  -- ── 3. 출금 트랜잭션 완료 처리 (잔액 차감 없음 — submit_withdraw에서 이미 처리됨)
  UPDATE public.transactions
  SET status = 'COMPLETED'
  WHERE id = p_tx_id;

  -- ── 4. 성공 응답 ──────────────────────────────────────────────
  RETURN json_build_object(
    'success', true,
    'user_id', v_tx.user_id,
    'amount',  v_tx.amount
  );

END;
$$;

-- -----------------------------------------------------------------
-- 2. reject_withdraw — WITHDRAW PENDING 거절 + 잔액 복구
--    submit_withdraw에서 차감된 금액을 되돌림
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_withdraw(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx public.transactions%ROWTYPE;
BEGIN

  -- ── 어드민 권한 검증 ────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── PENDING WITHDRAW 조회 및 잠금 ──────────────────────────
  SELECT * INTO v_tx
  FROM public.transactions
  WHERE id     = p_tx_id
    AND type   = 'WITHDRAW'
    AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  -- ── 잔액 복구 (submit_withdraw에서 차감됐으므로 환불) ───────
  UPDATE public.wallets
  SET balance    = balance + v_tx.amount,
      updated_at = NOW()
  WHERE user_id = v_tx.user_id;

  -- ── PENDING → REJECTED ─────────────────────────────────────
  UPDATE public.transactions
  SET status = 'REJECTED'
  WHERE id = p_tx_id;

  RETURN json_build_object('success', true);

END;
$$;
