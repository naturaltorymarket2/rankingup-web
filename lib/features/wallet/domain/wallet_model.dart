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
class MissionLogModel {
  final String id;
  final String status;       // IN_PROGRESS / SUCCESS / FAILED / TIMEOUT
  final DateTime startedAt;  // UTC — 표시 시 toLocal() 사용
  final String keyword;      // campaigns.keyword JOIN 결과

  const MissionLogModel({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.keyword,
  });

  factory MissionLogModel.fromMap(Map<String, dynamic> map) {
    final campaigns = map['campaigns'] as Map<String, dynamic>?;
    return MissionLogModel(
      id:        map['id']         as String,
      status:    map['status']     as String,
      startedAt: DateTime.parse(map['started_at'] as String).toUtc(),
      keyword:   campaigns?['keyword'] as String? ?? '-',
    );
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
