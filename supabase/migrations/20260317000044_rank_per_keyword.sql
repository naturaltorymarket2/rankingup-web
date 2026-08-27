-- =================================================================
-- Phase 24: 키워드별 순위 기록 + 앱에 위치 힌트 제공
--
-- 배경:
--   미션 유저가 "검색 결과에서 상품을 찾으세요"라는 안내만 받고 있어,
--   상품이 뒤 페이지에 있으면 사실상 찾을 수 없었다.
--   매일 크롤링으로 순위를 확보하고 있으므로 앱에 위치를 알려준다.
--     예) "약 37위 · 2페이지쯤에 있어요"
--
--   그런데 지금까지는 그룹의 시드(순위 추적 대표) 키워드 순위만 기록했다.
--   유저가 실제로 검색하는 건 각 캠페인의 미션 키워드이므로,
--   키워드별로 순위를 따로 저장해야 정확한 안내가 가능하다.
--
-- 변경:
--   campaign_rank_history.keyword  이 순위가 어떤 키워드의 것인지
--   campaign_rank_history.is_seed  시드 키워드 순위인지 여부
--
--   - 광고주 대시보드 순위 추이 차트 → is_seed = true (기존 의미 유지)
--   - 앱 미션 화면 위치 힌트        → 해당 캠페인의 미션 키워드 순위
--
-- 기존 데이터:
--   모두 시드 키워드 기준으로 수집된 값이므로 is_seed = true 로 채운다.
--   keyword 는 알 수 없으므로 NULL 로 둔다 (차트는 is_seed 로만 거른다).
-- =================================================================

ALTER TABLE public.campaign_rank_history
  ADD COLUMN IF NOT EXISTS keyword TEXT,
  ADD COLUMN IF NOT EXISTS is_seed BOOLEAN NOT NULL DEFAULT true;

-- 캠페인 + 키워드 기준 최신 순위 조회용
CREATE INDEX IF NOT EXISTS idx_rank_history_campaign_keyword
  ON public.campaign_rank_history(campaign_id, keyword, checked_at DESC);

-- 시드 순위(대시보드 차트)만 빠르게 거르기 위한 인덱스
CREATE INDEX IF NOT EXISTS idx_rank_history_seed
  ON public.campaign_rank_history(campaign_id, is_seed, checked_at DESC);

-- 앱 유저가 미션 화면에서 순위 힌트를 읽을 수 있도록 RLS 정책 추가.
-- (기존 정책은 광고주 본인 캠페인만 조회 가능 → 앱 유저는 못 읽었다)
-- 노출 대상은 승인 완료된 진행 중 캠페인의 순위 기록으로 한정한다.
DROP POLICY IF EXISTS rank_history_mission_select ON public.campaign_rank_history;
CREATE POLICY rank_history_mission_select ON public.campaign_rank_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.campaigns c
      WHERE c.id = campaign_rank_history.campaign_id
        AND c.status          = 'ACTIVE'
        AND c.approval_status = 'APPROVED'
    )
  );
