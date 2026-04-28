import 'dart:convert';

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 출금 내역 모델
// ─────────────────────────────────────────────────────────────────
//
// get_pending_withdraws / get_processed_withdraws RPC 응답 모델.
// memo 포맷 (JSON): {"bank": "은행명", "account": "계좌번호", "holder": "예금주"}
//
// 출금 수수료: 500P 고정
//   실이체 금액 = amount - fee (500)
// ─────────────────────────────────────────────────────────────────

class AdminWithdrawRecord {
  final String   id;
  final String   userId;
  final String   userEmail;
  final int      amount;     // 신청 금액 (수수료 포함)
  final String   status;     // PENDING / COMPLETED / REJECTED
  final String?  memo;       // JSON 문자열
  final DateTime createdAt;

  static const int fee = 500; // 출금 수수료 고정

  const AdminWithdrawRecord({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.memo,
  });

  factory AdminWithdrawRecord.fromMap(Map<String, dynamic> map) =>
      AdminWithdrawRecord(
        id:        map['id']         as String,
        userId:    map['user_id']    as String,
        userEmail: (map['user_email'] ?? '') as String,
        amount:    (map['amount'] as num).toInt(),
        status:    map['status']     as String,
        memo:      map['memo']       as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );

  // ── memo JSON 파싱 ────────────────────────────────────────────

  Map<String, dynamic> get _memoMap {
    if (memo == null || memo!.isEmpty) return {};
    try {
      return jsonDecode(memo!) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String get bankName      => (_memoMap['bank']    as String?) ?? '-';
  String get accountNumber => (_memoMap['account'] as String?) ?? '-';
  String get holderName    => (_memoMap['holder']  as String?) ?? '-';

  // ── 금액 계산 ─────────────────────────────────────────────────

  /// 실제 이체 금액 (신청금액 − 수수료)
  /// amount <= fee 이면 0 반환 (음수 방지)
  int get netAmount => amount <= fee ? 0 : amount - fee;

  // ── 상태 표시 ─────────────────────────────────────────────────

  String get statusLabel => switch (status) {
        'PENDING'   => '대기 중',
        'COMPLETED' => '처리완료',
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
