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

  /// 특정 캠페인의 최근 7일 순위 이력 (KST 날짜 기준 중복 제거)
  ///
  /// campaign_rank_history 직접 조회 (RLS: 본인 캠페인만)
  /// 스케줄러가 하루에 여러 번 실행되더라도 동일 날짜는 가장 최신 기록 1개만 반환
  Future<List<RankHistory>> fetchRankHistory(String campaignId) async {
    final sevenDaysAgo =
        DateTime.now().toUtc().subtract(const Duration(days: 7));

    // 최신순으로 충분히 가져온 뒤 Dart에서 KST 날짜 기준 중복 제거
    final res = await supabase
        .from('campaign_rank_history')
        .select('rank, checked_at')
        .eq('campaign_id', campaignId)
        .gte('checked_at', sevenDaysAgo.toIso8601String())
        .order('checked_at', ascending: false)
        .limit(30);

    final rows = (res as List<dynamic>)
        .map((e) => RankHistory.fromMap(e as Map<String, dynamic>))
        .toList();

    // KST 날짜별 첫 번째(최신) 항목만 유지 → 최대 7일치
    final seen = <String>{};
    final deduped = <RankHistory>[];
    for (final r in rows) {
      final kst = r.checkedAt.toUtc().add(const Duration(hours: 9));
      final dateKey =
          '${kst.year}-${kst.month.toString().padLeft(2, '0')}-${kst.day.toString().padLeft(2, '0')}';
      if (!seen.contains(dateKey)) {
        seen.add(dateKey);
        deduped.add(r);
        if (deduped.length >= 7) break;
      }
    }

    // 차트 표시를 위해 오름차순 정렬
    deduped.sort((a, b) => a.checkedAt.compareTo(b.checkedAt));
    return deduped;
  }
}
