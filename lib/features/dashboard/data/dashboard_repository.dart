import '../../../app/supabase_client.dart';
import '../../admin/domain/notice_model.dart';
import '../domain/dashboard_model.dart';

// ─────────────────────────────────────────────────────────────────
// 대시보드 데이터 접근 레이어
// ─────────────────────────────────────────────────────────────────

class DashboardRepository {
  /// 대시보드 전체 데이터 (요약 + 캠페인 목록)
  ///
  /// get_dashboard_data RPC 호출 → DashboardData 반환
  Future<DashboardData> fetchDashboardData() async {
    final res =
        await supabase.rpc('get_dashboard_data') as Map<String, dynamic>;

    if (res['success'] != true) {
      throw Exception(res['error'] ?? 'UNKNOWN_ERROR');
    }
    return DashboardData.fromMap(res);
  }

  /// 특정 캠페인의 최근 7일 순위 이력 (KST 날짜 기준 중복 제거)
  ///
  /// campaign_rank_history 직접 조회 (RLS: 본인 캠페인만)
  /// 스케줄러가 하루에 여러 번 실행되더라도 동일 날짜는 가장 최신 기록 1개만 반환
  Future<List<RankHistory>> fetchRankHistory(String campaignId) async {
    final sevenDaysAgo =
        DateTime.now().toUtc().subtract(const Duration(days: 7));

    // 최신순 정렬로 가져옴 — limit은 하루 최대 재실행 횟수를 고려해 넉넉하게
    final res = await supabase
        .from('campaign_rank_history')
        .select('rank, checked_at')
        .eq('campaign_id', campaignId)
        .gte('checked_at', sevenDaysAgo.toIso8601String())
        .order('checked_at', ascending: false)
        .limit(100);

    final rows = (res as List<dynamic>)
        .map((e) => RankHistory.fromMap(e as Map<String, dynamic>))
        .toList();

    // KST 날짜 → 해당 날짜의 가장 최신 RankHistory
    // 최신순으로 정렬된 상태에서 putIfAbsent: 날짜별 첫 등장(= 최신)만 보존
    final byDate = <String, RankHistory>{};
    for (final r in rows) {
      final kst = r.checkedAt.toUtc().add(const Duration(hours: 9));
      final dateKey =
          '${kst.year}-${kst.month.toString().padLeft(2, '0')}-${kst.day.toString().padLeft(2, '0')}';
      byDate.putIfAbsent(dateKey, () => r);
    }

    // 날짜 키 오름차순 정렬 → 차트용 반환
    final sorted = byDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => e.value).toList();
  }

  /// 공지사항 전체 목록 최신순 (get_notices RPC)
  ///
  /// 광고주 대시보드 상단 공지 섹션에서 사용
  Future<List<NoticeModel>> fetchNotices() async {
    final res = await supabase.rpc('get_notices');
    return (res as List<dynamic>)
        .map((e) => NoticeModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
