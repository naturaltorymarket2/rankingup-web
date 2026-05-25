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

/// 대시보드 캠페인 그룹 행 모델 (group_id 기준 집계)
class DashboardCampaign {
  final String       groupId;
  final String       seedKeyword;           // 순위 추적 대표 키워드
  final String       status;               // ACTIVE / ENDED
  final int          groupDailyTarget;      // 그룹 전체 일일 목표 (과금 기준)
  final List<String> subKeywords;           // 그룹 내 서브키워드 배열
  final int          todayCount;            // 오늘 KST 기준 그룹 합산 SUCCESS 건수
  final int          totalCount;            // 누적 그룹 합산 SUCCESS 건수
  final int?         currentRank;           // 최신 순위 (대표 캠페인 기준)
  final String       representativeCampaignId; // 그룹 내 최초 등록 캠페인 ID (라우팅 기준)

  const DashboardCampaign({
    required this.groupId,
    required this.seedKeyword,
    required this.status,
    required this.groupDailyTarget,
    required this.subKeywords,
    required this.todayCount,
    required this.totalCount,
    required this.currentRank,
    required this.representativeCampaignId,
  });

  factory DashboardCampaign.fromMap(Map<String, dynamic> map) {
    final rawSubKeywords = map['sub_keywords'];
    final List<String> subKeywords;
    if (rawSubKeywords is List) {
      subKeywords = rawSubKeywords.map((e) => e.toString()).toList();
    } else {
      subKeywords = [];
    }

    return DashboardCampaign(
      groupId:                  map['group_id']                   as String,
      seedKeyword:              map['seed_keyword']               as String? ?? '',
      status:                   map['status']                     as String,
      groupDailyTarget:         (map['group_daily_target']        as num?)?.toInt() ?? 0,
      subKeywords:              subKeywords,
      todayCount:               (map['today_count']               as num?)?.toInt() ?? 0,
      totalCount:               (map['total_count']               as num?)?.toInt() ?? 0,
      currentRank:              (map['current_rank']              as num?)?.toInt(),
      representativeCampaignId: map['representative_campaign_id'] as String,
    );
  }

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
        'ACTIVE'   => '진행 중',
        'ENDED'    => '종료',
        'RANK_OUT' => '순위 이탈',
        _          => displayStatus,
      };

  Color get statusColor => switch (displayStatus) {
        'ACTIVE'   => const Color(0xFF2E7D32),
        'ENDED'    => const Color(0xFF757575),
        'RANK_OUT' => const Color(0xFFB71C1C),
        _          => const Color(0xFF757575),
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
