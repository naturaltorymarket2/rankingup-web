import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../domain/mission_model.dart';

final missionRepositoryProvider = Provider.autoDispose<MissionRepository>(
  (_) => MissionRepository(),
);

class MissionRepository {
  static const int pageSize = 20;

  // ─────────────────────────────────────────────────────────────
  // 내부 유틸 — KST 오늘 00:00 기준 ISO 문자열
  // ─────────────────────────────────────────────────────────────
  /// KST 기준 오늘 날짜 (YYYY-MM-DD) — start_date 비교용
  static String _kstTodayDate() {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    return '${kst.year}-'
        '${kst.month.toString().padLeft(2, '0')}-'
        '${kst.day.toString().padLeft(2, '0')}';
  }

  static String _kstTodayStartIso() {
    final now = DateTime.now().toUtc();
    final kstNow = now.add(const Duration(hours: 9));
    return DateTime(kstNow.year, kstNow.month, kstNow.day)
        .subtract(const Duration(hours: 9))
        .toIso8601String();
  }

  // ─────────────────────────────────────────────────────────────
  // 홈 미션 보드: 활성 캠페인 목록 페이지 조회
  // ─────────────────────────────────────────────────────────────

  /// 활성 캠페인 목록 (무한 스크롤 페이지 단위, group_id별 DISTINCT)
  ///
  /// - status = 'ACTIVE' + approval_status = 'APPROVED' + expires_at >= 지금
  /// - 오늘 SUCCESS 한 그룹은 isCompleted=true로 표시 (제외하지 않음)
  /// - 그룹 내 남은 슬롯이 없는 서브키워드 제외 (미완료 캠페인만)
  /// - group_id별 1개 카드 (DISTINCT — 클라이언트 처리)
  /// - 정렬: 참여가능(isCompleted=false) 먼저, 참여완료(isCompleted=true) 나중에
  /// - 보안: product_url, tag_word SELECT 금지
  Future<List<CampaignMissionModel>> fetchActiveMissions({
    required String userId,
    required int page,
  }) async {
    final now = DateTime.now().toUtc();
    final todayStartIso = _kstTodayStartIso();

    // 1. 오늘 내가 SUCCESS 한 mission_logs → group_id / campaign_id 수집
    // 오늘 내가 참여한 기록 — 성공(SUCCESS)과 진행중(IN_PROGRESS) 모두 수집.
    // 서버(start_mission)가 두 경우 모두 재참여를 막으므로 화면도 같이 구분한다.
    final myLogsRaw = await supabase
        .from('mission_logs')
        .select('campaign_id, group_id, status')
        .eq('user_id', userId)
        .inFilter('status', ['SUCCESS', 'IN_PROGRESS'])
        .gte('started_at', todayStartIso) as List<dynamic>;

    final completedGroupIds     = <String>{};
    final completedCampaignIds  = <String>{}; // group_id NULL 폴백
    final inProgressGroupIds    = <String>{};
    final inProgressCampaignIds = <String>{};

    for (final r in myLogsRaw) {
      final m        = r as Map<String, dynamic>;
      final groupId  = m['group_id'] as String?;
      final isDone   = m['status'] == 'SUCCESS';
      if (groupId != null) {
        (isDone ? completedGroupIds : inProgressGroupIds).add(groupId);
      } else {
        (isDone ? completedCampaignIds : inProgressCampaignIds)
            .add(m['campaign_id'] as String);
      }
    }

    // 2. 활성 캠페인 조회 (완료 여부 무관 포함)
    final start = page * pageSize;
    final end   = start + pageSize - 1;

    final campaignsRaw = await supabase
        .from('campaigns')
        .select('id, keyword, daily_target, group_id, status, '
                'product_name, thumbnail_url')
        .eq('status', 'ACTIVE')
        .eq('approval_status', 'APPROVED')   // 어드민 승인 완료 광고만 노출
        // 광고 시작일 전에는 노출하지 않는다.
        // 등록 당일에는 크롤링 정보(순위·썸네일)가 없어 유저가 상품을
        // 찾을 단서 없이 미션을 받게 되기 때문이다.
        .lte('start_date', _kstTodayDate())
        .gte('expires_at', now.toIso8601String())
        .range(start, end) as List<dynamic>;

    if (campaignsRaw.isEmpty) return [];

    // 3. 오늘 각 캠페인 SUCCESS 건수 일괄 조회
    final campaignIds = campaignsRaw
        .map((c) => (c as Map<String, dynamic>)['id'] as String)
        .toList();

    final logsRaw = await supabase
        .from('mission_logs')
        .select('campaign_id')
        .inFilter('campaign_id', campaignIds)
        .eq('status', 'SUCCESS')
        .gte('started_at', todayStartIso) as List<dynamic>;

    final Map<String, int> todayCounts = {};
    for (final log in logsRaw) {
      final id = (log as Map<String, dynamic>)['campaign_id'] as String;
      todayCounts[id] = (todayCounts[id] ?? 0) + 1;
    }

    // 4. 모델 구성 + 필터 + 그룹별 DISTINCT + isCompleted 분류
    final seenGroupKeys = <String>{};
    final available     = <CampaignMissionModel>[];
    final completed     = <CampaignMissionModel>[];

    for (final raw in campaignsRaw) {
      final map     = raw as Map<String, dynamic>;
      final id      = map['id'] as String;
      final groupId = map['group_id'] as String?;
      final count   = todayCounts[id] ?? 0;
      final target  = map['daily_target'] as int;

      // 참여완료 여부: group_id 기준 또는 campaign_id 폴백
      final isCompleted =
          (groupId != null && completedGroupIds.contains(groupId)) ||
          (groupId == null && completedCampaignIds.contains(id));

      // 진행중(시작만 하고 정답 미입력) 여부 — 완료가 아닌 경우에만 의미가 있다
      final isInProgress = !isCompleted &&
          ((groupId != null && inProgressGroupIds.contains(groupId)) ||
           (groupId == null && inProgressCampaignIds.contains(id)));

      // 오늘 참여하지 않은 캠페인만 일일 목표 도달 시 제외
      // (참여한 미션은 '참여완료'로 계속 보여준다)
      if (!isCompleted && !isInProgress && count >= target) continue;

      // group_id별 DISTINCT (첫 번째 등장 = 쿼리 반환 순서 기준)
      final key = groupId ?? id;
      if (!seenGroupKeys.add(key)) continue;

      final model = CampaignMissionModel.fromMap(
        map,
        todaySuccessCount: count,
        isCompleted: isCompleted,
        isInProgress: isInProgress,
      );
      if (isCompleted || isInProgress) {
        completed.add(model);
      } else {
        available.add(model);
      }
    }

    // 참여가능 먼저, 참여완료 나중에
    return [...available, ...completed];
  }

