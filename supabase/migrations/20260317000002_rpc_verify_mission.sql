-- =================================================================
-- RPC: verify_mission(p_log_id, p_user_id, p_submitted_tag)
-- 호출: 앱 유저 (B2C)
-- 역할: 정답 검증 + 리워드 지급 (+7원)
--
-- 어뷰징 방지 (서버에서만 처리):
--   1. 호출자 = p_user_id 일치 검증
--   2. 본인의 IN_PROGRESS 미션만 검증 허용
--   3. 10분 타임아웃 — 클라이언트 타이머 불신, 서버 started_at 기준
--   4. wallet SELECT FOR UPDATE (포인트 동시성 제어)
--   5. 타임아웃 시 슬롯 반환
-- =================================================================
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
  v_log       public.mission_logs%ROWTYPE;
  v_tag_word  TEXT;
  v_reward    INTEGER := 7;   -- 미션 성공 1건 = 7원
  v_wallet_id UUID;
BEGIN

  -- ── 1. 호출자 본인 확인 ─────────────────────────────────────
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- ── 2. 미션 로그 조회 및 잠금 (FOR UPDATE) ───────────────────
  SELECT * INTO v_log
  FROM public.mission_logs
  WHERE id      = p_log_id
    AND user_id = p_user_id
    AND status  = 'IN_PROGRESS'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_MISSION');
  END IF;

  -- ── 3. 10분 타임아웃 체크 (서버 started_at 기준) ─────────────
  --      클라이언트 타이머만으로 판단하면 어뷰징 가능 → 서버에서만 처리
  IF NOW() > v_log.started_at + INTERVAL '10 minutes' THEN
    -- 실패 처리
    UPDATE public.mission_logs
    SET status       = 'TIMEOUT',
        completed_at = NOW()
    WHERE id = p_log_id;

    -- 슬롯 반환 (타임아웃 시 수량 복구)
    UPDATE public.campaigns
    SET remaining_slots = remaining_slots + 1
    WHERE id = v_log.campaign_id;

    RETURN json_build_object('success', false, 'error', 'TIMEOUT');
  END IF;

  -- ── 4. 정답 조회 (tag_word는 이 함수 내부에서만 사용) ─────────
  SELECT tag_word INTO v_tag_word
  FROM public.campaign_tags
  WHERE id = v_log.assigned_tag_id;

  -- ── 5. 정답 검증 (대소문자 무시 + 앞뒤 공백 제거) ────────────
  IF LOWER(TRIM(p_submitted_tag)) != LOWER(TRIM(v_tag_word)) THEN
    RETURN json_build_object('success', false, 'error', 'WRONG_TAG');
  END IF;

  -- ── 6. 유저 지갑 잠금 (SELECT FOR UPDATE) ────────────────────
  SELECT id INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'WALLET_NOT_FOUND');
  END IF;

  -- ── 7. 포인트 적립 (+7원) ────────────────────────────────────
  UPDATE public.wallets
  SET balance    = balance + v_reward,
      updated_at = NOW()
  WHERE id = v_wallet_id;

  -- ── 8. EARN 거래 내역 INSERT ──────────────────────────────────
  INSERT INTO public.transactions (user_id, type, amount, status, description)
  VALUES (p_user_id, 'EARN', v_reward, 'COMPLETED', '미션 성공 리워드');

  -- ── 9. 미션 로그 성공 처리 ────────────────────────────────────
  UPDATE public.mission_logs
  SET status       = 'SUCCESS',
      completed_at = NOW()
  WHERE id = p_log_id;

  RETURN json_build_object(
    'success', true,
    'earned',  v_reward
  );

END;
$$;
