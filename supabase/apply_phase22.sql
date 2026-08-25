-- =================================================================
-- Phase 22 광고 승인 구조 — migration 0038~0042 합본
--
-- Supabase SQL Editor에 이 파일 전체를 붙여넣고 한 번에 실행한다.
-- 파일 순서 = 적용 순서이며, 각 구문은 CREATE OR REPLACE /
-- IF NOT EXISTS 기반이라 중복 실행해도 안전하다.
--
-- ⚠️ 웹(Railway) 재배포 전에 반드시 먼저 실행할 것.
--    신규 register_campaign 시그니처가 없으면 광고 등록이 전부 실패한다.
-- =================================================================


-- ═══════════════════════════════════════════════════════════════
-- ▼ 20260317000038_add_campaign_approval.sql
-- ═══════════════════════════════════════════════════════════════

-- =================================================================
-- Phase 22: 광고 승인(어드민 검수) 구조 추가
--
-- 배경:
--   기존: 광고주가 캠페인을 등록하면 즉시 ACTIVE → 앱 미션 보드 노출 + 포인트 즉시 차감
--   변경: 광고주 등록 → 승인 대기(PENDING) → 어드민이 상품 페이지의 실제 #태그를
--         긁어 등록하고 승인 → 그때 포인트 차감 + ACTIVE 전환 → 앱 노출
--
-- 변경 내용:
--   1. campaigns.approval_status  PENDING / APPROVED / REJECTED
--   2. campaigns.approved_at / approved_by / reject_reason
--   3. 태그 정규화 함수 normalize_tag(TEXT)
--      - 어드민 등록 태그와 앱 유저 입력 태그를 같은 규칙으로 비교하기 위함
--      - 선행 '#' 제거 + 모든 공백 제거 + 소문자
--
-- 기존 데이터:
--   이미 운영 중인 캠페인은 등록 시점에 포인트가 차감된 상태이므로
--   전부 APPROVED로 소급 처리한다 (아래 UPDATE 1회 실행).
-- =================================================================

-- ── 1. campaigns 컬럼 추가 ──────────────────────────────────────

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS approved_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by     UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS reject_reason   TEXT;

-- CHECK 제약 (중복 실행 안전)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'campaigns_approval_status_check'
  ) THEN
    ALTER TABLE public.campaigns
      ADD CONSTRAINT campaigns_approval_status_check
      CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED'));
  END IF;
END $$;

-- ── 2. 기존 캠페인 소급 승인 처리 (1회성) ────────────────────────
--    이 migration 적용 시점에 이미 존재하던 캠페인 = 구 구조로 과금 완료된 건
UPDATE public.campaigns
SET approval_status = 'APPROVED',
    approved_at     = COALESCE(approved_at, created_at)
WHERE approval_status = 'PENDING'
  AND created_at < NOW();

-- ── 3. 인덱스 ────────────────────────────────────────────────────

-- 어드민 승인 대기 목록 조회용
CREATE INDEX IF NOT EXISTS idx_campaigns_approval_status
  ON public.campaigns(approval_status);

-- 앱 미션 보드 조회용 (ACTIVE + APPROVED 복합)
CREATE INDEX IF NOT EXISTS idx_campaigns_status_approval
  ON public.campaigns(status, approval_status);

