-- =================================================================
-- 스토어 트래픽 부스터 — DB 스키마 생성
-- Tables: users, business_info, wallets, transactions,
--         campaigns, campaign_tags, mission_logs
-- =================================================================

-- -----------------------------------------------------------------
-- 1. users  (auth.users 연동 | role: USER / ADMIN)
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
  id                   UUID        PRIMARY KEY
                                   REFERENCES auth.users(id) ON DELETE CASCADE,
  email                TEXT        UNIQUE,
  role                 TEXT        NOT NULL DEFAULT 'USER'
                                   CHECK (role IN ('USER', 'ADMIN')),
  device_id            TEXT        UNIQUE,   -- B2C 앱 기기 식별자
  bank_name            TEXT,                 -- 출금용 은행명
  bank_account_number  TEXT,                 -- 출금용 계좌번호
  bank_account_holder  TEXT,                 -- 예금주
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------
-- 2. business_info  (광고주 사업자 정보 | users 1:1)
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.business_info (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        UNIQUE NOT NULL
                               REFERENCES public.users(id) ON DELETE CASCADE,
  company_name     TEXT        NOT NULL,
  business_number  TEXT        NOT NULL,
  owner_name       TEXT        NOT NULL,
  phone            TEXT,
  address          TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------
-- 3. wallets  (포인트 잔액 | users 1:1)
-- ※ balance는 RPC에서만 수정 — 클라이언트 직접 UPDATE 금지
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallets (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        UNIQUE NOT NULL
                          REFERENCES public.users(id) ON DELETE CASCADE,
  balance     INTEGER     NOT NULL DEFAULT 0 CHECK (balance >= 0),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------
-- 4. transactions  (포인트 원장 | type: CHARGE/SPEND/EARN/WITHDRAW)
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.transactions (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES public.users(id),
  type         TEXT        NOT NULL
               CHECK (type IN ('CHARGE', 'SPEND', 'EARN', 'WITHDRAW')),
  amount       INTEGER     NOT NULL CHECK (amount > 0),
  status       TEXT        NOT NULL DEFAULT 'PENDING'
               CHECK (status IN ('PENDING', 'COMPLETED', 'REJECTED')),
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------
-- 5. campaigns  (광고 캠페인)
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaigns (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES public.users(id),
  product_url      TEXT        NOT NULL,
  keyword          TEXT        NOT NULL,
  daily_target     INTEGER     NOT NULL CHECK (daily_target > 0),
  duration_days    INTEGER     NOT NULL CHECK (duration_days > 0),
  budget           INTEGER     NOT NULL CHECK (budget > 0),
  remaining_slots  INTEGER     NOT NULL CHECK (remaining_slots >= 0),
  status           TEXT        NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE', 'PAUSED', 'COMPLETED')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ NOT NULL
);

-- -----------------------------------------------------------------
-- 6. campaign_tags  (정답 태그 풀 | campaigns 1:N)
-- ※ tag_word 는 클라이언트 응답에 절대 포함 금지
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_tags (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  UUID        NOT NULL
               REFERENCES public.campaigns(id) ON DELETE CASCADE,
  tag_word     TEXT        NOT NULL,  -- 서버 전용 — 외부 노출 금지
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------
-- 7. mission_logs  (미션 수행 이력)
-- -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mission_logs (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id      UUID        NOT NULL REFERENCES public.campaigns(id),
  user_id          UUID        NOT NULL REFERENCES public.users(id),
  device_id        TEXT        NOT NULL,
  assigned_tag_id  UUID        REFERENCES public.campaign_tags(id),
  status           TEXT        NOT NULL DEFAULT 'IN_PROGRESS'
                   CHECK (status IN ('IN_PROGRESS', 'SUCCESS', 'FAILED', 'TIMEOUT')),
  started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =================================================================
-- 인덱스
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_users_device_id          ON public.users(device_id);
CREATE INDEX IF NOT EXISTS idx_transactions_user_id     ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_user_id        ON public.campaigns(user_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status         ON public.campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaign_tags_campaign   ON public.campaign_tags(campaign_id);
CREATE INDEX IF NOT EXISTS idx_mission_logs_campaign    ON public.mission_logs(campaign_id);
CREATE INDEX IF NOT EXISTS idx_mission_logs_user        ON public.mission_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_mission_logs_device      ON public.mission_logs(device_id);
CREATE INDEX IF NOT EXISTS idx_mission_logs_started_at  ON public.mission_logs(started_at);

-- =================================================================
-- Row Level Security
-- =================================================================
ALTER TABLE public.users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_info   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaigns       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaign_tags   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mission_logs    ENABLE ROW LEVEL SECURITY;

-- users: 본인 레코드만 조회/수정
CREATE POLICY users_self_select ON public.users
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY users_self_update ON public.users
  FOR UPDATE USING (auth.uid() = id);

-- wallets: 본인 잔액만 조회 (수정은 RPC만 허용)
CREATE POLICY wallets_self_select ON public.wallets
  FOR SELECT USING (auth.uid() = user_id);

-- transactions: 본인 내역만 조회
CREATE POLICY transactions_self_select ON public.transactions
  FOR SELECT USING (auth.uid() = user_id);

-- campaigns: 광고주는 본인 캠페인, 앱 유저는 ACTIVE 캠페인만 조회
CREATE POLICY campaigns_read ON public.campaigns
  FOR SELECT USING (
    auth.uid() = user_id
    OR status = 'ACTIVE'
  );

-- campaign_tags: RPC에서만 접근 (SELECT 정책 없음 = 전면 차단)

-- mission_logs: 본인 로그만 조회
CREATE POLICY mission_logs_self_select ON public.mission_logs
  FOR SELECT USING (auth.uid() = user_id);

-- =================================================================
-- auth.users → public.users + wallets 자동 생성 트리거
-- =================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.wallets (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
