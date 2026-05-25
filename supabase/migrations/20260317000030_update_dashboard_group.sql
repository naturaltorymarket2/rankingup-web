-- =================================================================
-- get_dashboard_data RPC: 그룹 단위 집계
--
-- 변경 내용:
--   기존: campaign_id별 1행 반환 (서브키워드 수만큼 행 생성)
--   변경: group_id별 1행 반환 (서브키워드들을 집계)
--
-- 반환 필드 변경:
--   기존: id, keyword, daily_target, status, current_rank, today_success
--   변경: group_id, seed_keyword, status, group_daily_target,
--         sub_keywords(TEXT[]), today_count, total_count,
--         current_rank, representative_campaign_id
--
-- 상태 집계 규칙:
--   그룹 내 캠페인 중 하나라도 ACTIVE이면 → 'ACTIVE'
--   전부 ACTIVE가 아니면 → 'ENDED'
--
-- 유입수 집계:
--   today_count, total_count = 그룹 내 모든 캠페인의 SUCCESS mission_logs 합산
--
-- 순위:
--   representative_campaign_id (그룹 내 최초 등록 캠페인) 기준 최신 rank
--
-- active_count:
--   ACTIVE 캠페인이 1개 이상인 그룹 수 (기존: ACTIVE 캠페인 수)
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
  WHERE user_id = v_user_id
    AND status  = 'ACTIVE';

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
      CASE WHEN bool_or(c.status = 'ACTIVE') THEN 'ACTIVE' ELSE 'ENDED' END AS status,

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
