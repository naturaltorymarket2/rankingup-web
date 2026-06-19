import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────
// 진행 중인 미션 세션 영속화 (SharedPreferences)
// ─────────────────────────────────────────────────────────────────
//
// 배경: 네이버 앱 딥링크로 이동한 뒤 OS가 백그라운드의 Flutter 프로세스를
// 종료하면, go_router의 extra(메모리)만으로는 /mission/:id/active 화면이
// 복원되지 않아 백화면이 발생한다. 딥링크 실행 성공 직후 이 데이터를
// 저장해두고, extra가 비어 있을 때 campaignId로 복원한다.
//
// 단일 키 사용 — 하루 1회 참여 제한 구조상 사용자당 진행 중인 미션은
// 항상 최대 1개이므로 충분하다. 새 미션 시작 시 이전 값을 덮어쓴다.

class MissionSessionStorage {
  static const _key = 'pending_mission';

  static Future<void> save({
    required String campaignId,
    required String logId,
    required String keyword,
    int? tagIndex,
    String? productUrl,
    String? productName,
    String? brandName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'campaign_id':  campaignId,
      'log_id':       logId,
      'keyword':      keyword,
      'tag_index':    tagIndex,
      'product_url':  productUrl,
      'product_name': productName,
      'brand_name':   brandName,
    }));
  }

  /// [campaignId]가 일치하는 저장값이 있으면 반환, 없거나 다른 캠페인이면 null.
  static Future<Map<String, dynamic>?> restore(String campaignId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['campaign_id'] != campaignId) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
