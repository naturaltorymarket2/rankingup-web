-- =================================================================
-- 순위 추이 차트 테스트 데이터 삽입
--
-- 대상 캠페인: "공부의자", "헬스장갑 여성용"
-- 목적:
--   1) 최근 7일치 날짜별 1건 → 기본 차트 렌더링 확인
--   2) 같은 날짜에 추가 2건 → fetchRankHistory 중복 제거 로직 검증
--      (putIfAbsent: 최신 1건만 남아야 함 — 총 7포인트가 나와야 정상)
--
-- 실행 전 주의:
--   해당 키워드의 캠페인이 존재해야 함.
--   없으면 campaign_id 조회 결과가 NULL이 되어 INSERT가 스킵됨.
--
-- 실행 방법:
--   Supabase SQL Editor에 전체 붙여넣기 후 Run
-- =================================================================

DO $$
DECLARE
  v_campaign_chair  UUID;
  v_campaign_glove  UUID;

  -- KST 기준 오늘 UTC 자정 (KST 00:00 = UTC 전날 15:00)
  v_today_kst_utc   TIMESTAMPTZ := DATE_TRUNC('day', NOW() AT TIME ZONE 'Asia/Seoul')
                                   AT TIME ZONE 'Asia/Seoul';
BEGIN

  -- ── 캠페인 ID 조회 ────────────────────────────────────────────────
  SELECT id INTO v_campaign_chair
  FROM public.campaigns
  WHERE keyword = '공부의자'
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT id INTO v_campaign_glove
  FROM public.campaigns
  WHERE keyword = '헬스장갑 여성용'
  ORDER BY created_at DESC
  LIMIT 1;

  -- ── 디버그: 조회된 ID 출력 ────────────────────────────────────────
  RAISE NOTICE '공부의자 campaign_id: %',    v_campaign_chair;
  RAISE NOTICE '헬스장갑 여성용 campaign_id: %', v_campaign_glove;

  -- =================================================================
  -- [A] "공부의자" — 최근 7일 날짜별 1건 + 같은 날 중복 2건
  -- =================================================================

  IF v_campaign_chair IS NOT NULL THEN

    -- ── A-1: 날짜별 기본 1건 (D-6 ~ D-0) ─────────────────────────
    INSERT INTO public.campaign_rank_history (campaign_id, rank, checked_at) VALUES
      (v_campaign_chair,  7, v_today_kst_utc - INTERVAL '6 days' + INTERVAL '3 hours'),
      (v_campaign_chair,  5, v_today_kst_utc - INTERVAL '5 days' + INTERVAL '3 hours'),
      (v_campaign_chair,  8, v_today_kst_utc - INTERVAL '4 days' + INTERVAL '3 hours'),
      (v_campaign_chair,  3, v_today_kst_utc - INTERVAL '3 days' + INTERVAL '3 hours'),
      (v_campaign_chair,  6, v_today_kst_utc - INTERVAL '2 days' + INTERVAL '3 hours'),
      (v_campaign_chair,  4, v_today_kst_utc - INTERVAL '1 day'  + INTERVAL '3 hours'),
      (v_campaign_chair,  2, v_today_kst_utc                      + INTERVAL '3 hours');

    -- ── A-2: 중복 제거 검증용 — D-3, D-1에 추가 2건씩 ─────────────
    --   checked_at이 더 늦은(최신) 값이 putIfAbsent로 보존되어야 함
    --   → D-3: 최신 rank=3 보존 (이전 두 건 rank=9,10은 버려져야 함)
    --   → D-1: 최신 rank=4 보존 (이전 두 건 rank=8,10은 버려져야 함)
    INSERT INTO public.campaign_rank_history (campaign_id, rank, checked_at) VALUES
      -- D-3 중복 (기준 건보다 이른 시각)
      (v_campaign_chair, 10, v_today_kst_utc - INTERVAL '3 days' + INTERVAL '1 hour'),
      (v_campaign_chair,  9, v_today_kst_utc - INTERVAL '3 days' + INTERVAL '2 hours'),
      -- D-1 중복 (기준 건보다 이른 시각)
      (v_campaign_chair, 10, v_today_kst_utc - INTERVAL '1 day'  + INTERVAL '1 hour'),
      (v_campaign_chair,  8, v_today_kst_utc - INTERVAL '1 day'  + INTERVAL '2 hours');

    RAISE NOTICE '공부의자: 7 + 4 = 11건 INSERT 완료';

  ELSE
    RAISE WARNING '공부의자 캠페인을 찾을 수 없습니다. INSERT 스킵.';
  END IF;


  -- =================================================================
  -- [B] "헬스장갑 여성용" — 최근 7일 날짜별 1건 + 같은 날 중복 2건
  -- =================================================================

  IF v_campaign_glove IS NOT NULL THEN

    -- ── B-1: 날짜별 기본 1건 (D-6 ~ D-0) ─────────────────────────
    INSERT INTO public.campaign_rank_history (campaign_id, rank, checked_at) VALUES
      (v_campaign_glove,  9, v_today_kst_utc - INTERVAL '6 days' + INTERVAL '3 hours'),
      (v_campaign_glove,  6, v_today_kst_utc - INTERVAL '5 days' + INTERVAL '3 hours'),
      (v_campaign_glove, 10, v_today_kst_utc - INTERVAL '4 days' + INTERVAL '3 hours'),
      (v_campaign_glove,  4, v_today_kst_utc - INTERVAL '3 days' + INTERVAL '3 hours'),
      (v_campaign_glove,  7, v_today_kst_utc - INTERVAL '2 days' + INTERVAL '3 hours'),
      (v_campaign_glove,  3, v_today_kst_utc - INTERVAL '1 day'  + INTERVAL '3 hours'),
      (v_campaign_glove,  1, v_today_kst_utc                      + INTERVAL '3 hours');

    -- ── B-2: 중복 제거 검증용 — D-4, D-2에 추가 2건씩 ─────────────
    --   → D-4: 최신 rank=10 보존 (이전 rank=8,9은 버려져야 함)
    --   → D-2: 최신 rank=7  보존 (이전 rank=5,6은 버려져야 함)
    INSERT INTO public.campaign_rank_history (campaign_id, rank, checked_at) VALUES
      -- D-4 중복 (기준 건보다 이른 시각)
      (v_campaign_glove,  8, v_today_kst_utc - INTERVAL '4 days' + INTERVAL '1 hour'),
      (v_campaign_glove,  9, v_today_kst_utc - INTERVAL '4 days' + INTERVAL '2 hours'),
      -- D-2 중복 (기준 건보다 이른 시각)
      (v_campaign_glove,  5, v_today_kst_utc - INTERVAL '2 days' + INTERVAL '1 hour'),
      (v_campaign_glove,  6, v_today_kst_utc - INTERVAL '2 days' + INTERVAL '2 hours');

    RAISE NOTICE '헬스장갑 여성용: 7 + 4 = 11건 INSERT 완료';

  ELSE
    RAISE WARNING '헬스장갑 여성용 캠페인을 찾을 수 없습니다. INSERT 스킵.';
  END IF;

