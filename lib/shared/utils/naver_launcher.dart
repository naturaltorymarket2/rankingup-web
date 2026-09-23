import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────
// 네이버 앱 실행
// ─────────────────────────────────────────────────────────────────
//
// 커스텀 스킴(naversearchapp://)만으로는 네이버 앱이 꺼져 있을 때
// 실행되지 않는 기기가 있다. 앱이 이미 떠 있을 때만 동작하는 것처럼
// 보이던 문제가 이것이다.
//
// 그래서 안드로이드에서는 패키지를 직접 지정한 인텐트로 강제 실행하고,
// 그것도 실패하면 브라우저(또는 App Link 로 네이버 앱)로 넘긴다.

/// 네이버 앱 패키지명
const _naverPackage = 'com.nhn.android.search';

/// 검색 결과로 이동한다. 성공하면 true.
///
/// 순서: 패키지 지정 인텐트 → 커스텀 스킴 → 웹 검색
Future<bool> openNaverSearch(String keyword) async {
  if (keyword.isEmpty) return false;

  final encoded = Uri.encodeQueryComponent(keyword);
  final scheme  = 'naversearchapp://search?query=$encoded';
  final webUrl  = 'https://search.naver.com/search.naver?query=$encoded';

  // 1. 패키지를 직접 지정해 네이버 앱을 깨운다 (꺼져 있어도 실행된다)
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await AndroidIntent(
        action:  'action_view',
        data:    scheme,
        package: _naverPackage,
      ).launch();
      return true;
    } catch (_) {
      // 네이버 앱이 없거나 인텐트가 거부된 경우 — 아래로 넘어간다
    }
  }

  // 2. 커스텀 스킴 (다른 플랫폼 / 인텐트 실패 시)
  try {
    final ok = await launchUrl(
      Uri.parse(scheme),
      mode: LaunchMode.externalApplication,
    );
    if (ok) return true;
  } catch (_) {
    // 아래 웹으로 넘어간다
  }

  // 3. 웹 검색 — 네이버 앱이 없어도 미션을 이어갈 수 있게 한다
  try {
    return await launchUrl(
      Uri.parse(webUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
