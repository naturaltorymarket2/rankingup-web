-- =================================================================
-- campaigns RLS SELECT 정책 강화 (migration 0021)
-- =================================================================
--
-- 문제:
--   기존 단일 정책(auth.uid() = user_id OR status = 'ACTIVE')에서
--   광고주 B가 광고주 A의 ACTIVE 캠페인 UUID를 알면 직접 조회 가능
--   → product_url, 예산, 키워드 등 민감 정보 노출 위험
--
-- 해결:
--   ① Permissive 2개 (OR 조합)
--       - campaigns_owner_select  : 소유자(광고주) — 본인 캠페인 전체
--       - campaigns_active_select : 앱 유저(B2C)  — ACTIVE 캠페인만
--   ② Restrictive 1개 (AND 조합)
--       - campaigns_advertiser_restrict
--         광고주(business_info 등록 완료)는 본인 캠페인만 허용
--         → 타인의 ACTIVE 캠페인 접근 차단
--
-- 동작 검증:
--   ∙ B2C 앱 유저 → ACTIVE 캠페인 조회  ✅
--     Permissive (campaigns_active_select) 통과
--     Restrictive: NOT EXISTS(business_info) = TRUE → 통과
--
--   ∙ 광고주 → 본인 캠페인 조회          ✅
--     Permissive (campaigns_owner_select) 통과
--     Restrictive: auth.uid() = user_id = TRUE → 통과
--
--   ∙ 광고주 → 타인 ACTIVE 캠페인 조회   ❌ (차단)
--     Permissive (campaigns_active_select) 통과
--     Restrictive: EXISTS(business_info) = TRUE, auth.uid() ≠ user_id
--     → Restrictive 실패 → 접근 거부
--
-- Flutter 코드 확인:
--   campaign_repository.dart fetchCampaignDetail()
--     → .from('campaigns').select().eq('id', campaignId)
--     광고주가 본인 캠페인 조회 시 auth.uid() = user_id 조건 충족
--     → campaigns_owner_select + Restrictive 모두 통과 → 정상 동작
-- =================================================================


-- -----------------------------------------------------------------
-- 기존 통합 정책 제거
-- -----------------------------------------------------------------
DROP POLICY IF EXISTS campaigns_read ON public.campaigns;


-- =================================================================
-- Permissive 정책 (복수 정책은 PostgreSQL이 OR로 결합)
-- =================================================================

-- 정책 1: 캠페인 소유자 (광고주)
-- 본인이 등록한 모든 캠페인 조회 가능 (ACTIVE/PAUSED/COMPLETED 무관)
-- 사용처: fetchCampaignDetail, get_dashboard_data RPC
CREATE POLICY campaigns_owner_select ON public.campaigns
  FOR SELECT
  USING (auth.uid() = user_id);

-- 정책 2: 앱 유저 (B2C) — ACTIVE 캠페인만 조회
-- 사용처: mission_repository.fetchMissions(), mission_detail_screen
CREATE POLICY campaigns_active_select ON public.campaigns
  FOR SELECT
  USING (status = 'ACTIVE');


-- =================================================================
-- Restrictive 정책 (Permissive와 AND 결합 → 추가 제한 적용)
-- =================================================================

-- 광고주(business_info 등록 완료)는 본인 캠페인만 허용
--
-- 조건 해석:
--   NOT EXISTS(business_info) = TRUE  → 앱 유저이므로 제한 없이 통과
--   NOT EXISTS(business_info) = FALSE → 광고주이므로 반드시 본인 캠페인이어야 함
--
-- 결과:
--   앱 유저 + ACTIVE 캠페인 → Restrictive 통과 (NOT EXISTS = TRUE)
--   광고주 + 본인 캠페인   → Restrictive 통과 (auth.uid() = user_id)
--   광고주 + 타인 캠페인   → Restrictive 차단 (EXISTS 광고주이나 owner 아님)
CREATE POLICY campaigns_advertiser_restrict ON public.campaigns
  AS RESTRICTIVE
  FOR SELECT
  USING (
    NOT EXISTS (
      SELECT 1 FROM public.business_info
      WHERE business_info.user_id = auth.uid()
    )
    OR auth.uid() = user_id
  );
