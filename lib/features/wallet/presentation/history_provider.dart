import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet_model.dart';

// ─────────────────────────────────────────────────────────────────
// 참여 내역 상태
// ─────────────────────────────────────────────────────────────────

class HistoryState {
  final List<MissionLogModel> logs;
  final int page;
  final bool hasMore;
  final bool isLoadingMore;

  const HistoryState({
    required this.logs,
    required this.page,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  HistoryState copyWith({
    List<MissionLogModel>? logs,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return HistoryState(
      logs:          logs          ?? this.logs,
      page:          page          ?? this.page,
      hasMore:       hasMore       ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 참여 내역 프로바이더
// ─────────────────────────────────────────────────────────────────

final historyProvider =
    AsyncNotifierProvider.autoDispose<HistoryNotifier, HistoryState>(
  HistoryNotifier.new,
);

class HistoryNotifier extends AutoDisposeAsyncNotifier<HistoryState> {
  @override
  Future<HistoryState> build() async {
    final userId = supabase.auth.currentUser?.id ?? '';
    final logs   = await ref.read(walletRepositoryProvider)
        .fetchHistory(userId: userId, page: 0);
    return HistoryState(
      logs:    logs,
      page:    0,
      hasMore: logs.length == WalletRepository.pageSize,
    );
  }

  /// 다음 페이지 로드 (무한 스크롤)
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final userId   = supabase.auth.currentUser?.id ?? '';
      final nextPage = current.page + 1;
      final newLogs  = await ref.read(walletRepositoryProvider)
          .fetchHistory(userId: userId, page: nextPage);

      state = AsyncData(current.copyWith(
        logs:          [...current.logs, ...newLogs],
        page:          nextPage,
        hasMore:       newLogs.length == WalletRepository.pageSize,
        isLoadingMore: false,
      ));
    } catch (_) {
      // 에러 시 isLoadingMore 플래그 해제 (무한 스피너 방지)
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

// ─────────────────────────────────────────────────────────────────
// 이번 달 참여 요약 (건수 / 적립 포인트)
// ─────────────────────────────────────────────────────────────────

final monthlySummaryProvider =
    FutureProvider.autoDispose<({int count, int point})>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return (count: 0, point: 0);
  return WalletRepository().fetchMonthlySummary(userId);
});

// ─────────────────────────────────────────────────────────────────
// 진행 중인 미션 (이어하기용)
// ─────────────────────────────────────────────────────────────────

final activeMissionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  return WalletRepository().fetchActiveMission();
});
