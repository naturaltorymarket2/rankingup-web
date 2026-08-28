-- =================================================================
-- Phase 26 적용 SQL — Supabase SQL Editor 에 붙여넣고 실행
--
--   get_active_mission RPC — 진행 중인 미션을 이어서 진행하기 위해
--   log_id / tag_index 등 필요한 값만 반환한다 (정답 tag_word 는 미포함).
--
-- 중복 실행해도 안전하다.
-- =================================================================

-- =================================================================
-- Phase 26: 진행 중인 미션 이어하기
--
-- 배경:
--   미션을 시작하고 네이버로 나갔다가 앱을 종료하면 다시 들어갈 방법이
--   사실상 없다. 서버는 재참여를 막고(ALREADY_PARTICIPATED_TODAY),
--   화면에는 '진행중'으로만 표시될 뿐 이어서 진행할 수단이 없었다.
--   실제로 시작된 미션이 완료되지 않고 남아 있는 건이 확인된다.
--
--   이어하려면 log_id 와 '몇 번째 태그인지(tag_index)'가 필요한데,
--   campaign_tags 는 RLS 로 클라이언트 조회가 전면 차단돼 있다
--   (정답 tag_word 노출 방지). 그래서 필요한 값만 돌려주는 RPC 를 둔다.
--
-- 보안:
--   tag_word / assigned_tag_id 는 응답에 포함하지 않는다.
--   start_mission 과 동일하게 tag_index(sort_order)만 노출한다.
-- =================================================================

CREATE OR REPLACE FUNCTION public.get_active_mission()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row     RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- 오늘 시작해 아직 끝내지 않은 미션 (가장 최근 1건)
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
$$;
