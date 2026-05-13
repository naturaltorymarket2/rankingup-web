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
      ⚠️ Flutter campaign_new_screen에서 seed_keyword 전달 별도 작업 필요

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

- [ ] [DB] notices 테이블 신규 생성 (id, title, content, created_at, created_by)
- [ ] [어드민 웹] 공지 등록 화면 추가 (/admin/notice)
- [ ] [광고주 웹] 대시보드 상단 공지 확인 섹션 추가

---

## 🔴 긴급 — 앱 핵심 기능 장애

- [ ] 미션 시작 시 네이버 앱 딥링크 미작동 (naversearchapp:// scheme 실행 안 됨)
- [ ] 네이버 앱이 열린 후 앱 복귀 시 MissionActiveScreen 백화면 현상

## 🟠 UX 개선

- [ ] [APP] 태그 입력 화면 — 어떤 값을 입력해야 하는지 안내 문구 및 예시 화면 추가 필요
- [ ] [APP] 태그 입력 화면 — 뒤로가기 버튼 누락, 모달 닫기 수단 필요

## 🟡 신규 기능

- [ ] [어드민 웹] 공지사항 등록 섹션 추가 (운영자가 고객 고지용 공지 작성)
- [ ] [광고주 웹] 공지사항 확인 섹션 추가 (어드민이 등록한 공지를 광고주가 확인)

## 🔵 알려진 이슈 (기존 CLAUDE.md 14섹션에서 이전)

- [ ] campaigns RLS 정책 보완 — fetchCampaignDetail이 campaigns를 직접 SELECT함. UUID를 아는 경우 다른 광고주 캠페인 정보 노출 위험. 수정안: auth.uid() = user_id 조건만 허용하도록 SELECT 정책 강화 필요
