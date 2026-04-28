-- =================================================================
-- 테스트 데이터: campaigns 1개 + campaign_tags 3개 INSERT
--
-- 실행 위치: Supabase SQL Editor (postgres role, RLS 자동 bypass)
-- 목적: /web/campaign/:id 광고 상세 화면 테스트
--
-- 실행 전 확인:
--   1. Supabase > Table Editor > users 에 유저가 1명 이상 존재하는지 확인
--   2. 실행 후 하단 NOTICE 로그에서 campaign_id를 복사해 브라우저에서 확인
--      → http://localhost:8080/web/campaign/{campaign_id}
-- =================================================================

DO $$
DECLARE
  v_user_id     UUID;
  v_campaign_id UUID := gen_random_uuid();
BEGIN

  -- ── 1. 첫 번째 유저 UUID 조회 ──────────────────────────────────
  SELECT id INTO v_user_id
  FROM public.users
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'users 테이블이 비어 있습니다. 먼저 앱에서 회원가입 또는 로그인을 진행하세요.';
  END IF;

  -- ── 2. campaigns INSERT ────────────────────────────────────────
  --
  --   remaining_slots = daily_target × duration_days
  --   budget          = daily_target × duration_days × 50P
  --   expires_at      = end_date 다음날 자정 (register_campaign RPC 동일 로직)
  --
  INSERT INTO public.campaigns (
    id,
    user_id,
    product_url,
    keyword,
    daily_target,
    duration_days,
    budget,
    remaining_slots,
    status,
    start_date,
    end_date,
    expires_at
  ) VALUES (
    v_campaign_id,
    v_user_id,
    'https://smartstore.naver.com/example/products/1234567890',
    '무선 블루투스 이어폰',
    10,                                                    -- 일일 목표 10명
    14,                                                    -- 기간 14일
    7000,                                                  -- 10 × 14 × 50 = 7,000P
    140,                                                   -- 10 × 14 = 140 슬롯
    'ACTIVE',
    CURRENT_DATE,                                          -- 오늘 시작
    CURRENT_DATE + INTERVAL '13 days',                     -- 14일 후 종료
    (CURRENT_DATE + INTERVAL '14 days')::TIMESTAMPTZ       -- 종료일 다음날 자정
  );

  -- ── 3. campaign_tags INSERT (정답 태그 3개) ─────────────────────
  --
  --   ※ tag_word 는 서버 전용 — 클라이언트 응답에 절대 포함 금지
  --
  INSERT INTO public.campaign_tags (campaign_id, tag_word) VALUES
    (v_campaign_id, '블루투스이어폰'),
    (v_campaign_id, '무선이어폰추천'),
    (v_campaign_id, '노이즈캔슬링이어폰');

  -- ── 4. 결과 출력 ───────────────────────────────────────────────
  RAISE NOTICE '';
  RAISE NOTICE '✅ 테스트 데이터 INSERT 완료';
  RAISE NOTICE '   user_id     : %', v_user_id;
  RAISE NOTICE '   campaign_id : %', v_campaign_id;
  RAISE NOTICE '';
  RAISE NOTICE '▶ 광고 상세 URL:';
  RAISE NOTICE '   http://localhost:8080/web/campaign/%', v_campaign_id;

END;
$$;
