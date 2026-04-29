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

```
lib/
├── main.dart
├── app/
│   ├── router.dart          # go_router 전체 라우팅 정의
│   └── supabase_client.dart # Supabase 초기화
├── features/
│   ├── auth/                # 로그인, 회원가입
│   ├── mission/             # 홈, 미션 상세, 미션 진행
│   ├── wallet/              # 포인트, 출금
│   ├── campaign/            # 광고주 캠페인 등록/조회 (웹)
│   ├── dashboard/           # 광고주 대시보드 (웹)
│   ├── charge/              # 포인트 충전 (웹)
│   └── admin/               # 어드민 충전승인/출금처리 (웹)
├── shared/
│   ├── widgets/             # 공통 위젯
│   ├── models/              # 데이터 모델 클래스
│   └── utils/               # 공통 유틸
```

각 feature 폴더 내부 구조:
```
features/mission/
├── data/
│   └── mission_repository.dart   # Supabase 호출
├── domain/
│   └── mission_model.dart        # 데이터 모델
└── presentation/
    ├── mission_home_screen.dart
    ├── mission_detail_screen.dart
    └── mission_active_screen.dart
```

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
| `/admin/charge` | 충전 승인 |
| `/admin/withdraw` | 출금 처리 |

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

| RPC 함수명 | 역할 |
|------------|------|
| `start_mission(campaign_id, user_id, device_id)` | 미션 시작 + 태그 랜덤 할당 |
| `verify_mission(log_id, user_id, submitted_tag)` | 정답 검증 + 리워드 지급 |
| `approve_charge(tx_id)` | 충전 승인 + 포인트 지급 |
| `process_withdraw(tx_id)` | 출금 처리 완료 |
| `register_campaign(user_id, ...)` | 캠페인 등록 + 포인트 차감 |

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
1. 상품 URL + 키워드 입력
2. 파이썬 랭킹 모듈 API 호출 → 현재 순위 확인
3. 15위 이내: 다음 단계 활성화
4. 16위 이상: 등록 불가 메시지 표시 (빨간색)
5. 최종 등록 시: register_campaign RPC → 포인트 즉시 차감
```

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

현재 진행 Phase: **Phase 4 (어드민 + 배포) — 완료**

- ✅ 완료: Phase 1 전체
- ✅ 완료: Phase 2 전체
- ✅ 완료: Phase 3 전체
- ✅ 완료: Phase 4-1 ~ 4-8 (어드민, 랭킹 모듈, 배포 준비, 앱 이름 변경)
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
  - 개인정보처리방침: https://naturaltorymarket2.github.io/rankingup-privacy/
  - targetSdk: 35
  - 앱 아이콘: 임시 아이콘 적용 (파란 배경 + 흰색 "랭킹업" 텍스트)

  **배포 후 수동 처리 필요 항목**
  - ⚠️ start_mission RPC 일일 참여 제한 주석 해제 (테스트 완료 후)
  - ⚠️ 앱 아이콘 교체 (정식 출시 전)
  - ⚠️ Play Console 앱 설정 완료 (스크린샷, 설명, 콘텐츠 등급 등)
  - ⚠️ 프로덕션 트랙 출시 (내부 테스트 완료 후)

- ✅ 완료: Phase 4-10 — 웹 라우팅 버그 수정 + 기능 개선 (2026-04-27)
  - splash_screen.dart: kIsWeb 분기 추가 (웹/앱 라우팅 분리)
  - web_login_screen.dart: 광고주 회원가입 2-step 플로우 구현
  - rank_module/main.py: CORSMiddleware 추가 (Flutter Web 브라우저 지원)
  - campaign_new_screen.dart: 순위 조건 완화 (URL+키워드만 있으면 등록 가능)

- ✅ 완료: Phase 4-11 — GitHub 저장소 등록 + Path URL 라우팅 수정 + Nginx (2026-04-29)
  - store_traffic_booster/ git init + GitHub 저장소 연결 (main 브랜치)
  - android/key.properties → .gitignore 추가
  - main.dart: usePathUrlStrategy() 추가 (Hash URL → Path URL)
  - web/nginx.conf + Dockerfile 신규 (Railway SPA 라우팅)
  - AAB versionCode 3 → 4 빌드

- ✅ 완료: Phase 4-12 — 어드민 로그인 페이지 분리 (2026-04-29)
  - lib/features/auth/presentation/admin_login_screen.dart 신규 생성 (어드민 전용)
  - router.dart: /web/* → /web/login, /admin/* → /admin/login 가드 분리
  - web_login_screen.dart: fromAdmin 파라미터 및 오렌지 배너 제거
  - admin_charge_screen.dart, admin_withdraw_screen.dart: role 체크 로직 제거

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
