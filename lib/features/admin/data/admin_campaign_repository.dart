import '../../../app/supabase_client.dart';
import '../domain/admin_campaign_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 광고 승인 데이터 접근 레이어
//
// 모든 호출은 SECURITY DEFINER RPC 경유 — role=ADMIN 검증은 서버에서 수행.
// ─────────────────────────────────────────────────────────────────

class AdminCampaignRepository {
  /// 승인 대기(PENDING) 광고 그룹 목록
  Future<List<AdminCampaignRecord>> fetchPendingCampaigns() async {
    final res = await supabase.rpc('get_pending_campaigns')
        as Map<String, dynamic>;
    return _parseList(res);
  }

  /// 승인/거절 처리 완료 목록 (최근 20그룹)
  Future<List<AdminCampaignRecord>> fetchProcessedCampaigns() async {
    final res = await supabase.rpc('get_processed_campaigns')
        as Map<String, dynamic>;
    return _parseList(res);
  }

  /// 광고 승인 — 태그 등록 + 포인트 차감 + ACTIVE 전환
  ///
  /// [tags] 순서가 그대로 상품 페이지 노출 순서(sort_order)로 저장된다.
  /// 반환값: {'success': true/false, 'error': String?, ...}
  Future<Map<String, dynamic>> approveCampaign({
    required String       groupId,
    required List<String> tags,
  }) async {
    final res = await supabase.rpc('approve_campaign', params: {
      'p_group_id': groupId,
      'p_tags':     tags,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// 광고 거절 (등록 시점 차감이 없으므로 환불 처리 불필요)
  Future<Map<String, dynamic>> rejectCampaign({
    required String  groupId,
    String?          reason,
  }) async {
    final res = await supabase.rpc('reject_campaign', params: {
      'p_group_id': groupId,
      'p_reason':   reason,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ── 내부 유틸 ────────────────────────────────────────────────

  List<AdminCampaignRecord> _parseList(Map<String, dynamic> res) {
    if (res['success'] != true) {
      throw Exception(res['error'] ?? 'UNKNOWN_ERROR');
    }
    final list = res['campaigns'] as List<dynamic>? ?? const [];
    return list
        .map((e) => AdminCampaignRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
