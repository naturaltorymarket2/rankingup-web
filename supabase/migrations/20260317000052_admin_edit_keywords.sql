-- =================================================================
-- Phase 30: 어드민 키워드 수정
--
-- 배경:
--   광고주가 통합검색 8위 밖 키워드를 등록하면 리워드 유저가 상품을
--   찾지 못해 미션을 완주할 수 없다(100위 밖이면 사실상 불가능).
--   등록 화면 안내 + 추천 로직 개선으로 1차로 막고, 그래도 들어온
--   키워드는 운영자가 직접 고칠 수 있어야 한다.
--   (등록 화면에 "센터에서 일부 수정될 수 있습니다" 안내를 넣었다)
--
--   get_campaign_keywords(p_group_id)
--     그룹의 캠페인별 키워드 + 메인(순위 추적) 키워드 조회
--   update_campaign_keywords(p_group_id, p_campaign_ids, p_keywords, p_seed_keyword)
--     캠페인별 키워드 이름 변경 + 메인 키워드 변경
--
-- 범위:
--   키워드 '이름'만 바꾼다. 키워드 추가/삭제는 일일 목표 분배와
--   미션 이력에 영향을 주므로 여기서 다루지 않는다.
--   예산·일일 목표·승인 상태·태그는 변경하지 않는다.
--
-- 순위 기록:
--   campaign_rank_history 는 (campaign_id, keyword) 단위라 이름을 바꾸면
--   새 키워드는 기록이 없는 상태로 시작한다. 로컬 크롤러가 다음 실행 때
--   새 키워드부터 수집한다(앱 위치 힌트는 그때부터 표시된다).
-- =================================================================

-- =================================================================
-- 1. get_campaign_keywords(p_group_id)
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_campaign_keywords(p_group_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rows JSON;
  v_seed TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT MAX(seed_keyword) INTO v_seed
  FROM public.campaigns WHERE group_id = p_group_id;

  SELECT COALESCE(json_agg(json_build_object(
           'campaign_id', c.id,
           'keyword',     c.keyword
         ) ORDER BY c.created_at ASC), '[]'::JSON)
  INTO v_rows
  FROM public.campaigns c
  WHERE c.group_id = p_group_id;

  IF v_rows::TEXT = '[]' THEN
    RETURN json_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  RETURN json_build_object(
    'success',      true,
    'seed_keyword', v_seed,
    'keywords',     v_rows
  );
END;
$fn$;


-- =================================================================
-- 2. update_campaign_keywords(...)
--    p_campaign_ids[i] 의 키워드를 p_keywords[i] 로 바꾼다.
--    p_seed_keyword 가 비어 있지 않으면 그룹 전체의 메인 키워드도 바꾼다.
-- =================================================================
CREATE OR REPLACE FUNCTION public.update_campaign_keywords(
  p_group_id     UUID,
  p_campaign_ids UUID[],
  p_keywords     TEXT[],
  p_seed_keyword TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_count    INTEGER;
  v_owned    INTEGER;
  v_kw       TEXT;
  v_key      TEXT;
  v_keys     TEXT[] := ARRAY[]::TEXT[];
  v_changed  INTEGER := 0;
  v_rows     INTEGER;
  v_seed     TEXT;
  i          INTEGER;
BEGIN
  -- ── 1. 권한 ────────────────────────────────────────────────
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  -- ── 2. 파라미터 검증 ────────────────────────────────────────
  v_count := COALESCE(array_length(p_campaign_ids, 1), 0);
  IF v_count = 0 OR v_count <> COALESCE(array_length(p_keywords, 1), 0) THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;

  -- 전달된 캠페인이 모두 이 그룹 소속인지 (다른 광고 수정 방지)
  SELECT COUNT(*) INTO v_owned
  FROM public.campaigns
  WHERE group_id = p_group_id
    AND id = ANY (p_campaign_ids);

  IF v_owned <> v_count THEN
    RETURN json_build_object('success', false, 'error', 'NOT_IN_GROUP');
  END IF;

  -- 빈 값 / 길이 / 중복 (공백·대소문자 무시) 확인
  FOR i IN 1 .. v_count LOOP
    v_kw := regexp_replace(TRIM(COALESCE(p_keywords[i], '')), '\s+', ' ', 'g');
    IF v_kw = '' THEN
      RETURN json_build_object('success', false, 'error', 'EMPTY_KEYWORD');
    END IF;
    IF char_length(v_kw) > 50 THEN
      RETURN json_build_object(
        'success', false, 'error', 'KEYWORD_TOO_LONG', 'keyword', v_kw
      );
    END IF;

    v_key := lower(replace(v_kw, ' ', ''));
    IF v_key = ANY (v_keys) THEN
      RETURN json_build_object(
        'success', false, 'error', 'DUPLICATE_KEYWORD', 'keyword', v_kw
      );
    END IF;
    v_keys := array_append(v_keys, v_key);
  END LOOP;

  v_seed := regexp_replace(TRIM(COALESCE(p_seed_keyword, '')), '\s+', ' ', 'g');
  IF char_length(v_seed) > 50 THEN
    RETURN json_build_object(
      'success', false, 'error', 'KEYWORD_TOO_LONG', 'keyword', v_seed
    );
  END IF;

  -- ── 3. 키워드 변경 (바뀐 것만) ──────────────────────────────
  --    검증은 모두 위에서 끝낸다. 오류 JSON 반환은 트랜잭션을 되돌리지
  --    않으므로, 변경을 시작한 뒤에는 실패로 빠지는 경로가 없어야 한다.
  FOR i IN 1 .. v_count LOOP
    v_kw := regexp_replace(TRIM(p_keywords[i]), '\s+', ' ', 'g');

    UPDATE public.campaigns
       SET keyword = v_kw
     WHERE id = p_campaign_ids[i]
       AND keyword IS DISTINCT FROM v_kw;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_changed := v_changed + v_rows;
  END LOOP;

  -- ── 4. 메인(순위 추적) 키워드 변경 ──────────────────────────
  IF v_seed <> '' THEN
    UPDATE public.campaigns
       SET seed_keyword = v_seed
     WHERE group_id = p_group_id
       AND seed_keyword IS DISTINCT FROM v_seed;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows > 0 THEN
      v_changed := v_changed + 1;
    END IF;
  END IF;

  RETURN json_build_object('success', true, 'changed', v_changed);
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_campaign_keywords(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_campaign_keywords(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.update_campaign_keywords(UUID, UUID[], TEXT[], TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.update_campaign_keywords(UUID, UUID[], TEXT[], TEXT) TO authenticated;
