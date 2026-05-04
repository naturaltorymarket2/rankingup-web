import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../domain/wallet_model.dart';

final walletRepositoryProvider = Provider.autoDispose<WalletRepository>(
  (_) => WalletRepository(),
);

class WalletRepository {
  static const int pageSize = 20;

  // ─────────────────────────────────────────────────────────────
  // 참여 내역 조회 (mission_logs JOIN campaigns, 페이지네이션)
  // ─────────────────────────────────────────────────────────────

  /// 미션 참여 내역 목록 (최신순)
  ///
  /// - mission_logs.user_id = userId
  /// - campaigns.keyword JOIN
  /// - started_at DESC, 20건씩 페이지네이션
  Future<List<MissionLogModel>> fetchHistory({
    required String userId,
    required int page,
  }) async {
    final start = page * pageSize;
    final end   = start + pageSize - 1;

    final raw = await supabase
        .from('mission_logs')
        .select('id, status, started_at, campaigns(keyword)')
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .range(start, end) as List<dynamic>;

    return raw
        .map((m) => MissionLogModel.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  // ─────────────────────────────────────────────────────────────
  // 출금 신청
  // ─────────────────────────────────────────────────────────────

  /// 출금 신청 — submit_withdraw RPC 호출
  ///
  /// - SECURITY DEFINER RPC로 서버에서 처리 (RLS 우회)
  /// - 중복 체크 / 잔액 확인 / 잔액 차감 / transactions INSERT 모두 RPC 내부에서 처리
  /// - RPC가 RAISE EXCEPTION하면 PostgrestException으로 전파됨
  ///   → 호출부(WithdrawNotifier)에서 message를 파싱해 사용자에게 표시
  Future<void> submitWithdraw({
    required String userId,
    required int amount,
    required String bank,
    required String account,
    required String holder,
  }) async {
    await supabase.rpc('submit_withdraw', params: {
      'p_user_id': userId,
      'p_amount':  amount,
      'p_bank':    bank,
      'p_account': account,
      'p_holder':  holder,
    });
  }
}
