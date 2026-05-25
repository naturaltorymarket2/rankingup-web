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

  // 그룹 과금 구조 필드 (migration 0027 이후)
  final String?       groupId;
  final int           groupDailyTarget; // 0이면 구버전 데이터
  final String?       seedKeyword;      // 순위 추적 대표 키워드
  final List<String>  subKeywords;      // 그룹 내 전체 서브키워드 목록

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
    this.groupId,
    this.groupDailyTarget = 0,
    this.seedKeyword,
    this.subKeywords = const [],
  });

  factory CampaignModel.fromMap(
    Map<String, dynamic> map, {
    List<String> subKeywords = const [],
  }) => CampaignModel(
        id:               map['id']            as String,
        productUrl:       map['product_url']   as String,
        keyword:          map['keyword']       as String,
        dailyTarget:      (map['daily_target']   as num).toInt(),
        durationDays:     (map['duration_days']  as num).toInt(),
        budget:           (map['budget']         as num).toInt(),
        status:           map['status']        as String,
        groupId:          map['group_id']      as String?,
        groupDailyTarget: (map['group_daily_target'] as num?)?.toInt() ?? 0,
        seedKeyword:      map['seed_keyword']  as String?,
        subKeywords:      subKeywords,
        startDate: map['start_date'] != null
            ? DateTime.parse(map['start_date'] as String)
            : null,
        endDate: map['end_date'] != null
            ? DateTime.parse(map['end_date'] as String)
            : null,
      );

  /// 표시용 일일 목표: group_daily_target > 0이면 그룹 기준, 아니면 per-keyword
  int get displayDailyTarget =>
      groupDailyTarget > 0 ? groupDailyTarget : dailyTarget;

  /// 표시용 키워드: seed_keyword가 있으면 해당값, 없으면 keyword
  String get displayKeyword =>
      (seedKeyword != null && seedKeyword!.isNotEmpty) ? seedKeyword! : keyword;
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
