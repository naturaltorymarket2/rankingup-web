import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기기 고유 ID 반환
///
/// - Android: ANDROID_ID (Settings.Secure.ANDROID_ID)
/// - iOS    : identifierForVendor
/// - Web/기타: SharedPreferences에 저장된 임의 생성 ID
///
/// 어뷰징 방지용으로 Supabase RPC에 전달하며,
/// 동일 device_id 중복 계정 차단은 start_mission RPC에서 처리한다.
///
/// ⚠️ 과거 버그 (2026-08-27 수정)
///   androidInfo.id 를 기기 고유값으로 사용했는데, 이 값은 ANDROID_ID가 아니라
///   **펌웨어 빌드 번호**(예: BP2A.250605.031.A3)다.
///   같은 기종·같은 업데이트를 받은 기기는 모두 같은 값이 나오므로
///     - 서로 다른 사용자가 같은 기종을 쓰면 두 번째 사용자부터 영구 차단되고
///     - 기기를 바꾸면 같은 사람이 계정을 여러 개 만들 수 있어
///   어뷰징 방지 기능이 양쪽 모두 무력화돼 있었다.
///   → ANDROID_ID 로 교체. 기기마다 고유하고 앱을 재설치해도 유지된다.
Future<String> getDeviceId() async {
  if (kIsWeb) {
    return _getOrCreateStoredId();
  }

  if (Platform.isAndroid) {
    try {
      final androidId = await const AndroidId().getId();
      if (androidId != null && androidId.trim().isNotEmpty) {
        return androidId;
      }
    } catch (_) {
      // 일부 커스텀 ROM/제조사에서 조회 실패 — 아래 폴백으로 진행
    }

    // 폴백 1: 기기 정보 조합 (빌드번호 단독보다 충돌 가능성이 낮다)
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final combined = [
        info.id,             // 빌드 번호
        info.model,
        info.device,
        info.fingerprint,
      ].where((v) => v.trim().isNotEmpty).join('|');
      if (combined.isNotEmpty) {
        return 'android:${combined.hashCode.toUnsigned(32).toRadixString(16)}';
      }
    } catch (_) {
      // 기기 정보 조회도 실패 — 최종 폴백
    }

    // 폴백 2: 로컬 저장 ID (재설치 시 값이 바뀌므로 최후 수단)
    return _getOrCreateStoredId();
  }

  if (Platform.isIOS) {
    final info = await DeviceInfoPlugin().iosInfo;
    return info.identifierForVendor ?? await _getOrCreateStoredId();
  }

  return _getOrCreateStoredId();
}

/// SharedPreferences에 ID를 저장하고 재사용
Future<String> _getOrCreateStoredId() async {
  const key = '_local_device_id';
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(key);
  if (id == null) {
    id = _randomId();
    await prefs.setString(key, id);
  }
  return id;
}

/// 32자 알파-숫자 랜덤 ID 생성
String _randomId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rng = Random.secure();
  return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
}
