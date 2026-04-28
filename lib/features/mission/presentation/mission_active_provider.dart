import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../data/mission_repository.dart';
import '../domain/mission_model.dart';

// ─────────────────────────────────────────────────────────────────
// verify_mission RPC 호출 상태 (isVerifying)
// ─────────────────────────────────────────────────────────────────

/// [리워드 받기] 버튼 중복 클릭 방지 + RPC 결과 처리
///
/// 화면에서 직접 결과를 처리하기 때문에 state 는 isVerifying (bool) 만 관리.
/// RPC 결과는 verifyMission() 반환값으로 받아 호출부에서 처리한다.
final missionVerifyProvider =
    NotifierProvider.autoDispose<MissionVerifyNotifier, bool>(
  MissionVerifyNotifier.new,
);

class MissionVerifyNotifier extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false; // false = 대기 중

  /// verify_mission RPC 호출
  ///
  /// - 호출 중 state = true (버튼 비활성화)
  /// - 반환값: [VerifyMissionResult] (성공/오답/타임아웃/오류)
  /// - throw 하지 않음 — 호출부에서 결과 분기 처리
  Future<VerifyMissionResult> verifyMission({
    required String logId,
    required String submittedTag,
  }) async {
    state = true;
    try {
      final userId = supabase.auth.currentUser?.id ?? '';
      return await ref.read(missionRepositoryProvider).verifyMission(
        logId:        logId,
        userId:       userId,
        submittedTag: submittedTag,
      );
    } catch (_) {
      return VerifyMissionResult.error;
    } finally {
      try {
        state = false;
      } catch (_) {}
    }
  }
}
