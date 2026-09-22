-- =================================================================
-- Phase 29: 상품 태그 자동 수집
--
-- 배경:
--   승인은 운영자가 상품 페이지에 들어가 #태그를 직접 복사해 붙여넣는
--   방식이다. 건당 1~2분이 걸려 광고가 늘면 여기가 병목이 된다.
--   엑셀 대량 등록으로 한 번에 수십 건이 들어오면 감당할 수 없다.
--
--   크롤러가 미리 상품 페이지에서 태그를 긁어 두면, 운영자는 화면에
--   채워진 태그를 확인하고 승인만 누르면 된다.
--
-- 중요:
--   수집한 태그는 '초안'이다. 정답 태그 풀(campaign_tags)은 지금처럼
--   운영자가 승인할 때 확정된다. 잘못 긁힌 태그를 그대로 쓰면 유저가
--   맞힐 수 없는 문제가 출제되므로, 사람의 확인 단계를 없애지 않는다.
-- =================================================================

-- ── 1. 수집 결과 보관 ───────────────────────────────────────────
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS scraped_tags TEXT[],
  ADD COLUMN IF NOT EXISTS scraped_at   TIMESTAMPTZ;

COMMENT ON COLUMN public.campaigns.scraped_tags IS
  '크롤러가 상품 페이지에서 수집한 #태그 초안. 승인 화면 자동 입력용이며 정답 풀이 아니다.';

-- ── 2. 승인 대기 목록에 수집 태그 포함 ──────────────────────────
CREATE OR REPLACE FUNCTION public.get_pending_campaigns()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
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
      -- 크롤러가 수집한 태그 초안 (그룹 내 어느 캠페인에든 있으면 쓴다)
      (
        SELECT c3.scraped_tags FROM public.campaigns c3
        WHERE c3.group_id = c.group_id
          AND c3.scraped_tags IS NOT NULL
        ORDER BY c3.scraped_at DESC NULLS LAST
        LIMIT 1
      )                                                   AS scraped_tags,
      (
        SELECT c4.scraped_at FROM public.campaigns c4
        WHERE c4.group_id = c.group_id
          AND c4.scraped_tags IS NOT NULL
        ORDER BY c4.scraped_at DESC NULLS LAST
        LIMIT 1
      )                                                   AS scraped_at,
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
$fn$;

-- ── 3. 크롤러가 수집 결과를 저장하는 함수 ───────────────────────
--     service_role(로컬 크롤러)만 호출한다. 클라이언트는 호출하지 않는다.
CREATE OR REPLACE FUNCTION public.save_scraped_tags(
  p_group_id UUID,
  p_tags     TEXT[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.campaigns
     SET scraped_tags = p_tags,
         scraped_at   = NOW()
   WHERE group_id = p_group_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.save_scraped_tags(UUID, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_scraped_tags(UUID, TEXT[]) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.save_scraped_tags(UUID, TEXT[]) TO service_role;
