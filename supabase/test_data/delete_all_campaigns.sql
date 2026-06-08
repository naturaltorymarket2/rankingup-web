-- ============================================================
-- delete_all_campaigns.sql
-- 캠페인 관련 데이터 전체 삭제 (테이블 구조 유지)
-- 실행 위치: Supabase SQL Editor
-- ============================================================

-- 1. 미션 로그 (campaigns 참조 → 먼저 삭제)
DELETE FROM mission_logs;

-- 2. 순위 추이 (campaigns 참조 → 먼저 삭제)
DELETE FROM campaign_rank_history;

-- 3. 캠페인 태그 (campaigns 참조 → 먼저 삭제)
DELETE FROM campaign_tags;

-- 4. 캠페인 본체
DELETE FROM campaigns;

-- 5. 삭제 결과 확인 (모두 0이면 성공)
SELECT
  (SELECT COUNT(*) FROM campaigns)             AS campaigns,
  (SELECT COUNT(*) FROM campaign_tags)         AS campaign_tags,
  (SELECT COUNT(*) FROM campaign_rank_history) AS rank_history,
  (SELECT COUNT(*) FROM mission_logs)          AS mission_logs;
