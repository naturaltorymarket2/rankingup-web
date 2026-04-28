import '../../../app/supabase_client.dart';
import '../domain/admin_withdraw_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 출금 데이터 접근 레이어
// ─────────────────────────────────────────────────────────────────

class AdminWithdrawRepository {
  /// WITHDRAW + PENDING 전체 목록 (get_pending_withdraws RPC)
  Future<List<AdminWithdrawRecord>> fetchPendingWithdraws() async {
    final res = await supabase.rpc('get_pending_withdraws');
    return (res as List<dynamic>)
        .map((e) => AdminWithdrawRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// WITHDRAW + COMPLETED/REJECTED 최근 20건 (get_processed_withdraws RPC)
  Future<List<AdminWithdrawRecord>> fetchProcessedWithdraws() async {
    final res = await supabase.rpc('get_processed_withdraws');
    return (res as List<dynamic>)
        .map((e) => AdminWithdrawRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 출금 처리완료 (process_withdraw RPC)
  ///
  /// wallets.balance -= amount 후 status=COMPLETED
  /// 반환값: {'success': bool, 'new_balance': int?, 'error': String?}
  Future<Map<String, dynamic>> processWithdraw(String txId) async {
    final res = await supabase.rpc(
      'process_withdraw',
      params: {'p_tx_id': txId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// 출금 거절 (reject_withdraw RPC)
  ///
  /// status=REJECTED, 잔액 변경 없음
  /// 반환값: {'success': bool, 'error': String?}
  Future<Map<String, dynamic>> rejectWithdraw(String txId) async {
    final res = await supabase.rpc(
      'reject_withdraw',
      params: {'p_tx_id': txId},
    );
    return Map<String, dynamic>.from(res as Map);
  }
}
