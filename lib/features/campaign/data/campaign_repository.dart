import '../../../app/supabase_client.dart';
import '../../../shared/utils/rank_api_client.dart';
import '../domain/campaign_model.dart';

// ─────────────────────────────────────────────────────────────────
// 캠페인 데이터 접근 레이어
// ─────────────────────────────────────────────────────────────────

class CampaignRepository {
  /// 현재 로그인 유저의 포인트 잔액 조회
  Future<int> fetchBalance() async {
    final userId = supabase.auth.currentUser!.id;
    final res = await supabase
        .from('wallets')
        .select('balance')
        .eq('user_id', userId)
        .single();
    return (res['balance'] as num).toInt();
  }

  /// 상품 URL + 키워드로 현재 검색 순위 조회
  ///
  /// 반환: 순위(int) 또는 null (해당 키워드에서 상품 미노출)
  /// Throws:
  ///   RankTimeoutException  — 10초 타임아웃
  ///   RankApiException      — API 서버 오류 또는 RANK_API_URL 미설정
  ///   RankNetworkException  — 네트워크 연결 오류
  Future<int?> fetchProductRank(String productUrl, String keyword) async {
    // ── mock fallback (RANK_API_URL 미설정 시 아래 주석 해제) ────
    // await Future.delayed(const Duration(milliseconds: 800));
    // return 7; // mock 고정값
    // ─────────────────────────────────────────────────────────────
    try {
      final result =
          await RankApiClient().fetchRank(productUrl, keyword);
      return result.rank;
    } on RankNotFoundException {
      return null; // 해당 키워드에서 상품 미노출
    }
    // RankTimeoutException, RankApiException, RankNetworkException
    // 은 호출자(screen)로 전파
  }

  /// 캠페인 등록 RPC 호출
  ///
  /// register_campaign(p_user_id, p_product_url, p_keyword,
  ///                   p_daily_target, p_start_date, p_end_date, p_tags)
  /// 성공 시 campaign_id(String) 반환, 실패 시 Exception throw
  Future<String> registerCampaign({
    required String       userId,
    required String       productUrl,
    required String       keyword,
    required int          dailyTarget,
    required DateTime     startDate,
    required DateTime     endDate,
    required List<String> tags,
  }) async {
    final res = await supabase.rpc('register_campaign', params: {
      'p_user_id':       userId,
      'p_product_url':   productUrl,
      'p_keyword':       keyword,
      'p_daily_target':  dailyTarget,
      'p_start_date':    _toDateStr(startDate),
      'p_end_date':      _toDateStr(endDate),
      'p_tags':          tags,
    }) as Map<String, dynamic>;

    if (res['success'] != true) {
      throw Exception(res['error'] ?? 'UNKNOWN_ERROR');
    }
    return res['campaign_id'] as String;
  }

  /// 캠페인 상세 정보 조회 (campaigns 테이블)
  Future<CampaignModel> fetchCampaignDetail(String campaignId) async {
    final res = await supabase
        .from('campaigns')
        .select()
        .eq('id', campaignId)
        .single();
    return CampaignModel.fromMap(res);
  }

  /// 캠페인 미션 통계 조회
  ///
  /// mission_logs에서 성공 건수 집계 (RLS: 캠페인 소유자 접근 필요)
  /// campaign_rank_history에서 현재 순위 조회
  Future<CampaignStats> fetchCampaignStats(String campaignId) async {
    // KST 자정 계산 (UTC+9)
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final kstMidnight = DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
        .subtract(const Duration(hours: 9));

    // 오늘 KST 기준 성공 건수
    final todayRes = await supabase
        .from('mission_logs')
        .select('id')
        .eq('campaign_id', campaignId)
        .eq('status', 'SUCCESS')
        .gte('started_at', kstMidnight.toIso8601String());
    final todaySuccess = (todayRes as List).length;

    // 전체 누적 성공 건수
    final totalRes = await supabase
        .from('mission_logs')
        .select('id')
        .eq('campaign_id', campaignId)
        .eq('status', 'SUCCESS');
    final totalSuccess = (totalRes as List).length;

    // 현재 순위 (가장 최근 rank_history 1건)
    final rankRes = await supabase
        .from('campaign_rank_history')
        .select('rank')
        .eq('campaign_id', campaignId)
        .order('checked_at', ascending: false)
        .limit(1);
    final rankList = rankRes as List;
    final currentRank = rankList.isNotEmpty
        ? (rankList.first['rank'] as num?)?.toInt()
        : null;

    return CampaignStats(
      todaySuccess: todaySuccess,
      totalSuccess: totalSuccess,
      currentRank: currentRank,
    );
  }

  // ── 유틸 ──────────────────────────────────────────────────────

  String _toDateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
