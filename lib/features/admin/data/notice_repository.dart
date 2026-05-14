import '../../../app/supabase_client.dart';
import '../domain/notice_model.dart';

// ─────────────────────────────────────────────────────────────────
// 공지사항 데이터 접근 레이어 (어드민 전용)
// ─────────────────────────────────────────────────────────────────

class NoticeRepository {
  /// 전체 공지 목록 최신순 (get_notices RPC)
  ///
  /// SECURITY DEFINER — RLS bypass, 인증 사용자 누구나 호출 가능
  Future<List<NoticeModel>> fetchNotices() async {
    final res = await supabase.rpc('get_notices');
    return (res as List<dynamic>)
        .map((e) => NoticeModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 공지 등록 (create_notice RPC)
  ///
  /// ADMIN role이 아닌 경우 서버에서 FORBIDDEN 오류 반환 → Exception throw
  Future<void> createNotice({
    required String title,
    required String content,
  }) async {
    final res = await supabase.rpc('create_notice', params: {
      'p_title':   title,
      'p_content': content,
    }) as Map<String, dynamic>;

    if (res['success'] != true) {
      final error = res['error'] as String? ?? 'UNKNOWN_ERROR';
      throw Exception(error);
    }
  }
}
