# BACKLOG.md — 개선 및 버그 추적

> 이 파일은 운영 중 발견된 버그, UX 개선사항, 신규 기능 요청을 기록한다.
> 작업 완료 시 [ ] → [x] 로 변경하고, 완료 날짜를 항목 옆에 기록한다.

---

## 🔴 긴급 — 앱/광고주 계정 분리 동작 검증 (테스트 필요) (2026-06-20)

> 코드/DB(migration 0035~37) 변경 완료. git 커밋 완료 (7ba107f, 2026-07-02).
> 실제 동작 검증이 아직 안 된 상태. 상세 배경은 CLAUDE.md 섹션 14 참조.
> ⚠️ Phase 20(2026-07-02)에서 Step2(사업자정보 입력) 완전 제거됨.
>    웹 가입 시 signUp() 직후 `role=ADVERTISER` 즉시 설정 → 이메일 인증 완료 시 `/web/dashboard` 직행.

- [ ] [앱] 새 이메일 가입 → `role=USER` 생성되는지 SQL로 확인
- [N/A] [광고주 웹] Step2(사업자정보) 화면 — Phase 20에서 Step2 완전 제거됨
- [ ] [광고주 웹] 새 이메일 가입 → Step1 → 이메일 인증 클릭 → `/web/dashboard` 직행 확인
      및 DB에서 `role=ADVERTISER`로 설정됐는지 SQL로 확인
- [ ] [최우선] 앱에서 가입한 이메일로 웹 가입(Step1) 시도 → `check_email_exists`로
      즉시 차단되는지
- [ ] [최우선] 앱에서 가입만 하고 이메일 인증을 하지 않은 상태로 그 이메일을 웹에서
      가입 시도 → 차단되는지. GoTrue가 미인증 재가입 시도 시 에러 없이 조용히
      처리할 가능성이 있다고 추정만 했고 실측 안 됨 — 반드시 직접 재현 필요
- [ ] [앱] 광고주 role 계정으로 앱 로그인 시도 → 차단되는지
- [ ] [앱] 광고주로 로그인된 세션 상태에서 앱 재시작 → splash 단계에서 차단되는지
- [ ] [광고주 웹] 유저 role 세션 상태에서 `/web/*` URL 직접 진입 시도 → 차단되는지

## 🔴 긴급 — 버그 (최우선)

- [x] [광고주 웹] 순위 대시보드 동일 날짜 중복 노출 (2026-05-13)
      재수정 (2026-05-14): fetchRankHistory() limit 30→100, seen Set → Map+putIfAbsent 패턴으로 완전 재구현
- [x] [앱] 태그 입력 시 오류 발생 (2026-05-13)
- [x] [앱] 출금 신청 시 오류 발생 (2026-05-13)
      완료: submit_withdraw RPC가 Supabase에 미적용 상태였음. migration 0015(submit_withdraw RPC), 0016(process_withdraw/reject_withdraw 수정) Supabase SQL Editor 적용으로 해결. (2026-05-18)
- [x] [광고주 웹] 대시보드 내 광고 목록 일부만 노출 (2026-05-14)
      원인: get_dashboard_data RPC 캠페인 서브쿼리에 LIMIT 5 하드코딩 (migration 0008)
      수정: migration 0024_fix_dashboard_campaign_limit.sql 신규 생성 — LIMIT 제거
      ⚠️ Supabase SQL Editor에서 migration 0024 적용 필요

## 🟠 기능 변경 (최우선)

- [x] [랭킹 서버] 순위 추적 대상을 시드(대표) 키워드 1개만으로 변경 (2026-05-13)
      campaigns.seed_keyword 컬럼 추가 (migration 0018)
      register_campaign RPC에 p_seed_keyword 파라미터 추가 (DEFAULT NULL, 하위 호환)
      scheduler.py: (product_url, seed_keyword) 기준 그룹화 → API 1회 호출/그룹
      ⚠️ Supabase migration 0018 적용 필요
      ✅ Flutter campaign_new_screen seed_keyword 전달 완료 (2026-05-14)

## 🟡 신규 기능 — 태그 수동 입력 + 정답 태그 선택 (광고주/앱 연동) (최우선)

> 광고주 캠페인 등록 → 앱 미션 안내까지 연결되는 흐름
> (태그 자동 크롤링 방식 폐기 → 광고주 직접 입력 방식으로 변경)

- [x] [랭킹 서버] GET /tags 엔드포인트 추가 후 제거 (2026-05-13)
      Playwright 로컬 테스트 결과 smartstore.naver.com 봇 차단 확인 → 자동 크롤링 방식 폐기
      /tags 엔드포인트, fetch_product_tags 함수, beautifulsoup4 모두 제거

- [x] [DB] campaign_tags 테이블 구조 변경 (2026-05-13)
      is_answer BOOLEAN DEFAULT false 컬럼 추가
      sort_order INTEGER DEFAULT 0 컬럼 추가 (태그 입력 순서, 1-based)
      register_campaign RPC: p_answer_index INT 파라미터 추가 (정답 태그 위치)
      register_campaign RPC: 태그 최소 2개 검증 추가
      ⚠️ Supabase migration 0019 적용 필요

- [x] [광고주 웹] 캠페인 등록 Step 2 — 태그 수동 입력 UI (2026-05-13)
      [추가] 버튼으로 태그 추가 (최소 1개, 최대 10개, 중복 불가) ← 최소 2→1로 변경 (2026-05-14)
      라디오 버튼으로 정답 태그 1개 선택
      태그 1개 이상 + 정답 선택 시 [다음] 버튼 활성화
      p_tags + p_answer_index를 register_campaign RPC로 전달
      [수정] campaign_new_screen.dart: _tags.length >= 1, 안내 문구 변경 (2026-05-14)
      [재수정] campaign_new_screen.dart: 에러 표시 조건 if (_tags.length < 2) → if (_tags.isEmpty) (2026-05-16)
              _step2Valid는 이미 수정됐으나 에러 문구 표시 분기만 누락 — 태그 1개 입력 시 에러 문구 미표시 버그 수정
      [수정] migration 0025: register_campaign array_length < 2 → < 1 (2026-05-14)
      ⚠️ Supabase migration 0025 적용 필요

