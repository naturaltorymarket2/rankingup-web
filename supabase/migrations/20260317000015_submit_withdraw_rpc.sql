-- ============================================================
-- submit_withdraw RPC
-- 출금 신청 (SECURITY DEFINER — RLS 우회)
--
-- 변경 이유:
--   transactions_charge_insert RLS 정책이 type='CHARGE'만 허용하므로
--   클라이언트에서 직접 type='WITHDRAW' INSERT 불가.
--   SECURITY DEFINER 함수로 서버 측에서 처리.
--
-- 처리 순서:
--   1. 최소 출금 금액 체크 (5,000P)
--   2. 잔액 조회 + FOR UPDATE 잠금 (동시성 제어)
--   3. 잔액 부족 체크
--   4. 진행 중인 출금 신청 중복 체크
--   5. wallets.balance 차감 (출금 신청 시 즉시 차감)
--   6. transactions INSERT (type='WITHDRAW', status='PENDING')
--
-- NOTE:
--   process_withdraw RPC는 COMPLETED 처리만 하고 잔액을 차감하지 않음.
--   reject_withdraw RPC도 잔액을 복구하지 않음.
--   → 출금 거절 시 어드민이 Supabase Studio에서 수동으로 잔액 복구 필요.
--   (향후 reject_withdraw에 잔액 복구 로직 추가 권장)
-- ============================================================

CREATE OR REPLACE FUNCTION public.submit_withdraw(
  p_user_id   UUID,
  p_amount    INTEGER,
  p_bank      TEXT,
  p_account   TEXT,
  p_holder    TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance    INTEGER;
  v_net_amount INTEGER;
  v_pending    INTEGER;
BEGIN
  -- 1. 최소 출금 금액 체크
  IF p_amount < 5000 THEN
    RAISE EXCEPTION '최소 출금 금액은 5,000P입니다.';
  END IF;

  -- 2. 잔액 조회 + 동시성 잠금
  SELECT balance INTO v_balance
  FROM wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_balance IS NULL THEN
    RAISE EXCEPTION '지갑 정보를 찾을 수 없습니다.';
  END IF;

  -- 3. 잔액 부족 체크
  IF v_balance < p_amount THEN
    RAISE EXCEPTION '잔액이 부족합니다.';
  END IF;

  -- 4. 진행 중인 출금 신청 중복 체크
  SELECT COUNT(*) INTO v_pending
  FROM transactions
  WHERE user_id = p_user_id
    AND type    = 'WITHDRAW'
    AND status  = 'PENDING';

  IF v_pending > 0 THEN
    RAISE EXCEPTION '이미 출금 신청이 진행 중입니다.';
  END IF;

  -- 5. 수수료 차감 후 실수령액 계산
  v_net_amount := p_amount - 500;

  -- 6. 잔액 차감
  UPDATE wallets
  SET balance = balance - p_amount
  WHERE user_id = p_user_id;

  -- 7. 출금 내역 INSERT
  INSERT INTO transactions (user_id, type, amount, status, description, balance_after)
  VALUES (
    p_user_id,
    'WITHDRAW',
    p_amount,
    'PENDING',
    jsonb_build_object(
      'bank',       p_bank,
      'account',    p_account,
      'holder',     p_holder,
      'net_amount', v_net_amount
    )::text,
    (v_balance - p_amount)
  );
END;
$$;
