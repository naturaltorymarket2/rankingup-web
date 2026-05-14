-- =================================================================
-- register_campaign 시그니처 수정 (migration 0018 회귀 버그 해결)
--
-- 배경:
--   migration 0009: p_start_date / p_end_date 방식으로 변경
--   migration 0018: p_duration_days 방식으로 다시 되돌림 ← 회귀 버그
--   migration 0019: p_start_date / p_end_date + p_answer_index 로 재수정
--
--   Supabase에 0018만 적용되고 0019가 미적용인 경우:
--     Flutter campaign_repository.dart가 보내는 파라미터
--       (p_start_date, p_end_date, p_answer_index, p_seed_keyword)
--     와 DB 함수 시그니처가 완전 불일치 → 캠페인 등록 전면 장애
--
-- 수정:
--   올바른 시그니처를 강제 적용 (Flutter campaign_repository.dart와 완전 일치)
--     p_start_date DATE, p_end_date DATE    (p_duration_days 제거)
--     p_answer_index INTEGER                (정답 태그 인덱스, 필수)
--     p_seed_keyword TEXT DEFAULT NULL      (순위 추적용)
--
-- 전제 조건:
--   campaigns.seed_keyword, start_date, end_date 컬럼
--   campaign_tags.is_answer, sort_order 컬럼
--   → 이 migration에서 IF NOT EXISTS로 모두 안전하게 보장
-- =================================================================

-- ── 필수 컬럼 보장 (migration 0018, 0019 미적용 대비) ─────────────

-- campaigns: seed_keyword (migration 0018)
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS seed_keyword TEXT;

-- campaigns: start_date, end_date (migration 0009)
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS end_date   DATE;

-- campaign_tags: is_answer, sort_order (migration 0019)
ALTER TABLE public.campaign_tags
  ADD COLUMN IF NOT EXISTS is_answer  BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;


-- =================================================================
-- register_campaign RPC (올바른 시그니처 — Flutter 코드와 완전 일치)
--
-- Flutter campaign_repository.dart 파라미터 매핑:
--   'p_user_id'      → userId       (UUID)
--   'p_product_url'  → productUrl   (TEXT)
--   'p_keyword'      → keyword      (TEXT)
--   'p_daily_target' → dailyTarget  (INTEGER)
--   'p_start_date'   → startDate    (DATE, "YYYY-MM-DD")
--   'p_end_date'     → endDate      (DATE, "YYYY-MM-DD")
--   'p_tags'         → tags         (TEXT[])
--   'p_answer_index' → answerIndex  (INTEGER, 1-based)
--   'p_seed_keyword' → seedKeyword  (TEXT, nullable)
-- =================================================================
CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id       UUID,
  p_product_url   TEXT,
  p_keyword       TEXT,
  p_daily_target  INTEGER,
  p_start_date    DATE,
  p_end_date      DATE,
  p_tags          TEXT[],
  p_answer_index  INTEGER,           -- 정답 태그 인덱스 (1-based, 필수)
  p_seed_keyword  TEXT DEFAULT NULL  -- 시드 키워드 (순위 추적용). NULL이면 p_keyword 사용
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_duration_days INTEGER;
  v_budget        INTEGER;
  v_wallet_id     UUID;
  v_campaign_id   UUID;
  v_tag           TEXT;
  v_tag_idx       INTEGER := 0;
  v_seed_keyword  TEXT;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 파라미터 유효성 검증 ──────────────────────────────────
  IF p_daily_target <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_product_url = '' OR p_keyword = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  -- 태그 최소 2개 필수
  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) < 2 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;

  -- 정답 인덱스 범위 검증 (1 ≤ p_answer_index ≤ 태그 수)
  IF p_answer_index IS NULL
  OR p_answer_index < 1
  OR p_answer_index > array_length(p_tags, 1) THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_ANSWER_INDEX');
  END IF;

  -- ── 3. 기간 계산 및 최소 7일 검증 ────────────────────────────
  v_duration_days := p_end_date - p_start_date + 1;

  IF v_duration_days < 7 THEN
    RETURN json_build_object(
      'success', false,
      'error',   'DURATION_TOO_SHORT',
      'minimum', 7
    );
  END IF;

  -- seed_keyword: 빈 문자열이면 NULL 저장 (하위 호환)
  v_seed_keyword := NULLIF(TRIM(COALESCE(p_seed_keyword, '')), '');

  -- ── 4. 예산 계산: 일일 유입 × 기간(일) × 50원 ───────────────
  v_budget := p_daily_target * v_duration_days * 50;

  -- ── 5. 잔액 확인 + 지갑 잠금 (SELECT FOR UPDATE) ─────────────
  SELECT id INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = p_user_id
    AND balance >= v_budget
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success',  false,
      'error',    'INSUFFICIENT_BALANCE',
      'required', v_budget
    );
  END IF;

  -- ── 6. 예산 즉시 차감 ────────────────────────────────────────
  UPDATE public.wallets
  SET balance    = balance - v_budget,
      updated_at = NOW()
  WHERE id = v_wallet_id;

  -- ── 7. SPEND 거래 내역 INSERT ─────────────────────────────────
  INSERT INTO public.transactions (user_id, type, amount, status, description)
  VALUES (
    p_user_id,
    'SPEND',
    v_budget,
    'COMPLETED',
    FORMAT(
      '캠페인 등록 — 키워드: %s | %s ~ %s (%s일) × 일 %s명 × 50P',
      p_keyword,
      TO_CHAR(p_start_date, 'YYYY-MM-DD'),
      TO_CHAR(p_end_date,   'YYYY-MM-DD'),
      v_duration_days,
      p_daily_target
    )
  );

  -- ── 8. 캠페인 INSERT ──────────────────────────────────────────
  INSERT INTO public.campaigns (
    user_id, product_url, keyword, seed_keyword,
    daily_target, duration_days, budget,
    remaining_slots, status,
    start_date, end_date, expires_at
  )
  VALUES (
    p_user_id, p_product_url, p_keyword, v_seed_keyword,
    p_daily_target, v_duration_days, v_budget,
    p_daily_target * v_duration_days,
    'ACTIVE',
    p_start_date,
    p_end_date,
    p_end_date::TIMESTAMPTZ + INTERVAL '1 day'
  )
  RETURNING id INTO v_campaign_id;

  -- ── 9. 태그 INSERT (sort_order + is_answer 포함) ───────────────
  --      p_answer_index 번째 태그에만 is_answer=true 설정
  FOREACH v_tag IN ARRAY p_tags LOOP
    v_tag_idx := v_tag_idx + 1;
    INSERT INTO public.campaign_tags (campaign_id, tag_word, sort_order, is_answer)
    VALUES (v_campaign_id, TRIM(v_tag), v_tag_idx, (v_tag_idx = p_answer_index));
  END LOOP;

  -- ── 10. 성공 응답 ─────────────────────────────────────────────
  RETURN json_build_object(
    'success',     true,
    'campaign_id', v_campaign_id,
    'budget',      v_budget,
    'duration',    v_duration_days
  );

END;
$$;
