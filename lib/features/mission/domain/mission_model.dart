// =================================================================
// 미션 도메인 모델
// 보안 원칙: product_url, tag_word, assigned_tag_id 는 절대 포함 금지
// =================================================================

// ─────────────────────────────────────────────────────────────────
// 홈 미션 보드 + 상세 화면 공용 캠페인 모델
// ─────────────────────────────────────────────────────────────────

/// 캠페인 미션 모델 (홈/상세 공용)
///
/// tag_word, assigned_tag_id 는 절대 포함하지 않는다.
/// product_url 은 미션 진행 화면에서 유저 안내용으로 표시 (READ-ONLY).
/// currentRank 는 파이썬 랭킹 모듈 연동 후 설정되는 nullable 필드.
class CampaignMissionModel {
  final String campaignId;
  final String keyword;
  final int dailyTarget;

  /// 오늘 SUCCESS 건수 — mission_logs 집계 (서버)
  final int todaySuccessCount;

  /// 키워드 현재 검색 순위 — 파이썬 랭킹 모듈 연동 시 채움
  final int? currentRank;

  final String status;

  /// 상품 URL — 미션 진행 화면 안내용 (클립보드 복사)
  /// 홈 목록 조회 시에는 null
  final String? productUrl;

  /// 그룹 식별자 (group_id) — 그룹 단위 중복 참여 체크 및 DISTINCT용
  /// 기존 캠페인(마이그레이션 전)은 null 가능
  final String? groupId;

  /// 오늘 이미 참여 완료한 캠페인 여부 — 홈 보드에서 시각적 구분 표시용
  final bool isCompleted;

  /// 오늘 시작했지만 아직 정답을 입력하지 않은 상태.
  /// 서버(start_mission)가 재참여를 막으므로 화면에서도 구분해 보여준다.
  final bool isInProgress;

  /// 상품 썸네일 URL (크롤러가 순위 조회 중 확보).
  /// 같은 판매자의 비슷한 상품과 헷갈리지 않도록 사진으로 확인시킨다.
  final String? thumbnailUrl;

  /// 상품명 — 미션 진행 화면 안내용 (nullable, 구버전 캠페인은 null)
  final String? productName;

  /// 브랜드명 — 미션 진행 화면 안내용 (nullable, 구버전 캠페인은 null)
  final String? brandName;

  const CampaignMissionModel({
    required this.campaignId,
    required this.keyword,
    required this.dailyTarget,
    required this.todaySuccessCount,
    this.currentRank,
    required this.status,
    this.productUrl,
    this.groupId,
    this.isCompleted = false,
    this.isInProgress = false,
    this.thumbnailUrl,
    this.productName,
    this.brandName,
  });

  /// 오늘 달성률 0.0 ~ 1.0
  double get todayProgressRatio =>
      dailyTarget > 0
          ? (todaySuccessCount / dailyTarget).clamp(0.0, 1.0)
          : 0.0;

  /// 오늘 남은 슬롯
  int get todayRemaining =>
      (dailyTarget - todaySuccessCount).clamp(0, dailyTarget);

  /// RANK_OUT 상태 여부 — 상세 화면 경고 표시용
  bool get isRankOut => status == 'RANK_OUT';

  /// 오늘 이 그룹에 이미 참여했는지 (완료 또는 진행 중)
  bool get isParticipatedToday => isCompleted || isInProgress;

  // ── 상품 위치 힌트 (크롤러가 매일 수집한 미션 키워드 순위) ──────
  //    유저가 검색 결과에서 상품을 찾지 못해 미션을 포기하는 문제를 줄인다.

  /// 네이버 쇼핑 검색 결과 한 페이지당 상품 수
  static const int _pageSize = 40;

  /// 순위 정보를 안내할 수 있는 상태인지 (500위 안에서 발견된 경우)
  bool get hasRankHint => currentRank != null && currentRank! > 0;

  /// 상품이 있는 페이지 번호 (1-based)
  int get rankPage => hasRankHint ? ((currentRank! - 1) ~/ _pageSize) + 1 : 0;

  /// 화면 안내 문구 — 예) "약 37위 · 2페이지쯤에 있어요"
  String get rankHintText {
    if (!hasRankHint) return '';
    final page = rankPage;
    return page <= 1
        ? '약 $currentRank위 · 첫 페이지에 있어요'
        : '약 $currentRank위 · $page페이지쯤에 있어요';
  }

