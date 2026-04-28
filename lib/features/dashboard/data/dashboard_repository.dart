import '../../../app/supabase_client.dart';
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

  /// 특정 캠페인의 최근 7일 순위 이력
  ///
  /// campaign_rank_history 직접 조회 (RLS: 본인 캠페인만)
  /// 파이썬 랭킹 모듈 연동 전까지 빈 리스트 반환
  Future<List<RankHistory>> fetchRankHistory(String campaignId) async {
    final sevenDaysAgo =
        DateTime.now().toUtc().subtract(const Duration(days: 7));

    final res = await supabase
        .from('campaign_rank_history')
        .select('rank, checked_at')
        .eq('campaign_id', campaignId)
        .gte('checked_at', sevenDaysAgo.toIso8601String())
        .order('checked_at', ascending: true)
        .limit(7);

    return (res as List<dynamic>)
        .map((e) => RankHistory.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
