import '../../../app/supabase_client.dart';
import '../domain/admin_user_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 회원 관리 데이터 접근
//
// 전부 SECURITY DEFINER RPC 경유 — ADMIN 검증은 서버에서 한다.
// ─────────────────────────────────────────────────────────────────

class AdminUserRepository {
  /// 회원 목록 (이메일·기기 ID 부분 검색)
  Future<List<AdminUserRecord>> fetchUsers({String search = ''}) async {
    final res = await supabase.rpc('get_users', params: {
      'p_search': search.trim().isEmpty ? null : search.trim(),
      'p_limit':  200,
    }) as Map<String, dynamic>;

    if (res['success'] != true) {
      throw Exception(res['error'] ?? 'UNKNOWN_ERROR');
    }
    final list = res['users'] as List<dynamic>? ?? const [];
    return list
        .map((e) => AdminUserRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 역할 변경 / 기기 초기화
  Future<Map<String, dynamic>> updateUser({
    required String userId,
    String?         role,
    bool            clearDevice = false,
  }) async {
    final res = await supabase.rpc('admin_update_user', params: {
      'p_user_id':      userId,
      'p_role':         role,
      'p_clear_device': clearDevice,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// 계정 삭제 — 미션 기록·포인트 내역까지 함께 지워진다
  Future<Map<String, dynamic>> deleteUser({required String userId}) async {
    final res = await supabase.rpc('admin_delete_user', params: {
      'p_user_id': userId,
    });
    return Map<String, dynamic>.from(res as Map);
  }
}