- [x] [앱] 미션 진행 화면 — 정답 태그 안내 문구 개선 (2026-05-13)
      start_mission RPC 반환값에 tag_index 포함 (sort_order 값)
      "상품 페이지에서 N번째 태그를 입력하세요" 강조 박스 표시

- [x] [앱] 미션 진행 화면 — 네이버 태그 보는 방법 안내 이미지 추가 (2026-05-16)
      assets/images/mission_guide.png 추가, pubspec.yaml assets 섹션 등록
      mission_active_screen.dart _TagInputSection: amber 박스 바로 아래 Image.asset 삽입

- [x] [앱] 미션 설명 페이지 — 네이버 태그 보는 방법 안내 이미지 추가 (2026-05-17)
      mission_detail_screen.dart _InstructionSection: 4단계 안내 아래 Image.asset 삽입
      ClipRRect(borderRadius: 10) 적용

## 🟡 신규 기능 — 공지사항 (최우선)

- [x] [DB] notices 테이블 신규 생성 (id, title, content, created_at, created_by) (2026-05-14)
      get_notices RPC (전체 목록 최신순), create_notice RPC (ADMIN role 검증 후 INSERT)
      RLS: SELECT 모든 인증 사용자, INSERT/UPDATE/DELETE ADMIN only
      ⚠️ Supabase migration 0020 적용 필요
- [x] [어드민 웹] 공지 등록 화면 추가 (/admin/notice) (2026-05-14)
      제목 + 내용 입력 폼 + [등록] 버튼 + 등록된 공지 목록 표시
      /admin/charge AppBar에 [공지 등록] 버튼 추가
- [x] [광고주 웹] 대시보드 상단 공지 확인 섹션 추가 (2026-05-14)
      공지 없으면 섹션 미표시, 공지 있으면 상단에 연한 노란 카드로 표시
      공지 2개 이상이면 [전체 보기] 버튼으로 펼치기 가능

---

## 🔴 긴급 — 어뷰징 방지 미완성

- [x] [DB] start_mission RPC 일일 참여 제한 주석 해제 필수 (2026-05-14)
      migration 0022_enable_daily_mission_limit.sql 신규 생성
      step 3 주석 해제 + campaign_tags 컬럼 IF NOT EXISTS 보장
      ⚠️ Supabase SQL Editor에서 migration 0022 적용 필요

- [x] [DB] register_campaign 시그니처 회귀 버그 수정 (2026-05-14)
      migration 0018이 p_start_date/p_end_date를 p_duration_days로 되돌림 (회귀)
      migration 0023_fix_register_campaign_signature.sql 신규 생성
      p_start_date, p_end_date, p_answer_index, p_seed_keyword 시그니처 강제 적용
      필수 컬럼(seed_keyword, start_date, end_date, is_answer, sort_order) IF NOT EXISTS 포함
      ⚠️ Supabase SQL Editor에서 migration 0023 적용 필요

## 🔴 긴급 — 앱 핵심 기능 장애

- [x] 미션 시작 시 네이버 앱 딥링크 미작동 (2026-05-15)
      원인 A: userId null check 누락 — `?.id ?? ''` 빈 문자열 UUID로 RPC 호출 → UUID parse 오류
      원인 C: `catch (_)` 에러 무음 처리 — 실제 오류 내용이 사용자에게 미표시
      원인 D: `canLaunchUrl()` 사전 체크 없이 `launchUrl()` 직접 호출 — false 반환 시 /active 미이동
      수정: mission_detail_screen.dart (케이스 A/C/D), AndroidManifest.xml (<package com.naver.search> 추가)
- [x] 네이버 앱이 열린 후 앱 복귀 시 MissionActiveScreen 백화면 현상 (Phase 18, 2026-06-19)
      원인: go_router extra가 메모리에만 존재 → 네이버 앱 이동 중 OS가 Flutter 프로세스 종료 시 복원 불가
      수정: MissionSessionStorage (SharedPreferences) 도입 — launchUrl 성공 직후 세션 저장,
            mission_active_screen 진입 시 extra 없으면 campaign_id로 복원, 불일치 시 /home 리다이렉트
- [x] Railway rankingup-web 배포 중단 (2026-05-18)
      원인: Dockerfile 21번째 줄 nginx.conf 경로 오류 (/app/build/web/nginx.conf → /app/web/nginx.conf)
            Flutter build output에 nginx.conf가 포함되지 않으므로 복사 실패 → nginx 시작 불가
      수정: Dockerfile 경로를 소스 파일 위치(/app/web/nginx.conf)로 수정 후 GitHub push → Railway 자동 재배포 성공

## 🟠 버그 수정 권장 — 네이버 딥링크 미완성 이슈 (다음 버전)

