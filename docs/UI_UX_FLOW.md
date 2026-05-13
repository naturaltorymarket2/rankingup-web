# UI/UX Flow — 겟머니 (스토어 트래픽 부스터)

> 최종 업데이트: 2026-05-13
> 실제 구현 코드 기반 (lib/ 전체 검증 완료)

---

## 인터페이스 개요

| 인터페이스 | 대상 | 플랫폼 | 진입점 |
|------------|------|--------|--------|
| **앱 (B2C)** | 미션 수행 유저 | Android | `/splash` |
| **광고주 웹 (B2B)** | 스마트스토어 판매자 | Flutter Web | `/web/login` |
| **어드민 웹** | 운영자 | Flutter Web | `/admin/login` |
| **랭킹 API** | 내부 서버 간 통신 | Railway (Python FastAPI) | `GET /rank` |

---

## 1. 앱 (Android B2C)

### 1-1. 진입 및 인증 흐름

```
앱 실행
  └─ /splash (SplashScreen)
       ├─ Supabase 세션 복구 (최대 3초 대기)
       ├─ 세션 있음 → /home
       └─ 세션 없음 → /login

/login (LoginScreen)
  ├─ 이메일 + 비밀번호 로그인
  │    └─ 성공 → Device ID SharedPreferences 저장 → /home
  ├─ 회원가입 탭
  │    └─ signUp() → Device ID 저장 → /home
  └─ 에러: 이메일 미존재 / 비밀번호 오류 / 이미 사용 중인 이메일
```

### 1-2. 홈 — 미션 보드

```
/home (MissionHomeScreen)
  ├─ 상단: 포인트 잔액 표시
  ├─ 광고 배너 (AdMob 배너, 상단)
  ├─ 미션 카드 목록 (무한 스크롤, 페이지당 10개)
  │    각 카드: 키워드 / 일일 목표 / 현재 참여자 수 / 리워드 (+7원)
  ├─ 미션 카드 탭 → /mission/:id
  └─ 하단 네비게이션: [홈] [참여내역] [마이페이지]
```

**데이터 흐름:**
- `missionsProvider` → `mission_repository.fetchMissions()` → `campaigns` 테이블 (ACTIVE, 기간 유효)

### 1-3. 미션 상세

```
/mission/:id (MissionDetailScreen)
  ├─ 캠페인 정보: 상품명, 키워드, 리워드, 참여 가능 여부
  ├─ [미션 시작] 버튼 탭
  │    └─ start_mission RPC 호출 (p_campaign_id, p_user_id, p_device_id)
  │         ├─ 성공 → 키워드 클립보드 복사 → 딥링크 실행 → /mission/:id/active
  │         ├─ 실패 (이미 참여) → 토스트 "오늘 이미 참여한 미션입니다"
  │         └─ 실패 (마감) → 토스트 "오늘 미션이 마감되었습니다"
  └─ 뒤로가기 → /home
```

**start_mission RPC 서버 처리:**
1. `mission_logs`에서 동일 user_id + campaign_id + 오늘 날짜 중복 체크
2. `campaigns.current_count < daily_target` 수량 체크
3. `mission_logs` INSERT (status=STARTED)
4. `campaign_tags`에서 랜덤 태그 1개 할당 → log에 저장 (클라이언트 미반환)
5. log_id + keyword 반환

### 1-4. 미션 진행

```
/mission/:id/active (MissionActiveScreen)
  ├─ 딥링크 실행: naversearchapp://search?where=nexearch&query={키워드}
  │    (네이버 쇼핑앱으로 이동)
  ├─ AppLifecycleState.resumed 감지 → 앱 복귀 확인
  ├─ 복귀 후 3초 카운트다운 → [리워드 받기] 버튼 활성화
  ├─ 타이머 (10분, started_at 기준 서버 시간)
  ├─ [리워드 받기] → 정답 태그 입력 모달
  │    └─ verify_mission RPC 호출 (p_log_id, p_user_id, p_submitted_tag)
  │         ├─ 성공 → +7원 적립 + 폭죽 애니메이션 → /home
  │         ├─ 오답 → 진동 + 토스트 "틀렸습니다" (재시도 가능)
  │         └─ 10분 초과 → 실패 처리 + current_count 반환 → /home
  └─ 10분 타임아웃 → 자동 실패 처리
```