END;
$$;


-- =================================================================
-- 실행 후 검증 쿼리
-- =================================================================

-- [1] INSERT된 전체 행 확인 (checked_at 최신순)
-- SELECT c.keyword, rh.rank, rh.checked_at AT TIME ZONE 'Asia/Seoul' AS checked_kst
-- FROM campaign_rank_history rh
-- JOIN campaigns c ON c.id = rh.campaign_id
-- WHERE c.keyword IN ('공부의자', '헬스장갑 여성용')
-- ORDER BY c.keyword, rh.checked_at DESC;

-- [2] 중복 제거 후 날짜별 최신 1건 확인 (Flutter fetchRankHistory 결과 시뮬레이션)
--     → 캠페인당 정확히 7행이 나와야 정상
-- SELECT
--   c.keyword,
--   DATE(rh.checked_at AT TIME ZONE 'Asia/Seoul') AS kst_date,
--   MAX(rh.rank) FILTER (WHERE rh.checked_at = (
--     SELECT MAX(r2.checked_at)
--     FROM campaign_rank_history r2
--     WHERE r2.campaign_id = rh.campaign_id
--       AND DATE(r2.checked_at AT TIME ZONE 'Asia/Seoul') = DATE(rh.checked_at AT TIME ZONE 'Asia/Seoul')
--   )) AS latest_rank_that_day,
--   COUNT(*) AS raw_count_that_day
-- FROM campaign_rank_history rh
-- JOIN campaigns c ON c.id = rh.campaign_id
-- WHERE c.keyword IN ('공부의자', '헬스장갑 여성용')
-- GROUP BY c.keyword, kst_date
-- ORDER BY c.keyword, kst_date;

-- [3] 테스트 후 데이터 삭제 (필요 시)
-- DELETE FROM campaign_rank_history
-- WHERE campaign_id IN (
--   SELECT id FROM campaigns
--   WHERE keyword IN ('공부의자', '헬스장갑 여성용')
-- );
