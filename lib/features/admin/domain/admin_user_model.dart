import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 회원 관리 — 회원 1명
// ─────────────────────────────────────────────────────────────────

class AdminUserRecord {
  final String    id;
  final String    email;
  final String    role;            // USER / ADMIN
  /// 광고주 웹 접근 가능 여부. role 과 독립 — 앱 유저 겸업이 가능하다.
  final bool      isAdvertiser;
  final String?   deviceId;
  final DateTime  createdAt;
  final bool      emailConfirmed;
  final DateTime? lastSignInAt;
  final int       balance;
  final int       successCount;    // 정답까지 마친 미션
  final int       missionCount;    // 시작한 미션 전체
  final int       campaignCount;   // 등록한 광고 (있으면 삭제 불가)

  const AdminUserRecord({
    required this.id,
    required this.email,
    required this.role,
    required this.isAdvertiser,
    required this.deviceId,
    required this.createdAt,
    required this.emailConfirmed,
    required this.lastSignInAt,
    required this.balance,
    required this.successCount,
    required this.missionCount,
    required this.campaignCount,
  });

  factory AdminUserRecord.fromMap(Map<String, dynamic> m) => AdminUserRecord(
        id:             m['id'] as String,
        email:          m['email'] as String? ?? '(이메일 없음)',
        role:           m['role'] as String? ?? 'USER',
        isAdvertiser:   m['is_advertiser'] == true || m['role'] == 'ADVERTISER',
        deviceId:       m['device_id'] as String?,
        createdAt:      DateTime.parse(m['created_at'] as String),
        emailConfirmed: m['email_confirmed'] == true,
        lastSignInAt:   m['last_sign_in_at'] == null
            ? null
            : DateTime.parse(m['last_sign_in_at'] as String),
        balance:        (m['balance']        as num?)?.toInt() ?? 0,
        successCount:   (m['success_count']  as num?)?.toInt() ?? 0,
        missionCount:   (m['mission_count']  as num?)?.toInt() ?? 0,
        campaignCount:  (m['campaign_count'] as num?)?.toInt() ?? 0,
      );

  String get roleLabel => role == 'ADMIN' ? '관리자' : '앱 유저';

  Color get roleColor => role == 'ADMIN'
      ? const Color(0xFFB71C1C)
      : const Color(0xFF2E7D32);

  /// 삭제해도 되는 계정인지 (서버에서도 같은 기준으로 막는다)
  bool get canDelete => role != 'ADMIN' && campaignCount == 0;

  static const advertiserColor = Color(0xFF1E3A8A);

  bool get hasDevice => (deviceId ?? '').isNotEmpty;
}
