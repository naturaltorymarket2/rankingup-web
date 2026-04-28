import '../../../app/supabase_client.dart';
import '../domain/admin_charge_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 충전 데이터 접근 레이어
// ─────────────────────────────────────────────────────────────────

class AdminChargeRepository {
  /// CHARGE + PENDING 전체 목록 (get_pending_charges RPC)
  Future<List<AdminChargeRecord>> fetchPendingCharges() async {
    final res = await supabase.rpc('get_pending_charges');
    return (res as List<dynamic>)
        .map((e) => AdminChargeRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// CHARGE + COMPLETED/REJECTED 최근 20건 (get_processed_charges RPC)
  Future<List<AdminChargeRecord>> fetchProcessedCharges() async {
    final res = await supabase.rpc('get_processed_charges');
    return (res as List<dynamic>)
        .map((e) => AdminChargeRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 충전 승인 (approve_charge RPC)
  ///
  /// 반환값: {'success': true/false, 'error': String?}
  Future<Map<String, dynamic>> approveCharge(String txId) async {
    final res = await supabase.rpc(
      'approve_charge',
      params: {'p_tx_id': txId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// 충전 거절 (reject_charge RPC)
  ///
  /// 반환값: {'success': true/false, 'error': String?}
  Future<Map<String, dynamic>> rejectCharge(String txId) async {
    final res = await supabase.rpc(
      'reject_charge',
      params: {'p_tx_id': txId},
    );
    return Map<String, dynamic>.from(res as Map);
  }
}