**verify_mission RPC 서버 처리:**
1. `mission_logs`에서 log_id + user_id 조회
2. `NOW() - started_at > 10분` → FAILED 처리 + `campaigns.current_count - 1`
3. `p_submitted_tag = campaign_tags.tag_word` 비교
4. 성공: `mission_logs.status = COMPLETED` + `wallets.balance += 7` + `transactions` EARN INSERT
5. 실패: `mission_logs.status = FAILED`

### 1-5. 참여 내역

```
/history (HistoryScreen)
  ├─ 광고 배너 (AdMob 배너, 상단)
  ├─ 참여 내역 목록 (mission_logs JOIN campaigns)
  │    각 항목: 키워드 / 참여일시 / 결과 (성공/실패/진행중) / 적립 포인트
  └─ 하단 네비게이션
```

### 1-6. 마이페이지

```
/mypage (MypageScreen)
  ├─ 포인트 잔액 (wallets.balance)
  ├─ [출금 신청] 버튼 → /withdraw
  ├─ 이메일 표시
  └─ [로그아웃] → /login
```

### 1-7. 출금 신청

```
/withdraw (WithdrawScreen)
  ├─ 현재 잔액 표시
  ├─ 출금 금액 입력 (최소 5,000P, 수수료 500P 차감)
  ├─ 은행명 + 계좌번호 (10자 이상) + 예금주 입력
  ├─ [신청] → submit_withdraw RPC 호출
  │    └─ 잔액 즉시 차감 + transactions WITHDRAW PENDING INSERT
  └─ 처리 결과: 어드민이 /admin/withdraw에서 수동 처리
```

**포인트 차감 시점:** 출금 신청 시 `submit_withdraw` RPC에서 즉시 차감
- 어드민 `process_withdraw` RPC: PENDING → COMPLETED (잔액 추가 변경 없음)
- 어드민 `reject_withdraw` RPC: PENDING → REJECTED + 잔액 복구 (차감된 금액 환불)

---

## 2. 광고주 웹 (B2B)

### 2-1. 로그인 / 회원가입

```
/web/login (WebLoginScreen)
  ├─ [로그인] 탭
  │    └─ 이메일 + 비밀번호 → signIn() → /web/dashboard
  └─ [회원가입] 탭 (2-step)
       ├─ Step 1: 이메일 + 비밀번호 → signUp() → 세션 생성
       │    (Step 진행 인디케이터: ● → ○)
       └─ Step 2: 전화번호 + 회사명 + 사업자번호(10자리) + 세금계산서 이메일(선택)
            └─ register_advertiser RPC → business_info INSERT → /web/dashboard
```

**라우터 인증 가드:**
- `/web/*` 접근 시 세션 없으면 → `/web/login`
- `/admin/*` 접근 시 세션 없으면 → `/admin/login`

### 2-2. 광고주 대시보드

```
/web/dashboard (WebDashboardScreen)
  ├─ 포인트 잔액 카드
  ├─ 총 유입 수 / 캠페인 수 요약
  ├─ 캠페인 목록 (DashboardCampaign)
  │    각 항목: 키워드 / 상태 배지 / 오늘 유입 / 누적 유입 / 현재 순위
  │    상태: ACTIVE / PAUSED / ENDED / RANK_OUT(ACTIVE이나 순위 15위 초과)
  ├─ 캠페인 탭 → /web/campaign/:id
  ├─ [새 광고 등록] → /web/campaign/new
  ├─ [포인트 충전] → /web/charge
  └─ [포인트 내역] → /web/transactions
```

**데이터 흐름:**
- `dashboardDataProvider` → `dashboard_repository.fetchDashboardData()` → `get_dashboard_data` RPC
- RPC 반환: wallets.balance + campaigns (with today/total mission count + latest rank)

### 2-3. 광고 등록 (Step 1~3)

