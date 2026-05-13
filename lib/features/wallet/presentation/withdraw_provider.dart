import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  /// 성공: 정상 반환
  /// 실패: Exception throw (호출부에서 try/catch 처리)
  ///   - PostgrestException: Supabase RPC RAISE EXCEPTION → 사용자 메시지
  ///   - 기타: 기본 에러 메시지
  Future<void> submit({
    required int amount,
    required String bank,
    required String account,
    required String holder,
  }) async {
    state = true;
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        // 세션 만료 — 빈 문자열을 UUID로 전달하면 PostgreSQL 형식 오류 발생
        throw Exception('로그인이 필요합니다. 다시 로그인해 주세요.');
      }
      await ref.read(walletRepositoryProvider).submitWithdraw(
        userId:  userId,
        amount:  amount,
        bank:    bank,
        account: account,
        holder:  holder,
      );
    } on PostgrestException catch (e) {
      // RPC RAISE EXCEPTION 메시지를 그대로 전파
      throw Exception(e.message);
    } catch (e) {
      // Exception(userId 오류 등)은 그대로 rethrow, 그 외는 래핑
      if (e is Exception) rethrow;
      throw Exception('오류가 발생했습니다. 다시 시도해 주세요.');
    } finally {
      try {
        state = false;
      } catch (_) {}
    }
  }
}
