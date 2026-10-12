-- =================================================================
-- Phase 34: '이어하기'가 진행 중 미션 중 하나만 열리던 문제
--
-- 증상 (2026-10-12 실기기):
--   진행중 목록에 미션이 2건 보이는데, 위쪽 것을 누르면
--   "이어서 진행할 수 있는 미션이 없습니다" 가 떴다.
--
-- 원인:
--   get_active_mission 은 '가장 최근 1건'만 돌려준다. 앱은 돌려받은
--   campaign_id 가 누른 미션과 다르면 거부한다. 그래서 두 번째로
--   시작한 미션만 이어할 수 있었다.
--   (하루 1회 제한은 상품(그룹) 단위라, 서로 다른 상품을 동시에
--    진행하는 것은 정상이다 — 즉 2건 이상은 흔한 상황이다)
--
-- 해결:
--   어떤 미션을 이어할지 지정할 수 있게 한다.
--   p_campaign_id 를 주면 그 상품(그룹)의 진행 중 미션을 돌려준다.
--   값을 주지 않으면 기존대로 가장 최근 1건 — 구버전 앱도 그대로 동작한다.
--
-- 그룹 기준으로 찾는 이유:
--   미션 보드는 상품(group_id)당 한 장만 보여준다. 카드가 가리키는
--   campaign_id 와 실제로 시작한 서브키워드의 campaign_id 가 다를 수
--   있어, 그룹으로 찾아야 놓치지 않는다.
-- =================================================================

-- 인자 없는 기존 버전을 지운다. 그대로 두면 인자 없이 호출할 때
-- 어느 쪽인지 모호해져 오류가 난다.
DROP FUNCTION IF EXISTS public.get_active_mission();

CREATE OR REPLACE FUNCTION public.get_active_mission(
  p_campaign_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_user_id  UUID := auth.uid();
  v_group_id UUID;
  v_row      RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  IF p_campaign_id IS NOT NULL THEN
    SELECT group_id INTO v_group_id
    FROM public.campaigns WHERE id = p_campaign_id;
  END IF;

  SELECT ml.id            AS log_id,
         ml.campaign_id,
         ml.attempt_count,
         ct.sort_order    AS tag_index,
         c.keyword,
         c.product_url,
         c.product_name,
         c.brand_name,
         c.thumbnail_url
    INTO v_row
  FROM public.mission_logs ml
  JOIN public.campaigns     c  ON c.id  = ml.campaign_id
  LEFT JOIN public.campaign_tags ct ON ct.id = ml.assigned_tag_id
  WHERE ml.user_id = v_user_id
    AND ml.status  = 'IN_PROGRESS'
    AND (ml.started_at AT TIME ZONE 'Asia/Seoul')::DATE
        = (NOW()       AT TIME ZONE 'Asia/Seoul')::DATE
    AND (
      p_campaign_id IS NULL                              -- 지정 없음 → 최근 1건
      OR ml.campaign_id = p_campaign_id                  -- 같은 캠페인
      OR (v_group_id IS NOT NULL AND ml.group_id = v_group_id)  -- 같은 상품(그룹)
    )
  ORDER BY ml.started_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('success', true, 'mission', NULL);
  END IF;

  RETURN json_build_object(
    'success', true,
    'mission', json_build_object(
      'log_id',        v_row.log_id,
      'campaign_id',   v_row.campaign_id,
      'keyword',       v_row.keyword,
      'tag_index',     v_row.tag_index,
      'attempt_count', v_row.attempt_count,
      'product_url',   v_row.product_url,
      'product_name',  v_row.product_name,
      'brand_name',    v_row.brand_name,
      'thumbnail_url', v_row.thumbnail_url
    )
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_active_mission(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_active_mission(UUID) TO authenticated;
