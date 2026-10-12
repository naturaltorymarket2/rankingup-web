import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/supabase_client.dart';

// ─────────────────────────────────────────────────────────────────
// 강제 업데이트 확인
//
// 새 버전을 올려도 기기마다 Play 스토어에 뜨는 시점이 다르다. 그동안
// 구버전 사용자는 이미 고친 버그를 계속 겪는다. 서버가 가진 '최소 버전'
// 보다 낮으면 앱이 스스로 업데이트 화면을 띄운다.
//
// 값은 app_config 테이블에 있고 운영자가 SQL 한 줄로 바꾼다.
//   SELECT public.set_min_app_version(42, true);
//
// 원칙: 확인에 실패하면 막지 않는다.
//   서버가 잠깐 안 되거나 네트워크가 끊겼다고 앱을 못 쓰게 하면 안 된다.
// ─────────────────────────────────────────────────────────────────

class AppUpdateInfo {
  /// 업데이트가 필요한지
  final bool   needsUpdate;

  /// true면 건너뛸 수 없다 (닫기 버튼 없음)
  final bool   force;
  final String storeUrl;
  final String message;

  const AppUpdateInfo({
    required this.needsUpdate,
    required this.force,
    required this.storeUrl,
    required this.message,
  });

  static const none = AppUpdateInfo(
    needsUpdate: false,
    force:       false,
    storeUrl:    '',
    message:     '',
  );
}

const String _kDefaultStoreUrl =
    'https://play.google.com/store/apps/details?id=com.storetrafficbooster.app';

/// 현재 설치된 앱이 서버가 요구하는 최소 버전보다 낮은지 확인한다.
///
/// 웹에서는 항상 [AppUpdateInfo.none] 을 돌려준다(웹은 새로고침하면
/// 최신이라 업데이트 개념이 없다).
Future<AppUpdateInfo> checkAppUpdate() async {
  if (kIsWeb) return AppUpdateInfo.none;

  try {
    final info    = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    if (current == 0) return AppUpdateInfo.none; // 버전을 못 읽으면 막지 않는다

    final row = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'android_version')
        .maybeSingle();

    final value = (row?['value'] as Map?)?.cast<String, dynamic>();
    if (value == null) return AppUpdateInfo.none;

    final minCode = (value['min_version_code'] as num?)?.toInt() ?? 0;
    if (minCode <= 0 || current >= minCode) return AppUpdateInfo.none;

    return AppUpdateInfo(
      needsUpdate: true,
      force:       value['force'] == true,
      storeUrl:    (value['store_url'] as String?) ?? _kDefaultStoreUrl,
      message:     (value['message'] as String?) ??
          '새 버전이 나왔습니다. 업데이트 후 이용해 주세요.',
    );
  } catch (_) {
    // 조회 실패는 통과시킨다 — 서버 문제로 앱을 못 쓰게 만들지 않는다
    return AppUpdateInfo.none;
  }
}