  // ─────────────────────────────────────────────────────────────
  // 미션 상세 화면: 단일 캠페인 조회
  // ─────────────────────────────────────────────────────────────

  /// 캠페인 상세 조회
  ///
  /// 보안: product_url, tag_word 절대 SELECT 금지
  Future<CampaignMissionModel> fetchCampaignDetail(String campaignId) async {
    final todayStartIso = _kstTodayStartIso();

    final campaignRaw = await supabase
        .from('campaigns')
        .select('id, keyword, daily_target, status, product_url, '
                'product_name, brand_name, thumbnail_url')
        .eq('id', campaignId)
        .single() as Map<String, dynamic>;

    final logsRaw = await supabase
        .from('mission_logs')
        .select('id')
        .eq('campaign_id', campaignId)
        .eq('status', 'SUCCESS')
        .gte('started_at', todayStartIso) as List<dynamic>;

    // 상품 위치 힌트용 최신 순위 (크롤러가 매일 수집한 미션 키워드 기준)
    // is_seed=false = 유저가 실제로 검색할 미션 키워드의 순위
    int? currentRank;
    try {
      final rankRaw = await supabase
          .from('campaign_rank_history')
          .select('rank')
          .eq('campaign_id', campaignId)
          .eq('is_seed', false)
          .order('checked_at', ascending: false)
          .limit(1) as List<dynamic>;
      if (rankRaw.isNotEmpty) {
        currentRank = (rankRaw.first['rank'] as num?)?.toInt();
      }
    } catch (_) {
      // 순위 조회 실패는 미션 진행을 막지 않는다 — 힌트만 표시되지 않음
    }

    return CampaignMissionModel.fromMap(
      {...campaignRaw, 'current_rank': currentRank},
      todaySuccessCount: logsRaw.length,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // start_mission RPC 호출
  // ─────────────────────────────────────────────────────────────

  /// start_mission RPC 호출
  ///
  /// 성공 → [StartMissionResult] 반환 (logId + keyword만)
  /// 실패 → [StartMissionException] throw
  ///
  /// 보안: 응답에 tag_word, assigned_tag_id가 있어도 절대 파싱하지 않는다
  Future<StartMissionResult> startMission({
    required String campaignId,
    required String userId,
    required String deviceId,
  }) async {
    final response = await supabase.rpc(
      'start_mission',
      params: {
        'p_campaign_id': campaignId,
        'p_user_id':     userId,
        'p_device_id':   deviceId,
      },
    ) as Map<String, dynamic>;

    if (response['success'] != true) {
      final code = response['error'] as String? ?? '';
      throw StartMissionException(_mapErrorCode(code));
    }

    // tag_word, assigned_tag_id 는 파싱하지 않음 — StartMissionResult만 추출
    return StartMissionResult.fromMap(response);
  }

  /// RPC 에러 코드 → StartMissionError 변환
  static StartMissionError _mapErrorCode(String code) => switch (code) {
    'ALREADY_PARTICIPATED_TODAY' => StartMissionError.alreadyDone,
    'DAILY_LIMIT_REACHED'        => StartMissionError.capacityFull,
    'DEVICE_ALREADY_REGISTERED'  => StartMissionError.deviceBlocked,
    _                            => StartMissionError.unknown,
  };

  // ─────────────────────────────────────────────────────────────
  // verify_mission RPC 호출
  // ─────────────────────────────────────────────────────────────

  /// verify_mission RPC 호출
  ///
  /// 성공 → VerifyMissionResult.success
  /// 오답 → VerifyMissionResult.wrongAnswer
  /// 타임아웃 → VerifyMissionResult.timeout
  /// 그 외 → VerifyMissionResult.error (throw 아님, 화면에서 처리)
  ///
  /// 보안: 응답에 tag_word / assigned_tag_id 가 있어도 절대 파싱하지 않는다
  Future<VerifyMissionResult> verifyMission({
    required String logId,
    required String userId,
    required String submittedTag,
  }) async {
    final response = await supabase.rpc(
      'verify_mission',
      params: {
        'p_log_id':        logId,
        'p_user_id':       userId,
        'p_submitted_tag': submittedTag,
      },
    ) as Map<String, dynamic>;

    if (response['success'] == true) {
      return VerifyMissionResult.success;
    }

    final errorCode = response['error'] as String? ?? '';
    return switch (errorCode) {
      'WRONG_TAG' => VerifyMissionResult.wrongAnswer,
      'TIMEOUT'   => VerifyMissionResult.timeout,
      _           => VerifyMissionResult.error,
    };
  }
}
