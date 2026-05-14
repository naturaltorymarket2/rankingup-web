-- =================================================================
-- notices 테이블 생성 + RLS 정책 + RPC
--
-- 공지사항 기능:
--   - 어드민이 공지를 등록 (create_notice RPC, ADMIN role 검증)
--   - 모든 인증 사용자(광고주 포함)가 조회 가능 (get_notices RPC)
--
-- RLS 정책:
--   SELECT: 모든 인증 사용자 (authenticated)
--   INSERT/UPDATE/DELETE: ADMIN role만
-- =================================================================

-- ── 1. notices 테이블 생성 ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notices (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title      TEXT        NOT NULL,
  content    TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID        REFERENCES public.users(id)
);

-- ── 2. RLS 활성화 ─────────────────────────────────────────────────
ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;

-- SELECT: 모든 인증된 사용자 (광고주도 조회 가능)
CREATE POLICY "notices_select_authenticated"
  ON public.notices
  FOR SELECT
  TO authenticated
  USING (true);

-- INSERT: ADMIN role만
CREATE POLICY "notices_insert_admin"
  ON public.notices
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'ADMIN'
    )
  );

-- UPDATE: ADMIN role만
CREATE POLICY "notices_update_admin"
  ON public.notices
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'ADMIN'
    )
  );

-- DELETE: ADMIN role만
CREATE POLICY "notices_delete_admin"
  ON public.notices
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'ADMIN'
    )
  );


-- ── 3. get_notices RPC: 전체 목록 최신순 반환 ─────────────────────
CREATE OR REPLACE FUNCTION public.get_notices()
RETURNS TABLE (
  id         UUID,
  title      TEXT,
  content    TEXT,
  created_at TIMESTAMPTZ,
  created_by UUID
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id, n.title, n.content, n.created_at, n.created_by
  FROM public.notices n
  ORDER BY n.created_at DESC;
$$;


-- ── 4. create_notice RPC: ADMIN 검증 후 INSERT ────────────────────
CREATE OR REPLACE FUNCTION public.create_notice(
  p_title   TEXT,
  p_content TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role TEXT;
  v_notice_id UUID;
BEGIN
  -- ADMIN role 검증
  SELECT role INTO v_user_role
  FROM public.users
  WHERE id = auth.uid();

  IF v_user_role IS DISTINCT FROM 'ADMIN' THEN
    RETURN json_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  -- 입력값 검증
  IF trim(p_title) = '' THEN
    RETURN json_build_object('success', false, 'error', 'TITLE_REQUIRED');
  END IF;
  IF trim(p_content) = '' THEN
    RETURN json_build_object('success', false, 'error', 'CONTENT_REQUIRED');
  END IF;

  -- INSERT
  INSERT INTO public.notices (title, content, created_by)
  VALUES (trim(p_title), trim(p_content), auth.uid())
  RETURNING id INTO v_notice_id;

  RETURN json_build_object('success', true, 'notice_id', v_notice_id);
END;
$$;
