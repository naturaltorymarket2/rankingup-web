import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/admob_banner.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet_model.dart';
import 'history_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 참여 내역 화면 (/history)
// ─────────────────────────────────────────────────────────────────

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scrollController = ScrollController();

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

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(historyProvider.notifier).loadMore();
    }
  }

  /// 진행 중인 미션을 태그 입력 화면으로 이어서 연다.
  ///
  /// 이어하려면 log_id 와 '몇 번째 태그인지'가 필요한데 이 값은
  /// 서버(get_active_mission)에서만 받을 수 있다.
  Future<void> _resumeMission(MissionLogModel log) async {
    final mission = await WalletRepository().fetchActiveMission();
    if (!mounted) return;

    if (mission == null || mission['campaign_id'] != log.campaignId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('이어서 진행할 수 있는 미션이 없습니다.'),
        behavior: SnackBarBehavior.floating,
      ));
      ref.read(historyProvider.notifier).refresh();
      return;
    }

    context.push('/mission/${log.campaignId}/active', extra: {
      'log_id':        mission['log_id'],
      'keyword':       mission['keyword'],
      'tag_index':     mission['tag_index'],
      'product_url':   mission['product_url'],
      'product_name':  mission['product_name'],
      'brand_name':    mission['brand_name'],
      'thumbnail_url': mission['thumbnail_url'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('참여 내역'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // 이번 달 참여 요약 — "얼마 벌었는지"가 한눈에 보이도록
          _MonthlySummaryBar(summaryAsync: ref.watch(monthlySummaryProvider)),

          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),

              error: (err, _) => _ErrorView(
                onRetry: () => ref.read(historyProvider.notifier).refresh(),
              ),

              data: (state) {
                if (state.logs.isEmpty) {
                  return const _EmptyView();
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(historyProvider.notifier).refresh(),
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: state.logs.length + (state.isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (context, i) {
                      if (i == state.logs.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final log = state.logs[i];
                      return _LogCard(
                        log: log,
                        onResume: log.canResume ? () => _resumeMission(log) : null,
                      );
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
// 참여 내역 카드
// ─────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────
// 이번 달 요약 바
// ─────────────────────────────────────────────────────────────────

class _MonthlySummaryBar extends StatelessWidget {
  final AsyncValue<({int count, int point})> summaryAsync;
  const _MonthlySummaryBar({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    final summary = summaryAsync.valueOrNull;
    final count = summary?.count ?? 0;
    final point = summary?.point ?? 0;

    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F6FF),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined,
              size: 18, color: Color(0xFF1E3A8A)),
          const SizedBox(width: 8),
          Text(
            '이번 달 $count건 참여',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const Spacer(),
          Text(
            '+${point}P 적립',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final MissionLogModel log;
  final VoidCallback? onResume;
  const _LogCard({required this.log, this.onResume});

  static String _formatDate(DateTime utc) {
    final d = utc.toLocal();
    final y = d.year;
    final mo = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$y.$mo.$day $h:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = Color(log.statusColorValue);

    return InkWell(
      // 진행 중인 미션은 탭하면 이어서 진행한다
      onTap: log.canResume ? onResume : null,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // 상품 썸네일 (없으면 상태 아이콘)
          if ((log.thumbnailUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                log.thumbnailUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _StatusAvatar(
                    status: log.status, color: statusColor),
              ),
            )
          else
            _StatusAvatar(status: log.status, color: statusColor),
          const SizedBox(width: 14),

          // 키워드 + 일시
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.keyword,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((log.productName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    log.productName!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  _formatDate(log.startedAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
                // 오답으로 남아 있는 건은 이유를 알려준다
                if (log.subLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    log.subLabel!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFE65100)),
                  ),
                ],
              ],
            ),
          ),

          // 상태 + 리워드
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  log.statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (log.showReward) ...[
                const SizedBox(height: 4),
                Text(
                  '+${log.earnedPoint}P',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
              if (log.canResume) ...[
                const SizedBox(height: 4),
                const Text(
                  '이어하기 >',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ));
  }
}

// ── 상태 아이콘 (썸네일이 없을 때) ────────────────────────────────

class _StatusAvatar extends StatelessWidget {
  final String status;
  final Color  color;
  const _StatusAvatar({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        status == 'SUCCESS'
            ? Icons.check_circle_rounded
            : status == 'IN_PROGRESS'
                ? Icons.pending_rounded
                : Icons.cancel_rounded,
        color: color,
        size: 22,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 빈 상태 / 에러 상태
// ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '참여 내역이 없습니다',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '미션을 완료하면 여기에 기록됩니다',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          const Text('내역을 불러오지 못했습니다'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
