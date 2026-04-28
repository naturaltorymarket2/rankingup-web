// =================================================================
// 미션 도메인 모델
// 보안 원칙: product_url, tag_word, assigned_tag_id 는 절대 포함 금지
// =================================================================

// ─────────────────────────────────────────────────────────────────
// 홈 미션 보드 + 상세 화면 공용 캠페인 모델
// ─────────────────────────────────────────────────────────────────

/// 캠페인 미션 모델 (홈/상세 공용)
///
/// product_url, tag_word 는 절대 포함하지 않는다.
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

  const CampaignMissionModel({
    required this.campaignId,
    required this.keyword,
    required this.dailyTarget,
    required this.todaySuccessCount,
    this.currentRank,
    required this.status,
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

  /// Supabase 쿼리 Map → 모델
  /// todaySuccessCount 는 mission_logs 별도 집계 후 주입
  factory CampaignMissionModel.fromMap(
    Map<String, dynamic> map, {
    required int todaySuccessCount,
  }) {
    return CampaignMissionModel(
      campaignId: map['id'] as String,
      keyword: map['keyword'] as String,
      dailyTarget: map['daily_target'] as int,
      todaySuccessCount: todaySuccessCount,
      status: map['status'] as String,
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

  const StartMissionResult({
    required this.logId,
    required this.keyword,
    required this.startedAt,
  });

  /// RPC 응답 Map에서 생성
  /// tag_word, assigned_tag_id 키가 포함되어 있어도 파싱하지 않는다
  factory StartMissionResult.fromMap(Map<String, dynamic> map) {
    return StartMissionResult(
      logId: map['log_id'] as String,
      keyword: map['keyword'] as String,
      startedAt: DateTime.parse(map['started_at'] as String).toUtc(),
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
