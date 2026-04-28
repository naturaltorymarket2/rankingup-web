-- =================================================================
-- 어드민 출금 처리 — 서버사이드 함수
--
-- 변경 사항:
--   1. process_withdraw(p_tx_id UUID) RPC 업데이트
--      → 기존: status=COMPLETED만 처리 (잔액 차감 누락 버그)
--      → 수정: wallets.balance -= amount 차감 후 status=COMPLETED
--      ※ 출금 신청(submitWithdraw)은 잔액 미차감 — 여기서 처리
--   2. reject_withdraw(p_tx_id UUID) RPC 신규
--      → WITHDRAW PENDING → REJECTED (잔액 변경 없음)
--   3. get_pending_withdraws() RPC
--      → ADMIN 전용, WITHDRAW + PENDING 전체 목록 + 유저 이메일 + memo
--   4. get_processed_withdraws() RPC
--      → ADMIN 전용, WITHDRAW + COMPLETED/REJECTED 최근 20건
-- =================================================================

-- -----------------------------------------------------------------
-- 1. process_withdraw — 출금 완료 처리 (잔액 차감 포함)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_withdraw(p_tx_id UUID)
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

  -- ── 3. 지갑 잠금 + 잔액 충분 여부 확인 ───────────────────────
  SELECT id INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = v_tx.user_id
    AND balance >= v_tx.amount
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
  END IF;

  -- ── 4. 잔액 차감 (수수료 포함 신청금액 전체) ──────────────────
  UPDATE public.wallets
  SET balance    = balance - v_tx.amount,
      updated_at = NOW()
  WHERE id = v_wallet_id
  RETURNING balance INTO v_new_balance;

  -- ── 5. 출금 트랜잭션 완료 처리 ────────────────────────────────
  UPDATE public.transactions
  SET status = 'COMPLETED'
  WHERE id = p_tx_id;

  -- ── 6. 성공 응답 ──────────────────────────────────────────────
  RETURN json_build_object(
    'success',     true,
    'user_id',     v_tx.user_id,
    'amount',      v_tx.amount,
    'new_balance', v_new_balance
  );

END;
$$;

-- -----------------------------------------------------------------
-- 2. reject_withdraw — WITHDRAW PENDING 거절 (잔액 변경 없음)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_withdraw(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  -- ── 어드민 권한 검증 ────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── PENDING WITHDRAW → REJECTED ────────────────────────────
  UPDATE public.transactions
  SET status = 'REJECTED'
  WHERE id     = p_tx_id
    AND type   = 'WITHDRAW'
    AND status = 'PENDING';

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  RETURN json_build_object('success', true);

END;
$$;

-- -----------------------------------------------------------------
-- 3. get_pending_withdraws — ADMIN 전용, 대기 중인 출금 신청 전체
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pending_withdraws()
RETURNS TABLE (
  id          UUID,
  user_id     UUID,
  user_email  TEXT,
  amount      INTEGER,
  status      TEXT,
  memo        TEXT,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  IF NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'ADMIN'
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    t.id,
    t.user_id,
    usr.email::TEXT  AS user_email,
    t.amount,
    t.status,
    t.description    AS memo,
    t.created_at
  FROM public.transactions t
  JOIN public.users usr ON usr.id = t.user_id
  WHERE t.type   = 'WITHDRAW'
    AND t.status = 'PENDING'
  ORDER BY t.created_at DESC;

END;
$$;

-- -----------------------------------------------------------------
-- 4. get_processed_withdraws — ADMIN 전용, 처리 완료 내역 최근 20건
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_processed_withdraws()
RETURNS TABLE (
  id          UUID,
  user_id     UUID,
  user_email  TEXT,
  amount      INTEGER,
  status      TEXT,
  memo        TEXT,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  IF NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'ADMIN'
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    t.id,
    t.user_id,
    usr.email::TEXT  AS user_email,
    t.amount,
    t.status,
    t.description    AS memo,
    t.created_at
  FROM public.transactions t
  JOIN public.users usr ON usr.id = t.user_id
  WHERE t.type   = 'WITHDRAW'
    AND t.status IN ('COMPLETED', 'REJECTED')
  ORDER BY t.created_at DESC
  LIMIT 20;

END;
$$;
