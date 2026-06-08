-- =================================================================
-- campaigns.budget CHECK 제약 조건 수정
--
-- 배경:
--   migration 0028 이후 그룹 과금 구조에서 두 번째 이후 서브키워드 캠페인은
--   budget = 0으로 INSERT (첫 번째만 실제 과금).
--   그러나 기존 CHECK (budget > 0) 제약으로 budget = 0 INSERT 불가 → 400 에러.
--
-- 변경:
--   CHECK (budget > 0)  →  CHECK (budget >= 0)
--   (그룹 내 첫 번째 서브키워드만 실제 budget > 0, 이후 서브키워드는 budget = 0 허용)
-- =================================================================

ALTER TABLE public.campaigns
  DROP CONSTRAINT IF EXISTS campaigns_budget_check;

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_budget_check CHECK (budget >= 0);
0