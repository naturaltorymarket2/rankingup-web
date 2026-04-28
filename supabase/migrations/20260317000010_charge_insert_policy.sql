-- =================================================================
-- 충전 신청 지원 — transactions 테이블 INSERT 정책 추가
--
-- 충전 흐름:
--   1. 광고주 웹에서 직접 INSERT (type=CHARGE, status=PENDING)
--   2. 어드민이 입금 확인 후 approve_charge RPC 호출 → COMPLETED + 포인트 지급
--
-- 기존 SELECT 정책(transactions_self_select)과 함께 작동
-- =================================================================

-- -----------------------------------------------------------------
-- transactions: 본인 CHARGE 건만 PENDING 상태로 INSERT 허용
-- -----------------------------------------------------------------
CREATE POLICY transactions_charge_insert ON public.transactions
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND type   = 'CHARGE'
    AND status = 'PENDING'
  );
