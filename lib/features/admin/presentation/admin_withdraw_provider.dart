import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_withdraw_repository.dart';
import '../domain/admin_withdraw_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 출금 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final adminWithdrawRepositoryProvider = Provider<AdminWithdrawRepository>(
  (_) => AdminWithdrawRepository(),
);

/// WITHDRAW + PENDING 목록
///
/// 처리완료/거절 후 ref.invalidate(pendingWithdrawsProvider) 로 갱신
final pendingWithdrawsProvider =
    FutureProvider.autoDispose<List<AdminWithdrawRecord>>((ref) {
  return ref.read(adminWithdrawRepositoryProvider).fetchPendingWithdraws();
});

/// WITHDRAW + COMPLETED/REJECTED 최근 20건
final processedWithdrawsProvider =
    FutureProvider.autoDispose<List<AdminWithdrawRecord>>((ref) {
  return ref
      .read(adminWithdrawRepositoryProvider)
      .fetchProcessedWithdraws();
});
