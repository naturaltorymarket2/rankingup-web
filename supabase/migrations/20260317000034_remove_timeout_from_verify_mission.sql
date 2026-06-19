-- Phase 16: verify_mission에서 10분 타임아웃 로직 제거
-- WebView 전환으로 앱 이탈 없이 미션 수행 → 타임아웃 불필요

CREATE OR REPLACE FUNCTION public.verify_mission(
  p_log_id       UUID,
  p_user_id      UUID,
  p_submitted_tag TEXT
) RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  -- 10분 타임아웃 블록 제거 (WebView 전환으로 불필요)

  SELECT tag_word INTO v_tag_word FROM public.campaign_tags
    WHERE id = v_log.assigned_tag_id;

  IF LOWER(TRIM(p_submitted_tag)) != LOWER(TRIM(v_tag_word)) THEN
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
    SET status = 'SUCCESS', completed_at = NOW()
    WHERE id = p_log_id;

  RETURN json_build_object('success', true, 'earned', v_reward);
END;
$$;
