-- =================================================================
-- Phase 23 적용 SQL — Supabase SQL Editor 에 전체 붙여넣고 실행
--
--   1) 테스트용으로 등록됐던 광고 전부 삭제
--   2) 어드민 광고 삭제 기능 (delete_campaign_group / get_all_campaigns)
--   3) 순위 기록에 '500위 밖'(rank = NULL) 저장 허용
--
-- 중복 실행해도 안전하다.
-- =================================================================

-- ── 1. 기존 테스트 광고 전부 삭제 ────────────────────────────────
--    미션 이력 → 순위 기록 → 태그 → 캠페인 순으로 지운다.
--    (포인트는 환불하지 않는다 — 테스트 데이터이므로)
DELETE FROM public.mission_logs
 WHERE campaign_id IN (SELECT id FROM public.campaigns);
DELETE FROM public.campaign_rank_history
 WHERE campaign_id IN (SELECT id FROM public.campaigns);
DELETE FROM public.campaign_tags
 WHERE campaign_id IN (SELECT id FROM public.campaigns);
DELETE FROM public.campaigns;

-- 삭제 결과 확인 (0 이어야 정상)
SELECT COUNT(*) AS remaining_campaigns FROM public.campaigns;


-- =================================================================
-- Phase 23: 어드민 광고 삭제 기능
--
-- 어드민이 광고(그룹)를 완전히 삭제한다. 승인 대기/승인 완료/거절 상태
-- 모두 삭제 가능하며, 그룹에 속한 서브키워드 캠페인이 함께 지워진다.
--
-- 삭제 범위 (자식 테이블부터 순서대로):
--   mission_logs          미션 수행 이력
--   campaign_rank_history 순위 추이 기록
--   campaign_tags         정답 태그
--   campaigns             캠페인 본체
--
-- ⚠️ 포인트는 환불하지 않는다.
--    승인 완료된 광고를 삭제하면 이미 차감된 예산은 그대로 소멸한다.
--    환불이 필요하면 어드민이 충전 승인으로 별도 처리한다.
-- =================================================================

CREATE OR REPLACE FUNCTION public.delete_campaign_group(p_group_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign_ids UUID[];
  v_count        INTEGER;
  v_logs         INTEGER;
BEGIN
  -- ── 1. 권한 확인 ────────────────────────────────────────────
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  -- ── 2. 대상 캠페인 수집 ─────────────────────────────────────
  SELECT array_agg(id) INTO v_campaign_ids
  FROM public.campaigns
  WHERE group_id = p_group_id;

  IF v_campaign_ids IS NULL OR array_length(v_campaign_ids, 1) IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  v_count := array_length(v_campaign_ids, 1);

  -- ── 3. 자식 레코드부터 삭제 ─────────────────────────────────
  SELECT COUNT(*) INTO v_logs
  FROM public.mission_logs
  WHERE campaign_id = ANY (v_campaign_ids);

  DELETE FROM public.mission_logs          WHERE campaign_id = ANY (v_campaign_ids);
  DELETE FROM public.campaign_rank_history WHERE campaign_id = ANY (v_campaign_ids);
  DELETE FROM public.campaign_tags         WHERE campaign_id = ANY (v_campaign_ids);
  DELETE FROM public.campaigns             WHERE id          = ANY (v_campaign_ids);

  RETURN json_build_object(
    'success',        true,
    'campaign_count', v_count,
    'mission_count',  v_logs
  );
END;
$$;


-- =================================================================
-- 어드민 전체 광고 목록 조회 (승인 상태 무관)
--
-- 기존 get_pending_campaigns / get_processed_campaigns 는 상태별로
-- 나뉘어 있어 삭제 대상을 한눈에 보기 어렵다. 삭제 화면용으로
-- 전체 그룹을 최신순으로 반환한다.
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_all_campaigns()
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

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::JSON)
  INTO v_rows
  FROM (
    SELECT
      c.group_id,
      MIN(c.created_at)                              AS created_at,
      MAX(c.approval_status)                         AS approval_status,
      MAX(u.email)                                   AS user_email,
      MAX(c.product_name)                            AS product_name,
      MAX(c.brand_name)                              AS brand_name,
      MAX(c.product_url)                             AS product_url,
      MAX(c.seed_keyword)                            AS seed_keyword,
      array_agg(c.keyword ORDER BY c.created_at ASC) AS sub_keywords,
      MAX(c.group_daily_target)                      AS group_daily_target,
      MAX(c.duration_days)                           AS duration_days,
      MIN(c.start_date)                              AS start_date,
      MAX(c.end_date)                                AS end_date,
      SUM(c.budget)                                  AS budget,
      COUNT(*)                                       AS campaign_count,
      MAX(c.reject_reason)                           AS reject_reason,
      (
        SELECT c2.id FROM public.campaigns c2
        WHERE c2.group_id = c.group_id
        ORDER BY c2.created_at ASC LIMIT 1
      )                                              AS representative_campaign_id,
      (
        SELECT COUNT(*) FROM public.mission_logs ml
        WHERE ml.group_id = c.group_id
      )                                              AS mission_count
    FROM public.campaigns c
    JOIN public.users u ON u.id = c.user_id
    GROUP BY c.group_id
  ) t;

  RETURN json_build_object('success', true, 'campaigns', v_rows);
END;
$$;

-- =================================================================
-- 순위 기록: '500위 밖'을 표현할 수 있도록 rank 를 NULL 허용으로 변경
--
-- 메인(시드) 키워드는 로컬 크롤러가 매일 1회 네이버 쇼핑 검색을 훑어
-- 최대 500위까지 확인한다. 500위 안에 없으면 rank = NULL 로 기록하고
-- 화면에는 '500위 밖'으로 표시한다.
-- (기존에는 NOT NULL 이라 미노출을 아예 기록할 수 없어 차트가 비어 있었다)
-- =================================================================

ALTER TABLE public.campaign_rank_history
  ALTER COLUMN rank DROP NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'campaign_rank_history_rank_check'
  ) THEN
    ALTER TABLE public.campaign_rank_history
      DROP CONSTRAINT campaign_rank_history_rank_check;
  END IF;

  ALTER TABLE public.campaign_rank_history
    ADD CONSTRAINT campaign_rank_history_rank_check
    CHECK (rank IS NULL OR rank > 0);
END $$;

-- 크롤러가 어디까지 확인했는지 기록 (예: 500위까지 확인했으나 미발견)
ALTER TABLE public.campaign_rank_history
  ADD COLUMN IF NOT EXISTS checked_to INTEGER;
