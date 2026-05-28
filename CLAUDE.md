# CLAUDE.md — 스토어 트래픽 부스터 개발 지침서

> Claude Code는 이 파일을 모든 작업 전에 읽는다.
> 모르는 것이 생기면 PRD 문서(store_traffic_booster_PRD.docx)를 참조한다.

---

## 1. 프로젝트 한 줄 정의

스마트스토어 판매자(광고주)가 포인트를 충전하면, 앱 유저가 키워드 검색 미션을 수행하고 리워드를 받는 **B2B2C 트래픽 부스팅 플랫폼**.

---

## 2. 확정 기술 스택

| 레이어 | 기술 | 비고 |
|--------|------|------|
| UI / 앱 / 웹 | Flutter (Dart) | 단일 코드베이스 |
| 백엔드 / DB | Supabase (PostgreSQL) | BaaS, 별도 서버 없음 |
| 인증 | Supabase Auth + Device ID | |
| 상태관리 | flutter_riverpod | |
| 라우팅 | go_router | |
| 딥링크 | url_launcher | |
| 기기식별 | device_info_plus | |
| 광고 | google_mobile_ads (AdMob) | |
| 차트 | fl_chart | |
| 로컬저장 | shared_preferences | |

---

## 3. 디렉토리 구조

> 실제 구현 파일 기준 (2026-05-25 검증 완료)

```
lib/
├── main.dart
├── app/
│   ├── router.dart              # go_router 전체 라우팅 + 인증 리다이렉트
│   └── supabase_client.dart     # Supabase 초기화 (URL/anon key 하드코딩)
├── features/
│   ├── auth/
│   │   └── presentation/
│   │       ├── splash_screen.dart        # 자동로그인 체크, 웹/앱 분기
│   │       ├── login_screen.dart         # 앱 로그인/회원가입
│   │       └── web_login_screen.dart     # 광고주 로그인/회원가입 (2-step)
│   ├── mission/
│   │   ├── data/mission_repository.dart
│   │   ├── domain/mission_model.dart
│   │   └── presentation/
│   │       ├── mission_home_screen.dart  # 홈 — 미션 보드 (무한 스크롤)
│   │       ├── mission_home_provider.dart
│   │       ├── mission_detail_screen.dart
│   │       ├── mission_detail_provider.dart
│   │       ├── mission_active_screen.dart # 미션 진행중 (타이머, 딥링크)
│   │       └── mission_active_provider.dart
│   ├── wallet/
│   │   ├── data/wallet_repository.dart
│   │   ├── domain/wallet_model.dart
│   │   └── presentation/
│   │       ├── history_screen.dart       # 참여 내역
│   │       ├── history_provider.dart
│   │       ├── mypage_screen.dart        # 마이페이지 (잔액, 프로필)
│   │       ├── wallet_provider.dart
│   │       ├── withdraw_screen.dart      # 출금 신청
│   │       └── withdraw_provider.dart
│   ├── campaign/
│   │   ├── data/campaign_repository.dart # fetchProductRank, registerCampaign 등
│   │   ├── domain/campaign_model.dart    # CampaignModel, CampaignStats
│   │   └── presentation/
│   │       ├── campaign_new_screen.dart  # 광고 등록 (Step 1~3)
│   │       ├── campaign_detail_screen.dart # 광고 상세 + 순위 차트
│   │       └── campaign_provider.dart   # walletBalanceProvider, campaignDetailProvider
│   ├── dashboard/
│   │   ├── data/dashboard_repository.dart # fetchDashboardData, fetchRankHistory
│   │   ├── domain/dashboard_model.dart   # DashboardData, DashboardCampaign, RankHistory
│   │   └── presentation/
│   │       ├── web_dashboard_screen.dart
│   │       └── dashboard_provider.dart   # dashboardDataProvider, rankHistoryProvider
│   ├── charge/
│   │   ├── data/charge_repository.dart
│   │   ├── domain/charge_model.dart
│   │   └── presentation/
│   │       ├── charge_screen.dart        # 포인트 충전 (입금 정보 제출)
│   │       ├── charge_provider.dart
│   │       └── transactions_screen.dart  # 포인트 내역
│   └── admin/
│       ├── data/
│       │   ├── admin_charge_repository.dart
│       │   ├── admin_withdraw_repository.dart
│       │   └── notice_repository.dart
│       ├── domain/
│       │   ├── admin_charge_model.dart   # AdminChargeRecord (description 파싱)
│       │   ├── admin_withdraw_model.dart # AdminWithdrawRecord (JSON memo 파싱)
│       │   └── notice_model.dart
│       └── presentation/
│           ├── admin_charge_screen.dart  # ADMIN role 검증 필수
│           ├── admin_charge_provider.dart
│           ├── admin_withdraw_screen.dart
│           ├── admin_withdraw_provider.dart
│           ├── admin_notice_screen.dart  # 공지 등록 + 목록
│           └── admin_notice_provider.dart
└── shared/
    ├── widgets/
    │   ├── bottom_nav_bar.dart           # 앱 하단 네비게이션
    │   └── admob_banner.dart             # AdMob 배너 위젯
    ├── models/                           # (비어 있음 — 모델은 각 feature/domain/)
    └── utils/
        ├── rank_api_client.dart          # RankApiClient (--dart-define=RANK_API_URL)
        ├── admob_config.dart             # 광고 단위 ID 상수
        ├── admob_interstitial.dart       # 전면 광고 헬퍼
        └── device_util.dart             # Device ID 조회
```

**주요 아키텍처 참고 사항:**
- `rankHistoryProvider`는 `dashboard_provider.dart`에 정의, `campaign_detail_screen.dart`에서 import
- auth feature에 data/domain 폴더 없음 (Supabase Auth 직접 사용)
- `shared/models/` 디렉토리는 비어 있음 (각 feature의 `domain/` 폴더에 모델 정의)

---

## 4. 라우팅 구조 (go_router)

### 앱 (Android — B2C)
| 경로 | 화면 |
|------|------|
| `/splash` | 스플래시 (자동로그인 체크) |
| `/login` | 로그인 |
| `/home` | 홈 — 미션 보드 |
| `/mission/:id` | 미션 상세 |
| `/mission/:id/active` | 미션 진행중 |
| `/history` | 참여 내역 |
| `/mypage` | 마이페이지 |
| `/withdraw` | 출금 신청 |

### 웹 (광고주 — B2B)
| 경로 | 화면 |
|------|------|
| `/web/login` | 광고주 로그인/회원가입 |
| `/web/dashboard` | 메인 대시보드 |
| `/web/campaign/new` | 광고 등록 (Step 1~3) |
| `/web/campaign/:id` | 광고 상세 |
| `/web/charge` | 포인트 충전 |
| `/web/transactions` | 포인트 내역 |

### 어드민 웹 (운영자)
| 경로 | 화면 |
|------|------|
| `/admin/login` | 어드민 로그인 |
| `/admin/charge` | 충전 승인 |
| `/admin/withdraw` | 출금 처리 |
| `/admin/notice` | 공지 등록 |

---

## 5. DB 테이블 목록

> 스키마 상세는 PRD 섹션 5 참조. 아래는 Claude Code가 참조하는 핵심 요약.

| 테이블 | 역할 |
|--------|------|
| `users` | 통합 회원 (role: USER/ADMIN, device_id 포함) |
| `business_info` | 광고주 사업자 정보 (users와 1:1) |
| `wallets` | 포인트 잔액 (users와 1:1) |
| `transactions` | 포인트 원장 (CHARGE/SPEND/EARN/WITHDRAW) |
| `campaigns` | 광고 캠페인 |
| `campaign_tags` | 정답 태그 풀 (campaigns와 1:N) |
| `mission_logs` | 미션 수행 이력 |

---

## 6. Supabase RPC 목록 (서버사이드 함수)

반드시 Supabase SQL로 구현. 클라이언트에서 직접 INSERT/UPDATE 금지.

> 전체 14개 RPC (마이그레이션 0000~0013 기준, 2026-04-29 확인)

### 미션 / 핵심 (migration 0001~0005)

| RPC 함수명 | 파라미터 | 역할 |
|------------|----------|------|
| `start_mission` | `p_campaign_id uuid, p_user_id uuid, p_device_id text` | 미션 시작: 중복 체크 → 수량 체크 → log INSERT → 태그 랜덤 할당 |
| `verify_mission` | `p_log_id uuid, p_user_id uuid, p_submitted_tag text` | 정답 검증: 10분 타임아웃 + 리워드 +7P 지급 |
| `approve_charge` | `p_tx_id uuid` | 충전 승인: PENDING → COMPLETED + 포인트 지급 |
| `process_withdraw` | `p_tx_id uuid` | 출금 처리: PENDING → COMPLETED + 잔액 차감 (FOR UPDATE) |
| `register_campaign` | `p_user_id uuid, p_product_url text, p_keyword text, p_daily_target int, p_group_daily_target int, p_group_id uuid, p_start_date date, p_end_date date, p_tags text[], p_sort_orders int[], p_answer_index int, p_seed_keyword text` | 캠페인 등록: 예산 즉시 차감(group_daily_target 기준), 최소 7일, 50P/명/일. 동일 group_id로 서브키워드 묶음 |

### 광고주 / 대시보드 (migration 0007~0008)

| RPC 함수명 | 파라미터 | 역할 |
|------------|----------|------|
| `register_advertiser` | `p_company_name text, p_business_number text, p_phone text, p_tax_email text (optional)` | 광고주 사업자 정보 등록 (business_info INSERT) |
| `get_dashboard_data` | 없음 (auth.uid() 자동 사용) | 광고주 대시보드: 캠페인 목록 + 지갑 잔액 + 총 유입수 |

### 어드민 — 충전 처리 (migration 0012)

| RPC 함수명 | 파라미터 | 역할 |
|------------|----------|------|
| `reject_charge` | `p_tx_id uuid` | 충전 거절: PENDING → REJECTED (포인트 미지급) |
| `get_pending_charges` | 없음 (ADMIN role 검증) | 승인 대기 충전 목록 조회 |
| `get_processed_charges` | 없음 (ADMIN role 검증) | 처리 완료 충전 내역 조회 |

### 어드민 — 출금 처리 (migration 0013)

