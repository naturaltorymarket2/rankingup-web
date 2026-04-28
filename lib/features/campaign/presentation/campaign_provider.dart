import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/campaign_repository.dart';
import '../domain/campaign_model.dart';

// ─────────────────────────────────────────────────────────────────
// 캠페인 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (_) => CampaignRepository(),
);

/// 현재 로그인 유저의 포인트 잔액
///
/// Step 3 결제 확인 화면에서 실시간 잔액 표시에 사용
final walletBalanceProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.read(campaignRepositoryProvider).fetchBalance();
});

/// 캠페인 상세 정보 (campaigns 테이블)
final campaignDetailProvider =
    FutureProvider.autoDispose.family<CampaignModel, String>(
  (ref, campaignId) =>
      ref.read(campaignRepositoryProvider).fetchCampaignDetail(campaignId),
);

/// 캠페인 미션 통계 (오늘/누적 성공 건수, 현재 순위)
final campaignStatsProvider =
    FutureProvider.autoDispose.family<CampaignStats, String>(
  (ref, campaignId) =>
      ref.read(campaignRepositoryProvider).fetchCampaignStats(campaignId),
);
