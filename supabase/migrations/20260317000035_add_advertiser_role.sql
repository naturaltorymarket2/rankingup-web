-- =================================================================
-- users.role CHECK 제약에 ADVERTISER 추가
--
-- 배경: 앱 유저(USER)와 광고주를 구분하는 진짜 계정 타입이 없어
-- business_info 존재 여부로만 "추정"하던 상태였음. role에 ADVERTISER를
-- 추가해 계정 타입을 명시적으로 저장한다.
--
-- 주의: handle_new_user 트리거는 그대로 둔다 — 모든 신규 계정은
-- 여전히 role='USER'로 생성되고, 광고주는 사업자 등록 완료 시점
-- (register_advertiser RPC, migration 0036)에만 ADVERTISER로 전환된다.
-- 기존 계정들의 role을 일괄 변경하는 작업은 이 마이그레이션에 포함하지 않음.
-- =================================================================

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_check
  CHECK (role IN ('USER', 'ADMIN', 'ADVERTISER'));
