import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/admob_banner.dart';
import '../../wallet/presentation/wallet_provider.dart';
import '../domain/mission_model.dart';
import 'mission_home_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 홈 — 미션 보드 (무한 스크롤)
// ─────────────────────────────────────────────────────────────────

class MissionHomeScreen extends ConsumerStatefulWidget {
  const MissionHomeScreen({super.key});

  @override
  ConsumerState<MissionHomeScreen> createState() =>
      _MissionHomeScreenState();
}

/// 미션 보드 필터
enum MissionFilter { all, available, done }

class _MissionHomeScreenState extends ConsumerState<MissionHomeScreen> {
  final _scrollController = ScrollController();

  /// 참여가능 / 참여완료 필터 (기본: 전체)
  MissionFilter _filter = MissionFilter.all;

  List<CampaignMissionModel> _applyFilter(List<CampaignMissionModel> list) =>
      switch (_filter) {
        MissionFilter.all       => list,
        MissionFilter.available => list.where((m) => !m.isParticipatedToday).toList(),
        MissionFilter.done      => list.where((m) => m.isParticipatedToday).toList(),
      };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 하단 200px 이내에 도달하면 다음 페이지 요청
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(missionHomeProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final missionState = ref.watch(missionHomeProvider);
    final balanceAsync = ref.watch(walletBalanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('미션 보드'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () =>
                ref.read(missionHomeProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 포인트 잔액 헤더 ──────────────────────────────────
          _BalanceHeader(balanceAsync: balanceAsync),

          // ── 참여가능 / 참여완료 필터 ──────────────────────────
          _FilterBar(
            current: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),

          // ── 미션 목록 ─────────────────────────────────────────
          Expanded(
            child: missionState.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),

              error: (err, _) => _ErrorView(
                message: err.toString(),
                onRetry: () =>
                    ref.read(missionHomeProvider.notifier).refresh(),
              ),

              data: (state) {
                if (state.missions.isEmpty) {
                  return const _EmptyMissionsView();
                }

                final missions = _applyFilter(state.missions);
                if (missions.isEmpty) {
                  return _FilteredEmptyView(filter: _filter);
                }

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(missionHomeProvider.notifier).refresh(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    // 로딩 중일 때 마지막에 스피너 아이템 추가
                    itemCount: missions.length +
                        (state.isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= missions.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return _MissionCard(mission: missions[index]);
                    },
                  ),
                );
              },
            ),
          ),

          // ── 배너 광고 (하단 고정) ──────────────────────────────
          const AdmobBanner(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 참여가능 / 참여완료 필터 바
// ─────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final MissionFilter current;
  final ValueChanged<MissionFilter> onChanged;

  const _FilterBar({required this.current, required this.onChanged});

  static const _labels = {
    MissionFilter.all:       '전체',
    MissionFilter.available: '참여가능',
    MissionFilter.done:      '참여완료',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: MissionFilter.values.map((f) {
          final selected = f == current;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_labels[f]!),
              selected: selected,
              onSelected: (_) => onChanged(f),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.grey[700],
              ),
              selectedColor: const Color(0xFF1E3A8A),
              backgroundColor: Colors.grey[100],
              side: BorderSide(
                color: selected ? const Color(0xFF1E3A8A) : Colors.grey[300]!,
              ),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 필터 결과가 없을 때
// ─────────────────────────────────────────────────────────────────

class _FilteredEmptyView extends StatelessWidget {
  final MissionFilter filter;
  const _FilteredEmptyView({required this.filter});

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      MissionFilter.available => '지금 참여할 수 있는 미션이 없습니다.\n내일 다시 확인해주세요.',
      MissionFilter.done      => '오늘 참여한 미션이 없습니다.',
      MissionFilter.all       => '미션이 없습니다.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], height: 1.6),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 포인트 잔액 헤더
// ─────────────────────────────────────────────────────────────────

class _BalanceHeader extends StatelessWidget {
  final AsyncValue<int> balanceAsync;

  const _BalanceHeader({required this.balanceAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.indigo,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            '내 포인트',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const Spacer(),
          balanceAsync.when(
            loading: () => const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            error: (_, __) => const Text(
              '-- P',
              style: TextStyle(color: Colors.white70),
            ),
            data: (balance) => Text(
              '${_formatPoints(balance)} P',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 천 단위 쉼표 포맷 (intl 패키지 미사용)
  static String _formatPoints(int points) {
    return points.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 미션 카드
// ─────────────────────────────────────────────────────────────────

class _MissionCard extends StatelessWidget {
  final CampaignMissionModel mission;

  const _MissionCard({required this.mission});

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    // 오늘 이미 참여한 미션(완료/진행중)은 목록에 남기되 흐리게 표시하고 탭을 막는다.
    // 서버가 재참여를 거부하므로 눌러도 오류만 나기 때문이다.
    final isCompleted = mission.isParticipatedToday;
    final isFull      = !isCompleted && mission.todayRemaining == 0; // A-010
    final isAlmostFull = !isFull && !isCompleted && mission.todayProgressRatio > 0.8;
    final progressColor = (isFull || isCompleted)
        ? Colors.grey.shade400
        : (isAlmostFull ? Colors.red.shade400 : Colors.indigo);

    return Opacity(
      opacity: isCompleted ? 0.5 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: (isFull || isCompleted)
              ? null
              : () => context.push('/mission/${mission.campaignId}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 키워드 + 뱃지 ──────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        mission.keyword,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: (isFull || isCompleted)
                              ? Colors.grey.shade400
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isCompleted)
                      _CompletedBadge(isDone: mission.isCompleted)
                    else if (isFull)
                      const _SoldOutBadge()
                    else
                      const _RewardBadge(),
                  ],
                ),

                const SizedBox(height: 12),

                // ── 달성 현황 텍스트 ──────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '오늘 ${mission.todaySuccessCount}/${mission.dailyTarget}명 참여',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      isCompleted
                          ? (mission.isCompleted ? '오늘 미션완료' : '진행 중 — 앱에서 정답 입력')
                          : (isFull
                              ? '오늘 마감'
                              : '${mission.todayRemaining}명 남음'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isCompleted
                            ? Colors.grey.shade500
                            : (isFull
                                ? Colors.grey.shade500
                                : (isAlmostFull
                                    ? Colors.red.shade600
                                    : Colors.green.shade700)),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // ── 달성률 게이지 바 ──────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: mission.todayProgressRatio,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    minHeight: 7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 참여완료 뱃지
class _CompletedBadge extends StatelessWidget {
  /// 정답까지 마쳤으면 '미션완료', 시작만 했으면 '진행중'
  final bool isDone;
  const _CompletedBadge({this.isDone = true});

  @override
  Widget build(BuildContext context) {
    final color = isDone ? Colors.grey.shade500 : const Color(0xFFE65100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDone ? Colors.grey.shade100 : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDone ? Colors.grey.shade300 : const Color(0xFFFFCC80),
        ),
      ),
      child: Text(
        isDone ? '미션완료' : '진행중',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// A-010: 오늘 마감 뱃지
class _SoldOutBadge extends StatelessWidget {
  const _SoldOutBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '오늘 마감',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// 리워드 뱃지 (+7원) — 고정값
class _RewardBadge extends StatelessWidget {
  const _RewardBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Text(
        '+7원',
        style: TextStyle(
          color: Colors.indigo.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 빈 목록 상태
// ─────────────────────────────────────────────────────────────────

class _EmptyMissionsView extends StatelessWidget {
  const _EmptyMissionsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '진행 중인 미션이 없습니다',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '잠시 후 다시 확인해 주세요',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 에러 상태
// ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text(
              '미션 목록을 불러오지 못했습니다',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
