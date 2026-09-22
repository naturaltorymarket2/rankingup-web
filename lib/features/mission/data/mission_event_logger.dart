import '../../../app/supabase_client.dart';

// ─────────────────────────────────────────────────────────────────
// 미션 이탈 지점 기록
// ─────────────────────────────────────────────────────────────────
//
// 어디서 그만두는지 알아야 무엇을 고칠지 정할 수 있다.
// 지금까지는 '시작'과 '성공'만 알아서, 완주율이 낮아도 원인을 몰랐다.
//
// 기록은 미션 진행을 방해하면 안 된다. 그래서
//   - 결과를 기다리지 않고(await 하지 않아도 되게)
//   - 실패해도 조용히 넘어간다
// 사용자 식별은 서버(auth.uid())가 하므로 앱은 단계만 보낸다.

/// 미션 진행 단계
class MissionStep {
  static const viewDetail  = 'VIEW_DETAIL';   // 미션 상세를 열었다
  static const start       = 'START';         // 미션을 시작했다
  static const launchNaver = 'LAUNCH_NAVER';  // 네이버 앱으로 나갔다
  static const returnApp   = 'RETURN_APP';    // 앱으로 돌아왔다
  static const submit      = 'SUBMIT';        // 태그를 제출했다
  static const wrongTag    = 'WRONG_TAG';     // 오답 판정을 받았다
  static const success     = 'SUCCESS';       // 적립을 받았다

  const MissionStep._();
}

/// 단계 기록. 실패는 무시한다 — 통계 때문에 미션이 막히면 안 된다.
Future<void> logMissionEvent(
  String step, {
  String? campaignId,
  String? logId,
}) async {
  try {
    await supabase.rpc('log_mission_event', params: {
      'p_step':        step,
      'p_campaign_id': campaignId,
      'p_log_id':      logId,
    });
  } catch (_) {
    // 통계 기록 실패는 사용자에게 알리지 않는다
  }
}
