import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard_model.dart';

// ─────────────────────────────────────────────────────────────────
// 대시보드 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final _dashboardRepoProvider = Provider<DashboardRepository>(
  (_) => DashboardRepository(),
);

// ── 대시보드 전체 데이터 (요약 + 캠페인 목록) ─────────────────────

final dashboardDataProvider =
    AsyncNotifierProvider.autoDispose<DashboardDataNotifier, DashboardData>(
  DashboardDataNotifier.new,
);

class DashboardDataNotifier extends AutoDisposeAsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() => _fetch();

  Future<DashboardData> _fetch() =>
      ref.read(_dashboardRepoProvider).fetchDashboardData();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

// ── 캠페인별 순위 이력 (차트용, 드롭다운 선택 시 로드) ─────────────

final rankHistoryProvider =
    FutureProvider.autoDispose.family<List<RankHistory>, String>(
  (ref, campaignId) {
    if (campaignId.isEmpty) return Future.value([]);
    return ref.read(_dashboardRepoProvider).fetchRankHistory(campaignId);
  },
);
