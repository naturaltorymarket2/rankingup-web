-- =================================================================
-- RPC: process_withdraw(p_tx_id)
-- 호출: 어드민 (role = 'ADMIN')
-- 역할: PENDING 출금 트랜잭션 완료 처리
--
-- 출금 흐름:
--   1. 유저가 출금 신청 (별도 처리):
--      - balance >= (신청금액 + 500 수수료) 확인
--      - balance -= (신청금액 + 500) 즉시 차감
--      - transactions (type=WITHDRAW, status=PENDING) INSERT
--   2. 어드민이 실제 계좌 이체 후 process_withdraw 호출
--      - status → COMPLETED (잔액은 이미 차감됨, 추가 변경 없음)
--
-- 어뷰징 방지:
--   1. 호출자 role = 'ADMIN' 검증
--   2. PENDING WITHDRAW만 처리 (중복 처리 차단)
-- =================================================================
CREATE OR REPLACE FUNCTION public.process_withdraw(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx     public.transactions%ROWTYPE;
  v_user   public.users%ROWTYPE;
BEGIN

  -- ── 1. 어드민 권한 검증 ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. PENDING WITHDRAW 트랜잭션 조회 및 잠금 (FOR UPDATE) ───
  SELECT * INTO v_tx
  FROM public.transactions
  WHERE id     = p_tx_id
    AND type   = 'WITHDRAW'
    AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  -- ── 3. 출금 완료 처리 ────────────────────────────────────────
  --      잔액은 출금 신청 시 이미 차감됨 → balance 변경 없음
  UPDATE public.transactions
  SET status = 'COMPLETED'
  WHERE id = p_tx_id;

  -- ── 4. 어드민 송금에 필요한 계좌 정보 반환 ──────────────────
  SELECT * INTO v_user
  FROM public.users
  WHERE id = v_tx.user_id;

  RETURN json_build_object(
    'success',              true,
    'user_id',              v_tx.user_id,
    'amount',               v_tx.amount,
    'bank_name',            v_user.bank_name,
    'bank_account_number',  v_user.bank_account_number,
    'bank_account_holder',  v_user.bank_account_holder
  );

END;
$$;
