import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../data/wallet_repository.dart';

// ─────────────────────────────────────────────────────────────────
// 출금 신청 프로바이더
// ─────────────────────────────────────────────────────────────────

/// 출금 신청 제출 중 여부 (중복 제출 방지)
final withdrawProvider =
    NotifierProvider.autoDispose<WithdrawNotifier, bool>(
  WithdrawNotifier.new,
);

class WithdrawNotifier extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false; // isSubmitting

  /// 출금 신청 제출
  ///
  /// 성공: true 반환
  /// 실패: false 반환 (throw 하지 않음 — 호출부에서 처리)
  Future<bool> submit({
    required int amount,
    required String bank,
    required String account,
    required String holder,
  }) async {
    state = true;
    try {
      final userId = supabase.auth.currentUser?.id ?? '';
      await ref.read(walletRepositoryProvider).submitWithdraw(
        userId:  userId,
        amount:  amount,
        bank:    bank,
        account: account,
        holder:  holder,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        state = false;
      } catch (_) {}
    }
  }
}
