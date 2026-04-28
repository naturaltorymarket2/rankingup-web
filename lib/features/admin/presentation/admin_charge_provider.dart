import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../data/admin_charge_repository.dart';
import '../domain/admin_charge_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 충전 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final adminChargeRepositoryProvider = Provider<AdminChargeRepository>(
  (_) => AdminChargeRepository(),
);

/// 현재 로그인 유저의 role ('USER' / 'ADMIN' / null)
///
/// 어드민 화면 접근 제한에 사용
final currentUserRoleProvider = FutureProvider.autoDispose<String?>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final res = await supabase
      .from('users')
      .select('role')
      .eq('id', userId)
      .maybeSingle();

  return res?['role'] as String?;
});

/// CHARGE + PENDING 목록
///
/// 승인/거절 후 ref.invalidate(pendingChargesProvider) 로 갱신
final pendingChargesProvider =
    FutureProvider.autoDispose<List<AdminChargeRecord>>((ref) {
  return ref.read(adminChargeRepositoryProvider).fetchPendingCharges();
});

/// CHARGE + COMPLETED/REJECTED 최근 20건
final processedChargesProvider =
    FutureProvider.autoDispose<List<AdminChargeRecord>>((ref) {
  return ref.read(adminChargeRepositoryProvider).fetchProcessedCharges();
});