```
/web/campaign/new (CampaignNewScreen)
  ├─ Step 1: 상품 정보 + 키워드 선택
  │    ├─ 상품 URL 입력 (스마트스토어 링크)
  │    ├─ 대표 키워드(시드) 입력
  │    ├─ [키워드 자동완성] 버튼 (URL + 시드 키워드 모두 입력 시 활성화)
  │    │    └─ RankApiClient.fetchKeywords(url, seedKeyword) 호출 (최대 60초)
  │    │         → 키워드 선택 모달 (BottomSheet)
  │    │              ├─ 추천 키워드 목록 (자동완성 API 기반, 순위 뱃지 표시)
  │    │              │    초록 ≤15위 / 주황 >15위 / 회색 순위권 밖
  │    │              ├─ 직접 추가 섹션
  │    │              │    키워드 입력 → [추가] → fetchRank() 순위 조회 후 목록 추가
  │    │              │    삭제 [X] 버튼으로 제거 가능
  │    │              ├─ 최대 10개 ON 선택 가능
  │    │              └─ [N개 선택 완료] 버튼으로 닫기
  │    ├─ 선택된 키워드 수 표시 (변경 시 [키워드 자동완성] 재클릭)
  │    └─ URL + 시드 + 선택 키워드 1개 이상 시 [다음] 버튼 활성화
  │
  ├─ Step 2: 캠페인 설정
  │    ├─ 정답 태그 등록 (3~5개 단어, 미션 정답 풀)
  │    ├─ 시작일 / 종료일 선택 (최소 7일)
  │    ├─ 일일 목표 유입 수 입력 (명/일)
  │    ├─ 예산 미리보기: 키워드 수 × 기간 × 일일 목표 × 50P
  │    └─ [다음]
  │
  └─ Step 3: 최종 확인 및 등록
       ├─ 총 예산 확인 (키워드 수 × 기간 × 일일 목표 × 50P)
       ├─ 현재 포인트 잔액 표시
       ├─ [등록 완료] → 선택된 키워드 수만큼 register_campaign RPC 순차 호출
       │    └─ 성공: 각 캠페인별 포인트 즉시 차감 → /web/dashboard
       │    └─ 실패 (잔액 부족): 토스트 → /web/charge 안내
       └─ 실패 시 충전 버튼 제공
```

**register_campaign RPC 서버 처리 (키워드당 1회):**
1. 포인트 잔액 확인 (일수 × daily_target × 50)
2. `campaigns` INSERT
3. `campaign_tags` INSERT (태그 배열)
4. `wallets.balance -= 예산` + `transactions` SPEND INSERT

### 2-4. 광고 상세

```
/web/campaign/:id (CampaignDetailScreen)
  ├─ 상태 바: [진행중/일시중지/종료] 배지 + 기간 + 잔여 일수
  ├─ 캠페인 정보 카드
  │    키워드 / 일일 목표 / 기간 / 예산 / 상품 URL (외부 링크)
  ├─ 성과 현황 카드
  │    오늘 유입 / 현재 순위 (15위 이내 초록, 초과 빨강) / 누적 유입 + 달성률 프로그레스바
  └─ 순위 추이 차트 (fl_chart LineChart, 최근 7일)
       y축 반전: 1위 = 상단 (낮은 숫자 = 좋음)
```

**데이터 흐름:**
- `campaignDetailProvider` → `campaign_repository.fetchCampaignDetail(id)`
- `campaignStatsProvider` → `campaign_repository.fetchCampaignStats(id)` → mission_logs + campaign_rank_history
- `rankHistoryProvider` (dashboard_provider.dart) → `dashboard_repository.fetchRankHistory(id)` → campaign_rank_history (최근 7일)

> ⚠️ `campaign_rank_history`는 GitHub Actions 크론(매일 KST 03:00)이 `POST /run-scheduler`를 호출해 갱신
> → 미실행 시 차트 비어 있음

### 2-5. 포인트 충전

```
/web/charge (ChargeScreen)
  ├─ 현재 포인트 잔액
  ├─ 충전 금액 입력
  ├─ 세금계산서 발행 여부 선택 (선택 시 × 1.1 배율)
  ├─ 입금 정보 확인 (운영자 계좌)
  └─ [입금 완료 신청] → transactions CHARGE PENDING INSERT
       description: JSON {name: 입금자명, tax: 세금계산서여부, amount: 입금금액}
       → 어드민이 /admin/charge에서 수동 승인
```

### 2-6. 포인트 내역

```
/web/transactions (TransactionsScreen)
  └─ 전체 포인트 거래 내역 목록
       (CHARGE / SPEND / EARN / WITHDRAW) + 금액 + 일시 + 상태
```

---

## 3. 어드민 웹

