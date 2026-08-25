-- =================================================================
-- Phase 22: register_campaign RPC — 승인 대기 등록 + 과금 시점 이동
--
-- 변경 내용:
--   1. 포인트 차감 제거 → 어드민 승인 시점(approve_campaign)으로 이동
--      - 등록 시점에는 잔액 "확인"만 수행 (부족하면 등록 자체를 막아 UX 보호)
--      - SPEND 트랜잭션도 승인 시점에 기록
--   2. 태그 파라미터 제거 (p_tags / p_sort_orders / p_answer_index)
--      - 태그는 어드민이 상품 페이지에서 직접 긁어 등록 (approve_campaign)
--   3. 캠페인 생성 시 status = 'PAUSED', approval_status = 'PENDING'
--      → 승인 전까지 앱 미션 보드에 노출되지 않음
--
-- ⚠️ 기존 시그니처(태그 파라미터 포함)는 전부 DROP한다.
--    웹 클라이언트(campaign_repository.dart)도 함께 변경되었으므로
--    구 시그니처가 남아 있으면 오버로드 모호성만 유발한다.
-- =================================================================

-- ── 1. 기존 register_campaign 오버로드 전부 제거 ─────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'register_campaign'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE FORMAT('DROP FUNCTION IF EXISTS %s', r.sig);
  END LOOP;
END $$;

-- ── 2. 신규 register_campaign ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id            UUID,
  p_product_url        TEXT,
  p_keyword            TEXT,
  p_daily_target       INTEGER,
  p_group_daily_target INTEGER,
  p_group_id           UUID,
  p_start_date         DATE,
  p_end_date           DATE,
  p_seed_keyword       TEXT DEFAULT NULL,
  p_product_name       TEXT DEFAULT NULL,
  p_brand_name         TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       UUID;
  v_balance       INTEGER;
  v_duration_days INTEGER;
  v_total_cost    INTEGER;
  v_campaign_id   UUID;
  v_expires_at    TIMESTAMPTZ;
  v_is_first      BOOLEAN;
BEGIN
  -- ── 인증 확인 ───────────────────────────────────────────────
  v_user_id := auth.uid();
  IF v_user_id IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 파라미터 유효성 검사 ────────────────────────────────────
  IF p_product_url IS NULL OR TRIM(p_product_url) = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;
  IF p_keyword IS NULL OR TRIM(p_keyword) = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;
  IF p_daily_target IS NULL OR p_daily_target <= 0
  OR p_group_daily_target IS NULL OR p_group_daily_target <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  v_duration_days := (p_end_date - p_start_date) + 1;
  IF v_duration_days < 7 THEN
    RETURN json_build_object('success', false, 'error', 'DURATION_TOO_SHORT');
  END IF;

  -- ── 그룹 내 첫 번째 서브키워드인지 확인 (예산 귀속 결정) ─────
  v_is_first := NOT EXISTS (
    SELECT 1 FROM public.campaigns WHERE group_id = p_group_id
  );

  -- ── 잔액 확인 (차감은 하지 않음 — 승인 시점에 차감) ──────────
  --    승인 시점에 잔액이 부족하면 승인이 실패하므로,
  --    등록 시점에 미리 걸러 광고주에게 즉시 안내한다.
  IF v_is_first THEN
    v_total_cost := p_group_daily_target * v_duration_days * 50;

    SELECT COALESCE(balance, 0) INTO v_balance
    FROM public.wallets WHERE user_id = p_user_id;

    IF v_balance < v_total_cost THEN
      RETURN json_build_object(
        'success',  false,
        'error',    'INSUFFICIENT_BALANCE',
        'required', v_total_cost
      );
    END IF;
  END IF;

  -- ── 캠페인 생성 (승인 대기 상태) ─────────────────────────────
  v_expires_at := (p_end_date + INTERVAL '1 day')::TIMESTAMPTZ AT TIME ZONE 'Asia/Seoul';

  INSERT INTO public.campaigns (
    user_id, product_url, keyword,
    daily_target, group_daily_target, group_id,
    start_date, end_date, expires_at,
    duration_days, budget, status, approval_status, remaining_slots,
    seed_keyword, product_name, brand_name
  ) VALUES (
    p_user_id, p_product_url, p_keyword,
    p_daily_target, p_group_daily_target, p_group_id,
    p_start_date, p_end_date, v_expires_at,
    v_duration_days,
    CASE WHEN v_is_first THEN p_group_daily_target * v_duration_days * 50 ELSE 0 END,
    'PAUSED',    -- 승인 전까지 미션 보드 미노출
    'PENDING',
    p_daily_target,
    p_seed_keyword, p_product_name, p_brand_name
  )
  RETURNING id INTO v_campaign_id;

  RETURN json_build_object(
    'success',     true,
    'campaign_id', v_campaign_id,
    'status',      'PENDING_APPROVAL'
  );
END;
$$;
