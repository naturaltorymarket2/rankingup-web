-- =================================================================
-- RPC: check_email_exists(p_email)
-- 호출: 회원가입 전(미인증 상태) — 앱/웹 공통
-- 역할: 해당 이메일로 이미 가입된 계정이 있는지(인증 여부 무관) 확인
--
-- 배경: public.users는 본인 row만 SELECT 가능하도록 RLS가 걸려 있어
-- (users_self_select: auth.uid() = id), 가입 전 미인증 상태의 클라이언트는
-- 다른 이메일의 존재 여부를 직접 조회할 수 없다. 그렇다고 RLS를 풀면
-- 임의의 이메일 존재 여부를 누구나 조회할 수 있게 되므로, boolean 1개만
-- 반환하는 SECURITY DEFINER RPC로 좁혀서 우회한다.
--
-- 판단 기준: public.users.email — handle_new_user 트리거가 auth.users
-- INSERT 즉시(이메일 인증 여부와 무관하게) 채워주므로, 인증 여부와
-- 무관하게 "존재 자체"를 판단하려는 요구사항과 정확히 일치한다.
-- =================================================================

CREATE OR REPLACE FUNCTION public.check_email_exists(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users
    WHERE LOWER(email) = LOWER(TRIM(p_email))
  );
END;
$$;