-- ── 4. 태그 정규화 함수 ──────────────────────────────────────────
--    어드민이 붙여넣은 "#AAA#BBB" 를 파싱한 태그와,
--    앱 유저가 입력한 태그를 동일 규칙으로 비교하기 위한 공용 함수.
--    규칙: 선행 '#' 제거 → 모든 공백 제거 → 소문자
CREATE OR REPLACE FUNCTION public.normalize_tag(p_tag TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT LOWER(REGEXP_REPLACE(REGEXP_REPLACE(COALESCE(p_tag, ''), '^#+', ''), '\s', '', 'g'));
$$;

-- ── 5. RLS 보강 ─────────────────────────────────────────────────
--    앱 유저에게는 승인 완료된 ACTIVE 캠페인만 노출.
--    (광고주는 본인 캠페인 전체 조회 가능 — 승인 대기 상태 확인용)
DROP POLICY IF EXISTS campaigns_read ON public.campaigns;
CREATE POLICY campaigns_read ON public.campaigns
  FOR SELECT USING (
    auth.uid() = user_id
    OR (status = 'ACTIVE' AND approval_status = 'APPROVED')
  );


-- ═══════════════════════════════════════════════════════════════
-- ▼ 20260317000039_update_register_campaign_pending.sql
-- ═══════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════
-- ▼ 20260317000040_rpc_admin_campaign.sql
-- ═══════════════════════════════════════════════════════════════

-- =================================================================
-- Phase 22: 어드민 광고 승인 RPC
--
--   get_pending_campaigns()                     승인 대기 광고 그룹 목록
--   get_processed_campaigns()                   승인/거절 처리 완료 목록 (최근 20그룹)
--   approve_campaign(p_group_id, p_tags)        태그 등록 + 포인트 차감 + 승인
--   reject_campaign(p_group_id, p_reason)       거절 (차감 없음 → 환불 불필요)
--
-- 전부 role = 'ADMIN' 검증 후 동작하는 SECURITY DEFINER 함수.
--
-- 태그 규칙:
--   - 어드민이 상품 페이지에서 "#AAA#BBB#CCC" 형태로 긁어 붙여넣은 값을
--     웹에서 '#' 기준으로 분리해 배열로 전달한다.
--   - 배열 순서 = 상품 페이지에서의 실제 노출 순서 → sort_order 1..N
--   - 최대 10개
--   - 저장 시 normalize_tag() 로 정규화 (선행 '#'/공백 제거, 소문자)
--   - is_answer = true (전부 정답 후보) — start_mission이 이 중 1개를 랜덤 선택
-- =================================================================

-- ── 공용: 호출자가 ADMIN인지 확인 ───────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'ADMIN'
  );
$$;


-- =================================================================
-- 1. get_pending_campaigns() — 승인 대기 광고 그룹 목록
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_pending_campaigns()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSON;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at ASC), '[]'::JSON)
  INTO v_rows
  FROM (
    SELECT
      c.group_id,
      MIN(c.created_at)                                   AS created_at,
      MAX(c.user_id::TEXT)::UUID                          AS user_id,
      MAX(u.email)                                        AS user_email,
      MAX(c.product_name)                                 AS product_name,
      MAX(c.brand_name)                                   AS brand_name,
      MAX(c.product_url)                                  AS product_url,
      MAX(c.seed_keyword)                                 AS seed_keyword,
      array_agg(c.keyword ORDER BY c.created_at ASC)      AS sub_keywords,
      MAX(c.group_daily_target)                           AS group_daily_target,
      MAX(c.duration_days)                                AS duration_days,
      MIN(c.start_date)                                   AS start_date,
      MAX(c.end_date)                                     AS end_date,
      SUM(c.budget)                                       AS budget,
      COUNT(*)                                            AS campaign_count,
      (
        SELECT c2.id FROM public.campaigns c2
        WHERE c2.group_id = c.group_id
        ORDER BY c2.created_at ASC LIMIT 1
      )                                                   AS representative_campaign_id
    FROM public.campaigns c
    JOIN public.users u ON u.id = c.user_id
    WHERE c.approval_status = 'PENDING'
    GROUP BY c.group_id
  ) t;

  RETURN json_build_object('success', true, 'campaigns', v_rows);
END;
$$;


