import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 광고 승인 모델
//
// get_pending_campaigns / get_processed_campaigns RPC 응답 모델.
// 행 단위 = 광고 그룹(group_id) — 서브키워드들은 sub_keywords로 집계된다.
// ─────────────────────────────────────────────────────────────────

class AdminCampaignRecord {
  final String       groupId;
  final String       representativeCampaignId;
  final String       userEmail;
  final String       productName;
  final String       brandName;
  final String       productUrl;
  final String       seedKeyword;
  final List<String> subKeywords;
  final int          groupDailyTarget;
  final int          durationDays;
  final DateTime?    startDate;
  final DateTime?    endDate;
  final int          budget;          // 승인 시 차감될 포인트 (그룹 합산)
  final DateTime     createdAt;
  final int          campaignCount;

  // 처리 완료 목록에서만 채워지는 필드
  final String?      approvalStatus;  // APPROVED / REJECTED
  final DateTime?    processedAt;
  final String?      rejectReason;
  final List<String> tags;            // 어드민이 등록한 태그 (순서대로)

  const AdminCampaignRecord({
    required this.groupId,
    required this.representativeCampaignId,
    required this.userEmail,
    required this.productName,
    required this.brandName,
    required this.productUrl,
    required this.seedKeyword,
    required this.subKeywords,
    required this.groupDailyTarget,
    required this.durationDays,
    required this.budget,
    required this.createdAt,
    required this.campaignCount,
    this.startDate,
    this.endDate,
    this.approvalStatus,
    this.processedAt,
    this.rejectReason,
    this.tags = const [],
  });

  factory AdminCampaignRecord.fromMap(Map<String, dynamic> map) {
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];

    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();

    return AdminCampaignRecord(
      groupId:                  map['group_id'] as String,
      representativeCampaignId: map['representative_campaign_id'] as String? ?? '',
      userEmail:                map['user_email']    as String? ?? '-',
      productName:              map['product_name']  as String? ?? '-',
      brandName:                map['brand_name']    as String? ?? '-',
      productUrl:               map['product_url']   as String? ?? '',
      seedKeyword:              map['seed_keyword']  as String? ?? '',
      subKeywords:              strList(map['sub_keywords']),
      groupDailyTarget:         (map['group_daily_target'] as num?)?.toInt() ?? 0,
      durationDays:             (map['duration_days']      as num?)?.toInt() ?? 0,
      budget:                   (map['budget']             as num?)?.toInt() ?? 0,
      campaignCount:            (map['campaign_count']     as num?)?.toInt() ?? 0,
      createdAt:                parseDate(map['created_at']) ?? DateTime.now(),
      startDate:                parseDate(map['start_date']),
      endDate:                  parseDate(map['end_date']),
      approvalStatus:           map['approval_status'] as String?,
      processedAt:              parseDate(map['processed_at']),
      rejectReason:             map['reject_reason'] as String?,
      tags:                     strList(map['tags']),
    );
  }

  /// 표시용 키워드: seed_keyword 우선, 없으면 첫 서브키워드
  String get displayKeyword => seedKeyword.isNotEmpty
      ? seedKeyword
      : (subKeywords.isNotEmpty ? subKeywords.first : '-');

  String get periodLabel {
    if (startDate == null || endDate == null) return '-';
    String f(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return '${f(startDate!)} ~ ${f(endDate!)} ($durationDays일)';
  }

  String get statusLabel => switch (approvalStatus) {
        'APPROVED' => '승인됨',
        'REJECTED' => '거절됨',
        'PENDING'  => '대기 중',
        _          => approvalStatus ?? '대기 중',
      };

  Color get statusColor => switch (approvalStatus) {
        'APPROVED' => const Color(0xFF2E7D32),
        'REJECTED' => const Color(0xFFB71C1C),
        _          => const Color(0xFFE65100),
      };
}

// ─────────────────────────────────────────────────────────────────
// 붙여넣은 태그 문자열 파싱
// ─────────────────────────────────────────────────────────────────

/// 상품 페이지에서 긁어온 태그 문자열을 태그 목록으로 변환한다.
///
/// - 기본 구분자는 '#'  (예: "#AAA#BBB#CCC" → [AAA, BBB, CCC])
/// - '#'이 전혀 없으면 공백/줄바꿈/쉼표로 분리 (수기 입력 대비)
/// - 앞뒤 공백 제거, 빈 항목 제거
/// - 중복 제거 (대소문자·공백 무시) — 서버도 동일 기준으로 중복을 거부한다
/// - 순서 = 상품 페이지 노출 순서 → 그대로 sort_order 1..N 이 된다
List<String> parsePastedTags(String raw) {
  final source = raw.trim();
  if (source.isEmpty) return const [];

  final parts = source.contains('#')
      ? source.split('#')
      : source.split(RegExp(r'[\s,]+'));

  final result = <String>[];
  final seen   = <String>{};

  for (final part in parts) {
    final tag = part.trim();
    if (tag.isEmpty) continue;
    final key = tag.replaceAll(RegExp(r'\s'), '').toLowerCase();
    if (key.isEmpty) continue;
    if (!seen.add(key)) continue; // 중복
    result.add(tag);
  }
  return result;
}