> 진입점: `/admin/login` (AdminLoginScreen) — 어드민 전용 로그인 (회원가입 없음)
> 라우터 가드: `/admin/*` 접근 시 세션 없으면 → `/admin/login`
> role 검증: router.dart 세션 가드만 적용 (admin 화면 내부 role 체크 없음)

### 3-1. 어드민 로그인

```
/admin/login (AdminLoginScreen)
  └─ 이메일 + 비밀번호 → signIn() → /admin/charge
```

### 3-2. 충전 승인

```
/admin/charge (AdminChargeScreen)
  ├─ [대기 중] 탭
  │    각 항목: 입금자명 / 세금계산서 여부 / 입금금액 / 신청일시
  │    ├─ [승인] → approve_charge RPC
  │    │    └─ PENDING → COMPLETED + wallets.balance += 금액
  │    └─ [거절] → reject_charge RPC
  │         └─ PENDING → REJECTED (포인트 미지급)
  └─ [처리 완료] 탭
       처리된 내역 목록 (승인/거절 구분)
```

### 3-3. 출금 처리

```
/admin/withdraw (AdminWithdrawScreen)
  ├─ [대기 중] 탭
  │    각 항목 카드: 예금주 / 은행명 / 계좌번호 / 신청금액 / 실수령액(- 500P)
  │    ├─ [처리 완료] → process_withdraw RPC
  │    │    └─ PENDING → COMPLETED (잔액은 이미 신청 시 차감됨)
  │    └─ [거절] → reject_withdraw RPC
  │         └─ PENDING → REJECTED + wallets.balance += 신청금액 (잔액 복구)
  └─ [처리 완료] 탭
       처리된 출금 내역 목록
```

---

## 4. 랭킹 API 서버 (Python FastAPI)

### 배포 위치
- URL: `https://web-production-e7797.up.railway.app`
- Railway 서비스명: rank_module
- CORS 허용: `https://rankingup-web-production.up.railway.app`, `http://localhost`, `http://localhost:8080`

### 엔드포인트

```
GET /rank?url={smartstore_url}&keyword={keyword}
  응답:
  {
    "rank": 5,                    # 정수 (순위), null이면 상품 미노출
    "product_name": "상품명",     # HTML 태그 제거됨
    "thumbnail_url": "https://..." # 썸네일 URL, null 가능
  }

GET /keywords?url={smartstore_url}&keyword={seed_keyword}
  응답:
  {
    "keywords": [
      {"keyword": "헬스장갑", "rank": 1},
      {"keyword": "여자 헬스장갑", "rank": 7},
      {"keyword": "헬스장갑 추천", "rank": null}
    ]
  }
  처리: 네이버 자동완성 API → 후보 최대 10개 → 각 키워드별 순위 조회

POST /run-scheduler
  헤더: X-Scheduler-Secret: {토큰}
  응답: {"status": "started"}
  처리: update_all_campaign_ranks() 백그라운드 실행 (즉시 반환)

GET /health
  응답: {"status": "ok"}
```

### 내부 처리 (crawler.py)

```
fetch_naver_rank(url, keyword):
  1. URL에서 숫자 product_id 파싱 (_extract_numeric_id)
  2. 네이버 쇼핑 API 호출 (query={keyword}&display=100&sort=sim)
     → 6개 계정 순환, 429/403 시 다음 계정으로 전환
  3. 결과 100개 순회:
     - 1순위: productId 직접 비교
     - 2순위: _extract_numeric_id(item.link) 일치 여부 (fallback)
  4. 매칭 시 해당 순위 반환, 없으면 null

fetch_autocomplete_keywords(seed_keyword):
  → 네이버 자동완성 API (ac.search.naver.com/nx/ac)
  → 단어 수 2개 이하만 포함, seed_keyword 맨 앞 추가, 최대 10개 반환

fetch_related_keywords(product_url, seed_keyword):
  → SmartStore URL product_id 검증
  → fetch_autocomplete_keywords(seed_keyword)
  → 각 키워드별 fetch_naver_rank() + 0.3초 대기
```

### 일일 순위 갱신

