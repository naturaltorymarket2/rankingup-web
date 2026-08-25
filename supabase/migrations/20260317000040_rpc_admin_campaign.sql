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