| RPC 함수명 | 파라미터 | 역할 |
|------------|----------|------|
| `reject_withdraw` | `p_tx_id uuid` | 출금 거절: PENDING → REJECTED (잔액 복구 없음) |
| `get_pending_withdraws` | 없음 (ADMIN role 검증) | 출금 대기 목록 조회 |
| `get_processed_withdraws` | 없음 (ADMIN role 검증) | 처리 완료 출금 내역 조회 |

### 트리거 (자동 실행, 직접 호출 불가)

| 함수명 | 트리거 조건 | 역할 |
|--------|------------|------|
| `handle_new_user()` | auth.users INSERT 시 | public.users + public.wallets 자동 생성 |

> ⚠️ 트리거 생성 이슈: Supabase 대시보드 UI로 계정 생성 시 트리거 실패 가능
> → SQL Editor에서 public.users + public.wallets 수동 INSERT 필요

---

## 7. 핵심 비즈니스 로직

### 미션 흐름
```
미션 시작 버튼
  → start_mission RPC (서버: 중복체크 → 수량체크 → log INSERT → 태그 랜덤할당)
  → 키워드 클립보드 복사
  → 네이버 딥링크 실행: naversearchapp://search?where=nexearch&query={키워드}
  → 유저가 앱으로 복귀 (AppLifecycleState.resumed 감지)
  → 타이머 화면 노출 (started_at 기준 남은 시간 계산)
  → 복귀 후 3초간 [리워드 받기] 버튼 비활성화
  → 정답 입력 → verify_mission RPC
  → 성공: +7원 적립 + 폭죽 애니메이션
  → 실패(오답): 진동 + 오답 토스트
  → 실패(10분 초과): 실패 처리 + 수량 반환
```

### 포인트 계산
```
광고주 충전:  입력금액 × 1.1 (세금계산서 선택 시)
캠페인 예산:  일일 유입 × 기간(일) × 50원
유저 적립:    미션 성공 1건 = +7원
출금 수수료:  신청 금액에서 500P 차감
```

### 캠페인 등록 검증 순서
```
1. 상품 URL + 키워드 입력 → 다음 단계 버튼 활성화 (순위 조회는 선택사항)
2. [순위 조회] 버튼 클릭 시 → 파이썬 랭킹 모듈 API 호출
   - 15위 이내: 초록색 표시 (권장)
   - 16위 이상: 주황 경고 표시 (등록은 가능)
   - 찾을 수 없음: 주황 경고 표시 (등록은 가능)
3. 최종 등록 시: register_campaign RPC → 포인트 즉시 차감
```
> ⚠️ 2026-04-27 변경: 순위 제한 없이 URL+키워드만 있으면 등록 가능하도록 완화

---

## 8. 어뷰징 방지 규칙 (서버에서만 처리)

| 규칙 | 처리 위치 |
|------|----------|
| 동일 device_id 중복 계정 차단 | Supabase RPC |
| 동일 유저 하루 1회 미션 제한 | start_mission RPC |
| 정답 태그 랜덤 할당 (클라이언트 미노출) | start_mission RPC |
| 10분 타임아웃 (서버 started_at 기준) | verify_mission RPC |
| 포인트 동시성 제어 | SELECT FOR UPDATE |

---

## 9. 절대 하면 안 되는 것 (NEVER DO)

```
❌ 정답 tag_word를 클라이언트 응답에 포함하거나 노출
❌ 포인트 계산을 클라이언트에서 처리
❌ 미션 성공 여부를 클라이언트에서 판단
❌ 10분 타임아웃을 클라이언트 타이머로만 처리
❌ Device ID 중복 체크를 클라이언트에서만 수행
❌ wallets.balance를 클라이언트에서 직접 UPDATE
❌ DB 스키마를 PRD 확인 없이 임의 변경
❌ 어드민 페이지를 role 검증 없이 접근 허용
```

---

## 10. 개발 Phase 순서

```
Phase 1 (1~2주): 기반 세팅
  └─ Supabase 스키마 생성 → Flutter 초기화 → 라우팅 → 로그인/Device ID

Phase 2 (2~3주): 앱 핵심 기능
  └─ 미션 보드 → 미션 플로우 → 딥링크 → 정답검증 → 포인트 → AdMob

Phase 3 (2~3주): 웹 핵심 기능
  └─ 광고주 로그인 → 캠페인 등록 → 충전 → 대시보드

Phase 4 (1~2주): 어드민 + 배포
  └─ 충전승인 → 출금처리 → 파이썬 모듈 연동 → Play Store 배포
```

현재 진행 Phase: **Phase 10 완료 + 배포 후 버그 수정** (versionCode 14 Play Console 업로드 완료 2026-05-28)

- ✅ 완료: Phase 1 전체 (Supabase 스키마, Flutter 초기화, go_router, 로그인, Device ID)
- ✅ 완료: Phase 2 전체
  - 2-1: 홈 미션 보드 (무한 스크롤)
  - 2-2: 미션 상세 화면 + start_mission RPC
  - 2-3: 미션 진행 화면 (AppLifecycle 감지, 타이머, verify_mission RPC)
  - 2-4: 참여 내역, 마이페이지, 출금 신청 화면, 하단 네비게이션
  - 2-5: AdMob 배너(홈·참여내역) + 전면 광고(미션 성공 시)
- ✅ 완료: Phase 3 전체
  - 3-1: 광고주 로그인/회원가입 (/web/login) + register_advertiser RPC
  - 3-2: 광고주 대시보드 (/web/dashboard) + 인증 리다이렉트
  - 3-3: 캠페인 등록 Step 1~3 (/web/campaign/new) + register_campaign RPC
  - 3-4: 포인트 충전 화면 (/web/charge) + RLS 정책
  - 3-5: 포인트 내역 화면 (/web/transactions)
- ✅ 완료: Phase 4-1 — 어드민 충전 승인 (/admin/charge)
  - 20260317000012_admin_charge_rpc.sql — reject_charge / get_pending_charges / get_processed_charges RPC
  - admin/domain/admin_charge_model.dart — AdminChargeRecord (description 파싱: 입금자명/세금계산서/입금금액)
  - admin/data/admin_charge_repository.dart — fetchPendingCharges / fetchProcessedCharges / approveCharge / rejectCharge
  - admin/presentation/admin_charge_provider.dart — currentUserRoleProvider + pendingChargesProvider + processedChargesProvider
  - admin/presentation/admin_charge_screen.dart — ADMIN role 검증 + 대기 목록 ([승인]/[거절] 버튼) + 처리 완료 내역
- ✅ 완료: Phase 4-2 — 어드민 출금 처리 (/admin/withdraw)
  - 20260317000013_admin_withdraw_rpc.sql
    - process_withdraw RPC 업데이트: wallets.balance -= amount 차감 버그 수정 + FOR UPDATE 잠금 추가
    - reject_withdraw RPC 신규: WITHDRAW PENDING → REJECTED (잔액 변경 없음)
    - get_pending_withdraws / get_processed_withdraws RPC 신규
  - admin/domain/admin_withdraw_model.dart — AdminWithdrawRecord (memo JSON 파싱: bank/account/holder, netAmount 계산)
  - admin/data/admin_withdraw_repository.dart — processWithdraw / rejectWithdraw / fetchPendingWithdraws / fetchProcessedWithdraws
  - admin/presentation/admin_withdraw_provider.dart — pendingWithdrawsProvider + processedWithdrawsProvider
  - admin/presentation/admin_withdraw_screen.dart — ADMIN role 검증 + 대기 목록 (카드 UI) + 처리 완료 내역
- ✅ 완료: Phase 4-3 — 파이썬 랭킹 모듈 연동 (rank_api_client.dart)
  - shared/utils/rank_api_client.dart — RankApiClient (--dart-define=RANK_API_URL 주입, 10초 타임아웃, 커스텀 예외 4종: Timeout/NotFound/Api/Network)
  - campaign_repository.dart — fetchProductRank() 실제 API 호출로 교체 (mock 주석 유지, RankNotFoundException → null 반환)
  - campaign_new_screen.dart — 타입별 예외 SnackBar 처리 + 상품 미노출(_rankNotFound) UI 추가
- ✅ 완료: Phase 4-4 — Play Store 배포 준비
  - android/key.properties — 서명 키 실제 값 입력 완료 (keyAlias=upload, storeFile=/Users/daeun/upload-keystore.jks)
  - android/app/build.gradle.kts — applicationId(com.storetrafficbooster.app)/targetSdk(35)/versionCode(3)/versionName(1.0.0)/signingConfig/minify 설정
    - ※ minSdk는 linter에 의해 flutter.minSdkVersion으로 유지됨
  - android/app/proguard-rules.pro — Flutter/OkHttp/AdMob/Kotlin keep 규칙
  - AndroidManifest.xml — INTERNET 퍼미션 추가 + naversearchapp:// queries 추가
  - shared/utils/admob_config.dart — 배너/전면 광고 단위 ID 실제 값으로 교체
    - 앱 ID: ca-app-pub-6225110164827541~2986900842
    - 배너: ca-app-pub-6225110164827541/7157245996
    - 전면: ca-app-pub-6225110164827541/3625195096
  - CLAUDE.md — Play Store 배포 체크리스트 섹션 추가 (섹션 12)

