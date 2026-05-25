-- =================================================================
-- campaigns / mission_logs 테이블: 그룹 과금 구조 컬럼 추가
--
-- 배경:
--   기존 구조: 키워드 N개 선택 → campaigns 행 N개 생성, 키워드마다 독립 과금
--   변경 구조: 메인 키워드(순위 추적용) 아래 서브키워드들을 그룹으로 묶어
--             그룹 단위 1회 과금, 유저에게는 서브키워드 중 랜덤 1개 노출
--
-- 변경 내용:
--   1. campaigns.group_id UUID — 같은 메인 키워드 그룹 식별자
--      - 동일 group_id를 가진 campaigns 행들이 하나의 광고 그룹
--      - DEFAULT gen_random_uuid(): 기존 단독 캠페인은 각자 고유 group_id 부여
--   2. campaigns.group_daily_target INTEGER — 그룹 전체 일일 목표 (과금 기준)
--      - 예: 서브키워드 2개, group_daily_target=100 → 각 daily_target=50
--      - 예산 계산: group_daily_target × 기간 × 50P (키워드 수 무관)
--   3. mission_logs.group_id UUID — 그룹 단위 중복 참여 체크용
--      - start_mission RPC에서 campaigns.group_id를 조회해 함께 저장
--      - 중복 체크 기준: (user_id, group_id, 오늘 날짜)
--        → 서브키워드 A로 참여 시 동일 그룹의 서브키워드 B도 당일 차단
--
-- 기존 데이터:
--   기존 캠페인 데이터는 운영 전 모두 삭제 예정이므로 데이터 마이그레이션 불필요.
--   DEFAULT 값으로 기존 행 처리: group_id = gen_random_uuid(), group_daily_target = 0
-- =================================================================

-- ── 1. campaigns 테이블 컬럼 추가 ────────────────────────────────

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS group_id           UUID    NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS group_daily_target INTEGER NOT NULL DEFAULT 0;

-- ── 2. campaigns 인덱스 추가 ─────────────────────────────────────

-- 그룹 내 캠페인 전체 조회용 (get_dashboard_data RPC, fetchMissions 등)
CREATE INDEX IF NOT EXISTS idx_campaigns_group_id
  ON public.campaigns(group_id);

-- 그룹 + 상태 복합 인덱스 (ACTIVE 그룹 미션 목록 조회용)
CREATE INDEX IF NOT EXISTS idx_campaigns_group_id_status
  ON public.campaigns(group_id, status);

-- ── 3. mission_logs 테이블 컬럼 추가 ─────────────────────────────

ALTER TABLE public.mission_logs
  ADD COLUMN IF NOT EXISTS group_id UUID;

-- ── 4. mission_logs 인덱스 추가 ──────────────────────────────────

-- 그룹 단위 일일 중복 참여 체크용
-- start_mission RPC: WHERE user_id = p_user_id AND group_id = v_group_id AND created_at >= KST 자정
CREATE INDEX IF NOT EXISTS idx_mission_logs_user_group_date
  ON public.mission_logs(user_id, group_id, created_at);
