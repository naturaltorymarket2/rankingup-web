import 'dart:convert';

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 충전 내역 모델
// ─────────────────────────────────────────────────────────────────
//
// get_pending_charges / get_processed_charges RPC 응답 모델.
// description 포맷: "입금자명: X | 세금계산서: Y/N | 입금금액: N"
// ─────────────────────────────────────────────────────────────────

class AdminChargeRecord {
  final String   id;
  final String   userId;
  final String   userEmail;
  final int      amount;      // 신청 포인트 (입력 금액)
  final String   status;      // PENDING / COMPLETED / REJECTED
  final String?  description;
  final DateTime createdAt;

  const AdminChargeRecord({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.description,
  });

  factory AdminChargeRecord.fromMap(Map<String, dynamic> map) =>
      AdminChargeRecord(
        id:          map['id']         as String,
        userId:      map['user_id']    as String,
        userEmail:   (map['user_email'] ?? '') as String,
        amount:      (map['amount'] as num).toInt(),
        status:      map['status']     as String,
        description: map['description'] as String?,
        createdAt:   DateTime.parse(map['created_at'] as String).toLocal(),
      );

  // ── description 파싱 ──────────────────────────────────────────
  // C-009: jsonDecode 우선 파싱, 실패 시 RegExp fallback
  // JSON 포맷: {"depositor":"...", "tax_invoice":true, "total_amount":N}
  // 구형 포맷: "입금자명: X | 세금계산서: Y/N | 입금금액: N"

  static Map<String, dynamic>? _tryJsonDecode(String? desc) {
    if (desc == null) return null;
    try {
      final decoded = jsonDecode(desc);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// 입금자명
  String get depositorName {
    final json = _tryJsonDecode(description);
    if (json != null) return (json['depositor'] as String? ?? '-');
    final m = RegExp(r'입금자명: ([^|]+)').firstMatch(description ?? '');
    return m?.group(1)?.trim() ?? '-';
  }

  /// 세금계산서 요청 여부
  bool get hasTaxInvoice {
    final json = _tryJsonDecode(description);
    if (json != null) return json['tax_invoice'] == true;
    return (description ?? '').contains('세금계산서: Y');
  }

  /// 실제 입금 금액 (세금 포함 여부 반영)
  int get totalTransferAmount {
    final json = _tryJsonDecode(description);
    if (json != null) return (json['total_amount'] as num?)?.toInt() ?? amount;
    final m = RegExp(r'입금금액: (\d+)').firstMatch(description ?? '');
    return int.tryParse(m?.group(1) ?? '') ?? amount;
  }

  // ── 상태 표시 ─────────────────────────────────────────────────

  String get statusLabel => switch (status) {
        'PENDING'   => '대기 중',
        'COMPLETED' => '승인됨',
        'REJECTED'  => '거절됨',
        _           => status,
      };

  Color get statusColor => switch (status) {
        'PENDING'   => const Color(0xFFE65100),
        'COMPLETED' => const Color(0xFF2E7D32),
        'REJECTED'  => const Color(0xFFB71C1C),
        _           => const Color(0xFF757575),
      };
}