- ✅ 완료: Phase 4-5 — 로컬 테스트 및 버그 수정 (2026-04-05)

  **웹 호환성 수정 (Flutter Web)**
  - `main.dart` — `kIsWeb` 조건 추가: 웹 실행 시 `MobileAds.instance.initialize()` 스킵
    (google_mobile_ads는 웹 미지원 → 미처리 시 흰 화면 크래시)
  - `login_screen.dart` — `kIsWeb` 조건 추가: 웹 실행 시 `Platform.isAndroid` 호출 방지
    (`dart:io`의 Platform은 웹에서 UnsupportedError 발생)

  **플레이스홀더 화면 구현**
  - `splash_screen.dart` — 실제 세션 체크 구현: 500ms 지연 → currentSession 확인 → /home or /login
  - `login_screen.dart` — 실제 로그인/회원가입 구현: 이메일+비밀번호, Device ID 저장, 에러 매핑

  **환경변수 설정**
  - `supabase_client.dart` — defaultValue에 실제 Supabase URL/anon key 입력
    (--dart-define 없이 `flutter run --release` 단독 실행 가능)
  - `.vscode/launch.json` — Flutter debug/release 실행 구성 추가

  **Supabase RPC 버그 수정**
  - `get_pending_charges`, `get_processed_charges` — `id` ambiguous 오류 수정
    (`WHERE id = auth.uid()` → `WHERE u.id = auth.uid()`, 조인 별칭 u→usr)
    원인: RETURNS TABLE의 id 컬럼과 users.id 컬럼명 충돌 (PostgreSQL 42702)
  - `get_pending_withdraws`, `get_processed_withdraws` — 동일한 id ambiguous 오류 수정
  - `get_pending_withdraws`, `get_processed_withdraws` — `t.memo` → `t.description AS memo`
    원인: transactions 테이블에 memo 컬럼 없음, description에 JSON 형태로 저장됨 (PostgreSQL 42703)

  **AAB 빌드 성공**
  - `flutter build appbundle --release` → `app-release.aab` (49.5MB) 빌드 완료

  **로컬 테스트 완료 항목**
  - Android 에뮬레이터 (API 36): 스플래시 → 로그인 → 회원가입 정상 동작
  - 광고주 웹 (`flutter run -d chrome --web-port=8080`):
    - `/web/login` → `/web/dashboard` → `/web/campaign/new` → `/web/charge` → `/web/transactions` 정상
    - `/web/campaign/:id` (광고 상세) — 미구현 플레이스홀더 상태
  - 어드민 웹:
    - `/admin/charge` (충전 승인) 정상
    - `/admin/withdraw` (출금 처리) 정상

  **테스트 계정 (Supabase)**
  - 이메일: naturaltorymarket2@gmail.com / 비밀번호: 123456
  - role: ADMIN (수동 설정)
  - ※ Supabase 대시보드에서 직접 생성 시 handle_new_user 트리거가 실패할 수 있음
    → SQL Editor에서 public.users + public.wallets 수동 INSERT 필요

- ✅ 완료: Phase 4-6 — 광고 상세 화면 구현 + 테스트 데이터

  **광고 상세 화면 구현 (/web/campaign/:id)**
  - `campaign/presentation/campaign_detail_screen.dart` — 전체 구현
    - 상태 바: 진행 중/일시 중지/종료 배지 + 기간 + 잔여 일수
    - 캠페인 정보 카드: 키워드, 일일 목표, 기간, 예산, 상품 URL (외부 링크)
    - 성과 현황 카드: 오늘 유입 / 현재 순위(15위 이내 초록, 초과 빨강) / 누적 유입 + 달성률 프로그레스바
    - 순위 추이 차트: fl_chart LineChart (최근 7일, y축 반전으로 1위=상단 표시)
  - `campaign/presentation/campaign_provider.dart` — `campaignDetailProvider`, `campaignStatsProvider` 추가
  - `campaign/data/campaign_repository.dart` — `fetchCampaignDetail()`, `fetchCampaignStats()` 메서드 추가
    - `fetchCampaignStats()`: KST 자정 기준 오늘 성공 건수 + 누적 건수 + campaign_rank_history 최신 순위
  - `campaign/domain/campaign_model.dart` — `CampaignStats` 클래스 추가 + `CampaignModel.fromMap()` startDate/endDate 추가

  **테스트 데이터 SQL**
  - `supabase/test_data/insert_test_campaign.sql` 신규 생성
    - 키워드 "무선 블루투스 이어폰", 10명/일, 14일, ACTIVE 상태 캠페인 INSERT
    - campaign_tags 3개 (블루투스이어폰 / 무선이어폰추천 / 노이즈캔슬링이어폰) INSERT
    - 실행 결과에서 campaign_id 출력 → `http://localhost:8080/web/campaign/{id}` 확인
    - ※ users 테이블 비어 있으면 EXCEPTION 발생 — 앱 로그인 후 실행 필요

- ✅ 완료: Phase 4-7 — 파이썬 랭킹 모듈 서버 개발

  **rank_module/ 디렉토리 (version1/rank_module/)**
  - `crawler.py` — 네이버 쇼핑 공식 Search API 기반 순위 조회
    - 네이버 API 계정 6개 등록, 한도 초과(429/403) 시 자동으로 다음 계정으로 전환
    - SmartStore URL에서 product_id 파싱 → API 결과의 productId 필드와 매칭 (100위까지)
    - 1순위: productId 직접 비교 / 2순위: link URL에 product_id 포함 여부 (fallback)
    - 싱글톤 `_NaverApiClient`로 프로세스 내 계정 전환 상태 유지
    - API 엔드포인트: `GET openapi.naver.com/v1/search/shop.json?query={keyword}&display=100`
  - `main.py` — FastAPI 서버 (GET /rank?url=&keyword=)
    - Flutter rank_api_client.dart 스펙과 동일한 응답 형식
    - 서버 시작 시 BackgroundScheduler 자동 등록
    - GET /health 헬스 체크 엔드포인트 포함
    - 핸들러 sync 함수 (FastAPI 스레드풀 자동 실행)
  - `scheduler.py` — APScheduler BackgroundScheduler 일일 순위 갱신
    - 매일 KST 03:00 (SCHEDULER_HOUR/MINUTE 환경변수로 조정 가능)
    - ACTIVE 캠페인 전체 순위 조회 → campaign_rank_history INSERT
    - 캠페인 간 1초 대기 (API 과부하 방지)
    - service_role key로 RLS bypass
  - `requirements.txt` — fastapi, uvicorn, requests, apscheduler, supabase, python-dotenv
  - `.env.example` — 환경변수 템플릿 (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PORT, SCHEDULER_HOUR/MINUTE)

  **네이버 API 계정 (crawler.py에 하드코딩)**
  - 계정 1: E09SGvUsSXi155g2Nvuh
  - 계정 2: dgn3OcYdXliI0H4q8jww
  - 계정 3: sUUN4YCKILvwbDGuL7tL
  - 계정 4: I9TQEzQoTceN5qukTyOb
  - 계정 5: 8qpWedtXuvjmamMsCBBc
  - 계정 6: RXdmUvVbdWzT0zrO7pAC

  **실행 방법:**
  ```bash
  cd rank_module
  pip install -r requirements.txt
  cp .env.example .env   # SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 입력
  uvicorn main:app --host 0.0.0.0 --port 8000

  # 크롤러 단독 테스트
  python crawler.py "https://smartstore.naver.com/store/products/12345678" "키워드"

  # 스케줄러 즉시 1회 실행 (테스트)
  python scheduler.py
  ```

- ✅ 완료: Phase 4-8 — 앱 이름 "겟머니" 변경 (2026-04-23)

  **변경된 파일 (6개 파일, 6곳)**
  - `android/app/src/main/AndroidManifest.xml` — `android:label` → `"겟머니"`
  - `lib/main.dart` — `title: 'Store Traffic Booster'` → `'겟머니'`
  - `lib/features/auth/presentation/splash_screen.dart` — 스플래시 텍스트 → `'겟머니'`
  - `lib/features/auth/presentation/login_screen.dart` — 로고 하단 텍스트 → `'겟머니'`
  - `lib/features/auth/presentation/web_login_screen.dart` — 로고 타이틀 + 하단 안내 문구 → `'겟머니'`
  - `lib/features/dashboard/presentation/web_dashboard_screen.dart` — AppBar 타이틀 → `'겟머니'`

  **패키지 이름 확인**
  - `android/app/build.gradle.kts` — `applicationId = "com.storetrafficbooster.app"` 유지 (변경 없음)
  - Play Store applicationId는 한 번 등록하면 변경 불가이므로 현행 유지

- ✅ 완료: Phase 4-9 — 내부 테스트 배포 (2026-04-23)

  **배포 환경**
  - 플랫폼: Google Play Console 내부 테스트 트랙
  - 앱 ID: com.storetrafficbooster.app
  - 버전코드: 2 / 버전명: 1.0.0
  - 배포일: 2026-04-23
  - 상태: 내부 테스터에게 제공됨 (검토되지 않음)

  **배포 완료 항목**
  - Railway 랭킹 서버: https://web-production-e7797.up.railway.app
  - RANK_API_URL: https://web-production-e7797.up.railway.app/rank
  - Flutter 웹 배포: https://rankingup-web-production.up.railway.app
  - 개인정보처리방침: https://naturaltorymarket2.github.io/rankingup-privacy/
  - targetSdk: 35
  - 앱 아이콘: 임시 아이콘 적용 (파란 배경 + 흰색 "겟머니" 텍스트)

  **배포 후 수동 처리 필요 항목**
  - ⚠️ start_mission RPC 일일 참여 제한 주석 해제 (테스트 완료 후)
  - ⚠️ 앱 아이콘 교체 (정식 출시 전)
  - ⚠️ Play Console 앱 설정 완료 (스크린샷, 설명, 콘텐츠 등급 등)
  - ⚠️ 프로덕션 트랙 출시 (내부 테스트 완료 후)

- ✅ 완료: Phase 4-10 — 웹 라우팅 버그 수정 + 기능 개선 (2026-04-27)

  **버그 1: 웹 라우팅 (스플래시 → 광고주 대시보드)**
  - `lib/features/auth/presentation/splash_screen.dart`
    - 기존: 세션 있으면 무조건 `/home` (앱 화면) 이동
    - 수정: `kIsWeb` 분기 추가
      ```dart
      context.go(kIsWeb ? '/web/dashboard' : '/home');
      // 세션 없을 때:
      context.go(kIsWeb ? '/web/login' : '/login');
      ```
    - 원인: 단일 코드베이스에서 웹/앱 분기 누락

  **버그 2: 광고주 회원가입 2단계 UI**
  - `lib/features/auth/presentation/web_login_screen.dart`
    - 기존: 이메일+비밀번호 입력 시 즉시 로그인 처리 (사업자 정보 입력 단계 없음)
    - 수정: 2-step 회원가입 플로우 구현
      - Step 1: 이메일 + 비밀번호 → `supabase.auth.signUp()` → 세션 생성되면 Step 2
      - Step 2: 전화번호 + 회사명 + 사업자번호 + 세금계산서 이메일 → `register_advertiser` RPC → 대시보드
    - `_signupStep` (1 or 2) 상태 변수 추가
    - `_buildStepIndicator()` 위젯 추가 (점 + 선 UI)
    - `_switchTab()` 탭 전환 시 step 초기화

  **버그 3: 랭킹 모듈 CORS 오류 (웹에서 "네트워크 연결을 확인해주세요")**
  - `rank_module/main.py`
    - 기존: CORS 미들웨어 없음 → 브라우저가 응답 차단
    - 수정: `CORSMiddleware` 추가
      ```python
      app.add_middleware(
          CORSMiddleware,
          allow_origins=['https://rankingup-web-production.up.railway.app', 'http://localhost', 'http://localhost:8080'],
          allow_methods=['GET'],
          allow_headers=['*'],
      )
      ```
    - 원인: Flutter Android는 CORS 무관, Flutter Web(브라우저)은 CORS 강제

  **기능 변경: 캠페인 등록 순위 조건 완화**
  - `lib/features/campaign/presentation/campaign_new_screen.dart`
    - 기존: 순위 조회 후 15위 이내여야 다음 단계 활성화
    - 수정: URL + 키워드만 입력하면 다음 단계 활성화 (순위 조회는 선택사항)
      ```dart
      bool get _step1Valid =>
          _urlCtrl.text.trim().isNotEmpty &&
          _keywordCtrl.text.trim().isNotEmpty;
      ```
    - 순위 미노출: 빨간 오류 → 주황 경고 (등록은 가능)
    - 16위 이상: 빨간 오류(등록 불가) → 주황 경고 (등록 가능하나 효과 제한적)
    - Railway 재배포 완료 (rank_module CORS 수정 포함)