-- =================================================================
-- 2. get_processed_campaigns() — 처리 완료 목록 (최근 20그룹)
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_processed_campaigns()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSON;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.processed_at DESC), '[]'::JSON)
  INTO v_rows
  FROM (
    SELECT
      c.group_id,
      MIN(c.created_at)                              AS created_at,
      MAX(COALESCE(c.approved_at, c.created_at))     AS processed_at,
      MAX(c.approval_status)                         AS approval_status,
      MAX(u.email)                                   AS user_email,
      MAX(c.product_name)                            AS product_name,
      MAX(c.brand_name)                              AS brand_name,
      MAX(c.product_url)                             AS product_url,
      MAX(c.seed_keyword)                            AS seed_keyword,
      array_agg(c.keyword ORDER BY c.created_at ASC) AS sub_keywords,
      MAX(c.group_daily_target)                      AS group_daily_target,
      SUM(c.budget)                                  AS budget,
      MAX(c.reject_reason)                           AS reject_reason,
      (
        SELECT c2.id FROM public.campaigns c2
        WHERE c2.group_id = c.group_id
        ORDER BY c2.created_at ASC LIMIT 1
      )                                              AS representative_campaign_id,
      (
        SELECT COALESCE(array_agg(ct.tag_word ORDER BY ct.sort_order), ARRAY[]::TEXT[])
        FROM public.campaign_tags ct
        WHERE ct.campaign_id = (
          SELECT c3.id FROM public.campaigns c3
          WHERE c3.group_id = c.group_id
          ORDER BY c3.created_at ASC LIMIT 1
        )
      )                                              AS tags
    FROM public.campaigns c
    JOIN public.users u ON u.id = c.user_id
    WHERE c.approval_status IN ('APPROVED', 'REJECTED')
    GROUP BY c.group_id
    ORDER BY MAX(COALESCE(c.approved_at, c.created_at)) DESC
    LIMIT 20
  ) t;

  RETURN json_build_object('success', true, 'campaigns', v_rows);
END;
$$;


