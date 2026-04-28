-- =================================================================
-- 테스트 데이터 v2: 캠페인 5개 + campaign_tags 각 3개 INSERT
--
-- 실행 위치: Supabase > SQL Editor (postgres role, RLS 자동 bypass)
-- 목적: 앱 미션 보드 테스트 (다양한 카테고리)
--
-- 실행 전 확인:
--   앱에서 최소 1회 로그인 → public.users 에 레코드 존재해야 함
-- =================================================================

DO $$
DECLARE
  v_user_id UUID;

  v_id1 UUID := gen_random_uuid();
  v_id2 UUID := gen_random_uuid();
  v_id3 UUID := gen_random_uuid();
  v_id4 UUID := gen_random_uuid();
  v_id5 UUID := gen_random_uuid();
BEGIN

  -- ── 첫 번째 유저 조회 ─────────────────────────────────────────
  SELECT id INTO v_user_id
  FROM public.users
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '❌ users 테이블이 비어 있습니다. 앱에서 먼저 로그인하세요.';
  END IF;

  -- ── 캠페인 1: 블루투스 이어폰 ─────────────────────────────────
  INSERT INTO public.campaigns (
    id, user_id, product_url, keyword,
    daily_target, duration_days, budget, remaining_slots,
    status, start_date, end_date, expires_at
  ) VALUES (
    v_id1, v_user_id,
    'https://smartstore.naver.com/techstore01/products/1000000001',
    '블루투스 이어폰',
    5, 14, 3500, 70,           -- 5명/일 × 14일 × 50P = 3,500P
    'ACTIVE',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '13 days',
    (CURRENT_DATE + INTERVAL '14 days')::TIMESTAMPTZ
  );
  INSERT INTO public.campaign_tags (campaign_id, tag_word) VALUES
    (v_id1, '무선이어폰'),
    (v_id1, '블루투스이어폰추천'),
    (v_id1, '노이즈캔슬링이어폰');

  -- ── 캠페인 2: 에어프라이어 ────────────────────────────────────
  INSERT INTO public.campaigns (
    id, user_id, product_url, keyword,
    daily_target, duration_days, budget, remaining_slots,
    status, start_date, end_date, expires_at
  ) VALUES (
    v_id2, v_user_id,
    'https://smartstore.naver.com/homestore02/products/2000000002',
    '에어프라이어',
    8, 14, 5600, 112,           -- 8명/일 × 14일 × 50P = 5,600P
    'ACTIVE',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '13 days',
    (CURRENT_DATE + INTERVAL '14 days')::TIMESTAMPTZ
  );
  INSERT INTO public.campaign_tags (campaign_id, tag_word) VALUES
    (v_id2, '에어프라이어추천'),
    (v_id2, '가정용에어프라이어'),
    (v_id2, '오일프리에어프라이어');

  -- ── 캠페인 3: 캠핑 의자 ──────────────────────────────────────
  INSERT INTO public.campaigns (
    id, user_id, product_url, keyword,
    daily_target, duration_days, budget, remaining_slots,
    status, start_date, end_date, expires_at
  ) VALUES (
    v_id3, v_user_id,
    'https://smartstore.naver.com/outdoorstore03/products/3000000003',
    '캠핑 의자',
    6, 14, 4200, 84,            -- 6명/일 × 14일 × 50P = 4,200P
    'ACTIVE',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '13 days',
    (CURRENT_DATE + INTERVAL '14 days')::TIMESTAMPTZ
  );
  INSERT INTO public.campaign_tags (campaign_id, tag_word) VALUES
    (v_id3, '경량캠핑의자'),
    (v_id3, '접이식캠핑의자'),
    (v_id3, '캠핑체어추천');

  -- ── 캠페인 4: 마스크팩 ───────────────────────────────────────
  INSERT INTO public.campaigns (
    id, user_id, product_url, keyword,
    daily_target, duration_days, budget, remaining_slots,
    status, start_date, end_date, expires_at
  ) VALUES (
    v_id4, v_user_id,
    'https://smartstore.naver.com/beautystore04/products/4000000004',
    '마스크팩',
    10, 14, 7000, 140,           -- 10명/일 × 14일 × 50P = 7,000P
    'ACTIVE',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '13 days',
    (CURRENT_DATE + INTERVAL '14 days')::TIMESTAMPTZ
  );
  INSERT INTO public.campaign_tags (campaign_id, tag_word) VALUES
    (v_id4, '수분마스크팩'),
    (v_id4, '시트마스크추천'),
    (v_id4, '보습마스크팩');

  -- ── 캠페인 5: 요가 매트 ──────────────────────────────────────
  INSERT INTO public.campaigns (
    id, user_id, product_url, keyword,
    daily_target, duration_days, budget, remaining_slots,
    status, start_date, end_date, expires_at
  ) VALUES (
    v_id5, v_user_id,
    'https://smartstore.naver.com/sportsstore05/products/5000000005',
    '요가 매트',
    7, 14, 4900, 98,             -- 7명/일 × 14일 × 50P = 4,900P
    'ACTIVE',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '13 days',
    (CURRENT_DATE + INTERVAL '14 days')::TIMESTAMPTZ
  );
  INSERT INTO public.campaign_tags (campaign_id, tag_word) VALUES
    (v_id5, '두꺼운요가매트'),
    (v_id5, '미끄럼방지요가매트'),
    (v_id5, '홈트요가매트');

  -- ── 결과 출력 ────────────────────────────────────────────────
  RAISE NOTICE '';
  RAISE NOTICE '✅ 테스트 캠페인 5개 INSERT 완료';
  RAISE NOTICE '   user_id: %', v_user_id;
  RAISE NOTICE '';
  RAISE NOTICE '▶ 생성된 캠페인 목록:';
  RAISE NOTICE '   1. 블루투스 이어폰  — id: %', v_id1;
  RAISE NOTICE '   2. 에어프라이어     — id: %', v_id2;
  RAISE NOTICE '   3. 캠핑 의자        — id: %', v_id3;
  RAISE NOTICE '   4. 마스크팩         — id: %', v_id4;
  RAISE NOTICE '   5. 요가 매트        — id: %', v_id5;
  RAISE NOTICE '';
  RAISE NOTICE '▶ 앱을 새로고침(재시작)하면 미션 보드에 표시됩니다.';

END;
$$;