- ✅ 완료: Phase 4-11 — GitHub 저장소 등록 + Path URL 라우팅 수정 + Nginx (2026-04-29)

  **GitHub 저장소 초기화 (store_traffic_booster/)**
  - 저장소: https://github.com/naturaltorymarket2/rankingup-web (브랜치: main)
  - store_traffic_booster/ 내부에 `git init` (기존 홈 디렉토리 git과 분리)
  - `android/key.properties` → `.gitignore` 추가 (서명 키 노출 방지)
  - 118개 파일 최초 커밋 후 force push (remote main 기존 커밋과 히스토리 불일치)

  **Path URL 라우팅 수정 (lib/main.dart)**
  - `usePathUrlStrategy()` + `import 'package:flutter_web_plugins/url_strategy.dart'` 추가
  - 원인: Hash URL (#/) 전략에서 브라우저가 `localhost/admin/charge`를 직접 입력하면 Flutter가 경로를 읽지 못하고 `/`로 처리 → 스플래시 → 대시보드로 리다이렉트
  - 수정: Path URL 전략으로 변경 → 브라우저 직접 접근 경로 정상 인식

  **Railway Nginx SPA 설정**
  - `web/nginx.conf` 신규 — `${PORT}` 변수로 Railway 포트 자동 적용, `/index.html` SPA fallback
  - `Dockerfile` 신규 — 멀티 스테이지: Flutter build (ARG RANK_API_URL) → nginx:alpine 서빙
  - nginx:alpine 1.19+의 `/etc/nginx/templates/*.template` 자동 envsubst 처리 활용

  **AAB 빌드 versionCode 4**
  - `android/app/build.gradle.kts` versionCode 3 → 4
  - 빌드: `flutter build appbundle --release --dart-define=RANK_API_URL=https://web-production-e7797.up.railway.app/rank`
  - 결과: app-release.aab (47MB)

- ✅ 완료: Phase 4-12 — 어드민 로그인 페이지 분리 (2026-04-29)

  **`/admin/login` 페이지 신규 생성**
  - `lib/features/auth/presentation/admin_login_screen.dart` — 어드민 전용 로그인 (회원가입 없음)
  - UI: 관리자 아이콘 + "관리자 로그인" 타이틀, 로그인 성공 시 `/admin/charge` 이동

  **`/web/login` 과 `/admin/login` 완전 분리**
  - `lib/app/router.dart` — redirect 가드 분리:
    - `/web/*` → 세션 없으면 `/web/login`
    - `/admin/*` → 세션 없으면 `/admin/login`
  - `web_login_screen.dart` — `fromAdmin` 파라미터 및 오렌지 배너 제거

  **role 기반 리다이렉트 로직 제거**
  - `admin_charge_screen.dart` — `currentUserRoleProvider` watch + role != 'ADMIN' 체크 제거
  - `admin_withdraw_screen.dart` — 동일 변경
  - 세션 만료 시 catch 블록 리다이렉트: `/web/login` → `/admin/login`
  - GitHub 반영 완료 (commit: 25c599f)

- ✅ 완료: Phase 4-13 — 출금 신청 RLS 버그 수정 (2026-04-29)

  **원인 분석**
  - `transactions_charge_insert` RLS 정책이 `type='CHARGE'`만 허용 → 클라이언트에서 `type='WITHDRAW'` INSERT 불가
  - `withdraw_provider.dart`의 `catch (_) { return false; }` 가 예외를 삼켜 "오류가 발생했습니다" 표시

  **수정 내용**
  - `supabase/migrations/20260317000015_submit_withdraw_rpc.sql` 신규
    - `submit_withdraw` RPC (SECURITY DEFINER): 최소금액/잔액/중복 체크 + 잔액 차감 + transactions INSERT
  - `supabase/migrations/20260317000016_fix_withdraw_rpcs.sql` 신규
    - `process_withdraw` 수정: 잔액 차감 제거 → status=COMPLETED만 처리
    - `reject_withdraw` 수정: 잔액 복구 추가 (거절 시 신청 금액 환불)
  - `wallet_repository.dart`: 직접 INSERT → `submit_withdraw` RPC 호출로 교체
  - `withdraw_provider.dart`: `Future<bool>` → `Future<void>`, PostgrestException 파싱 후 throw
  - `withdraw_screen.dart`: `try/catch` 패턴으로 교체, 에러 메시지를 빨간 SnackBar로 표시

⚠️ 배포 전 수동 처리 필요 (코드 외 작업):
- ⚠️ **start_mission RPC 일일 참여 제한 주석 해제 필수** — 테스트용으로 임시 비활성화 중
  (`supabase/migrations/20260317000001_rpc_start_mission.sql` step 3 주석 → 해제 후 Supabase에 재적용)
- 앱 아이콘 교체 (512×512px, 현재 임시 아이콘 사용 중)
- Play Console 등록 (앱 설명, 스크린샷, 개인정보처리방침 URL, 콘텐츠 등급)
- ✅ rank_module 서버 배포 완료: https://web-production-e7797.up.railway.app
- ✅ RANK_API_URL 설정 완료: https://web-production-e7797.up.railway.app/rank
- ✅ Flutter 웹 배포 완료: https://rankingup-web-production.up.railway.app
- ✅ AAB 빌드 완료 (47MB, versionCode 4) — `build/app/outputs/bundle/release/app-release.aab`

- ✅ 완료: Phase 5-1 — 랭킹 서버 /keywords 엔드포인트 추가 (2026-05-04)

  **rank_module/ 변경 사항**
  - `crawler.py` — `fetch_related_keywords(product_url, seed_keyword)` 구현
    - 기존: SmartStore 페이지 og:title 스크래핑 → Naver 429로 항상 실패
    - 수정: seed_keyword 기반으로 변경 (페이지 접근 없음)
    - `_fetch_product_name()` 함수 제거 (og:title 스크래핑 코드 완전 삭제)
    - `__main__` --keywords 플래그: `{url} {seed_keyword}` 두 인자로 변경
  - `main.py` — `GET /keywords?url=&keyword=` (keyword 파라미터 필수 추가)
  - Railway 배포 완료 (commit: 4ca5769)

- ✅ 완료: Phase 5-2 — 캠페인 등록 키워드 자동완성 기능 (2026-05-04)

  **Flutter 변경 사항**
  - `lib/shared/utils/rank_api_client.dart`
    - `fetchKeywords(productUrl, seedKeyword)` — seed_keyword 파라미터 추가
    - `_keywordsTimeout = Duration(seconds: 60)` 추가 (fetchRank의 10s와 별도)
  - `lib/features/campaign/presentation/keyword_select_modal.dart` (신규)
    - `showKeywordSelectModal(context, keywords, {preSelected})` — BottomSheet 모달
    - 최대 10개 ON 가능, 순위 뱃지 (초록 ≤15위, 주황 >15위, 회색 null)
    - `preSelected` 파라미터로 재오픈 시 이전 선택 상태 복원 (B-7 버그 수정)
  - `lib/features/campaign/presentation/campaign_new_screen.dart`
    - Step 1: 상품 URL + 대표 키워드(시드) 입력 필드 추가
    - `fetchKeywords(url, seed)` 호출 → 모달 → 선택 키워드 저장
    - `_step1Valid`: URL + 시드 키워드 + 선택 키워드 1개 이상 필요
    - 선택된 키워드 수만큼 `register_campaign` RPC 순차 호출 (다중 캠페인 등록)
    - Step 2: 키워드 × 기간 × 일일 목표 × 50P 예산 미리보기 카드
  - Flutter commit: f18fe1d

- ✅ 완료: Phase 5-QA — 키워드 자동완성 + 다중 캠페인 등록 QA (2026-05-05)
  - B-7 버그 수정: 모달 재오픈 시 이전 선택 상태 초기화 → `preSelected` 파라미터로 해결
  - A-1~E-2 전 항목 Pass (D-3: SnackBar 아닌 인라인 UI — 의도된 동작)

- ✅ 완료: Phase 5-디버깅 — /keywords 타임아웃 원인 파악 및 수정 (2026-05-05)
  - 증상: 타임아웃 에러 (Flutter 10초 제한 초과)
  - 원인: 슬라이딩 윈도우 20개 후보 × 0.5초 sleep + API 호출 = ~21초
  - 수정 A: `crawler.py` — `_MAX_KEYWORDS 20→10`, `sleep(0.5→0.3)` (Railway commit: a07df52)
  - 수정 B: `rank_api_client.dart` — `_keywordsTimeout = Duration(seconds: 60)` 추가 (Flutter commit: 3fd9238)
  - 결과: 21.2초 → 10.1초 (-52%)

- ✅ 완료: Phase 5-3 — 네이버 자동완성 API로 키워드 수집 방식 교체 (2026-05-05)
  - `crawler.py` — `fetch_autocomplete_keywords(seed_keyword)` 신규 추가
    - URL: `https://ac.search.naver.com/nx/ac`
    - 단어 수 2개 이하만 포함, seed_keyword 맨 앞 추가, 최대 10개 반환
  - `_generate_keyword_candidates()` (슬라이딩 윈도우) 완전 제거
  - `fetch_related_keywords()`: product_id 검증 → 자동완성 후보 → 각 키워드별 순위 조회
  - 결과: Railway 응답 10.1초 → **9.3초**, 키워드 품질 대폭 개선 (실검색어 기반)
  - Railway commit: e9b05a4

- ✅ 완료: Phase 6-1 — AAB 빌드 versionCode 5 (2026-05-05)
  - `android/app/build.gradle.kts`: versionCode 4 → 5
  - Phase 5 기능(키워드 자동완성 + 다중 캠페인 등록) 반영한 배포용 빌드
  - 빌드 명령: `flutter build appbundle --release --dart-define=RANK_API_URL=https://web-production-e7797.up.railway.app/rank`
  - 결과: `build/app/outputs/bundle/release/app-release.aab` (47MB)
  - Flutter commit: d4a795e

- ✅ 완료: Phase 6-2 — 순위 조회 매칭 로직 고도화 (2026-05-07)

  **rank_module/crawler.py 변경 사항** (rank_module commit: 4ca72cf)
  - `_normalize_url(url)` 추가: 소문자 변환, 쿼리·프래그먼트 제거, trailing slash 제거
  - `_extract_numeric_id(url)` 추가: URL 경로의 마지막 숫자 세그먼트 추출
  - `from urllib.parse import urlparse` import 추가 (표준 라이브러리)
  - `fetch_naver_rank()` 매칭 순서 변경:
    - 기존: productId 직접 비교 → `product_id in link` (포함 여부 — 오탐 가능성)
    - 변경: 정규화 URL 완전 일치 → productId 비교 (더 정확)
  - `_call()` `sort='sim'` 파라미터 추가 (유사도순 명시)
  - `_extract_product_id()`는 `fetch_related_keywords` SmartStore URL 검증용으로 유지
  - Railway 자동 배포 완료

- ✅ 완료: Phase 6-3 — 순위 추이 데이터 미업데이트 문제 해결 (2026-05-07)

  **원인**: Railway 무료 플랜에서 비활성 시 컨테이너 슬립 → APScheduler 미실행

  **해결: GitHub Actions 외부 크론으로 대체** (rank_module commit: 1f15caa)
  - `main.py` — `POST /run-scheduler` 엔드포인트 추가
    - `X-Scheduler-Secret` 헤더로 토큰 검증
    - `update_all_campaign_ranks()` BackgroundTasks로 실행 → 즉시 `{"status":"started"}` 반환
  - `.github/workflows/daily_rank_update.yml` 신규 생성
    - 매일 UTC 18:00 (KST 03:00) 자동 실행 (`cron: '0 18 * * *'`)
    - `workflow_dispatch`로 GitHub Actions UI 수동 실행 가능
    - `curl --fail --retry 3`으로 실패 시 재시도
  - **GitHub Secret 등록**: `SCHEDULER_SECRET`
  - **Railway Variables 등록**: `SCHEDULER_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`
  - `campaign_rank_history` 데이터 정상 적재 확인 (2026-05-07)

- ✅ 완료: Phase 6-4 — 순위 매칭 로직 재수정 (2026-05-11)

  **배경**: Phase 6-2에서 추가한 `_normalize_url` 완전일치 로직 제거 요청
  → productId 단일 비교로 변경 → link URL fallback 누락 버그 발견 → 즉시 복원

  **rank_module/crawler.py 최종 변경 사항**
  - `_normalize_url(url)` 함수 삭제 (fetch_naver_rank 외 사용처 없음)
  - `fetch_naver_rank()` 매칭 순서 최종 확정:
    - 1순위: `target_id == str(item.get('productId', ''))` — productId 직접 비교
    - 2순위: `target_id == _extract_numeric_id(item.get('link', ''))` — 링크 URL fallback
  - `_extract_numeric_id()` 유지 (fetch_naver_rank에서 계속 사용)
  - `_extract_product_id()` 유지 (fetch_related_keywords SmartStore URL 검증용)
  - rank_module commit: d3a4911 (URL 정규화 제거), 4135619 (link fallback 복원)
  - Railway 자동 배포 완료

- ✅ 완료: Phase 6-5 — 캠페인 등록 키워드 직접 추가 기능 (2026-05-11)

  **Flutter 변경 사항** (Flutter commit: 53a48f2)
  - `lib/features/campaign/presentation/keyword_select_modal.dart`
    - `showKeywordSelectModal()`: `productUrl` named 파라미터 추가 (기본값 `''`)
    - 직접 추가 섹션 신규:
      - `_customKeywords`: 직접 추가 키워드 목록 (`List<KeywordRankResult>`)
      - `_customToggles`: 직접 추가 키워드 ON/OFF (`List<bool>`)
      - `_customController`: 텍스트 입력 컨트롤러
      - `_isAddingKeyword`: 순위 조회 중 로딩 상태 bool
    - `_addCustomKeyword()` 동작:
      - 중복 키워드 → 토스트 "이미 추가된 키워드입니다"
      - 직접 추가 10개 초과 → 토스트 "직접 추가는 최대 10개까지 가능합니다"
      - `productUrl` 있으면 `RankApiClient.fetchRank()` 호출 → 성공 시 실제 순위, 실패 시 null (회색 뱃지)
      - 추가 즉시 ON 상태, 입력창 초기화
    - `_removeCustomKeyword(index)`: [X] 버튼으로 직접 추가 키워드 삭제
    - `_selectedCount`: 추천 + 직접 추가 ON 수 합산
    - 최종 반환: 추천 선택 목록 + 직접 추가 선택 목록 합산
    - `_RecommendedKeywordTile` / `_CustomKeywordTile` 별도 위젯으로 분리
  - `lib/features/campaign/presentation/campaign_new_screen.dart`
    - `showKeywordSelectModal()` 호출 시 `productUrl: _urlCtrl.text.trim()` 파라미터 추가

- ✅ 완료: Phase 7-1 — 긴급 버그 3개 수정 (2026-05-13)
  - 순위 대시보드 동일 날짜 중복 노출: Dart에서 KST 날짜 기준 중복 제거
  - 태그 입력 오류: userId null 체크 추가 + verify_mission NULL 태그 보안 버그 수정 (migration 0017)
  - 출금 신청 오류: userId null 체크 + Exception 메시지 유실 방지

- ✅ 완료: Phase 7-2 — 순위 추적 시드 키워드 1개로 변경 (2026-05-13)
  - campaigns 테이블 seed_keyword 컬럼 추가 (migration 0018)
  - register_campaign RPC p_seed_keyword 파라미터 추가 (DEFAULT NULL, 하위 호환)
  - scheduler.py: (product_url, seed_keyword) 기준 그룹화 → API 1회 호출/그룹

- ✅ 완료: Phase 7-3 — 태그 수동 입력 + 정답 태그 선택 기능 (2026-05-13)
  - campaign_tags 테이블 is_answer BOOLEAN + sort_order INTEGER 컬럼 추가 (migration 0019)
  - register_campaign RPC: p_answer_index 파라미터 추가, 태그 최소 2개 검증, p_start_date/p_end_date 시그니처 수정
  - start_mission RPC: ORDER BY RANDOM() → WHERE is_answer=true 방식으로 변경, 응답에 tag_index 포함
  - 광고주 웹: 태그 수동 입력([추가] 버튼) + 라디오 버튼 정답 선택 UI
  - 앱: "상품 페이지에서 N번째 태그를 입력하세요" 강조 안내 문구 추가
  - 랭킹 서버: GET /tags 엔드포인트 + fetch_product_tags 함수 + beautifulsoup4 제거 (봇 차단 확인)
  ⚠️ Supabase migration 0018, 0019 수동 적용 필요

- ✅ 완료: Phase 7-4 — UX 개선: 태그 입력 화면 안내 문구 + 뒤로가기 버튼 (2026-05-14)
  - `lib/features/mission/presentation/mission_active_screen.dart`
    - 태그 입력 섹션에 amber 설명 박스 추가: "태그는 상품명 아래 #으로 시작하는 키워드입니다"
    - hintText `'태그 입력'` → `'예) #헬스장갑'` 변경
    - `_goBackToWaiting()` 메서드 추가: 타이머/잠금 리셋 + `_isResumed = false` 전환 (미션 취소 아님)
    - `PopScope(canPop: false)` 전체 빌드 래핑
    - `canGoBack` 조건(`_isResumed && !_isTimedOut && !_isSuccess`)에서 AppBar leading 뒤로가기 버튼 표시

- ✅ 완료: Phase 7-5 — 보안: campaigns RLS SELECT 정책 강화 (2026-05-14)
  - `supabase/migrations/20260317000021_fix_campaigns_rls.sql` 신규
  - 기존 단일 정책(`campaigns_read`) 제거
  - Permissive 2개:
    - `campaigns_owner_select`: 소유자(광고주) — 본인 캠페인 전체
    - `campaigns_active_select`: 앱 유저(B2C) — ACTIVE 캠페인만
  - Restrictive 1개:
    - `campaigns_advertiser_restrict`: `business_info` 등록 광고주는 본인 캠페인만 허용
      → 타인의 ACTIVE 캠페인 UUID 직접 접근 차단
  ⚠️ Supabase migration 0021 수동 적용 필요

- ✅ 완료: Phase 7-6 — AAB 빌드 versionCode 6 (2026-05-14)
  - `android/app/build.gradle.kts`: versionCode 5 → 6
  - Phase 7 전체 반영 (UX 개선 + 보안 + 공지사항 + seed_keyword 전달)
  - 빌드 결과: `build/app/outputs/bundle/release/app-release.aab` (49.9MB)
  - Flutter commit: d8b8a0a

- ✅ 완료: Phase 7-7 — QA 전수 점검 및 버그 수정 (2026-05-14)

  **어뷰징 방지 / DB 회귀 수정**
  - migration 0022: `start_mission` 일일 참여 제한 주석 해제 활성화 (어뷰징 방지 핵심)
  - migration 0023: `register_campaign` 시그니처 회귀 버그 수정 (0018이 `p_duration_days`로 되돌린 문제)
    - 올바른 시그니처 강제 적용: `p_start_date, p_end_date, p_answer_index, p_seed_keyword`
    - 필수 컬럼 `IF NOT EXISTS` 포함 (migration 0018/0019 미적용 환경 대비)

  **Flutter 수정**
  - `campaign_repository.dart`: `fetchCampaignStats()` `started_at` → `completed_at` 기준 통일 (KST 자정 필터)
  - `campaign_new_screen.dart`: `currentUser!.id` 강제 언래핑 → null-safe 패턴 (`?.id` + 조기 return + SnackBar)
  - `migration 0015`: NOTE 주석 오류 수정 (reject_withdraw 잔액 복구 로직 migration 0016에서 추가됨 명시)

  **QA 검증 (코드 변경 없음)**
  - `rank_api_client.dart` GET /rank, /keywords 응답 파싱 — Python 서버 필드명 완전 일치 확인
  - `scheduler.py` seed_keyword 그룹화 — SELECT/fallback/key 정상 동작 확인
  - `_goBackToWaiting()` `_remainingSeconds = 600` 하드코딩 — `_isResumed = false` 동시 설정으로 안전 확인

  **배포 환경 수정**
  - `Dockerfile`: `ARG RANK_API_URL` 주입 방식 → URL 직접 하드코딩 (Railway 빌드 변수 미전달 문제 해결)
  - `dashboard_repository.dart`: `fetchRankHistory()` 날짜 중복 제거 재수정
    - `limit(30)` → `limit(100)` (하루 여러 번 실행 대비)
    - `seen Set` + 조기 break → `Map<String, RankHistory>` + `putIfAbsent` 패턴으로 재구현
  ⚠️ Supabase migration 0022, 0023 수동 적용 필요

- ✅ 완료: Phase 7-8 — 대시보드 및 캠페인 등록 운영 개선 (2026-05-14)
  - `supabase/migrations/20260317000024_fix_dashboard_campaign_limit.sql` 신규
    - `get_dashboard_data` RPC 캠페인 목록 서브쿼리 `LIMIT 5` 제거 → 전체 반환
    - 원인: migration 0008에 하드코딩된 `LIMIT 5` (캠페인 6개 이상 시 목록 잘림)
  - `supabase/migrations/20260317000025_fix_tag_min_count.sql` 신규
    - `register_campaign` RPC 태그 검증: `array_length(p_tags, 1) < 2` → `< 1` (최소 1개로 완화)
  - `campaign_new_screen.dart`: `_tags.length >= 1`, 안내 문구 "최소 1개, 최대 10개"로 변경
  ⚠️ Supabase migration 0024, 0025 수동 적용 필요

- ✅ 완료: Phase 8-1 — 미션 딥링크 + 캠페인 태그 에러 버그 수정 (2026-05-16)

  **딥링크 버그 수정 (`lib/features/mission/presentation/mission_detail_screen.dart`)**
  - 케이스 A: `supabase.auth.currentUser?.id ?? ''` 빈 문자열 → `?.id` null 체크 + 조기 return + SnackBar
    - 빈 문자열을 UUID 타입으로 RPC 전달 시 PostgreSQL UUID parse 오류 발생
  - 케이스 C: `catch (_)` 무음 처리 → `catch (e)` + `e.toString()` SnackBar 표시
    - 실제 오류 내용이 완전히 숨겨져 디버깅 불가한 상태였음
  - 케이스 D: `launchUrl()` 직접 호출 → `canLaunchUrl()` 사전 체크 추가
    - false 반환 시 "네이버 앱을 실행할 수 없습니다" SnackBar + 조기 return
    - false 반환 시 `/mission/:id/active` 라우팅이 아예 실행되지 않았음

  **`android/app/src/main/AndroidManifest.xml`**
  - `<queries>` 블록에 `<package android:name="com.naver.search" />` 추가
  - Android 11+ 패키지 가시성 정책: scheme intent(`naversearchapp://`) 만으로는 `canLaunchUrl()` 신뢰 불가
  - 패키지 직접 선언으로 보완

  **캠페인 태그 에러 조건 재수정 (`lib/features/campaign/presentation/campaign_new_screen.dart`)**
  - 에러 표시 조건: `if (_tags.length < 2)` → `if (_tags.isEmpty)`
  - `_step2Valid`는 `_tags.length >= 1`로 이미 수정됐으나 에러 문구 표시 분기만 누락
  - 태그 1개 입력 시에도 "태그를 1개 이상 입력해주세요." 에러가 표시되는 버그

  **versionCode 7** → AAB 빌드 완료 (48MB)

- ✅ 완료: Phase 8-2 — 출금 오류 메시지 개선 (2026-05-16)
  - `lib/features/wallet/presentation/withdraw_provider.dart` catch 블록 개선
  - 기존: `catch(e)` 에서 `throw Exception('오류가 발생했습니다. 다시 시도해 주세요.')` 고정 문구
  - 변경:
    - `on PostgrestException catch (e)`: `e.message` 그대로 전파 (RPC RAISE EXCEPTION 메시지 보존)
    - `catch (e)`: `e is Exception`이면 rethrow, 아니면 `runtimeType + toString()` 포함 메시지로 래핑
  - 배경: Dart `Error` 계열(AssertionError, TypeError 등)은 `on Exception`에 걸리지 않음
    - 기존 코드에서 `Error` 계열 예외가 `catch(e)`에 도달하면 고정 문구로 숨겨짐
  - 개선 후 실기기에서 `e.runtimeType` 확인으로 실제 오류 원인 추적 가능
  - **versionCode 8** → AAB 빌드 완료 (49.9MB)

- ✅ 완료: Phase 8-3 — 태그 안내 이미지 삽입 (2026-05-16)
  - `assets/images/mission_guide.png` 신규 추가 (438KB)
  - `pubspec.yaml`: `flutter.assets` 섹션 신규 추가
  - `lib/features/mission/presentation/mission_active_screen.dart`
    - `_TagInputSection` amber 안내 박스("태그는 상품명 아래 #으로 시작하는 키워드입니다") 바로 아래
    - `Image.asset('assets/images/mission_guide.png', width: double.infinity, fit: BoxFit.contain)` 삽입
    - 이미지 위아래 `SizedBox(height: 8)` 여백

- ✅ 완료: Phase 8-4 — 태그 순서 입력 프로세스 개선 (2026-05-16)

  **배경**: 광고주가 태그 이름만 입력하고 몇 번째인지 입력 UI 없음
  → `sort_order` = 루프 카운터(추가 순서, 의미 없는 값)
  → 앱 유저에게 "N번째 태그를 입력하세요" 안내가 실제 위치와 불일치

  **변경 파일:**
  - `lib/features/campaign/presentation/campaign_new_screen.dart`
    - `_tags`: `List<String>` → `List<Map<String, dynamic>>` (`{'name': String, 'order': int}`)
    - 태그 추가 UI: `[태그 이름]` + `[순서(몇 번째)]` + `[추가]` 3개 필드로 변경
    - 태그 목록: `"3번째 | #헬스장갑"` 형식 표시
    - 이름 중복 + 순서 중복 방지 검증 추가
    - `answerIndex`: 목록 인덱스(1-based) → 선택 태그의 실제 순서값
  - `lib/features/campaign/data/campaign_repository.dart`
    - `sortOrders: List<int>` 파라미터 추가, RPC에 `p_sort_orders` 전달
  - `supabase/migrations/20260317000026_fix_sort_order_input.sql` (신규)
    - `register_campaign` RPC: `p_sort_orders INTEGER[]` 파라미터 추가
    - `sort_order = p_sort_orders[i]` (광고주 직접 입력값)
    - `is_answer = (p_sort_orders[i] = p_answer_index)` 조건으로 변경
  ✅ Supabase migration 0026 적용 완료 (2026-05-16)

  **versionCode 9** → AAB 빌드 완료 (50.4MB)

- ✅ 완료: Phase 8-5 — 미션 설명 페이지 태그 안내 이미지 추가 (2026-05-17)
  - `lib/features/mission/presentation/mission_detail_screen.dart`
    - `_InstructionSection` 4단계 안내 텍스트 아래 `Image.asset` 삽입
    - `ClipRRect(borderRadius: BorderRadius.circular(10))` 적용
  - 배경: Phase 8-3에서 미션 진행 화면(active)에 이미지 추가 완료,
    이번에 미션 시작 전 설명 화면(detail)에도 동일 이미지 추가
  - **versionCode 10** → AAB 빌드 완료 (50.4MB)

- ✅ 완료: Phase 8-6 — 출금 RPC Supabase 적용 (2026-05-18)
  - submit_withdraw RPC (migration 0015), process_withdraw/reject_withdraw 수정 (migration 0016) Supabase SQL Editor 직접 적용
  - 원인: RPC 코드는 migration 파일로 존재했으나 Supabase에 미적용 상태 → 출금 신청 시 오류 발생
  - migration 0019 (campaign_tags is_answer+sort_order 컬럼) 적용 완료
  - migration 0022 (start_mission 일일 참여 제한 활성화) 적용 완료

- ✅ 완료: Phase 8-7 — Railway 광고주 웹 배포 복구 (2026-05-18)
  - 원인: `Dockerfile` 21번째 줄 `COPY --from=build /app/build/web/nginx.conf`
    → Flutter `build web` 출력물에 nginx.conf 미포함 → 복사 실패 → nginx 시작 불가
  - 수정: `COPY --from=build /app/web/nginx.conf` (소스 파일 위치로 변경)
  - commit 6812132 push → Railway 자동 재배포 성공

- ✅ 완료: Phase 8-8 — 미션 진행 화면 상품 URL 표시 (2026-05-18)
  - `lib/features/mission/domain/mission_model.dart` — `CampaignMissionModel.productUrl: String?` 필드 추가
  - `lib/features/mission/data/mission_repository.dart` — `fetchCampaignDetail()` SELECT에 `product_url` 추가
  - `lib/features/mission/presentation/mission_detail_screen.dart` — extra 맵에 `'product_url': campaign.productUrl` 추가
  - `lib/app/router.dart` — `MissionActiveScreen(productUrl: extra?['product_url'] as String?)` 전달
  - `lib/features/mission/presentation/mission_active_screen.dart`
    - `MissionActiveScreen` / `_ActiveBody` / `_TagInputSection`: `productUrl` 파라미터 추가
    - `_TagInputSection`: 상품 URL 텍스트(말줄임표) + 복사 버튼 컨테이너 삽입
  - 배경: 네이버 딥링크 미작동 시 유저가 직접 상품 페이지에 접근할 수 있도록 URL 제공
  - **versionCode 11** → AAB 빌드 완료 (50.4MB)

- ✅ 완료: Phase 9 — QA 피드백 반영 + 코드 품질 개선 (2026-05-22)
  - brand.naver.com 브랜드스토어 URL 파싱 지원 (`_BRAND_PATTERN` 추가, `_extract_product_id` 분기)
  - 일일 유입 수량 입력 개선 — 최대 3,000명, 100단위 자유 입력
  - 순위 추적 키워드 / 미션 키워드 섹션 분리 UI
  - 태그 입력 Step 2 amber 안내 카드 추가 (①②③ 입력 방법 + 예시)
  - Code Review 수정: Critical(`_answerIndex` 경계 가드) / Major(`threading.Lock`, unused var) / Minor(`Colors.amber.shadeN`)
  - Playwright MCP QA 전 항목 PASS (TC-01~TC-04)
  - **versionCode 12** → AAB 빌드 완료 (50.4MB)

- ✅ 완료(Flutter): Phase 10 — 그룹 과금 구조 변경 (2026-05-25)

  **배경**: 다중 서브키워드 등록 시 키워드 수 × 과금 → 1회 과금으로 변경
  - `group_id` (UUID) 를 클라이언트에서 생성, 동일 그룹 서브키워드 묶음
  - `group_daily_target` = 광고주 입력 일일 목표 (그룹 전체 기준 과금)
  - 서브키워드별 `daily_target` = `group_daily_target ~/ 키워드수` (첫 번째에 나머지 합산)
  - 예산 계산: `dailyTarget × duration × 50P` (키워드수 무관)

  **변경된 파일 (9개):**
  - `lib/features/dashboard/domain/dashboard_model.dart`
    - DashboardCampaign: `groupId, seedKeyword, groupDailyTarget, subKeywords(List<String>), representativeCampaignId` 추가
    - `displayStatus` getter: ACTIVE이고 순위 없음/낮음 → RANK_OUT
  - `lib/features/dashboard/data/dashboard_repository.dart`
    - `get_dashboard_data` RPC 신규 반환 필드(`sub_keywords`, `representative_campaign_id` 등) 파싱
  - `lib/features/dashboard/presentation/web_dashboard_screen.dart`
    - 캠페인 행: `seedKeyword` 메인 표시, `subKeywords` 서브텍스트(`A · B · C` 형식)
    - 오늘/누적 유입, 일일 목표: 그룹 합산값 표시
    - 캠페인 탭 라우팅: `/web/campaign/$representativeCampaignId`
  - `lib/features/campaign/data/campaign_repository.dart`
    - `registerCampaign()`: `groupId, groupDailyTarget, seedKeyword` 파라미터 추가 → RPC `p_group_id, p_group_daily_target` 전달
    - `fetchCampaignDetail()`: `group_id` 기준 서브키워드 목록 추가 조회
    - `fetchCampaignStats()`: `group_id` 기준 그룹 전체 `mission_logs` 합산 (오늘/누적)
  - `lib/features/campaign/domain/campaign_model.dart`
    - `groupId, groupDailyTarget, seedKeyword, subKeywords` 필드 추가
    - `displayDailyTarget` getter: `groupDailyTarget > 0 ? groupDailyTarget : dailyTarget`
    - `displayKeyword` getter: `seedKeyword`가 있으면 해당값, 없으면 `keyword`
  - `lib/features/campaign/presentation/campaign_new_screen.dart`
    - `uuid: ^4.5.1` 패키지 사용 → `const Uuid().v4()`로 `groupId` 생성
    - 예산: `_dailyTarget × _durationDays × 50` (키워드수 제거)
    - Step 2 안내: "N개 서브키워드 균등 분배 (각 X명)" 추가
    - 등록 버튼: "광고 등록 (포인트 1회 차감)"
    - `_submit()`: 동일 `groupId`로 서브키워드별 `registerCampaign()` 순차 호출
  - `lib/features/campaign/presentation/campaign_detail_screen.dart`
    - AppBar·키워드 행: `displayKeyword` 표시
    - 서브키워드 목록: 메인 키워드 아래 작은 텍스트로 `A · B · C` 형식 표시
    - 일일 목표 / 달성률 프로그레스바: `displayDailyTarget` 기준
  - `lib/features/mission/data/mission_repository.dart`
    - `fetchActiveMissions()`: 오늘 `SUCCESS` 로그에서 `group_id` 수집 → 그룹 단위 참여 제외
    - `group_id`별 DISTINCT: `seenGroupKeys` Set으로 클라이언트에서 처리 (Supabase 클라이언트 DISTINCT ON 미지원)
  - `pubspec.yaml`: `uuid: ^4.5.1` 추가

  **제약 사항 (변경 없음):**
  - `mission_detail_screen.dart`: `start_mission` 파라미터 변경 없음 (campaign_id 기준 유지)
  - `mission_active_screen.dart`: 변경 없음
  - `router.dart`: 경로 변경 없음 (/web/campaign/:id 유지)

  **버그 수정 (migration 0031, 2026-05-25):**
  - `campaigns.budget CHECK (budget > 0)` → `CHECK (budget >= 0)` 완화
  - 원인: 두 번째 이후 서브키워드 등록 시 `budget=0` INSERT → PostgreSQL 제약 위반 → 400 에러
  - 파일: `supabase/migrations/20260317000031_fix_budget_check_constraint.sql`
  - ✅ 적용 완료 (2026-05-25)

  **Playwright QA 결과 (2026-05-25):**
  - TC-01 UI: ✅ PASS — 예산 계산식·버튼 텍스트·서브키워드 분배 안내 확인
  - TC-01 실제 등록: ✅ PASS — 5,000,000P 충전 후 2개 서브키워드 등록 성공 (migration 0031 적용 후)
  - TC-02 대시보드: ✅ PASS — 1행 그룹 표시, seedKeyword 메인, subKeywords 서브, 일일 목표 100, 상세 화면 정상 진입
  - TC-03: ✅ PASS (코드 로직) — 미션 카드 탭 네비게이션 정상, DISTINCT 실데이터 검증 앱 실기기 필요
  - TC-04: ✅ PASS (RPC 동작) — `startMission` 정상 호출, SUCCESS 기반 그룹 차단 실검증 앱 실기기 필요
  - 발견: Flutter Web 탭 이벤트는 `PointerEvent(pointerType:'touch', pointerId:1)` 필수 (MouseEvent 불가)

  ✅ **Supabase 마이그레이션 0027~0031 전체 적용 완료 (2026-05-25)**

- ✅ 완료: Phase 10 배포 후 버그 수정 (2026-05-27~28)

  **프로덕션 대시보드 크래시 수정 (2026-05-27)**
  - 증상: `TypeError: null: type 'minified:z6' is not a subtype of type 'String'` — `/web/dashboard` 접속 시 화면 크래시
  - 원인: `DashboardCampaign.fromMap`에서 `map['group_id'] as String`, `map['status'] as String`, `map['representative_campaign_id'] as String` — non-nullable 캐스트
    마이그레이션 0027/0030 이전 생성된 캠페인이 신규 RPC 필드에 null 반환 시 crash
  - 수정: `lib/features/dashboard/domain/dashboard_model.dart`
    ```dart
    groupId:                  map['group_id']                   as String? ?? '',
    status:                   map['status']                     as String? ?? 'ENDED',
    representativeCampaignId: map['representative_campaign_id'] as String? ?? '',
    ```
  - commit: b6c214e (2026-05-27)

  **순위 추이 차트 Y축 개선 (2026-05-27)**
  - 변경: `lib/features/campaign/presentation/campaign_detail_screen.dart` — `_buildLineChartData()`
    - Y축 방향 변경: 음수 트릭 제거 → rank 값 그대로 플롯 (1=하단, 15=상단, 위로 갈수록 숫자 커짐)
    - Y축 고정: `minY=1 / maxY=15` (데이터 범위 무관)
    - rank > 15 데이터 포인트 필터링 (그래프 미표시 — 이탈 처리)
    - 좌축 레이블: 1위·5위·10위·15위만 표시
    - 그리드: 같은 위치(1·5·10·15)에만 수평선 표시
  - commit: 42ea637 (2026-05-27)

  **Android 광고 ID 권한 선언 추가 (2026-05-28)**
  - 증상: Play Console 업로드 시 "광고 ID 선언이 불완전함" 오류 — 비공개 테스트 제출 차단
  - 원인: `google_mobile_ads` 사용 + `targetSdk=35` (Android 13+) → `AD_ID` 권한 명시 필수
  - 수정: `android/app/src/main/AndroidManifest.xml`
    ```xml
    <uses-permission android:name="com.google.android.gms.permission.AD_ID"/>
    ```
  - commit: 67fc4c6 (2026-05-28)
  - ⚠️ Play Console 데이터 보안 섹션에서 광고 ID 수집 여부 선언 필요 (콘솔 수동 작업)

  **versionCode 14 AAB 빌드 (2026-05-28)**
  - `android/app/build.gradle.kts`: versionCode 13 → 14
  - 포함 내용: 프로덕션 대시보드 크래시 수정 + 차트 개선 + AD_ID 권한
  - 빌드 결과: `build/app/outputs/bundle/release/app-release.aab` (50.4MB)
  - commit: c960ac0 (2026-05-28)

---

## 11. 작업 요청 방식 (Claude Code에게)

작업 요청 시 아래 형식을 사용한다:

```
[Phase N - 작업번호] 작업명
예: [Phase 1 - 1-2] Flutter 프로젝트 초기화 및 패키지 설치
```

작업 완료 후 반드시:
1. 변경된 파일 목록 출력
2. 다음 작업 번호 안내
3. 테스트 필요 항목 안내

---

## 12. Play Store 배포 체크리스트 (Phase 4-4)

### 배포 전 필수 완료 항목

#### 🔑 앱 서명 키
- [x] `keytool`로 키스토어 생성 완료 (`/Users/daeun/upload-keystore.jks`)
- [x] `android/key.properties` 실제 값 입력 완료 (keyAlias=upload)
- [ ] 키스토어 파일(.jks)을 git 외부에 안전하게 백업 (분실 시 업데이트 불가)

#### 📦 빌드 설정 확인
- [x] `applicationId = "com.storetrafficbooster.app"` 설정 완료
- [x] `versionCode = 14` / `versionName = "1.0.0"` 설정 완료 (내부 테스트 배포: 2, 현재 빌드: 14)
- [ ] 업데이트 배포 시마다 versionCode 증가 필수
- [x] AdMob 앱 ID 실제 값으로 교체 완료 (ca-app-pub-6225110164827541~2986900842)
- [x] 배너/전면 광고 단위 ID 실제 값으로 교체 완료

#### 🏪 Play Console 등록 항목
- [x] 앱 이름: "겟머니" (확정)
- [ ] 앱 아이콘: 512×512px PNG (현재 기본 Flutter 아이콘 — 교체 필요)
- [ ] 스크린샷: 최소 2장 (폰), 태블릿 선택
- [ ] 짧은 설명 (80자 이내) / 전체 설명
- [ ] 개인정보처리방침 URL (필수)
- [ ] 콘텐츠 등급 설문 완료
- [ ] 타겟 국가 설정

#### 🔒 개인정보 / 정책
- [ ] 개인정보처리방침 페이지 준비 (수집 항목: 이메일, Device ID, 포인트 내역)
- [ ] AdMob 사용 시 "광고 ID" 항목 데이터 안전 섹션에 신고
- [ ] 금융 데이터(포인트 잔액/출금) 데이터 안전 섹션에 신고

### AAB 빌드 명령어

```bash
# 릴리즈 AAB 빌드
flutter build appbundle --release \
  --dart-define=RANK_API_URL=https://web-production-e7797.up.railway.app/rank

# 빌드 산출물 경로
# build/app/outputs/bundle/release/app-release.aab
# ※ 빌드 전 versionCode 증가 필수 (android/app/build.gradle.kts)
```

### 앱 아이콘 교체 방법

```bash
# flutter_launcher_icons 패키지 사용 권장
flutter pub add --dev flutter_launcher_icons
# pubspec.yaml에 flutter_icons 설정 후:
flutter pub run flutter_launcher_icons
```

---

## 13. 배포 현황 (2026-05-25 기준)

### 서비스 URL

| 서비스 | URL | 상태 |
|--------|-----|------|
| 랭킹 모듈 API (Railway) | https://web-production-e7797.up.railway.app | ✅ 운영 중 |
| Flutter 웹 (Railway) | https://rankingup-web-production.up.railway.app | ✅ 운영 중 |
| 개인정보처리방침 | https://naturaltorymarket2.github.io/rankingup-privacy/ | ✅ 운영 중 |

### Android 앱 상태

| 항목 | 값 |
|------|-----|
| 플랫폼 | Google Play Console 내부 테스트 트랙 |
| applicationId | com.storetrafficbooster.app |
| 배포된 versionCode | 14 (2026-05-28 업로드 완료) |
| 빌드 결과물 | build/app/outputs/bundle/release/app-release.aab (50.4MB) |

### GitHub 저장소

| 항목 | 값 |
|------|-----|
| Flutter 프로젝트 | https://github.com/naturaltorymarket2/rankingup-web |
| 랭킹 모듈 | https://github.com/naturaltorymarket2/rankingup |
| 브랜치 | main |
| 마지막 push | 2026-05-28 (fix: AD_ID permission + versionCode 14) |

### GitHub Actions

| 워크플로우 | 실행 시각 | 동작 |
|-----------|----------|------|
| `daily_rank_update.yml` | 매일 UTC 18:00 (KST 03:00) | `POST /run-scheduler` 호출 → `campaign_rank_history` 갱신 |

### 환경변수 설정

```bash
# Flutter 빌드/실행 시 필요한 --dart-define 변수
RANK_API_URL=https://web-production-e7797.up.railway.app/rank

# SUPABASE_URL / SUPABASE_ANON_KEY는 supabase_client.dart defaultValue에 하드코딩됨
# (별도 --dart-define 없이 flutter run 가능)
```

### 테스트 계정

| 계정 | 이메일 | 비밀번호 | role |
|------|--------|----------|------|
| 어드민 | naturaltorymarket2@gmail.com | 123456 | ADMIN |
| 어드민2 | test-admin@test.com | (설정한 비밀번호) | ADMIN |

> ※ Supabase 대시보드에서 계정 생성 시 `handle_new_user` 트리거 실패 가능
> → SQL Editor에서 `public.users` + `public.wallets` 수동 INSERT 필요

### 로컬 개발 실행 명령어

```bash
# 앱 실행 (Android 에뮬레이터)
cd store_traffic_booster
flutter run --dart-define=RANK_API_URL=https://web-production-e7797.up.railway.app/rank

# 웹 실행 (광고주/어드민) — Railway rank 서버 사용
flutter run -d chrome --web-port=8080 \
  --dart-define=RANK_API_URL=https://web-production-e7797.up.railway.app/rank

# 웹 실행 — 로컬 rank 서버 사용 (CORS 이슈 없음, Playwright QA 권장)
# 1) rank_module 로컬 실행 후:
# cd rank_module && uvicorn main:app --host 0.0.0.0 --port 8000
flutter run -d chrome --web-port=8080 \
  --dart-define=RANK_API_URL=http://localhost:8000/rank

# 랭킹 모듈 로컬 실행
cd rank_module
uvicorn main:app --host 0.0.0.0 --port 8000

# 스케줄러 수동 1회 실행 (로컬)
cd rank_module
python3 scheduler.py

# 스케줄러 엔드포인트 테스트
curl -X POST http://localhost:8000/run-scheduler \
  -H "X-Scheduler-Secret: {SCHEDULER_SECRET 값}"
```

---

### Supabase 수동 적용 필요 Migration

> Supabase SQL Editor에서 아래 순서대로 실행.
> `CREATE OR REPLACE` / `ADD COLUMN IF NOT EXISTS` 이므로 중복 실행 안전.

| 순서 | 파일명 | 핵심 내용 | 상태 |
|------|--------|-----------|------|
| 1 | `20260317000017_fix_verify_mission_null_tag.sql` | verify_mission NULL 태그 보안 버그 수정 (어떤 태그든 통과되는 취약점 차단) | ⚠️ 미적용 확인 필요 |
| 2 | `20260317000018_add_seed_keyword.sql` | campaigns.seed_keyword 컬럼 추가 + register_campaign p_seed_keyword 파라미터 | ⚠️ 미적용 확인 필요 |
| 3 | `20260317000019_update_campaign_tags.sql` | campaign_tags.is_answer + sort_order 컬럼 추가, register_campaign p_answer_index 추가, start_mission tag_index 응답 | ✅ 적용 완료 (2026-05-18) |
| 4 | `20260317000020_create_notices.sql` | notices 테이블 + RLS + get_notices / create_notice RPC | ⚠️ 미적용 확인 필요 |
| 5 | `20260317000021_fix_campaigns_rls.sql` | campaigns RLS 강화 (타 광고주 ACTIVE 캠페인 접근 차단) | ⚠️ 미적용 확인 필요 |
| 6 | `20260317000022_enable_daily_mission_limit.sql` | **start_mission 일일 참여 제한 활성화** (어뷰징 방지 핵심) | ✅ 적용 완료 (2026-05-18) |
| 7 | `20260317000023_fix_register_campaign_signature.sql` | register_campaign 시그니처 확정 (0018 회귀 버그 방지, Flutter 완전 일치) | ❌ 신규 — 즉시 적용 필요 |
| 8 | `20260317000024_fix_dashboard_campaign_limit.sql` | get_dashboard_data RPC 캠페인 목록 LIMIT 5 제거 → 전체 반환 | ❌ 신규 — 즉시 적용 필요 |
| 9 | `20260317000025_fix_tag_min_count.sql` | register_campaign RPC 태그 최소 개수 2 → 1로 완화 | ✅ 적용 완료 (2026-05-14) |
| 10 | `20260317000026_fix_sort_order_input.sql` | register_campaign p_sort_orders INTEGER[] 추가 — 광고주 직접 입력 태그 순서 저장 | ✅ 적용 완료 (2026-05-16) |
| 11 | `20260317000027_add_campaign_group.sql` | campaigns 테이블: `group_id uuid`, `group_daily_target int DEFAULT 0` 컬럼 추가. mission_logs 테이블: `group_id uuid` 컬럼 추가 | ✅ 적용 완료 (2026-05-25) |
| 12 | `20260317000028_update_register_campaign_group.sql` | register_campaign RPC: `p_group_id uuid, p_group_daily_target int` 파라미터 추가. 예산 차감 기준을 `group_daily_target × duration × 50`으로 변경. `campaigns.group_id` / `campaigns.group_daily_target` INSERT | ✅ 적용 완료 (2026-05-25) |
| 13 | `20260317000029_update_start_mission_group.sql` | start_mission RPC: 일일 참여 체크를 `group_id` 기준으로 변경 (`mission_logs.group_id` 기반). `mission_logs.group_id` INSERT 처리 | ✅ 적용 완료 (2026-05-25) |
| 14 | `20260317000030_update_dashboard_group.sql` | get_dashboard_data RPC: `group_id`, `seed_keyword`, `group_daily_target`, `sub_keywords(text[])`, `representative_campaign_id` 반환 필드 추가. group_id별 DISTINCT ON 처리 | ✅ 적용 완료 (2026-05-25) |
| 15 | `20260317000031_fix_budget_check_constraint.sql` | campaigns.budget CHECK 완화: `CHECK (budget > 0)` → `CHECK (budget >= 0)`. 두 번째 이후 서브키워드 budget=0 INSERT 허용 | ✅ 적용 완료 (2026-05-25) |

**적용 명령 (Supabase SQL Editor):**
```sql
-- 파일 내용을 복사하여 순서대로 실행
-- 각 파일 실행 후 오류 없으면 다음 파일로
```

**적용 후 검증:**
```sql
-- 1. register_campaign 시그니처 확인
SELECT proname, pg_get_function_arguments(oid)
FROM pg_proc
WHERE proname = 'register_campaign' AND pronamespace = 'public'::regnamespace;
-- 결과에 p_start_date, p_end_date, p_sort_orders, p_answer_index, p_seed_keyword 포함 확인

-- 2. start_mission 일일 제한 활성화 확인
SELECT prosrc FROM pg_proc
WHERE proname = 'start_mission' AND pronamespace = 'public'::regnamespace;
-- 결과에 'ALREADY_PARTICIPATED_TODAY' 문자열 포함 확인

-- 3. campaign_tags 컬럼 확인
SELECT column_name FROM information_schema.columns
WHERE table_name = 'campaign_tags' AND table_schema = 'public'
ORDER BY ordinal_position;
-- is_answer, sort_order 컬럼 포함 확인
```

---

## 14. 추후 개선 사항

개선사항, 버그, 신규 기능 요청은 모두 **`BACKLOG.md`** 파일에서 관리한다.

> Claude Code는 개선사항 관련 작업 시 반드시 `BACKLOG.md`를 먼저 읽는다.
