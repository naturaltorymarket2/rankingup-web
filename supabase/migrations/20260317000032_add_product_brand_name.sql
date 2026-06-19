-- Phase 16: campaigns 테이블에 product_name, brand_name 컬럼 추가

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS product_name TEXT,
  ADD COLUMN IF NOT EXISTS brand_name   TEXT;