  /// Supabase 쿼리 Map → 모델
  /// todaySuccessCount 는 mission_logs 별도 집계 후 주입
  factory CampaignMissionModel.fromMap(
    Map<String, dynamic> map, {
    required int todaySuccessCount,
    bool isCompleted = false,
    bool isInProgress = false,
  }) {
    return CampaignMissionModel(
      campaignId:        map['id']           as String,
      keyword:           map['keyword']      as String,
      dailyTarget:       map['daily_target'] as int,
      todaySuccessCount: todaySuccessCount,
      status:            map['status']       as String,
      productUrl:        map['product_url']  as String?,
      groupId:           map['group_id']     as String?,
      // 크롤러가 수집한 미션 키워드 순위 (상품 위치 힌트용, 없으면 null)
      currentRank:       (map['current_rank'] as num?)?.toInt(),
      thumbnailUrl:      map['thumbnail_url'] as String?,
      isInProgress:      isInProgress,
      isCompleted:       isCompleted,
      productName:       map['product_name'] as String?,
      brandName:         map['brand_name']   as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// start_mission RPC 관련 모델
// ─────────────────────────────────────────────────────────────────

/// start_mission RPC 성공 반환값
///
/// 보안: tag_word, assigned_tag_id 는 이 모델에 절대 저장하지 않는다.
/// logId 는 DB UUID (작업 스펙의 BigInt와 상이).
/// startedAt 은 서버 UTC 시각 — 클라이언트 타이머 기준값으로만 사용.
class StartMissionResult {
  /// 미션 로그 ID (UUID)
  final String logId;

  /// 클립보드 복사 + 네이버 딥링크용 키워드
  final String keyword;

  /// 서버 기록 미션 시작 시각 (UTC)
  /// 타이머 기준값 — 클라이언트 DateTime.now()로 대체 금지
  final DateTime startedAt;

  /// 정답 태그 순서 (1-based). "N번째 태그를 입력하세요" 안내용.
  /// null이면 안내 미표시 (기존 캠페인 하위 호환).
  final int? tagIndex;

  const StartMissionResult({
    required this.logId,
    required this.keyword,
    required this.startedAt,
    this.tagIndex,
  });

  /// RPC 응답 Map에서 생성
  /// tag_word, assigned_tag_id 키가 포함되어 있어도 파싱하지 않는다
  factory StartMissionResult.fromMap(Map<String, dynamic> map) {
    return StartMissionResult(
      logId: map['log_id'] as String,
      keyword: map['keyword'] as String,
      startedAt: DateTime.parse(map['started_at'] as String).toUtc(),
      tagIndex: map['tag_index'] as int?,
    );
  }
}

/// start_mission 실패 유형
enum StartMissionError {
  alreadyDone,   // ALREADY_PARTICIPATED_TODAY
  capacityFull,  // DAILY_LIMIT_REACHED
  deviceBlocked, // DEVICE_ALREADY_REGISTERED
  unknown;

  /// 화면 표시용 토스트 메시지
  String get message => switch (this) {
    StartMissionError.alreadyDone =>   '오늘 이미 참여한 미션입니다',
    StartMissionError.capacityFull =>  '오늘 수량이 마감되었습니다',
    StartMissionError.deviceBlocked => '이 기기로는 참여할 수 없습니다',
    StartMissionError.unknown =>       '오류가 발생했습니다. 다시 시도해 주세요',
  };
}

/// start_mission RPC 실패 예외
class StartMissionException implements Exception {
  final StartMissionError error;
  const StartMissionException(this.error);

  @override
  String toString() => 'StartMissionException(${error.name})';
}

// ─────────────────────────────────────────────────────────────────
// verify_mission RPC 관련 모델
// ─────────────────────────────────────────────────────────────────

/// verify_mission RPC 결과 유형
///
/// 보안: 어떤 경우에도 tag_word, assigned_tag_id 를 담지 않는다.
enum VerifyMissionResult {
  /// 정답 + 시간 내 → +7원 적립 성공
  success,

  /// 오답 (WRONG_TAG)
  wrongAnswer,

  /// 10분 초과 (TIMEOUT) — 서버 started_at 기준
  timeout,

  /// 그 외 서버 오류
  error;

  String get message => switch (this) {
    VerifyMissionResult.success =>     '+7원이 적립되었습니다!',
    VerifyMissionResult.wrongAnswer => '오답입니다. 다시 확인해주세요',
    VerifyMissionResult.timeout =>     '시간이 초과되었습니다',
    VerifyMissionResult.error =>       '오류가 발생했습니다. 다시 시도해 주세요',
  };
}
