-- =================================================================
-- Phase 27: 날짜가 지난 '진행 중' 미션 정리
--
-- 배경:
--   미션을 시작만 하고 끝내지 않으면 mission_logs 가 IN_PROGRESS 로
--   영원히 남는다. 참여 내역에는 계속 '진행 중 / 이어하기'로 보이지만,
--   get_active_mission 은 '오늘 시작한' 미션만 돌려주므로 눌러도
--   "이어서 진행할 수 있는 미션이 없습니다"만 뜬다.
--   실제로 08/27, 08/28 에 시작한 건이 그대로 남아 신고됐다.
--
--   미션은 하루 단위로 끝나는 구조다(하루 1회 참여, 그날의 태그를 출제).
--   날짜가 지나면 이어서 진행할 수 없으므로 TIMEOUT 으로 종료 처리한다.
--   TIMEOUT 은 기존 CHECK 제약에 이미 포함된 값이라 스키마 변경이 없다.
--
-- 주의:
--   포인트는 성공(SUCCESS) 시에만 지급되므로 정리해도 정산 영향이 없다.
--   당일 참여 제한도 '오늘' 기준이라 지난 기록을 정리해도 영향이 없다.
-- =================================================================

-- ── 1. 정리 함수 ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_stale_missions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.mission_logs
     SET status       = 'TIMEOUT',
         completed_at = COALESCE(completed_at, NOW())
   WHERE status = 'IN_PROGRESS'
     AND (started_at AT TIME ZONE 'Asia/Seoul')::DATE
         < (NOW()   AT TIME ZONE 'Asia/Seoul')::DATE;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 일일 크롤러(service_role)가 호출한다. 앱/웹 클라이언트는 호출하지 않는다.
REVOKE ALL ON FUNCTION public.expire_stale_missions() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_stale_missions() FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.expire_stale_missions() TO service_role;

-- ── 2. 지금 남아 있는 건 즉시 정리 ──────────────────────────────
SELECT public.expire_stale_missions();