-- =================================================================
-- 3. approve_campaign(p_group_id, p_tags)
--    태그 등록 → 포인트 차감 → ACTIVE 전환
-- =================================================================
CREATE OR REPLACE FUNCTION public.approve_campaign(
  p_group_id UUID,
  p_tags     TEXT[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id     UUID;
  v_total_cost   INTEGER;
  v_balance      INTEGER;
  v_wallet_id    UUID;
  v_seed_keyword TEXT;
  v_tag_count    INTEGER;
  v_campaign_ids UUID[];
  v_clean_tags   TEXT[] := ARRAY[]::TEXT[];
  v_tag          TEXT;
  v_norm         TEXT;
  v_cid          UUID;
  v_idx          INTEGER;
BEGIN
  -- ── 1. 권한 확인 ────────────────────────────────────────────
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  -- ── 2. 태그 검증 및 정규화 ──────────────────────────────────
  IF p_tags IS NULL OR array_length(p_tags, 1) IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;

  FOREACH v_tag IN ARRAY p_tags LOOP
    v_norm := public.normalize_tag(v_tag);
    IF v_norm <> '' THEN
      IF v_norm = ANY (v_clean_tags) THEN
        RETURN json_build_object(
          'success', false, 'error', 'DUPLICATE_TAG', 'tag', v_norm
        );
      END IF;
      v_clean_tags := array_append(v_clean_tags, v_norm);
    END IF;
  END LOOP;

  v_tag_count := COALESCE(array_length(v_clean_tags, 1), 0);

  IF v_tag_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;
  IF v_tag_count > 10 THEN
    RETURN json_build_object(
      'success', false, 'error', 'TOO_MANY_TAGS', 'count', v_tag_count
    );
  END IF;

  -- ── 3. 대상 그룹 잠금 (PENDING 건만) ────────────────────────
  SELECT array_agg(id ORDER BY created_at),
         MAX(user_id::TEXT)::UUID,
         SUM(budget),
         MAX(seed_keyword)
  INTO v_campaign_ids, v_owner_id, v_total_cost, v_seed_keyword
  FROM (
    SELECT id, created_at, user_id, budget, seed_keyword
    FROM public.campaigns
    WHERE group_id        = p_group_id
      AND approval_status = 'PENDING'
    FOR UPDATE
  ) locked;

  IF v_campaign_ids IS NULL OR array_length(v_campaign_ids, 1) IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_PENDING');
  END IF;

  v_total_cost := COALESCE(v_total_cost, 0);

  -- ── 4. 광고주 잔액 확인 + 차감 (승인 시점 과금) ──────────────
  IF v_total_cost > 0 THEN
    SELECT id, balance INTO v_wallet_id, v_balance
    FROM public.wallets
    WHERE user_id = v_owner_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
    END IF;

    IF v_balance < v_total_cost THEN
      RETURN json_build_object(
        'success',  false,
        'error',    'INSUFFICIENT_BALANCE',
        'required', v_total_cost,
        'balance',  v_balance
      );
    END IF;

    UPDATE public.wallets
    SET balance = balance - v_total_cost, updated_at = NOW()
    WHERE id = v_wallet_id;

    INSERT INTO public.transactions (user_id, type, amount, status, description)
    VALUES (
      v_owner_id, 'SPEND', v_total_cost, 'COMPLETED',
      FORMAT('광고 승인 — %s', COALESCE(v_seed_keyword, '캠페인'))
    );
  END IF;

  -- ── 5. 태그 재등록 (그룹 내 모든 캠페인에 동일 태그 세트) ────
  --      광고주 등록 태그는 폐기하고 어드민이 수집한 태그로 전면 교체
  DELETE FROM public.campaign_tags
  WHERE campaign_id = ANY (v_campaign_ids);

  FOREACH v_cid IN ARRAY v_campaign_ids LOOP
    v_idx := 0;
    FOREACH v_norm IN ARRAY v_clean_tags LOOP
      v_idx := v_idx + 1;
      INSERT INTO public.campaign_tags (campaign_id, tag_word, sort_order, is_answer)
      VALUES (v_cid, v_norm, v_idx, true);   -- 전부 정답 후보 (랜덤 출제)
    END LOOP;
  END LOOP;

  -- ── 6. 승인 처리 ────────────────────────────────────────────
  UPDATE public.campaigns
  SET status          = 'ACTIVE',
      approval_status = 'APPROVED',
      approved_at     = NOW(),
      approved_by     = auth.uid(),
      reject_reason   = NULL
  WHERE id = ANY (v_campaign_ids);

  RETURN json_build_object(
    'success',        true,
    'campaign_count', array_length(v_campaign_ids, 1),
    'tag_count',      v_tag_count,
    'charged',        v_total_cost
  );
END;
$$;


-- =================================================================
-- 4. reject_campaign(p_group_id, p_reason)
--    등록 시점에 차감된 포인트가 없으므로 환불 처리 불필요
-- =================================================================
CREATE OR REPLACE FUNCTION public.reject_campaign(
  p_group_id UUID,
  p_reason   TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  UPDATE public.campaigns
  SET approval_status = 'REJECTED',
      status          = 'PAUSED',
      approved_at     = NOW(),
      approved_by     = auth.uid(),
      reject_reason   = NULLIF(TRIM(COALESCE(p_reason, '')), '')
  WHERE group_id        = p_group_id
    AND approval_status = 'PENDING';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'NOT_PENDING');
  END IF;

  RETURN json_build_object('success', true, 'campaign_count', v_count);
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- ▼ 20260317000041_random_tag_and_approval_guard.sql
-- ═══════════════════════════════════════════════════════════════

-- =================================================================
-- Phase 22: 랜덤 정답 태그 출제 + 승인 캠페인만 미션 허용
--
-- 변경 내용:
--   1. start_mission
--      - 캠페인 유효성 조건에 approval_status = 'APPROVED' 추가
--        (승인 전 캠페인은 어떤 경로로도 미션 시작 불가)
--      - 정답 태그 선택: is_answer=true 고정 1건 → 등록된 태그 중 ORDER BY RANDOM() 1건
--        → 매 미션마다 "몇 번째 태그"가 랜덤으로 출제된다.
--   2. verify_mission
--      - 제출 태그 비교를 normalize_tag() 기준으로 통일
--        (앱 유저가 '#'을 붙여 입력하거나 공백을 섞어도 정상 매칭)
--
-- 응답 규약 유지:
--   tag_word / assigned_tag_id 는 절대 응답에 포함하지 않는다.
--   유저에게는 tag_index(sort_order)만 전달된다.
-- =================================================================

-- ── 1. start_mission ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.start_mission(
  p_campaign_id  UUID,
  p_user_id      UUID,
  p_device_id    TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log_id     UUID;
  v_started_at TIMESTAMPTZ;
  v_tag_id     UUID;
  v_tag_index  INTEGER;
  v_campaign   public.campaigns%ROWTYPE;
  v_group_id   UUID;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 동일 device_id 중복 계정 차단 ────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.users
    WHERE device_id = p_device_id
      AND id != p_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'DEVICE_ALREADY_REGISTERED');
  END IF;

  -- ── 3. 대상 캠페인의 group_id 조회 ───────────────────────────
  SELECT group_id INTO v_group_id
  FROM public.campaigns
  WHERE id = p_campaign_id;

  -- ── 4. 그룹 기반 일일 참여 제한 ──────────────────────────────
  IF v_group_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.mission_logs
      WHERE group_id = v_group_id
        AND user_id  = p_user_id
        AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
            = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
        AND status IN ('IN_PROGRESS', 'SUCCESS')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_PARTICIPATED_TODAY');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.mission_logs
      WHERE campaign_id = p_campaign_id
        AND user_id     = p_user_id
        AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
            = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
        AND status IN ('IN_PROGRESS', 'SUCCESS')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'ALREADY_PARTICIPATED_TODAY');
    END IF;
  END IF;

  -- ── 5. 캠페인 유효성 + remaining_slots SELECT FOR UPDATE ─────
  --      승인 완료(APPROVED) 캠페인만 미션 시작 가능
  SELECT * INTO v_campaign
  FROM public.campaigns
  WHERE id              = p_campaign_id
    AND status          = 'ACTIVE'
    AND approval_status = 'APPROVED'
    AND expires_at      > NOW()
    AND remaining_slots > 0
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'CAMPAIGN_UNAVAILABLE');
  END IF;

  -- ── 6. 캠페인 일일 슬롯 초과 차단 ────────────────────────────
  IF (
    SELECT COUNT(*) FROM public.mission_logs
    WHERE campaign_id = p_campaign_id
      AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
          = (NOW()    AT TIME ZONE 'Asia/Seoul')::DATE
      AND status IN ('IN_PROGRESS', 'SUCCESS')
  ) >= v_campaign.daily_target THEN
    RETURN json_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED');
  END IF;

  -- ── 7. remaining_slots 차감 ──────────────────────────────────
  UPDATE public.campaigns
  SET remaining_slots = remaining_slots - 1
  WHERE id = p_campaign_id;

  -- ── 8. 정답 태그 랜덤 할당 ───────────────────────────────────
  --      어드민이 등록한 태그 풀에서 매번 무작위로 1개 선택.
  --      tag_word 응답 포함 금지 — sort_order만 tag_index로 반환.
  SELECT id, sort_order INTO v_tag_id, v_tag_index
  FROM public.campaign_tags
  WHERE campaign_id = p_campaign_id
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_tag_id IS NULL THEN
    -- 태그가 없으면 슬롯 복구 후 오류 반환 (승인 절차상 발생하지 않아야 정상)
    UPDATE public.campaigns
    SET remaining_slots = remaining_slots + 1
    WHERE id = p_campaign_id;
    RETURN json_build_object('success', false, 'error', 'NO_TAGS_AVAILABLE');
  END IF;

  -- ── 9. mission_log INSERT (group_id 포함) ────────────────────
  INSERT INTO public.mission_logs
    (campaign_id, user_id, device_id, assigned_tag_id, status, started_at, group_id)
  VALUES
    (p_campaign_id, p_user_id, p_device_id, v_tag_id, 'IN_PROGRESS', NOW(), v_group_id)
  RETURNING id, started_at INTO v_log_id, v_started_at;

  -- ── 10. 성공 응답 ────────────────────────────────────────────
  RETURN json_build_object(
    'success',    true,
    'log_id',     v_log_id,
    'keyword',    v_campaign.keyword,
    'started_at', v_started_at,
    'tag_index',  v_tag_index
  );

