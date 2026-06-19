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

  /// 캠페인 등록 RPC 호출 (그룹 과금 구조)
  ///
  /// register_campaign(p_user_id, p_product_url, p_keyword,
  ///                   p_daily_target, p_group_daily_target, p_group_id,
  ///                   p_start_date, p_end_date,
  ///                   p_tags, p_sort_orders, p_answer_index, p_seed_keyword)
  /// 성공 시 campaign_id(String) 반환, 실패 시 Exception throw
  Future<String> registerCampaign({
    required String       userId,
    required String       productUrl,
    required String       keyword,
    required int          dailyTarget,      // 서브키워드별 분배된 일일 목표
    required int          groupDailyTarget, // 그룹 전체 일일 목표 (과금 기준)
    required String       groupId,          // 그룹 식별자 UUID (클라이언트 생성)
    required DateTime     startDate,
    required DateTime     endDate,
    required List<String> tags,
    required List<int>    sortOrders,  // 각 태그의 실제 네이버 상품 페이지 순서값
    required int          answerIndex, // 정답 태그의 실제 순서값 (sortOrders 배열 내 값 중 하나)
    String?               seedKeyword,
    String?               productName,
    String?               brandName,
  }) async {
    final res = await supabase.rpc('register_campaign', params: {
      'p_user_id':            userId,
      'p_product_url':        productUrl,
      'p_keyword':            keyword,
      'p_daily_target':       dailyTarget,
      'p_group_daily_target': groupDailyTarget,
      'p_group_id':           groupId,
      'p_start_date':         _toDateStr(startDate),
      'p_end_date':           _toDateStr(endDate),
      'p_tags':               tags,
      'p_sort_orders':        sortOrders,
      'p_answer_index':       answerIndex,
      'p_seed_keyword':       seedKeyword,
      'p_product_name':       productName,
      'p_brand_name':         brandName,
    }) as Map<String, dynamic>;

    if (res['success'] != true) {
      throw Exception(res['error'] ?? 'UNKNOWN_ERROR');
    }
    return res['campaign_id'] as String;
  }

  /// 캠페인 상세 정보 조회 (campaigns 테이블)
  ///
  /// group_id가 있으면 그룹 내 전체 서브키워드도 함께 조회하여 반환
  Future<CampaignModel> fetchCampaignDetail(String campaignId) async {
    final res = await supabase
        .from('campaigns')
        .select()
        .eq('id', campaignId)
        .single() as Map<String, dynamic>;

    final groupId = res['group_id'] as String?;
    List<String> subKeywords = const [];
    if (groupId != null) {
      final groupRes = await supabase
          .from('campaigns')
          .select('keyword')
          .eq('group_id', groupId) as List<dynamic>;
      subKeywords = groupRes
          .map((c) => (c as Map<String, dynamic>)['keyword'] as String)
          .toList();
    }

    return CampaignModel.fromMap(res, subKeywords: subKeywords);
  }

  /// 캠페인 미션 통계 조회 (그룹 전체 합산)
  ///
  /// group_id가 있으면 그룹 내 전체 campaign_id 기준으로 mission_logs 합산
  /// campaign_rank_history에서 현재 순위 조회 (representativeCampaignId 기준)
  Future<CampaignStats> fetchCampaignStats(String campaignId) async {
    // KST 자정 계산 (UTC+9)
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final kstMidnight = DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
        .subtract(const Duration(hours: 9));

    // 1. 해당 캠페인의 group_id 조회
    final campaignRes = await supabase
        .from('campaigns')
        .select('group_id')
        .eq('id', campaignId)
        .single() as Map<String, dynamic>;
    final groupId = campaignRes['group_id'] as String?;

    // 2. 그룹 내 전체 campaign_id 수집
    List<String> targetIds;
    if (groupId != null) {
      final groupRes = await supabase
          .from('campaigns')
          .select('id')
          .eq('group_id', groupId) as List<dynamic>;
      targetIds = groupRes
          .map((c) => (c as Map<String, dynamic>)['id'] as String)
          .toList();
    } else {
      targetIds = [campaignId];
    }

    // 3. 오늘 KST 기준 성공 건수 (그룹 합산)
    final todayRes = await supabase
        .from('mission_logs')
        .select('id')
        .inFilter('campaign_id', targetIds)
        .eq('status', 'SUCCESS')
        .not('completed_at', 'is', null)
        .gte('completed_at', kstMidnight.toIso8601String());
    final todaySuccess = (todayRes as List).length;

    // 4. 전체 누적 성공 건수 (그룹 합산)
    final totalRes = await supabase
        .from('mission_logs')
        .select('id')
        .inFilter('campaign_id', targetIds)
        .eq('status', 'SUCCESS');
    final totalSuccess = (totalRes as List).length;

    // 5. 현재 순위 (가장 최근 rank_history 1건 — representativeCampaignId 기준)
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
