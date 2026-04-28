-- =================================================================
-- 대시보드 지원 — campaign_rank_history 테이블 + RLS + RPC
--
-- 변경 사항:
--   1. campaign_rank_history 테이블 생성 (파이썬 랭킹 모듈이 주기적으로 INSERT)
--   2. mission_logs에 광고주 조회 정책 추가 (자신의 캠페인 로그 집계용)
--   3. RPC get_dashboard_data() — 요약 + 캠페인 목록 한 번에 반환
--
-- 파이썬 랭킹 모듈 연동 전까지 rank_history는 빈 상태
-- (Phase 4: 파이썬 모듈 연동 시 service_role로 INSERT)
-- =================================================================

-- -----------------------------------------------------------------
-- 1. campaign_rank_history 테이블
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_rank_history (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  UUID        NOT NULL
               REFERENCES public.campaigns(id) ON DELETE CASCADE,
  rank         INTEGER     NOT NULL CHECK (rank > 0),
  checked_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rank_history_campaign_time
  ON public.campaign_rank_history(campaign_id, checked_at DESC);

ALTER TABLE public.campaign_rank_history ENABLE ROW LEVEL SECURITY;

-- 광고주는 본인 캠페인의 순위 이력 조회 가능
CREATE POLICY rank_history_owner_select ON public.campaign_rank_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = campaign_id
        AND c.user_id = auth.uid()
    )
  );

-- -----------------------------------------------------------------
-- 2. mission_logs — 광고주 조회 정책 추가
--    (자신의 캠페인에 대한 미션 로그 집계용)
--    기존 mission_logs_self_select 와 OR 관계로 작동
-- -----------------------------------------------------------------
CREATE POLICY mission_logs_campaign_owner_select ON public.mission_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = campaign_id
        AND c.user_id = auth.uid()
    )
  );

-- -----------------------------------------------------------------
-- 3. RPC: get_dashboard_data
--    반환: balance, active_count, today_traffic, campaigns(최대 5개)
--
--    campaigns 각 항목:
--      id, keyword, daily_target, status,
--      current_rank (rank_history 최신값, NULL 가능),
--      today_success (오늘 KST 기준 SUCCESS 건수)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_dashboard_data()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID    := auth.uid();
  v_balance      INTEGER;
  v_active_count INTEGER;
  v_today_traffic INTEGER;
  v_today_kst    DATE;
  v_campaigns    JSON;
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

  -- ── 내 캠페인 목록 (최대 5개, 최신 등록 순) ─────────────────
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
    LIMIT 5
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
