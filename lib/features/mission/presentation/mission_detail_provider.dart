import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mission_repository.dart';
import '../domain/mission_model.dart';

// ─────────────────────────────────────────────────────────────────
// 캠페인 상세 조회 (FutureProvider.family)
// ─────────────────────────────────────────────────────────────────

/// campaignId를 키로 캠페인 상세를 비동기 조회
final campaignDetailProvider = FutureProvider.autoDispose
    .family<CampaignMissionModel, String>((ref, campaignId) {
  return ref.read(missionRepositoryProvider).fetchCampaignDetail(campaignId);
});

// ─────────────────────────────────────────────────────────────────
// 미션 시작 버튼 로딩 상태 (bool)
// ─────────────────────────────────────────────────────────────────

/// [미션 시작] 버튼 비활성화 제어용 isStarting 상태
///
/// true 동안 버튼 비활성화 → 중복 클릭 방지
final missionStartProvider =
    NotifierProvider.autoDispose<MissionStartNotifier, bool>(
  MissionStartNotifier.new,
);

class MissionStartNotifier extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false;

  /// start_mission RPC 호출
  ///
  /// - 호출 중 state = true (버튼 비활성화)
  /// - 성공: [StartMissionResult] 반환
  /// - 실패: [StartMissionException] throw (호출부에서 catch)
  Future<StartMissionResult> startMission({
    required String campaignId,
    required String userId,
    required String deviceId,
  }) async {
    state = true;
    try {
      return await ref.read(missionRepositoryProvider).startMission(
        campaignId: campaignId,
        userId:     userId,
        deviceId:   deviceId,
      );
    } finally {
      // 자동 dispose 후 state 접근 방지
      try {
        state = false;
      } catch (_) {}
    }
  }
}
