// =================================================================
// 지갑/내역 도메인 모델
// 보안 원칙: tag_word, assigned_tag_id 절대 포함 금지
// =================================================================

// ─────────────────────────────────────────────────────────────────
// 지갑 잔액 모델
// ─────────────────────────────────────────────────────────────────

class WalletModel {
  final String userId;
  final int balance;

  const WalletModel({
    required this.userId,
    required this.balance,
  });
}

// ─────────────────────────────────────────────────────────────────
// 미션 참여 내역 모델 (mission_logs JOIN campaigns)
// ─────────────────────────────────────────────────────────────────

/// 참여 내역 카드 1건
///
/// Supabase 쿼리: `.select('id, status, started_at, campaigns(keyword)')`
/// 미션 1건 성공 시 적립 포인트 (verify_mission RPC 와 동일 값)
const int kMissionReward = 7;

class MissionLogModel {
  final String id;
  final String status;       // IN_PROGRESS / SUCCESS / FAILED / TIMEOUT
  final DateTime startedAt;  // UTC — 표시 시 toLocal() 사용
  final String keyword;      // campaigns.keyword JOIN 결과

  // 어떤 상품이었는지 기억할 수 있도록 함께 표시
  final String  campaignId;
  final String? productName;
  final String? thumbnailUrl;

  /// 정답 시도 횟수 — 오답으로 남아 있는 건을 구분하는 데 쓴다
  final int attemptCount;

  const MissionLogModel({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.keyword,
    required this.campaignId,
    this.productName,
    this.thumbnailUrl,
    this.attemptCount = 0,
  });

  factory MissionLogModel.fromMap(Map<String, dynamic> map) {
    final campaigns = map['campaigns'] as Map<String, dynamic>?;
    return MissionLogModel(
      id:            map['id']         as String,
      status:        map['status']     as String,
      startedAt:     DateTime.parse(map['started_at'] as String).toUtc(),
      keyword:       campaigns?['keyword'] as String? ?? '-',
      campaignId:    map['campaign_id'] as String? ?? '',
      productName:   campaigns?['product_name']  as String?,
      thumbnailUrl:  campaigns?['thumbnail_url'] as String?,
      attemptCount:  (map['attempt_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 적립 포인트 (성공 건만)
  int get earnedPoint => status == 'SUCCESS' ? kMissionReward : 0;

  /// 이어서 진행할 수 있는 상태인지
  bool get canResume => status == 'IN_PROGRESS';

  /// 진행 중인데 오답 시도가 있었으면 그 사실을 알려준다
  String? get subLabel {
    if (status == 'IN_PROGRESS' && attemptCount > 0) {
      return '정답이 일치하지 않았어요 (${attemptCount}회 시도)';
    }
    return null;
  }

  // ── 표시용 변환 ──────────────────────────────────────────────

  String get statusLabel => switch (status) {
    'SUCCESS'     => '적립 완료',
    'TIMEOUT'     => '시간 초과',
    'FAILED'      => '실패',
    'IN_PROGRESS' => '진행 중',
    _             => '알 수 없음',
  };

  /// Color 값 (Flutter import 없이 순수 Dart)
  int get statusColorValue => switch (status) {
    'SUCCESS'     => 0xFF2E7D32, // green.shade800
    'TIMEOUT'     => 0xFFE65100, // deepOrange.shade900
    'FAILED'      => 0xFFB71C1C, // red.shade900
    _             => 0xFF757575, // grey.shade600 (IN_PROGRESS)
  };

  bool get showReward => status == 'SUCCESS';
}
