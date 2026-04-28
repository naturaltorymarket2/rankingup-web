-- =================================================================
-- 출금 신청 지원 마이그레이션
--
-- 1. transactions 테이블에 memo 컬럼 추가 (출금 계좌 정보 JSON 저장)
-- 2. 유저가 WITHDRAW/PENDING 거래를 직접 INSERT할 수 있도록 RLS 정책 추가
--    - 포인트 차감은 어드민 process_withdraw RPC에서만 처리
--    - INSERT 정책은 type=WITHDRAW, status=PENDING 에 한정
-- =================================================================

-- 1. memo 컬럼 추가 (은행명/계좌번호/예금주 JSON)
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS memo TEXT;

-- 2. 유저 출금 신청 INSERT 허용 RLS 정책
--    조건: 본인 user_id + type='WITHDRAW' + status='PENDING' 만 허용
CREATE POLICY transactions_self_withdraw ON public.transactions
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND type   = 'WITHDRAW'
    AND status = 'PENDING'
  );