END;
$$;


-- ── 2. verify_mission — 태그 비교를 normalize_tag 기준으로 통일 ──
CREATE OR REPLACE FUNCTION public.verify_mission(
  p_log_id        UUID,
  p_user_id       UUID,
  p_submitted_tag TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log       mission_logs%ROWTYPE;
  v_tag_word  TEXT;
  v_reward    INTEGER := 7;
  v_wallet_id UUID;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  SELECT * INTO v_log FROM public.mission_logs
    WHERE id = p_log_id AND user_id = p_user_id AND status = 'IN_PROGRESS'
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  -- 10분 타임아웃 블록 없음 (migration 0034에서 의도적으로 제거)

  SELECT tag_word INTO v_tag_word FROM public.campaign_tags
    WHERE id = v_log.assigned_tag_id;

  IF v_tag_word IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  -- '#' / 공백 / 대소문자 차이를 무시하고 비교
  IF public.normalize_tag(p_submitted_tag) <> public.normalize_tag(v_tag_word) THEN
    RETURN json_build_object('success', false, 'error', 'WRONG_TAG');
  END IF;

  SELECT id INTO v_wallet_id FROM public.wallets
    WHERE user_id = p_user_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  UPDATE public.wallets
    SET balance = balance + v_reward, updated_at = NOW()
    WHERE id = v_wallet_id;

  INSERT INTO public.transactions (user_id, type, amount, status, description)
    VALUES (p_user_id, 'EARN', v_reward, 'COMPLETED', '미션 성공 리워드');

  UPDATE public.mission_logs
    SET status = 'SUCCESS', completed_at = NOW()
    WHERE id = p_log_id;

  RETURN json_build_object('success', true, 'earned', v_reward);
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- ▼ 20260317000042_update_dashboard_approval.sql
-- ═══════════════════════════════════════════════════════════════

-- =================================================================
-- Phase 22: get_dashboard_data RPC — 승인 상태 반영
--
-- 변경 내용:
--   1. 그룹 상태 집계에 승인 상태 추가
--      PENDING  : 그룹 내 승인 대기 캠페인이 하나라도 있으면 (어드민 검수 중)
--      ACTIVE   : 승인 완료 + ACTIVE 캠페인이 하나라도 있으면
--      REJECTED : 승인 거절된 그룹
--      ENDED    : 그 외 (기간 종료 등)
--   2. active_count(진행중 광고 수)에서 승인 대기 그룹 제외
--
-- 나머지 로직은 migration 0030과 동일.
-- =================================================================

CREATE OR REPLACE FUNCTION public.get_dashboard_data()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       UUID    := auth.uid();
  v_balance       INTEGER;
  v_active_count  INTEGER;
  v_today_traffic INTEGER;
  v_today_kst     DATE;
  v_campaigns     JSON;
BEGIN

  -- ── 인증 확인 ───────────────────────────────────────────────
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- ── KST 기준 오늘 날짜 ─────────────────────────────────────
  v_today_kst := (NOW() AT TIME ZONE 'Asia/Seoul')::DATE;

  -- ── 잔여 포인트 ─────────────────────────────────────────────
  SELECT COALESCE(balance, 0) INTO v_balance
  FROM public.wallets
  WHERE user_id = v_user_id;

  -- ── 진행중 광고 그룹 수 ────────────────────────────────────
  --    ACTIVE 캠페인이 1개 이상인 그룹의 수 (기존: ACTIVE 캠페인 행 수)
  SELECT COUNT(DISTINCT group_id) INTO v_active_count
  FROM public.campaigns
  WHERE user_id         = v_user_id
    AND status          = 'ACTIVE'
    AND approval_status = 'APPROVED';

  -- ── 오늘 총 유입수 (내 캠페인 전체 그룹 합산) ────────────────
  SELECT COALESCE(COUNT(*), 0) INTO v_today_traffic
  FROM public.mission_logs ml
  JOIN public.campaigns c ON c.id = ml.campaign_id
  WHERE c.user_id = v_user_id
    AND ml.status = 'SUCCESS'
    AND (ml.completed_at AT TIME ZONE 'Asia/Seoul')::DATE = v_today_kst;

  -- ── 내 캠페인 그룹 목록 (group_id 기준 집계, 최초 등록 역순) ──
  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.first_created DESC), '[]'::JSON)
  INTO v_campaigns
  FROM (
    SELECT
      c.group_id,

      -- 그룹 상태: ACTIVE 캠페인이 하나라도 있으면 ACTIVE, 아니면 ENDED
      CASE
        WHEN bool_or(c.approval_status = 'PENDING')  THEN 'PENDING'
        WHEN bool_or(c.status = 'ACTIVE'
                 AND c.approval_status = 'APPROVED') THEN 'ACTIVE'
        WHEN bool_or(c.approval_status = 'REJECTED') THEN 'REJECTED'
        ELSE 'ENDED'
      END AS status,

      -- 그룹 전체 일일 목표 (서브키워드 전체 공통값)
      MAX(c.group_daily_target) AS group_daily_target,

      -- 서브키워드 배열 (등록 순서대로)
      array_agg(c.keyword ORDER BY c.created_at ASC) AS sub_keywords,

      -- 그룹 최초 등록 시각 (정렬용)
      MIN(c.created_at) AS first_created,

      -- 대표 캠페인 ID: 그룹 내 최초 등록 (순위 차트, 상세 라우팅 기준)
      (
        SELECT c2.id
        FROM public.campaigns c2
        WHERE c2.group_id  = c.group_id
          AND c2.user_id   = v_user_id
        ORDER BY c2.created_at ASC
        LIMIT 1
      ) AS representative_campaign_id,

      -- 순위 추적 대표 키워드 (그룹 내 공통)
      (
        SELECT c2.seed_keyword
        FROM public.campaigns c2
        WHERE c2.group_id = c.group_id
          AND c2.user_id  = v_user_id
        ORDER BY c2.created_at ASC
        LIMIT 1
      ) AS seed_keyword,

      -- 오늘 그룹 전체 SUCCESS 건수 (KST 기준)
      (
        SELECT COUNT(*)
        FROM public.mission_logs ml
        JOIN public.campaigns c2 ON c2.id = ml.campaign_id
        WHERE c2.group_id = c.group_id
          AND c2.user_id  = v_user_id
          AND ml.status   = 'SUCCESS'
          AND (ml.completed_at AT TIME ZONE 'Asia/Seoul')::DATE = v_today_kst
      ) AS today_count,

      -- 그룹 전체 누적 SUCCESS 건수
      (
        SELECT COUNT(*)
        FROM public.mission_logs ml
        JOIN public.campaigns c2 ON c2.id = ml.campaign_id
        WHERE c2.group_id = c.group_id
          AND c2.user_id  = v_user_id
          AND ml.status   = 'SUCCESS'
      ) AS total_count,

      -- 현재 순위: 대표 캠페인 기준 최신 campaign_rank_history
      (
        SELECT rh.rank
        FROM public.campaign_rank_history rh
        WHERE rh.campaign_id = (
          SELECT c2.id
          FROM public.campaigns c2
          WHERE c2.group_id = c.group_id
            AND c2.user_id  = v_user_id
          ORDER BY c2.created_at ASC
          LIMIT 1
        )
        ORDER BY rh.checked_at DESC
        LIMIT 1
      ) AS current_rank

    FROM public.campaigns c
    WHERE c.user_id = v_user_id
    GROUP BY c.group_id
  ) t;

  -- ── 응답 ────────────────────────────────────────────────────
  RETURN json_build_object(
    'success',       true,
    'balance',       v_balance,
    'active_count',  v_active_count,
    'today_traffic', v_today_traffic,
    'campaigns',     v_campaigns
  );

END;
$$;
