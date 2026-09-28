-- =================================================================
-- Phase 30: 등록 시점 순위 보관
--
-- 배경:
--   어드민 키워드 수정 화면에서 어떤 키워드를 고쳐야 하는지 알 수 없었다.
--   [순위 확인]을 키워드마다 눌러야 했고, 한 번 누를 때마다 SerpApi
--   쿼터(무료 월 250회)를 쓴다.
--
--   광고주가 등록할 때 이미 통합검색 순위를 조회해 화면에 보여 준다.
--   그 값을 버리지 말고 저장해 두면, 어드민은 쿼터를 쓰지 않고도
--   8위 밖 키워드를 바로 가려낼 수 있다.
--
-- 값의 의미:
--   campaigns.initial_rank = 등록 시점의 네이버 '통합검색' 노출 순위(1~10).
--   NULL 은 두 가지를 뜻한다 — 순위권 밖이었거나, 조회하지 않았거나.
--   구분을 위해 initial_rank_at 을 함께 둔다(조회했으면 시각이 남는다).
--
--   ⚠️ campaign_rank_history.rank 와 기준이 다르다. 그쪽은 로컬 크롤러가
--   매기는 '쇼핑 검색' 순위(최대 500위)다. 섞어 쓰지 않는다.
-- =================================================================

-- ── 1. 컬럼 추가 ────────────────────────────────────────────────
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS initial_rank    INTEGER,
  ADD COLUMN IF NOT EXISTS initial_rank_at TIMESTAMPTZ;

COMMENT ON COLUMN public.campaigns.initial_rank IS
  '등록 시점 통합검색 노출 순위(1~10). NULL = 순위권 밖 또는 미조회.';
COMMENT ON COLUMN public.campaigns.initial_rank_at IS
  '등록 시점 순위를 조회한 시각. NULL 이면 조회하지 않았다는 뜻.';


-- =================================================================
-- 2. register_campaign — p_initial_rank 추가
--
--    기존 시그니처(migration 0039)에 파라미터 하나를 더한 것 외에는
--    동작이 같다. 오버로드가 남으면 모호성이 생기므로 전부 DROP 후 재정의.
-- =================================================================
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

CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id            UUID,
  p_product_url        TEXT,
  p_keyword            TEXT,
  p_daily_target       INTEGER,
  p_group_daily_target INTEGER,
  p_group_id           UUID,
  p_start_date         DATE,
  p_end_date           DATE,
  p_seed_keyword       TEXT    DEFAULT NULL,
  p_product_name       TEXT    DEFAULT NULL,
  p_brand_name         TEXT    DEFAULT NULL,
  p_initial_rank       INTEGER DEFAULT NULL,
  p_rank_checked       BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
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

  -- ── 잔액 확인 (차감은 승인 시점) ────────────────────────────
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
    seed_keyword, product_name, brand_name,
    initial_rank, initial_rank_at
  ) VALUES (
    p_user_id, p_product_url, p_keyword,
    p_daily_target, p_group_daily_target, p_group_id,
    p_start_date, p_end_date, v_expires_at,
    v_duration_days,
    CASE WHEN v_is_first THEN p_group_daily_target * v_duration_days * 50 ELSE 0 END,
    'PAUSED',    -- 승인 전까지 미션 보드 미노출
    'PENDING',
    p_daily_target,
    p_seed_keyword, p_product_name, p_brand_name,
    p_initial_rank,
    -- 순위를 조회한 경우에만 시각을 남긴다.
    -- (조회했는데 순위권 밖이면 rank 는 NULL, 시각은 기록된다)
    CASE WHEN p_rank_checked THEN NOW() ELSE NULL END
  )
  RETURNING id INTO v_campaign_id;

  RETURN json_build_object(
    'success',     true,
    'campaign_id', v_campaign_id,
    'status',      'PENDING_APPROVAL'
  );
END;
$fn$;


-- =================================================================
-- 3. get_campaign_keywords — 등록 시점 순위 함께 반환
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_campaign_keywords(p_group_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rows JSON;
  v_seed TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT MAX(seed_keyword) INTO v_seed
  FROM public.campaigns WHERE group_id = p_group_id;

  SELECT COALESCE(json_agg(json_build_object(
           'campaign_id',     c.id,
           'keyword',         c.keyword,
           'initial_rank',    c.initial_rank,
           'rank_checked',    (c.initial_rank_at IS NOT NULL)
         ) ORDER BY c.created_at ASC), '[]'::JSON)
  INTO v_rows
  FROM public.campaigns c
  WHERE c.group_id = p_group_id;

  IF v_rows::TEXT = '[]' THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  RETURN json_build_object(
    'success',      true,
    'seed_keyword', v_seed,
    'keywords',     v_rows
  );
END;
$fn$;
