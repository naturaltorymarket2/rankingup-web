-- =================================================================
-- 어드민 충전 승인 — 서버사이드 함수
--
-- 변경 사항:
--   1. reject_charge(p_tx_id UUID) RPC
--      → CHARGE PENDING 상태를 REJECTED로 변경 (ADMIN 전용)
--   2. get_pending_charges() RPC
--      → ADMIN 전용, CHARGE + PENDING 전체 목록 + 유저 이메일
--   3. get_processed_charges() RPC
--      → ADMIN 전용, CHARGE + COMPLETED/REJECTED 최근 20건 + 유저 이메일
-- =================================================================

-- -----------------------------------------------------------------
-- 1. reject_charge — PENDING CHARGE 거절 처리
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_charge(p_tx_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  -- ── 1. 어드민 권한 검증 ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. PENDING CHARGE 상태 → REJECTED 변경 ───────────────────
  UPDATE public.transactions
  SET status = 'REJECTED'
  WHERE id     = p_tx_id
    AND type   = 'CHARGE'
    AND status = 'PENDING';

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_TRANSACTION');
  END IF;

  RETURN json_build_object('success', true);

END;
$$;

-- -----------------------------------------------------------------
-- 2. get_pending_charges — ADMIN 전용, 대기 중인 충전 신청 전체
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pending_charges()
RETURNS TABLE (
  id          UUID,
  user_id     UUID,
  user_email  TEXT,
  amount      INTEGER,
  status      TEXT,
  description TEXT,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  -- ── ADMIN 권한 검증 ──────────────────────────────────────────
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
    usr.email::TEXT     AS user_email,
    t.amount,
    t.status,
    t.description,
    t.created_at
  FROM public.transactions t
  JOIN public.users usr ON usr.id = t.user_id
  WHERE t.type   = 'CHARGE'
    AND t.status = 'PENDING'
  ORDER BY t.created_at DESC;

END;
$$;

-- -----------------------------------------------------------------
-- 3. get_processed_charges — ADMIN 전용, 처리 완료 내역 최근 20건
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_processed_charges()
RETURNS TABLE (
  id          UUID,
  user_id     UUID,
  user_email  TEXT,
  amount      INTEGER,
  status      TEXT,
  description TEXT,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  -- ── ADMIN 권한 검증 ──────────────────────────────────────────
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
    usr.email::TEXT     AS user_email,
    t.amount,
    t.status,
    t.description,
    t.created_at
  FROM public.transactions t
  JOIN public.users usr ON usr.id = t.user_id
  WHERE t.type   = 'CHARGE'
    AND t.status IN ('COMPLETED', 'REJECTED')
  ORDER BY t.created_at DESC
  LIMIT 20;

END;
$$;
