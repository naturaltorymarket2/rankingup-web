import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../data/mission_repository.dart';
import '../domain/mission_model.dart';

// ─────────────────────────────────────────────────────────────────
// 상태 클래스
// ─────────────────────────────────────────────────────────────────

class MissionHomeState {
  final List<CampaignMissionModel> missions;
  final int page;
  final bool hasMore;
  final bool isLoadingMore;

  const MissionHomeState({
    required this.missions,
    required this.page,
    required this.hasMore,
    required this.isLoadingMore,
  });

  MissionHomeState copyWith({
    List<CampaignMissionModel>? missions,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return MissionHomeState(
      missions: missions ?? this.missions,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// AsyncNotifier
// ─────────────────────────────────────────────────────────────────

final missionHomeProvider = AsyncNotifierProvider.autoDispose<
    MissionHomeNotifier, MissionHomeState>(MissionHomeNotifier.new);

class MissionHomeNotifier
    extends AutoDisposeAsyncNotifier<MissionHomeState> {
  // ── 초기 로드 ──────────────────────────────────────────────────
  @override
  Future<MissionHomeState> build() => _fetchPage(page: 0, existing: const []);

  // ── 내부: 페이지 요청 ──────────────────────────────────────────
  Future<MissionHomeState> _fetchPage({
    required int page,
    required List<CampaignMissionModel> existing,
  }) async {
    final userId = supabase.auth.currentUser?.id ?? '';
    final repo = ref.read(missionRepositoryProvider);

    final fresh = await repo.fetchActiveMissions(
      userId: userId,
      page: page,
    );

    return MissionHomeState(
      missions: [...existing, ...fresh],
      page: page,
      hasMore: fresh.length >= MissionRepository.pageSize,
      isLoadingMore: false,
    );
  }

  // ── 무한 스크롤: 다음 페이지 ────────────────────────────────────
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    // 로딩 스피너용 상태 업데이트
    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final next = await _fetchPage(
        page: current.page + 1,
        existing: current.missions,
      );
      state = AsyncData(next);
    } catch (_) {
      // 추가 로드 실패 시 기존 리스트 유지, isLoadingMore 해제
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  // ── 당겨서 새로고침 ───────────────────────────────────────────
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, existing: const []),
    );
  }
}