```
GitHub Actions (cron: '0 18 * * *' = KST 03:00):
  → POST /run-scheduler (X-Scheduler-Secret 헤더 포함)
  → --retry 3, --max-time 30

/run-scheduler 내부 (BackgroundTasks):
  → update_all_campaign_ranks()
  1. Supabase에서 ACTIVE 캠페인 전체 조회 (service_role key, RLS bypass)
  2. 각 캠페인: fetch_naver_rank(product_url, keyword)
  3. 순위 있을 때만 campaign_rank_history INSERT
  4. 캠페인 간 1초 대기 (API 과부하 방지)

※ APScheduler도 서버 시작 시 등록되나 Railway 무료 플랜 슬립 시 미실행
   → GitHub Actions가 실질적인 주 실행 수단
```

---

## 5. 전체 데이터 흐름

### 포인트 생명주기

```
[광고주] 포인트 충전 신청
  → transactions CHARGE PENDING INSERT
  → [어드민] approve_charge RPC
  → wallets.balance += 금액
  → transactions CHARGE COMPLETED

[광고주] 캠페인 등록
  → register_campaign RPC (키워드별 1회)
  → wallets.balance -= 예산
  → transactions SPEND COMPLETED

[유저] 미션 성공
  → verify_mission RPC
  → wallets.balance += 7
  → transactions EARN COMPLETED

[유저] 출금 신청
  → submit_withdraw RPC
  → wallets.balance -= 신청금액 (즉시 차감)
  → transactions WITHDRAW PENDING INSERT

[어드민] 출금 처리
  → process_withdraw RPC → PENDING → COMPLETED (잔액 변경 없음)
  또는
  → reject_withdraw RPC → PENDING → REJECTED + wallets.balance += 신청금액 (환불)
```

### 미션 수행 상세 흐름

```
start_mission RPC
  → mission_logs INSERT (status=STARTED)
  → 반환: {log_id, keyword}

사용자: 네이버 앱 이동 → 검색 → 구매 페이지 확인 → 앱 복귀

verify_mission RPC
  → 10분 초과 체크 (started_at 기준)
  → 태그 정답 비교 (campaign_tags.tag_word)
  → 성공: mission_logs COMPLETED + wallets +7 + transactions EARN
  → 실패: mission_logs FAILED
  → 타임아웃: mission_logs FAILED + campaigns.current_count - 1
```

### 순위 데이터 흐름

```
[GitHub Actions, 매일 KST 03:00]
  → POST /run-scheduler
  → ACTIVE 캠페인 목록 조회
  → 각 캠페인: 네이버 쇼핑 API 호출
  → campaign_rank_history INSERT

[광고주 웹]
  → /web/dashboard: 최신 순위 1건 조회 (per campaign)
  → /web/campaign/:id: 최근 7일 순위 차트 (fl_chart)
  → /web/campaign/new: [키워드 자동완성] → /keywords API → 실시간 순위 조회
```

---

## 6. 어뷰징 방지 포인트

| 단계 | 방지 규칙 | 처리 위치 |
|------|-----------|----------|
| 회원가입 | Device ID 중복 → 새 계정 차단 | Supabase RPC (handle_new_user) |
| 미션 시작 | 동일 유저 하루 1회 제한 | start_mission RPC |
| 미션 시작 | 정답 태그 클라이언트 미반환 | start_mission RPC (log에만 저장) |
| 정답 제출 | 10분 타임아웃 (서버 started_at 기준) | verify_mission RPC |
| 포인트 지급 | 동시성 제어 (SELECT FOR UPDATE) | verify_mission / submit_withdraw RPC |
| 어드민 접근 | 세션 없으면 /admin/login 리다이렉트 | router.dart |

---

## 7. 주요 제약 및 알려진 이슈

| 항목 | 내용 |
|------|------|
| start_mission 일일 제한 | 테스트용으로 주석 처리 중 → 정식 출시 전 해제 필수 |
| 순위 차트 빈 화면 | GitHub Actions 미실행 시 campaign_rank_history 데이터 없음 |
| CORS 허용 도메인 | main.py에 Flutter 웹 URL 하드코딩 (URL 변경 시 수정 필요) |
| 어드민 계정 생성 | Supabase 대시보드 UI 생성 시 트리거 실패 → SQL 직접 INSERT 필요 |
| rankHistoryProvider | dashboard_provider.dart 정의 → campaign_detail_screen.dart에서 cross-feature import |
| /keywords 응답 시간 | 자동완성 API + 순위 조회 × 10개 = 약 9~10초 (Flutter 타임아웃 60초 설정) |
