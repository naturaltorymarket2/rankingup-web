-- Phase 16: register_campaign RPC에 p_product_name, p_brand_name 파라미터 추가

CREATE OR REPLACE FUNCTION public.register_campaign(
  p_user_id            UUID,
  p_product_url        TEXT,
  p_keyword            TEXT,
  p_daily_target       INTEGER,
  p_group_daily_target INTEGER,
  p_group_id           UUID,
  p_start_date         DATE,
  p_end_date           DATE,
  p_tags               TEXT[],
  p_sort_orders        INTEGER[],
  p_answer_index       INTEGER,
  p_seed_keyword       TEXT    DEFAULT NULL,
  p_product_name       TEXT    DEFAULT NULL,
  p_brand_name         TEXT    DEFAULT NULL
)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id       UUID;
  v_wallet_id     UUID;
  v_balance       INTEGER;
  v_duration_days INTEGER;
  v_total_cost    INTEGER;
  v_campaign_id   UUID;
  v_expires_at    TIMESTAMPTZ;
  v_is_first      BOOLEAN;
BEGIN
  -- 인증 확인
  v_user_id := auth.uid();
  IF v_user_id IS DISTINCT FROM p_user_id THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- 파라미터 유효성 검사
  IF p_product_url IS NULL OR TRIM(p_product_url) = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;
  IF p_keyword IS NULL OR TRIM(p_keyword) = '' THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_PARAMS');
  END IF;
  IF array_length(p_tags, 1) IS NULL OR array_length(p_tags, 1) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'TAGS_REQUIRED');
  END IF;
  IF p_answer_index IS NULL OR p_answer_index < 1 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_ANSWER_INDEX');
  END IF;

  v_duration_days := (p_end_date - p_start_date) + 1;
  IF v_duration_days < 7 THEN
    RETURN json_build_object('success', false, 'error', 'DURATION_TOO_SHORT');
  END IF;

  -- 그룹 내 첫 번째 서브키워드인지 확인 (과금 여부 결정)
  v_is_first := NOT EXISTS (
    SELECT 1 FROM public.campaigns WHERE group_id = p_group_id
  );

  -- 첫 번째 서브키워드일 때만 포인트 차감
  IF v_is_first THEN
    v_total_cost := p_group_daily_target * v_duration_days * 50;

    SELECT id, balance INTO v_wallet_id, v_balance
      FROM public.wallets WHERE user_id = p_user_id FOR UPDATE;

    IF v_balance < v_total_cost THEN
      RETURN json_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
    END IF;

    UPDATE public.wallets
      SET balance = balance - v_total_cost, updated_at = NOW()
      WHERE id = v_wallet_id;

    INSERT INTO public.transactions (user_id, type, amount, status, description)
      VALUES (p_user_id, 'SPEND', v_total_cost, 'COMPLETED', '광고 캠페인 등록');
  END IF;

  -- 캠페인 생성
  v_expires_at := (p_end_date + INTERVAL '1 day')::TIMESTAMPTZ AT TIME ZONE 'Asia/Seoul';

  INSERT INTO public.campaigns (
    user_id, product_url, keyword,
    daily_target, group_daily_target, group_id,
    start_date, end_date, expires_at,
    duration_days, budget, status, remaining_slots,
    seed_keyword, product_name, brand_name
  ) VALUES (
    p_user_id, p_product_url, p_keyword,
    p_daily_target, p_group_daily_target, p_group_id,
    p_start_date, p_end_date, v_expires_at,
    v_duration_days,
    CASE WHEN v_is_first THEN p_group_daily_target * v_duration_days * 50 ELSE 0 END,
    'ACTIVE',
    p_daily_target,
    p_seed_keyword, p_product_name, p_brand_name
  )
  RETURNING id INTO v_campaign_id;

  -- 태그 등록
  FOR i IN 1..array_length(p_tags, 1) LOOP
    INSERT INTO public.campaign_tags (campaign_id, tag_word, sort_order, is_answer)
      VALUES (
        v_campaign_id,
        p_tags[i],
        p_sort_orders[i],
        p_sort_orders[i] = p_answer_index
      );
  END LOOP;

  RETURN json_build_object('success', true, 'campaign_id', v_campaign_id);
END;
$$;
