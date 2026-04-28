import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 충전 내역 모델 (transactions 테이블, type = 'CHARGE')
// ─────────────────────────────────────────────────────────────────

class ChargeRecord {
  final String   id;
  final int      amount;      // 지급될 포인트 (입력 금액)
  final String   status;      // PENDING / COMPLETED / REJECTED
  final DateTime createdAt;
  final String?  description; // "입금자명: X | 세금계산서: Y/N | 입금금액: Nwon"

  const ChargeRecord({
    required this.id,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.description,
  });

  factory ChargeRecord.fromMap(Map<String, dynamic> map) => ChargeRecord(
        id:          map['id']     as String,
        amount:      (map['amount'] as num).toInt(),
        status:      map['status'] as String,
        createdAt:   DateTime.parse(map['created_at'] as String).toLocal(),
        description: map['description'] as String?,
      );

  // ── description 파싱 ──────────────────────────────────────────

  /// 입금자명
  String get depositorName {
    final m = RegExp(r'입금자명: ([^|]+)')
        .firstMatch(description ?? '');
    return m?.group(1)?.trim() ?? '-';
  }

  /// 세금계산서 요청 여부
  bool get hasTaxInvoice =>
      (description ?? '').contains('세금계산서: Y');

  /// 실제 입금 금액 (세금 포함 여부에 따라 다름)
  int get totalTransferAmount {
    final m = RegExp(r'입금금액: (\d+)')
        .firstMatch(description ?? '');
    return int.tryParse(m?.group(1) ?? '') ?? amount;
  }

  // ── 상태 표시 ──────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────
// 전체 거래 내역 모델 (transactions 테이블, 모든 type)
// ─────────────────────────────────────────────────────────────────

class TransactionRecord {
  final String   id;
  final String   type;         // CHARGE / SPEND / EARN / WITHDRAW
  final int      amount;
  final String   status;       // PENDING / COMPLETED / REJECTED
  final String?  description;
  final DateTime createdAt;
  final int?     balanceAfter; // NULL: 과거 레코드 또는 PENDING

  const TransactionRecord({
    required this.id,
    required this.type,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.description,
    this.balanceAfter,
  });

  factory TransactionRecord.fromMap(Map<String, dynamic> map) =>
      TransactionRecord(
        id:          map['id']     as String,
        type:        map['type']   as String,
        amount:      (map['amount'] as num).toInt(),
        status:      map['status'] as String,
        description: map['description'] as String?,
        createdAt:   DateTime.parse(map['created_at'] as String).toLocal(),
        balanceAfter: map['balance_after'] == null
            ? null
            : (map['balance_after'] as num).toInt(),
      );

  // ── Type 표시 ────────────────────────────────────────────────

  String get typeLabel => switch (type) {
        'CHARGE'   => '충전',
        'SPEND'    => '지출',
        'EARN'     => '적립',
        'WITHDRAW' => '출금',
        _          => type,
      };

  Color get typeColor => switch (type) {
        'CHARGE'   => const Color(0xFF1565C0),
        'SPEND'    => const Color(0xFFE65100),
        'EARN'     => const Color(0xFF2E7D32),
        'WITHDRAW' => const Color(0xFF6A1B9A),
        _          => const Color(0xFF757575),
      };

  /// CHARGE / EARN 은 입금(+), SPEND / WITHDRAW 는 출금(-)
  bool get isCredit => type == 'CHARGE' || type == 'EARN';

  String get amountDisplay {
    final sign = isCredit ? '+' : '-';
    return '$sign${_fmtNum(amount)}P';
  }

  // ── Status 표시 ──────────────────────────────────────────────

  String get statusLabel => switch (status) {
        'PENDING'   => '대기 중',
        'COMPLETED' => '완료',
        'REJECTED'  => '거절됨',
        _           => status,
      };

  Color get statusColor => switch (status) {
        'PENDING'   => const Color(0xFFE65100),
        'COMPLETED' => const Color(0xFF2E7D32),
        'REJECTED'  => const Color(0xFFB71C1C),
        _           => const Color(0xFF757575),
      };

  static String _fmtNum(int n) {
    final s   = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
