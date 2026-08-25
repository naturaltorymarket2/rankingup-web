import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_campaign_repository.dart';
import '../domain/admin_campaign_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 광고 승인 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final adminCampaignRepositoryProvider = Provider<AdminCampaignRepository>(
  (_) => AdminCampaignRepository(),
);

/// 승인 대기 광고 그룹 목록
///
/// 승인/거절 후 ref.invalidate(pendingCampaignsProvider) 로 갱신
final pendingCampaignsProvider =
    FutureProvider.autoDispose<List<AdminCampaignRecord>>((ref) {
  return ref.read(adminCampaignRepositoryProvider).fetchPendingCampaigns();
});

/// 처리 완료(승인/거절) 광고 그룹 목록 — 최근 20건
final processedCampaignsProvider =
    FutureProvider.autoDispose<List<AdminCampaignRecord>>((ref) {
  return ref.read(adminCampaignRepositoryProvider).fetchProcessedCampaigns();
});
