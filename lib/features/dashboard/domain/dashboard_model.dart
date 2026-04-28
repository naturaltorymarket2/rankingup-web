import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 대시보드 데이터 모델
// ─────────────────────────────────────────────────────────────────

/// get_dashboard_data RPC 전체 응답
class DashboardData {
  final int balance;
  final int activeCount;
  final int todayTraffic;
  final List<DashboardCampaign> campaigns;

  const DashboardData({
    required this.balance,
    required this.activeCount,
    required this.todayTraffic,
    required this.campaigns,
  });

  factory DashboardData.fromMap(Map<String, dynamic> map) {
    final rawList = map['campaigns'] as List<dynamic>? ?? [];
    return DashboardData(
      balance:      (map['balance']       as num?)?.toInt() ?? 0,
      activeCount:  (map['active_count']  as num?)?.toInt() ?? 0,
      todayTraffic: (map['today_traffic'] as num?)?.toInt() ?? 0,
      campaigns: rawList
          .map((e) => DashboardCampaign.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 대시보드 캠페인 행 모델
class DashboardCampaign {
  final String id;
  final String keyword;
  final int    dailyTarget;
  final String status;        // DB 상태: ACTIVE / PAUSED / COMPLETED
  final int?   currentRank;   // 최신 순위 (rank_history 없으면 null)
  final int    todaySuccess;  // 오늘 KST 기준 성공 건수

  const DashboardCampaign({
    required this.id,
    required this.keyword,
    required this.dailyTarget,
    required this.status,
    required this.currentRank,
    required this.todaySuccess,
  });

  factory DashboardCampaign.fromMap(Map<String, dynamic> map) =>
      DashboardCampaign(
        id:           map['id']           as String,
        keyword:      map['keyword']      as String,
        dailyTarget:  (map['daily_target'] as num).toInt(),
        status:       map['status']       as String,
        currentRank:  (map['current_rank'] as num?)?.toInt(),
        todaySuccess: (map['today_success'] as num?)?.toInt() ?? 0,
      );

  // ── 파생 속성 ─────────────────────────────────────────────────

  /// 표시용 상태 (ACTIVE + 순위이탈 → RANK_OUT)
  String get displayStatus {
    if (status == 'ACTIVE' &&
        (currentRank == null || currentRank! > 15)) {
      return 'RANK_OUT';
    }
    return status;
  }

  String get statusLabel => switch (displayStatus) {
        'ACTIVE'    => '진행 중',
        'PAUSED'    => '일시 중지',
        'COMPLETED' => '종료',
        'RANK_OUT'  => '순위 이탈',
        _           => displayStatus,
      };

  Color get statusColor => switch (displayStatus) {
        'ACTIVE'    => const Color(0xFF2E7D32),
        'PAUSED'    => const Color(0xFFE65100),
        'COMPLETED' => const Color(0xFF757575),
        'RANK_OUT'  => const Color(0xFFB71C1C),
        _           => const Color(0xFF757575),
      };

  String get rankLabel =>
      currentRank != null ? '$currentRank위' : '-';
}

/// 순위 이력 단일 항목 (campaign_rank_history 행)
class RankHistory {
  final DateTime checkedAt; // UTC
  final int      rank;

  const RankHistory({required this.checkedAt, required this.rank});

  factory RankHistory.fromMap(Map<String, dynamic> map) => RankHistory(
        checkedAt: DateTime.parse(map['checked_at'] as String).toUtc(),
        rank:      (map['rank'] as num).toInt(),
      );
}
