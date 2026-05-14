# BACKLOG.md — 개선 및 버그 추적

> 이 파일은 운영 중 발견된 버그, UX 개선사항, 신규 기능 요청을 기록한다.
> 작업 완료 시 [ ] → [x] 로 변경하고, 완료 날짜를 항목 옆에 기록한다.

---

## 🔴 긴급 — 버그 (최우선)

- [x] [광고주 웹] 순위 대시보드 동일 날짜 중복 노출 (2026-05-13)
- [x] [앱] 태그 입력 시 오류 발생 (2026-05-13)
- [x] [앱] 출금 신청 시 오류 발생 (2026-05-13)

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
      [추가] 버튼으로 태그 추가 (최소 2개, 최대 10개, 중복 불가)
      라디오 버튼으로 정답 태그 1개 선택
      태그 2개 이상 + 정답 선택 시 [다음] 버튼 활성화
      p_tags + p_answer_index를 register_campaign RPC로 전달

- [x] [앱] 미션 진행 화면 — 정답 태그 안내 문구 개선 (2026-05-13)
      start_mission RPC 반환값에 tag_index 포함 (sort_order 값)
      "상품 페이지에서 N번째 태그를 입력하세요" 강조 박스 표시

- [ ] [앱] 미션 진행 화면 — 네이버 태그 보는 방법 안내 이미지 추가
      초보자용 캡쳐 이미지 삽입 (이미지 에셋 준비 필요 — 수동 작업)

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

- [ ] 미션 시작 시 네이버 앱 딥링크 미작동 (naversearchapp:// scheme 실행 안 됨)
- [ ] 네이버 앱이 열린 후 앱 복귀 시 MissionActiveScreen 백화면 현상

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

## 🟠 UX 개선

- [x] [APP] 태그 입력 화면 — 어떤 값을 입력해야 하는지 안내 문구 및 예시 화면 추가 필요 (2026-05-14)
      "태그는 상품명 아래 #으로 시작하는 키워드입니다" 설명 박스 + hintText "예) #헬스장갑" 추가
- [x] [APP] 태그 입력 화면 — 뒤로가기 버튼 누락, 모달 닫기 수단 필요 (2026-05-14)
      태그 입력 상태(canGoBack)에서 AppBar 뒤로가기 버튼 + 시스템 뒤로가기 제스처 처리
      PopScope(canPop: false) + _goBackToWaiting() → _WaitingBody로 복귀 (미션 취소 아님)

## 🟡 신규 기능

- [x] [어드민 웹] 공지사항 등록 섹션 추가 (2026-05-14) → 위 공지사항 항목 참조
- [x] [광고주 웹] 공지사항 확인 섹션 추가 (2026-05-14) → 위 공지사항 항목 참조

## 🔵 알려진 이슈 (기존 CLAUDE.md 14섹션에서 이전)

- [x] campaigns RLS 정책 보완 — fetchCampaignDetail이 campaigns를 직접 SELECT함. UUID를 아는 경우 다른 광고주 캠페인 정보 노출 위험. (2026-05-14)
      migration 0021: Permissive 2개(owner_select, active_select) + Restrictive 1개(advertiser_restrict)
      광고주(business_info 존재)의 타인 ACTIVE 캠페인 접근 차단
      ⚠️ Supabase migration 0021 수동 적용 필요
