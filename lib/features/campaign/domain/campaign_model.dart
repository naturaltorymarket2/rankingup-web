// ─────────────────────────────────────────────────────────────────
// 캠페인 도메인 모델 (campaigns 테이블 기반)
// ─────────────────────────────────────────────────────────────────

class CampaignModel {
  final String   id;
  final String   productUrl;
  final String   keyword;
  final int      dailyTarget;
  final int      durationDays;
  final int      budget;
  final String   status;
  final DateTime? startDate;
  final DateTime? endDate;

  const CampaignModel({
    required this.id,
    required this.productUrl,
    required this.keyword,
    required this.dailyTarget,
    required this.durationDays,
    required this.budget,
    required this.status,
    this.startDate,
    this.endDate,
  });

  factory CampaignModel.fromMap(Map<String, dynamic> map) => CampaignModel(
        id:           map['id']           as String,
        productUrl:   map['product_url']  as String,
        keyword:      map['keyword']      as String,
        dailyTarget:  (map['daily_target']  as num).toInt(),
        durationDays: (map['duration_days'] as num).toInt(),
        budget:       (map['budget']        as num).toInt(),
        status:       map['status']       as String,
        startDate: map['start_date'] != null
            ? DateTime.parse(map['start_date'] as String)
            : null,
        endDate: map['end_date'] != null
            ? DateTime.parse(map['end_date'] as String)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────
// 캠페인 미션 통계 (상세 화면용)
// ─────────────────────────────────────────────────────────────────

class CampaignStats {
  final int  todaySuccess;
  final int  totalSuccess;
  final int? currentRank;

  const CampaignStats({
    required this.todaySuccess,
    required this.totalSuccess,
    this.currentRank,
  });
}
