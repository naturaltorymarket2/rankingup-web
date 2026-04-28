import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기기 고유 ID 반환
///
/// - Android: Android ID (기기+계정 조합 고유값)
/// - iOS    : identifierForVendor
/// - Web/기타: SharedPreferences에 저장된 임의 생성 ID
///
/// 어뷰징 방지용으로 Supabase RPC에 전달하며,
/// 동일 device_id 중복 계정 차단은 start_mission RPC에서 처리.
Future<String> getDeviceId() async {
  if (kIsWeb) {
    return _getOrCreateStoredId();
  }

  final plugin = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final info = await plugin.androidInfo;
    return info.id; // Android ID
  }

  if (Platform.isIOS) {
    final info = await plugin.iosInfo;
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
