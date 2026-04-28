import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────
// 커스텀 예외
// ─────────────────────────────────────────────────────────────────

/// 순위 조회 API 타임아웃 (10초 초과)
class RankTimeoutException implements Exception {
  const RankTimeoutException();
}

/// 해당 키워드에서 상품을 찾을 수 없음 (rank=null 응답)
class RankNotFoundException implements Exception {
  const RankNotFoundException();
}

/// API 서버 오류 (4xx/5xx) 또는 RANK_API_URL 미설정
class RankApiException implements Exception {
  final int statusCode;
  const RankApiException(this.statusCode);
}

/// 네트워크 연결 오류
class RankNetworkException implements Exception {
  final Object cause;
  const RankNetworkException(this.cause);
}

// ─────────────────────────────────────────────────────────────────
// 순위 조회 결과 모델
// ─────────────────────────────────────────────────────────────────

class RankResult {
  final int     rank;
  final String  productName;
  final String? thumbnailUrl;

  const RankResult({
    required this.rank,
    required this.productName,
    this.thumbnailUrl,
  });
}

// ─────────────────────────────────────────────────────────────────
// 파이썬 랭킹 모듈 HTTP 클라이언트
// ─────────────────────────────────────────────────────────────────
//
// 환경변수 주입:
//   flutter run   --dart-define=RANK_API_URL=https://your-rank-api.example.com/rank
//   flutter build --dart-define=RANK_API_URL=https://your-rank-api.example.com/rank
//
// API 스펙:
//   GET {RANK_API_URL}?url={product_url}&keyword={keyword}
//   성공:     {"rank": 7,    "product_name": "상품명", "thumbnail_url": "https://..."}
//   미노출:   {"rank": null, "product_name": "...",   "thumbnail_url": "..."}
// ─────────────────────────────────────────────────────────────────

class RankApiClient {
  static const _baseUrl =
      String.fromEnvironment('RANK_API_URL', defaultValue: '');

  static const _timeout = Duration(seconds: 10);

  /// 상품 URL + 키워드로 네이버 쇼핑 순위를 조회합니다.
  ///
  /// Throws:
  ///   [RankNotFoundException]  — rank=null (해당 키워드에서 상품 미노출)
  ///   [RankTimeoutException]   — 10초 타임아웃 초과
  ///   [RankApiException]       — 4xx/5xx 서버 오류 또는 RANK_API_URL 미설정
  ///   [RankNetworkException]   — 네트워크 연결 오류
  Future<RankResult> fetchRank(String productUrl, String keyword) async {
    if (_baseUrl.isEmpty) {
      throw const RankApiException(0); // RANK_API_URL 미설정
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'url':     productUrl,
        'keyword': keyword,
      },
    );

    late http.Response response;
    try {
      response = await http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const RankTimeoutException();
    } catch (e) {
      throw RankNetworkException(e);
    }

    if (response.statusCode != 200) {
      throw RankApiException(response.statusCode);
    }

    late Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const RankApiException(-1); // JSON 파싱 실패
    }

    final rank = body['rank'] as int?;
    if (rank == null) throw const RankNotFoundException();

    return RankResult(
      rank:         rank,
      productName:  (body['product_name'] as String?) ?? '',
      thumbnailUrl: body['thumbnail_url'] as String?,
    );
  }
}
