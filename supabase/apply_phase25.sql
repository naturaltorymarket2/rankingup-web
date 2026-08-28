-- =================================================================
-- Phase 25 적용 SQL — Supabase SQL Editor 에 붙여넣고 실행
--
--   1) campaigns.thumbnail_url  — 앱에서 상품을 사진으로 식별
--   2) mission_logs.attempt_count / last_submitted_tag — 오답 원인 추적
--   3) verify_mission 갱신 (오답 입력값 기록, 정답은 여전히 비노출)
--
-- 중복 실행해도 안전하다.
-- =================================================================

-- =================================================================
-- Phase 25: 상품 식별 정보(썸네일) + 오답 입력 기록
--
-- 배경 1 — 유저가 엉뚱한 상품에서 태그를 읽는 문제
--   같은 판매자가 용량만 다른 상품(50팩 / 100팩)을 여러 개 운영하면
--   검색 결과에서 어느 것이 미션 대상인지 구분이 안 된다.
--   실제로 운영자 테스트에서도 50팩 상품에 들어가 오답 처리됐다.
--   → 상품 썸네일을 저장해 앱에서 사진으로 확인할 수 있게 한다.
--     (크롤러가 순위를 찾을 때 이미 썸네일 URL을 함께 받아오고 있다)
--
-- 배경 2 — 오답 원인을 확인할 방법이 없음
--   지금은 오답이면 실패 응답만 가고 아무 기록이 남지 않아,
--   "정답을 넣었는데 안 된다"는 문의가 와도 확인할 수단이 없다.
--   → 시도 횟수와 마지막 입력값을 기록한다. 어뷰징 판별에도 쓰인다.
-- =================================================================

-- ── 1. 상품 썸네일 ──────────────────────────────────────────────
ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- ── 2. 오답 입력 기록 ───────────────────────────────────────────
ALTER TABLE public.mission_logs
  ADD COLUMN IF NOT EXISTS attempt_count      INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_submitted_tag TEXT;

-- ── 3. verify_mission: 오답 시 입력값 기록 ──────────────────────
--     정답 태그는 여전히 응답에 포함하지 않는다.
CREATE OR REPLACE FUNCTION public.verify_mission(
  p_log_id        UUID,
  p_user_id       UUID,
  p_submitted_tag TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log       mission_logs%ROWTYPE;
  v_tag_word  TEXT;
  v_reward    INTEGER := 7;
  v_wallet_id UUID;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  SELECT * INTO v_log FROM public.mission_logs
    WHERE id = p_log_id AND user_id = p_user_id AND status = 'IN_PROGRESS'
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  SELECT tag_word INTO v_tag_word FROM public.campaign_tags
    WHERE id = v_log.assigned_tag_id;

  IF v_tag_word IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  -- '#' / 공백 / 대소문자 차이를 무시하고 비교
  IF public.normalize_tag(p_submitted_tag) <> public.normalize_tag(v_tag_word) THEN
    -- 오답 입력값을 남긴다 (정답이 무엇인지는 응답에 포함하지 않는다)
    UPDATE public.mission_logs
      SET attempt_count      = attempt_count + 1,
          last_submitted_tag = LEFT(COALESCE(p_submitted_tag, ''), 100)
      WHERE id = p_log_id;

    RETURN json_build_object('success', false, 'error', 'WRONG_TAG');
  END IF;

  SELECT id INTO v_wallet_id FROM public.wallets
    WHERE user_id = p_user_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  UPDATE public.wallets
    SET balance = balance + v_reward, updated_at = NOW()
    WHERE id = v_wallet_id;

  INSERT INTO public.transactions (user_id, type, amount, status, description)
    VALUES (p_user_id, 'EARN', v_reward, 'COMPLETED', '미션 성공 리워드');

  UPDATE public.mission_logs
    SET status             = 'SUCCESS',
        completed_at       = NOW(),
        attempt_count      = attempt_count + 1,
        last_submitted_tag = LEFT(COALESCE(p_submitted_tag, ''), 100)
    WHERE id = p_log_id;

  RETURN json_build_object('success', true, 'earned', v_reward);
END;
$$;