- [ ] [앱] 네이버 앱 콜드 스타트 미작동 — launchUrl()이 true를 반환해도 네이버 앱이 열리지 않음
      재현 환경: Galaxy Tab S6 Lite (SM-P610), Android 10, 배터리 최적화 해제 후에도 재현
      증상: launchUrl 직후 아무 반응 없음. 1.5초 딜레이 추가 후에도 동일. 네이버 백그라운드 상태에서는 작동함.
      시도한 대응: canLaunchUrl 제거(Phase 19), 1.5초 delay 추가(Phase 19) — 근본 해결 안 됨
      추정 원인: Android 10 패키지 가시성 + 배터리 최적화 + 삼성 OEM 인텐트 처리 조합 문제
      다음 시도 방안: Intent.ACTION_VIEW를 platform channel로 직접 호출, 또는 네이버 스토어 링크(https://) 폴백

- [ ] [앱] 네이버 딥링크 URL — 앱 열려도 메인 페이지로 이동 (검색 결과 아님)
      재현 환경: 네이버 앱 백그라운드 상태에서 launchUrl 작동 시
      증상: naversearchapp://search?query=키워드 실행 시 네이버 메인 화면으로 이동. 검색 결과 미표시.
      추정 원인: 네이버 앱이 이 스킴을 onNewIntent가 아닌 새 Activity로 처리하거나 파라미터를 무시
      완화책: 미션 진행 화면에 https://search.shopping.naver.com/search/all?query=키워드 URL 표시 + 복사 (Phase 19 적용)

## 🟠 버그 수정 권장

- [x] [광고주 웹] campaign_new_screen.dart userId 강제 언래핑 크래시 위험 (2026-05-14)
      수정: currentUser != null 체크 → null 시 SnackBar("로그인이 필요합니다") + 조기 return
      참고: withdraw_provider.dart, mission_active_provider.dart는 올바르게 처리됨

- [x] [광고주 웹 / DB] fetchCampaignStats와 get_dashboard_data 오늘 유입수 기준 불일치 (2026-05-14)
      수정: fetchCampaignStats completed_at 기준으로 통일
            `.not('completed_at', 'is', null).gte('completed_at', kstMidnight)` 적용

- [x] [앱] mission_detail_screen에서 start_mission 응답의 tag_index 전달 경로 검증 (2026-05-14)
      검증 결과: mission_detail_screen.dart `result.tagIndex` → `'tag_index': result.tagIndex` (extra)
                mission_model.dart StartMissionResult.fromMap: `map['tag_index'] as int?`
                MissionActiveScreen: tagIndex 파라미터 수신 — 이미 올바르게 구현됨 (코드 변경 불필요)

- [x] [DB] migration 0015 NOTE 주석 오류 수정 (2026-05-14)
      기존: "reject_withdraw RPC도 잔액을 복구하지 않음 → 수동 복구 필요"
      수정: migration 0016에서 reject_withdraw 잔액 복구 로직이 이미 추가됨을 명시

- [x] [광고주 웹 + 앱] 태그 순서 입력 프로세스 개선 (2026-05-16)
      문제: sort_order = 루프 카운터(추가 순서) → 실제 네이버 상품 페이지 태그 순서와 무관
      수정:
        campaign_new_screen.dart: _tags List<String> → List<Map> {'name','order'}
          순서 입력 필드(숫자) 추가, 태그 목록에 "N번째 | 태그명" 표시
        campaign_repository.dart: sortOrders 파라미터 추가, p_sort_orders RPC 전달
        migration 0026: p_sort_orders INTEGER[] 파라미터 추가
          sort_order = p_sort_orders[i] (광고주 직접 입력값)
          p_answer_index = 정답 태그의 실제 순서값 (p_sort_orders 내 값)
          is_answer: p_sort_orders[i] = p_answer_index 조건으로 변경
        mission_active_screen.dart: 변경 불필요 (tagIndex → sort_order 이미 올바름)
      ✅ Supabase migration 0026 적용 완료 (2026-05-16)

- [x] [앱] 출금 신청 — 에러 원인 불명 (2026-05-16)
      증상: "오류가 발생했습니다. 다시 시도해주세요" 고정 문구 → 실제 오류 내용 미표시
      개선: withdraw_provider.dart catch(e) 블록 → e.runtimeType + e.toString() 포함 메시지로 변경 (versionCode 9 배포 완료)
      다음 단계: 실기기 테스트 후 e.runtimeType 로그 확인 — PostgrestException 외 Error 계열 예외 의심
      관련 파일: lib/features/wallet/presentation/withdraw_provider.dart

- [x] [랭킹 서버] brand.naver.com 브랜드스토어 URL 파싱 지원 — _BRAND_PATTERN 추가, _extract_product_id 분기 처리 (2026-05-22)
- [x] [랭킹 서버] _NaverApiClient._idx threading.Lock race condition 수정 — fetch_items 전체 Lock 적용 (2026-05-22)
- [x] [광고주 웹] _step2Valid _answerIndex 경계 조건 가드 추가 — `_answerIndex < _tags.length` 인덱스 경계 방어 (Critical 버그) (2026-05-22)
- [x] [광고주 웹] Colors.amber 강제 언래핑(`!`) → .shadeN 교체 (2026-05-22)

- [ ] [DB] campaigns.remaining_slots 일일 리셋 로직 부재 — 캠페인 전체 기간 단일 풀로 동작 중 (2026-06-19)
      현상: remaining_slots는 캠페인 생성 시 daily_target 값으로 1회 초기화된 후,
            캠페인 종료일까지 단 한 번도 리셋되지 않는 누적 카운터로 동작 중
            (일일 리셋 cron/스케줄러 부재 확인됨 — 코드 전체 검색 결과 없음).
      영향: start_mission의 슬롯 체크가 remaining_slots > 0 조건이므로, 이 값이 0이 되면
            그 시점부터 캠페인 종료일까지 해당 캠페인은 모든 사용자에게 CAMPAIGN_UNAVAILABLE로 막힘.
      설계 의도 의심 사유: UI_UX_FLOW.md, CLAUDE.md 등 문서 전반에서 "일일 목표 유입 수",
            "daily_target"이라는 표현을 사용 — 매일 리셋되는 것이 원래 의도였을 가능성이 높음.
            즉 설계 의도와 실제 구현이 어긋나 있을 수 있음.
      발견 경위: 미션 진행 플로우를 딥링크 방식으로 되돌리는 작업 중, "사용자가 네이버 앱에서
            끝까지 복귀하지 않는 경우"의 영향도를 분석하다가 발견됨. 미복귀 빈도가 늘면
            이 한도 도달 시점이 더 앞당겨지는 부작용이 있음 (단, 이 버그 자체는 딥링크 전환과
            무관하게 기존부터 존재하던 구조).
      확인 필요:
        1. remaining_slots가 정말 일일 단위가 아니라 캠페인 전체 기간 단위로 의도된 설계인지
           (의도된 거라면 "daily_target" 컬럼/문서 명칭이 오해를 유발하므로 명칭 정정 필요)
        2. 일일 리셋이 의도였다면, 매일 자정(KST) remaining_slots를 daily_target으로
           복원하는 스케줄러(GitHub Actions 또는 Supabase pg_cron) 추가 필요
        3. 임시 완화책으로, 관리자가 특정 캠페인의 remaining_slots를 수동 조회/보정할 수 있는
           SQL 또는 어드민 화면 기능 마련 검토
      우선순위: 중간 (당장 서비스 중단은 아니나, 운영 중인 캠페인이 예고 없이 조기 소진되어
            광고주 불만으로 이어질 수 있음 — 누적될수록 악화)

## 🟠 UX 개선

- [x] [APP] 태그 입력 화면 — 어떤 값을 입력해야 하는지 안내 문구 및 예시 화면 추가 필요 (2026-05-14)
      "태그는 상품명 아래 #으로 시작하는 키워드입니다" 설명 박스 + hintText "예) #헬스장갑" 추가
- [x] [APP] 태그 입력 화면 — 뒤로가기 버튼 누락, 모달 닫기 수단 필요 (2026-05-14)
      태그 입력 상태(canGoBack)에서 AppBar 뒤로가기 버튼 + 시스템 뒤로가기 제스처 처리
      PopScope(canPop: false) + _goBackToWaiting() → _WaitingBody로 복귀 (미션 취소 아님)
- [x] [앱] 미션 진행 화면 — 상품 URL 표시 추가 (2026-05-18)
      네이버 딥링크 미작동 시 유저가 직접 상품 페이지에 접근할 수 있도록 URL 제공
      _TagInputSection 내 상품 URL 텍스트(말줄임표) + 클립보드 복사 버튼 추가
      변경 파일: mission_model.dart, mission_repository.dart, mission_detail_screen.dart, router.dart, mission_active_screen.dart
      versionCode 11 AAB 빌드 완료 (50.4MB)

- [x] [광고주 웹] 일일 유입 수량 입력 개선 — 최대 3,000명, 100단위 자유 입력 (2026-05-22)
- [x] [광고주 웹] 순위 추적 키워드 / 미션 키워드 섹션 분리 UI (2026-05-22)
- [x] [광고주 웹] 태그 입력 안내 카드 추가 — Step 2 amber 박스 (①②③ 입력 방법 안내 + 예시) (2026-05-22)

## 🟡 확인 필요 — QA 점검

- [x] [랭킹 서버] rank_api_client.dart GET /rank, /keywords 응답 파싱 검증 (2026-05-14)
      GET /rank: {"rank", "product_name", "thumbnail_url"} — Flutter 파싱 필드명 완전 일치
      GET /keywords: {"keywords": [{keyword, rank}]} — Flutter 파싱 필드명 완전 일치
      코드 변경 불필요

- [x] [랭킹 서버] scheduler.py seed_keyword 기반 그룹화 검증 (2026-05-14)
      select('id, product_url, keyword, seed_keyword') — seed_keyword SELECT 확인
      track_kw = c.get('seed_keyword') or c['keyword'] — NULL 시 keyword fallback 확인
      key = (product_url, track_kw) — (product_url, 추적 키워드) 그룹화 정상
      코드 변경 불필요

- [x] [앱] _goBackToWaiting() _remainingSeconds = 600 하드코딩 검증 (2026-05-14)
      _isResumed = false와 동시 설정 → 타이머(_ActiveBody) 미표시 상태에서만 할당됨
      복귀 시 _onResumedFromNaver() → _calcRemaining() → widget.startedAt(서버 시각) 기준 정확히 재계산
      코드 변경 불필요

## 🟡 신규 기능

- [x] [어드민 웹] 공지사항 등록 섹션 추가 (2026-05-14) → 위 공지사항 항목 참조
- [x] [광고주 웹] 공지사항 확인 섹션 추가 (2026-05-14) → 위 공지사항 항목 참조
- [x] [광고주 웹] 회원가입 Step 2 미완료 시 대시보드 접근 차단 (2026-06-20)
      당초 계획(business_info 없음 → Step2로 강제 리다이렉트)에서 설계가 더 발전됨:
      앱/광고주 계정을 가입 단계부터 분리하고 users.role(USER/ADMIN/ADVERTISER)을
      단일 진실 공급원으로 삼는 구조로 확장 적용 — CLAUDE.md 섹션 14 참조.
      router.dart 가드 + web_login_screen.dart + splash_screen.dart 전부 role 기준으로 체크.
      ↓ Phase 20(2026-07-02): Step2 자체를 제거하는 방향으로 변경됨.
        signUp() 직후 role=ADVERTISER 즉시 설정 → 이메일 인증 완료 시 /web/dashboard 직행.
        BACKLOG Phase 20 섹션 및 CLAUDE.md Phase 20 섹션 참조.

## 🔵 알려진 이슈 (기존 CLAUDE.md 14섹션에서 이전)

- [x] campaigns RLS 정책 보완 — fetchCampaignDetail이 campaigns를 직접 SELECT함. UUID를 아는 경우 다른 광고주 캠페인 정보 노출 위험. (2026-05-14)
      migration 0021: Permissive 2개(owner_select, active_select) + Restrictive 1개(advertiser_restrict)
      광고주(business_info 존재)의 타인 ACTIVE 캠페인 접근 차단
      ⚠️ Supabase migration 0021 수동 적용 필요

## 🔵 기술부채

- [ ] [앱] StartMissionResult.startedAt 강제 캐스팅 정리
      파일: lib/features/mission/domain/mission_model.dart (112~113줄, 131줄)
      내용: startedAt 필드가 Phase 16 이후 어디서도 읽히지 않는 dead code.
            start_mission RPC 응답에서 started_at을 제거하거나 스펙 변경 시 즉시 crash 위험.
      처리 시점: start_mission RPC 수정 작업 시 함께 정리
      우선순위: 낮음

---

## ✅ Phase 10 — 그룹 과금 구조 변경 (2026-05-25 완료)

> Flutter 구현 완료. Supabase 마이그레이션 0027~0031 적용 완료. versionCode 13 Play Console 업로드 완료.

### ✅ Flutter 구현 완료 항목

- [x] [광고주 웹] campaign_new_screen.dart — uuid 패키지로 groupId 생성, 예산 계산 `dailyTarget × duration × 50` (키워드수 제거), Step 2 "N개 서브키워드 균등 분배" 안내, 버튼 텍스트 "광고 등록 (포인트 1회 차감)" (2026-05-25)
- [x] [광고주 웹] campaign_repository.dart — `registerCampaign()` `groupId, groupDailyTarget` 파라미터 추가, RPC에 `p_group_id, p_group_daily_target` 전달 (2026-05-25)
- [x] [광고주 웹] campaign_repository.dart — `fetchCampaignDetail()` group_id 기준 서브키워드 목록 추가 조회, `fetchCampaignStats()` group_id 기준 그룹 전체 mission_logs 합산 (2026-05-25)
- [x] [광고주 웹] campaign_model.dart — `groupId, groupDailyTarget, seedKeyword, subKeywords` 필드, `displayDailyTarget / displayKeyword` getter 추가 (2026-05-25)
- [x] [광고주 웹] campaign_detail_screen.dart — `displayKeyword` / `displayDailyTarget` 사용, 서브키워드 목록 `A · B` 형식 표시 (2026-05-25)
- [x] [광고주 웹] dashboard_model.dart — DashboardCampaign에 `groupId, seedKeyword, groupDailyTarget, subKeywords, representativeCampaignId` 추가 (2026-05-25)
- [x] [광고주 웹] dashboard_repository.dart — `get_dashboard_data` RPC 신규 반환 필드 파싱 (2026-05-25)
- [x] [광고주 웹] web_dashboard_screen.dart — seedKeyword 메인·subKeywords 서브 표시, 그룹 합산 통계, `representativeCampaignId` 라우팅 (2026-05-25)
- [x] [앱] mission_repository.dart — `fetchActiveMissions()` group_id 기반 완료 그룹 제외, `seenGroupKeys` Set으로 group_id DISTINCT 처리 (2026-05-25)
- [x] pubspec.yaml — `uuid: ^4.5.1` 추가 (2026-05-25)

### ✅ Supabase DB 마이그레이션 적용 완료 (2026-05-25)

- [x] migration 0027 — campaigns 테이블: `group_id uuid`, `group_daily_target int DEFAULT 0` 컬럼 추가. mission_logs: `group_id uuid` 컬럼 추가 (2026-05-25)
- [x] migration 0028 — `register_campaign` RPC: `p_group_id, p_group_daily_target` 파라미터 추가. 예산 차감 기준 `group_daily_target × duration × 50`으로 변경 (2026-05-25)
- [x] migration 0029 — `get_dashboard_data` RPC: `group_id, seed_keyword, group_daily_target, sub_keywords(text[]), representative_campaign_id` 반환 필드 추가, group_id DISTINCT ON 처리 (2026-05-25)
- [x] migration 0030 — `start_mission` RPC: 일일 참여 체크를 `group_id` 기준으로 변경, `mission_logs.group_id` INSERT 처리 (2026-05-25)
- [x] migration 0031 — `campaigns.budget CHECK (budget >= 0)` 수정 — 두 번째 서브키워드 budget=0 INSERT 허용 (2026-05-25)

### ✅ QA 수동 검증 완료 (2026-05-25)

- [x] TC-01 실제 등록: 5,000,000P 충전 후 2개 서브키워드 그룹 등록 → 35,000P 차감, 대시보드 리디렉트 성공
      **버그 발견 및 수정**: 두 번째 서브키워드 등록 시 `budget=0` → `CHECK (budget > 0)` 위반 400 에러
      **수정**: migration 0031 — `CHECK (budget >= 0)`으로 완화. 재테스트 후 **PASS** (2026-05-25)
- [x] TC-02 대시보드: seedKeyword 메인 / subKeywords 서브 / group_daily_target 일일 목표 표시 확인
      **PASS**: 남자수영복(메인) + "남자수영복 / 남자수영복바지"(서브) 1행 표시, 0/100 일일 목표, 상세 화면 진입 정상 (2026-05-25)
- [ ] TC-03 미션 보드 DISTINCT: 동일 group_id 2개 캠페인 → 미션 보드에 카드 1개만 노출 확인 (앱 실기기 필요)
- [ ] TC-04 중복 참여 방지: 미션 완료(SUCCESS) 후 동일 그룹 카드가 보드에서 사라지는지 확인 (앱 실기기 필요)

### 📝 Playwright QA 발견 사항 (2026-05-25)

- Flutter Web 요소 탭: `PointerEvent(pointerType:'touch', pointerId:1)` 방식 필수 (MouseEvent / PointerEvent 기본값 불가)
  ```javascript
  node.dispatchEvent(new PointerEvent('pointerdown', {
    bubbles: true, pointerId: 1, pointerType: 'touch', isPrimary: true,
    clientX: cx, clientY: cy, pressure: 1
  }));
  ```
- TC-01 UI 검증: ✅ PASS — 예산 계산식·버튼 텍스트·서브키워드 분배 안내 확인
- TC-01 실제 등록: ✅ PASS (migration 0031 적용 후) — 2개 서브키워드 모두 등록 성공
- TC-02 대시보드: ✅ PASS — 1행 그룹 표시, 서브키워드 부제 표시, 상세 화면 정상 진입
- TC-03 카드 네비게이션: ✅ PASS — 미션 카드 → 미션 상세 이동 정상
- TC-04 RPC 동작: ✅ PASS — `startMission` 정상 호출, "신발장 2026.05.25 15:40 진행 중" 이력 생성

### 🚀 배포 완료 (2026-05-25)

- [x] AAB versionCode 13 빌드 완료 (50.4MB)
- [x] GitHub push 완료 (`feat(phase10): 그룹 과금 구조 변경 + versionCode 13`, 18 files)
- [x] Play Console 내부 테스트 트랙 업로드 완료 (versionCode 13)

---

## ✅ Phase 10 배포 후 버그 수정 (2026-05-27~28)

- [x] [광고주 웹] 프로덕션 대시보드 크래시 수정 (2026-05-27)
      증상: Railway 프로덕션 접속 시 `TypeError: null: type 'minified:z6' is not a subtype of type 'String'`
      원인: `DashboardCampaign.fromMap` — `group_id`, `status`, `representative_campaign_id` non-nullable String 캐스트
            Phase 10 마이그레이션 이전 등록 캠페인이 신규 RPC 필드에 null 반환 시 crash
      수정: `lib/features/dashboard/domain/dashboard_model.dart` — 3개 필드 `as String? ?? ''` (status는 `?? 'ENDED'`)
      commit: b6c214e

- [x] [광고주 웹] 순위 추이 차트 Y축 개선 (2026-05-27)
      변경: `lib/features/campaign/presentation/campaign_detail_screen.dart`
      - 방향 변경: 음수 트릭 제거 → rank 그대로 플롯 (1=하단, 15=상단, 위로 갈수록 숫자 커짐)
      - Y축 고정: minY=1 / maxY=15 (데이터 범위 무관)
      - rank > 15 데이터 포인트 필터링 (그래프 미표시, 이탈 처리)
      - 좌축 레이블: 1위·5위·10위·15위만 표시
      commit: 42ea637

- [x] [Android] AD_ID 권한 누락 — Play Console 비공개 테스트 제출 차단 (2026-05-28)
      증상: "광고 ID 선언이 불완전함" 오류 → 업로드 차단
      원인: google_mobile_ads 사용 + targetSdk=35 → AD_ID 권한 명시 필수 (Android 13+ 정책)
      수정: `android/app/src/main/AndroidManifest.xml`
            `<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>` 추가
      ⚠️ Play Console 데이터 보안 섹션 "광고 ID 수집" 선언 필요 (콘솔 수동 작업)
      commit: 67fc4c6

### 🚀 배포 완료 (2026-05-28)

- [x] AAB versionCode 14 빌드 완료 (50.4MB) — 프로덕션 크래시 수정 + 차트 개선 + AD_ID 권한 포함
- [x] GitHub push 완료 (commits: b6c214e, 42ea637, c960ac0, 67fc4c6)
- [ ] Play Console 비공개 테스트 트랙 업로드 (versionCode 14 AAB 업로드 중)

---

## ✅ Phase 11 — 배포 후 UI/차트 버그 수정 (2026-06-08)

- [x] [광고주 웹] 캠페인 등록 Step 2 — 태그 안내 이미지 삽입 (2026-06-08)
      campaign_new_screen.dart _buildStep2(): amber 안내 카드 아래, 정답 태그 _WebCard 위에
      assets/images/tag_guide.png 추가 + pubspec.yaml 등록
      ClipRRect(borderRadius: 10) + Image.asset, 위아래 SizedBox(height: 12)
      commit: 291b427

- [x] [광고주 웹] 순위 추이 차트 x축 날짜 중복 레이블 수정 (2026-06-08)
      campaign_detail_screen.dart _buildLineChartData():
      - history → sorted (checkedAt 오름차순 정렬 복사본)
      - bottomTitles SideTitles에 interval: 1 추가
      - getTitlesWidget: 비정수값 가드 (value != value.roundToDouble() → SizedBox.shrink())
      commit: 70fb049

### 🚀 배포 완료 (2026-06-08)

- [x] Flutter web 빌드 완료 (291b427, 70fb049)
- [x] GitHub push 완료 → Railway 자동 재배포
- [x] AAB versionCode 15 빌드 완료 (51.3MB) — commit: a0cbb9e (공개 테스트용, 이미 사용된 코드로 프로덕션 불가)
- [x] AAB versionCode 16 빌드 완료 (51.3MB) — commit: 6ef3649 (2026-06-09)
- [x] Play Console 프로덕션 트랙 업로드 완료 (versionCode 16)

---

## ✅ Phase 12 — x축 날짜 중복 근본 수정 + DB 정리 (2026-06-09)

> Phase 11-2에서 fl_chart interval 렌더링 중복을 수정했으나, DB 누적 중복 레코드 및 scheduler INSERT-always 로직이 근본 원인으로 남아 있었음. 실데이터 분석(169건 → 중복 85건) 후 3-레이어 완전 수정.

- [x] [광고주 웹] 회원가입 Step 2 전화번호 유효성 검사 강화 (2026-06-09)
      web_login_screen.dart: `_step2Valid` getter (RegExp `^\d{10,11}$`)
      FilteringTextInputFormatter.digitsOnly + LengthLimitingTextInputFormatter(11)
      버튼: `_isLoading || !_step2Valid ? null : _onSignUpStep2`
      레이블: '휴대폰 번호 *' → '전화번호 *', hintText → '숫자만 입력 (10~11자리)'
      commit: 030a37f
      ↓ Phase 20(2026-07-02): Step2 완전 제거 — _step2Valid, _onSignUpStep2 모두 삭제됨.

- [x] [랭킹 서버] crawler.py 브랜드스토어 URL 감지 로그 개선 (2026-06-09)
      _extract_product_id(): 스마트스토어(_SS_PATTERN) 우선 → 브랜드스토어(_BRAND_PATTERN) fallback
      fetch_naver_rank(): target_id = _extract_product_id(url) or _extract_numeric_id(url)
      브랜드스토어 URL 감지 시 INFO 로그 추가
      commit: 730d655

- [x] [랭킹 서버] scheduler.py INSERT → upsert 변경 (2026-06-09)
      기존: 매 실행마다 INSERT → 하루 여러 번 실행(수동 트리거, Railway 재시작) 시 중복 레코드 발생
      변경: 당일 레코드 SELECT → 있으면 UPDATE(rank, checked_at), 없으면 INSERT
      day_start/day_end: KST 자정 기준 범위, 루프 외부 1회 계산
      commit: 839f544

- [x] [광고주 웹] 순위 추이 차트 KST 날짜 dedup 이중 방어 (2026-06-09)
      campaign_detail_screen.dart _buildLineChartData(): byDate map으로 KST 날짜 기준 당일 최신 레코드만 유지
      sorted → deduped 변수명, maxX/spots/getTitlesWidget 모두 deduped 기준
      dashboard_repository.dart의 기존 dedup에 더한 차트 레이어 방어
      commit: a35d993

- [x] [DB] campaign_rank_history 중복 레코드 85건 정리 (2026-06-09)
      분석: 총 169건 중 동일 캠페인+KST날짜 중복 85건 (scheduler 수동 실행 누적)
      DELETE: WHERE id NOT IN (SELECT MIN(id) ... GROUP BY campaign_id, DATE(checked_at AT TIME ZONE 'Asia/Seoul'))
      결과: 169 → 84건, 중복 그룹 0개 확인
      방법: service_role key + PostgREST REST API (Management API Cloudflare 403 우회)

### 🚀 배포 완료 (2026-06-09)

- [x] rankingup 서버 GitHub push 완료 (commits: 730d655, 839f544) → Railway 자동 재배포
- [x] rankingup-web GitHub push 완료 (commits: 030a37f, a35d993) → Railway 자동 재배포

---

## ✅ Phase 14 — 이메일 인증 도입 (2026-06-15)

- [x] [앱/웹] 이메일 인증 도입 — splash/login/web_login에 emailConfirmedAt 체크 추가, EmailVerifyScreen 신규, onAuthStateChange 자동 감지 + fallback 버튼 방식 병행 (Phase 14)
      splash_screen.dart: 세션 복구 후 앱 한정 emailConfirmedAt 체크 → null이면 /email_verify
      login_screen.dart: 로그인 성공 시 emailConfirmedAt 체크, 회원가입 성공 시 항상 /email_verify
      email_verify_screen.dart (신규): 인증 메일 재발송 + 인증 완료했어요 버튼 + USER_UPDATED 리스너
      router.dart: /email_verify 라우트 추가 (extra: {'email': email} 수신)
      web_login_screen.dart: _signupStep double 변경, Step 1.5 이메일 인증 대기 신규, onAuthStateChange 리스너 + fallback 버튼
      ⚠️ Supabase 콘솔: Authentication → Providers → Email → "Confirm email" 활성화 필요

---

## ✅ Phase 15 — 미션 보드 참여완료/참여가능 구분 표시 (2026-06-17)

- [x] [앱] 미션 보드 — 오늘 참여완료한 캠페인 카드 표시 (제거하지 않고 구분 표시)
      변경 전: 참여완료 그룹을 쿼리/루프에서 완전 제거 → 보드에서 사라짐
      변경 후: isCompleted=true로 마킹 → 보드 하단에 dimmed(opacity 0.5) + "참여완료" 배지로 표시
      정렬: 참여가능(isCompleted=false) 먼저, 참여완료(isCompleted=true) 나중에

      mission_model.dart: CampaignMissionModel.isCompleted: bool 필드 추가 (기본값 false)
      mission_repository.dart:
        - 쿼리에서 .not('id', 'in', ...) 필터 제거 (완료 캠페인 포함)
        - 루프에서 completedGroupIds 포함 시 continue → isCompleted=true 마킹으로 변경
        - available / completed 두 리스트 분류 후 [...available, ...completed] 반환
        - 미완료 캠페인만 일일 목표 도달 시 제외
      mission_home_screen.dart:
        - _MissionCard: Opacity(opacity: isCompleted ? 0.5 : 1.0) 래핑
        - onTap: isCompleted일 때 null (상세 이동 차단)
        - 뱃지: 참여완료→_CompletedBadge(회색), 마감→_SoldOutBadge, 기본→_RewardBadge
        - 우측 텍스트: '오늘 참여완료' (회색)
        - _CompletedBadge 위젯 신규 추가

### 🚀 빌드 완료 (2026-06-17)

- [x] AAB versionCode 19 빌드 완료 (51.5MB) — Play Console 미업로드

---

## ✅ Phase 13 — 앱 이름 퀴즈캐시나우 변경 + versionCode 18 프로덕션 배포 (2026-06-11)

- [x] [앱/웹] 앱 이름 "겟머니" → "퀴즈캐시나우" 전체 변경 (2026-06-11)
      AndroidManifest.xml / main.dart / splash_screen / login_screen / web_login_screen / admin_login_screen / web_dashboard_screen 7개 파일 수정
      commit: d7bf299

- [x] [개인정보처리방침] rankingup-privacy 저장소 앱 이름·운영자명 변경 (2026-06-11)
      앱 이름: 랭킹업 (RankingUp) → 퀴즈캐시나우
      운영자명: natural tory market → 주식회사 보스턴블루
      저작권 표시 / <title> / header / 개요 / 연락처 섹션 변경, 이메일 유지
      commit: 2ddf71a (naturaltorymarket2/rankingup-privacy)

### 🚀 배포 완료 (2026-06-11)

- [x] AAB versionCode 18 빌드 완료 (49MB) — commit: 9d3d2cd
- [x] GitHub push 완료 (rankingup-web: d7bf299, 9d3d2cd) → Railway 자동 재배포
- [x] Play Console 프로덕션 트랙 업로드 완료 (versionCode 18)


---

## ✅ Phase 16 — 미션 플로우 WebView 전환 + 광고주 상품명/브랜드명 입력 (2026-06-17)

- [x] [DB] campaigns 테이블에 product_name, brand_name 컬럼 추가 (migration 0032)
- [x] [DB] register_campaign RPC에 p_product_name, p_brand_name 파라미터 추가 (migration 0033)
- [x] [DB] verify_mission RPC에서 10분 타임아웃 블록 제거 (migration 0034)
- [x] [앱] webview_flutter ^4.10.0 패키지 추가
- [x] [앱] MissionSearchScreen 신규 생성 (/mission/:id/search)
      WebViewController + 네이버 쇼핑 URL 로드 + AppBar [태그 입력] 버튼
- [x] [앱] router.dart: /mission/:id/search 라우트 추가, /active 라우트 파라미터 업데이트
- [x] [앱] mission_detail_screen.dart: 딥링크 코드 전체 제거 → /search 화면 이동
      url_launcher/services import 제거, 미션 방법 안내 문구 변경
- [x] [앱] mission_active_screen.dart 전면 재작성
      WidgetsBindingObserver/타이머/라이프사이클 전체 제거, 즉시 활성화
      AppBar [네이버 쇼핑 보기] 버튼 추가, _ProductInfoCard 신규
      startedAt 파라미터 제거, productName/brandName 추가
- [x] [앱] CampaignMissionModel: productName, brandName 필드 추가
- [x] [앱] mission_repository.fetchCampaignDetail(): product_name, brand_name SELECT 추가
- [x] [웹] CampaignModel: productName, brandName 필드 추가
- [x] [웹] campaign_repository.registerCampaign(): p_product_name, p_brand_name 전달
- [x] [웹] campaign_new_screen.dart: Step 1에 상품명/브랜드명 입력 필드 추가
      _step1Valid 조건 업데이트, Step 3 요약에 표시
- [x] [웹] campaign_detail_screen.dart: 상품명/브랜드명 조건부 표시

---

## ✅ Phase 18 — 미션 진행 방식 WebView → 딥링크 복원 + 백화면 버그 수정 (2026-06-19)

- [x] [앱] mission_search_screen.dart 제거 (WebView 화면)
- [x] [앱] router.dart: /mission/:id/search 라우트 제거
- [x] [앱] mission_detail_screen.dart: 딥링크 방식 복원 (canLaunchUrl + launchUrl)
- [x] [앱] mission_session_storage.dart 신규: SharedPreferences 기반 미션 세션 저장/복원/삭제
      launchUrl 성공 직후 저장 → active 화면 진입 시 복원 → dispose()에서 삭제
- [x] [앱] mission_active_screen.dart: WidgetsBindingObserver 재추가, _WaitingBody 복원
      _isResumed 전환 + 복귀 후 3초 버튼 잠금, _resolved 완료 전 resumed 콜백 무시

### 🚀 배포 완료 (2026-06-19)
- [x] versionCode 21 AAB (51.5MB) + APK (60.7MB) 빌드 완료
- [x] GitHub push 완료 (rankingup-web: 985bbb8 → 7b7c909)
- [x] Play Console 프로덕션 트랙 업로드 완료

---

## ✅ Phase 19 — 딥링크 안정성 개선 + 미션 진행 화면 상품 URL 변경 (2026-06-26)

- [x] [DB] device_id 중복 충돌 수동 해소 — chs1989b@gmail.com device_id NULL 처리
      `UPDATE public.users SET device_id = NULL WHERE email = 'chs1989b@gmail.com';`
      test-user@test.com 계정의 DEVICE_ALREADY_REGISTERED 오류 해소 확인

- [x] [앱] mission_detail_screen.dart — canLaunchUrl 사전 체크 제거
      변경 전: canLaunchUrl() → 실패 시 스낵바, 성공 시 launchUrl()
      변경 후: launchUrl() 단독 + try-catch (Android OEM custom scheme 신뢰 불가 문제 대응)

- [x] [앱] mission_detail_screen.dart — 딥링크 URL 파라미터 정리
      `naversearchapp://search?where=nexearch&query=` → `naversearchapp://search?query=`
      (where=nexearch 파라미터 제거 — 일부 기기에서 파라미터 무시로 검색 미동작)

- [x] [앱] mission_detail_screen.dart — context.push() 직전 1.5초 딜레이 추가
      `await Future.delayed(const Duration(milliseconds: 1500))`
      (콜드 스타트 시 Flutter UI가 네이버 앱 전환을 방해하는 레이스 컨디션 방지)

- [x] [앱] mission_active_screen.dart — 상품 URL → 네이버 쇼핑 검색 URL 변경
      keyword가 있으면 `https://search.shopping.naver.com/search/all?query=${Uri.encodeQueryComponent(keyword)}`
      keyword 없으면 기존 productUrl fallback
      효과: 딥링크 미작동 시 사용자가 URL 복사 → 브라우저에서 직접 검색 가능

### 🚀 빌드 완료 (2026-06-26)
- [x] versionCode 22 AAB (51.5MB) 빌드 완료
- [ ] GitHub push 대기 (mission_detail_screen.dart, mission_active_screen.dart, build.gradle.kts(versionCode 22→23) 미커밋 상태)
- [ ] Play Console 프로덕션 트랙 업로드 대기 (versionCode 22 또는 23)

---

## ✅ Phase 20 — 광고주 회원가입 Step2 제거 + role 즉시 설정 (2026-07-02)

> 광고주 회원가입에서 사업자 정보 입력(Step2) 프로세스를 완전히 제거.
> signUp() 직후 role=ADVERTISER 즉시 설정 → 이메일 인증 완료 시 /web/dashboard 직행.
> (이전: signUp → 이메일 인증 → Step2 사업자정보 입력 → register_advertiser RPC → 대시보드)
> (이후: signUp → role=ADVERTISER 즉시 UPDATE → 이메일 인증 → /web/dashboard)

- [x] Railway 빌드 실패 수정 — Phase 14 미커밋 파일 커밋 (2026-07-02)
      commit 7ba107f: account_type.dart(신규), web_login_screen.dart, login_screen.dart, splash_screen.dart
      원인: router.dart(a0b7d7d)가 account_type.dart를 import하나 해당 파일이 git에 없어 Railway 빌드 실패

- [x] Railway 재배포 트리거 — 빈 커밋 (2026-07-02)
      commit 91da047: "chore: trigger Railway redeploy"
      Railway 이미지 push가 10분 이상 멈춘 상태를 해소하기 위해 빈 커밋으로 새 빌드 강제 트리거

- [x] [광고주 웹] web_login_screen.dart — Step2 관련 코드 전체 제거 (2026-07-02)
      제거: showStep2 생성자 파라미터, _signupStep 상태변수
      제거: _signupPhoneCtrl, _signupCompanyCtrl, _signupBizNumCtrl, _signupTaxEmailCtrl (TextEditingController 4개)
      제거: _onSignUpStep2(), _buildSignUpStep2(), _buildStepIndicator(), _stepDot()
      제거: _step2Valid getter, _mapRpcError() 메서드
      추가: bool _isEmailVerifyStep = false (기존 _signupStep double 대체)
      추가: signUp() 직후 `supabase.from('users').update({'role': 'ADVERTISER'}).eq('id', currentUser.id)` 호출
      변경: _checkWebConfirmed() — setState(() => _signupStep = 2.0) → context.go('/web/dashboard')
      변경: onAuthStateChange 리스너 — emailConfirmedAt 확인 후 /web/dashboard 직행
      변경: _currentForm() — _signupStep 분기 → _isEmailVerifyStep bool 분기 단순화

- [x] [광고주 웹] router.dart — step2 파라미터 처리 제거 (2026-07-02)
      변경: /?code= 이메일 인증 콜백 — isRegisteredAdvertiser 체크 제거, return '/web/dashboard' 단일 라인
      제거: /web/login 빌더의 showStep2 쿼리 파라미터 읽기 및 WebLoginScreen showStep2 전달

### 🚀 커밋 완료 (2026-07-02)
- [x] commit dbfca47 — "feat: remove step2 signup flow, set ADVERTISER role on web signup"
- [x] GitHub push 완료 (rankingup-web: 91da047 → dbfca47) → Railway 자동 재배포 트리거
