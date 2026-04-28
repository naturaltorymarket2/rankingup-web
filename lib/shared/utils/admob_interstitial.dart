import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_config.dart';

// ─────────────────────────────────────────────────────────────────
// 전면 광고 관리자 (정적 클래스)
// ─────────────────────────────────────────────────────────────────
//
// 사용 패턴:
//   1. 미리 로드:  AdmobInterstitial.load()     — fire and forget
//   2. 노출:       AdmobInterstitial.showAd(onDismissed: () => ...)
//
// - 광고 미로드 시 showAd는 onDismissed 콜백을 즉시 실행 (앱 흐름 유지)
// - 로드 실패는 무시 — 전면 광고 미노출로 처리

class AdmobInterstitial {
  AdmobInterstitial._(); // 인스턴스화 방지

  static InterstitialAd? _ad;

  /// 전면 광고 미리 로드 (fire and forget — await 불필요)
  static void load() {
    if (_ad != null) return; // 이미 로드됨
    try {
      InterstitialAd.load(
        adUnitId: AdmobConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _ad = ad,
          onAdFailedToLoad: (_) {}, // 로드 실패는 무시
        ),
      );
    } catch (_) {}
  }

  /// 전면 광고 노출
  ///
  /// - 광고가 준비된 경우: 광고 노출 → 닫힘/실패 시 [onDismissed] 호출
  /// - 광고가 없는 경우:  [onDismissed] 즉시 호출 (앱 흐름 보장)
  static void showAd({required void Function() onDismissed}) {
    final ad = _ad;
    _ad = null; // 소비 후 즉시 해제

    if (ad == null) {
      onDismissed();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        onDismissed();
      },
    );

    ad.show();
  }
}
