-- =================================================================
-- get_dashboard_data RPC: 캠페인 목록 LIMIT 5 제거
--
-- 배경:
--   migration 0008에서 get_dashboard_data의 campaigns 서브쿼리에
--   LIMIT 5가 하드코딩되어 있음.
--   → 캠페인이 6개 이상이면 목록에 5개만 표시됨.
--
-- 수정:
--   LIMIT 5 제거 → 본인 캠페인 전체 반환 (최신 등록 순)
--   그 외 모든 로직은 migration 0008과 동일
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

  -- ── 진행중 광고 건수 ─────────────────────────────────────────
  SELECT COUNT(*) INTO v_active_count
  FROM public.campaigns
  WHERE user_id = v_user_id
    AND status = 'ACTIVE';

  -- ── 오늘 총 유입수 (내 캠페인 전체 합계) ────────────────────
  SELECT COALESCE(COUNT(*), 0) INTO v_today_traffic
  FROM public.mission_logs ml
  JOIN public.campaigns c ON c.id = ml.campaign_id
  WHERE c.user_id = v_user_id
    AND ml.status = 'SUCCESS'
    AND (ml.completed_at AT TIME ZONE 'Asia/Seoul')::DATE = v_today_kst;

  -- ── 내 캠페인 목록 전체 (최신 등록 순) ──────────────────────
  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON) INTO v_campaigns
  FROM (
    SELECT
      c.id,
      c.keyword,
      c.daily_target,
      c.status,
      -- 최신 순위 (rank_history 없으면 NULL)
      (
        SELECT rh.rank
        FROM public.campaign_rank_history rh
        WHERE rh.campaign_id = c.id
        ORDER BY rh.checked_at DESC
        LIMIT 1
      ) AS current_rank,
      -- 오늘 KST 기준 SUCCESS 건수
      (
        SELECT COUNT(*)
        FROM public.mission_logs ml
        WHERE ml.campaign_id = c.id
          AND ml.status = 'SUCCESS'
          AND (ml.completed_at AT TIME ZONE 'Asia/Seoul')::DATE = v_today_kst
      ) AS today_success
    FROM public.campaigns c
    WHERE c.user_id = v_user_id
    ORDER BY c.created_at DESC
    -- LIMIT 제거: 캠페인 수에 관계없이 전체 반환
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
