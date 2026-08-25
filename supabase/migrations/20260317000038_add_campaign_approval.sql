-- =================================================================
-- Phase 22: 광고 승인(어드민 검수) 구조 추가
--
-- 배경:
--   기존: 광고주가 캠페인을 등록하면 즉시 ACTIVE → 앱 미션 보드 노출 + 포인트 즉시 차감
--   변경: 광고주 등록 → 승인 대기(PENDING) → 어드민이 상품 페이지의 실제 #태그를
--         긁어 등록하고 승인 → 그때 포인트 차감 + ACTIVE 전환 → 앱 노출
--
-- 변경 내용:
--   1. campaigns.approval_status  PENDING / APPROVED / REJECTED
--   2. campaigns.approved_at / approved_by / reject_reason
--   3. 태그 정규화 함수 normalize_tag(TEXT)
--      - 어드민 등록 태그와 앱 유저 입력 태그를 같은 규칙으로 비교하기 위함
--      - 선행 '#' 제거 + 모든 공백 제거 + 소문자
--
-- 기존 데이터:
--   이미 운영 중인 캠페인은 등록 시점에 포인트가 차감된 상태이므로
--   전부 APPROVED로 소급 처리한다 (아래 UPDATE 1회 실행).
-- =================================================================

-- ── 1. campaigns 컬럼 추가 ──────────────────────────────────────

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'PENDING',
  ADD COLUMN IF NOT EXISTS approved_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by     UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS reject_reason   TEXT;

-- CHECK 제약 (중복 실행 안전)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'campaigns_approval_status_check'
  ) THEN
    ALTER TABLE public.campaigns
      ADD CONSTRAINT campaigns_approval_status_check
      CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED'));
  END IF;
END $$;

-- ── 2. 기존 캠페인 소급 승인 처리 (1회성) ────────────────────────
--    이 migration 적용 시점에 이미 존재하던 캠페인 = 구 구조로 과금 완료된 건
UPDATE public.campaigns
SET approval_status = 'APPROVED',
    approved_at     = COALESCE(approved_at, created_at)
WHERE approval_status = 'PENDING'
  AND created_at < NOW();

-- ── 3. 인덱스 ────────────────────────────────────────────────────

-- 어드민 승인 대기 목록 조회용
CREATE INDEX IF NOT EXISTS idx_campaigns_approval_status
  ON public.campaigns(approval_status);

-- 앱 미션 보드 조회용 (ACTIVE + APPROVED 복합)
CREATE INDEX IF NOT EXISTS idx_campaigns_status_approval
  ON public.campaigns(status, approval_status);

-- ── 4. 태그 정규화 함수 ──────────────────────────────────────────
--    어드민이 붙여넣은 "#AAA#BBB" 를 파싱한 태그와,
--    앱 유저가 입력한 태그를 동일 규칙으로 비교하기 위한 공용 함수.
--    규칙: 선행 '#' 제거 → 모든 공백 제거 → 소문자
CREATE OR REPLACE FUNCTION public.normalize_tag(p_tag TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT LOWER(REGEXP_REPLACE(REGEXP_REPLACE(COALESCE(p_tag, ''), '^#+', ''), '\s', '', 'g'));
$$;

-- ── 5. RLS 보강 ─────────────────────────────────────────────────
--    앱 유저에게는 승인 완료된 ACTIVE 캠페인만 노출.
--    (광고주는 본인 캠페인 전체 조회 가능 — 승인 대기 상태 확인용)
DROP POLICY IF EXISTS campaigns_read ON public.campaigns;
CREATE POLICY campaigns_read ON public.campaigns
  FOR SELECT USING (
    auth.uid() = user_id
    OR (status = 'ACTIVE' AND approval_status = 'APPROVED')
  );
