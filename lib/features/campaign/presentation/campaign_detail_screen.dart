import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../dashboard/domain/dashboard_model.dart';
import '../../dashboard/presentation/dashboard_provider.dart';
import '../domain/campaign_model.dart';
import 'campaign_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 광고 상세 화면  (/web/campaign/:id)
// ─────────────────────────────────────────────────────────────────

class CampaignDetailScreen extends ConsumerWidget {
  final String id;

  const CampaignDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(campaignDetailProvider(id));
    final statsAsync  = ref.watch(campaignStatsProvider(id));
    final rankAsync   = ref.watch(rankHistoryProvider(id));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: _buildAppBar(context, detailAsync.valueOrNull?.keyword),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('오류: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(campaignDetailProvider(id));
                  ref.invalidate(campaignStatsProvider(id));
                  ref.invalidate(rankHistoryProvider(id));
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (campaign) => _buildBody(
          context, campaign, statsAsync, rankAsync,
        ),
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, String? keyword) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF1E3A8A)),
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go('/web/dashboard'),
      ),
      title: Text(
        keyword ?? '광고 상세',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E3A8A),
          fontSize: 18,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () => context.go('/web/dashboard'),
          child: const Text(
            '대시보드',
            style: TextStyle(color: Color(0xFF1E3A8A)),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Body ─────────────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    CampaignModel campaign,
    AsyncValue<CampaignStats> statsAsync,
    AsyncValue<List<RankHistory>> rankAsync,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusBar(campaign),
              const SizedBox(height: 16),
              _buildInfoCard(context, campaign),
              const SizedBox(height: 16),
              _buildStatsCard(campaign, statsAsync),
              const SizedBox(height: 16),
              _buildRankChartCard(rankAsync),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── 상태 바 (상태 배지 + 기간 + 잔여 일수) ───────────────────────

  Widget _buildStatusBar(CampaignModel campaign) {
    final statusLabel = switch (campaign.status) {
      'ACTIVE'    => '진행 중',
      'PAUSED'    => '일시 중지',
      'COMPLETED' => '종료',
      _           => campaign.status,
    };
    final statusColor = switch (campaign.status) {
      'ACTIVE'    => const Color(0xFF2E7D32),
      'PAUSED'    => const Color(0xFFE65100),
      'COMPLETED' => const Color(0xFF757575),
      _           => const Color(0xFF757575),
    };

    final start = campaign.startDate;
    final end   = campaign.endDate;
    final dateStr = (start != null && end != null)
        ? '${_dateStr(start)} ~ ${_dateStr(end)}'
        : '-';
    final remaining = end?.difference(DateTime.now()).inDays;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            dateStr,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        if (remaining != null && remaining >= 0)
          Text(
            '잔여 $remaining일',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: remaining <= 3
                  ? const Color(0xFFE65100)
                  : Colors.grey[600],
            ),
          ),
      ],
    );
  }

  // ── 캠페인 정보 카드 ─────────────────────────────────────────────

  Widget _buildInfoCard(BuildContext context, CampaignModel campaign) {
    return _SectionCard(
      title: '캠페인 정보',
      child: Column(
        children: [
          _InfoRow(label: '키워드', value: campaign.keyword, bold: true),
          const Divider(height: 24),
          _InfoRow(
            label: '일일 목표',
            value: '${_fmt(campaign.dailyTarget)}명',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: '캠페인 기간',
            value: '${campaign.durationDays}일',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: '총 예산',
            value: '${_fmt(campaign.budget)}P',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: '상품 URL',
            value: campaign.productUrl,
            isLink: true,
            onTap: () => _launchUrl(campaign.productUrl),
          ),
        ],
      ),
    );
  }

  // ── 성과 카드 ────────────────────────────────────────────────────

  Widget _buildStatsCard(
    CampaignModel campaign,
    AsyncValue<CampaignStats> statsAsync,
  ) {
    return _SectionCard(
      title: '성과 현황',
      child: statsAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '통계를 불러올 수 없습니다.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
        data: (stats) {
          final progress = campaign.dailyTarget > 0
              ? (stats.todaySuccess / campaign.dailyTarget).clamp(0.0, 1.0)
              : 0.0;
          final rankLabel = stats.currentRank != null
              ? '${stats.currentRank}위'
              : '데이터 없음';
          final rankColor = stats.currentRank != null
              ? (stats.currentRank! <= 15
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFB71C1C))
              : Colors.grey;

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      label: '오늘 유입',
                      value: '${stats.todaySuccess} / ${campaign.dailyTarget}',
                      sub: '달성률 ${(progress * 100).toInt()}%',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      label: '현재 검색 순위',
                      value: rankLabel,
                      valueColor: rankColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      label: '누적 총 유입',
                      value: '${_fmt(stats.totalSuccess)}명',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '일일 달성률',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    color: const Color(0xFF2E7D32),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 순위 추이 차트 카드 ──────────────────────────────────────────

  Widget _buildRankChartCard(AsyncValue<List<RankHistory>> rankAsync) {
    return _SectionCard(
      title: '순위 추이 (최근 7일)',
      child: SizedBox(
        height: 220,
        child: rankAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Center(child: Text('오류: $e',
                  style: const TextStyle(color: Colors.red))),
          data: (history) => history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      '순위 데이터가 없습니다.\n랭킹 모듈 연동 후 표시됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                          height: 1.6),
                    ),
                  ),
                )
              : LineChart(_buildLineChartData(history)),
        ),
      ),
    );
  }

  LineChartData _buildLineChartData(List<RankHistory> history) {
    // y축 반전: 1위가 상단에 오도록 rank를 음수로 변환
    final spots = history.asMap().entries
        .map((e) => FlSpot(
              e.key.toDouble(),
              -e.value.rank.toDouble(),
            ))
        .toList();

    final ranks  = history.map((h) => h.rank).toList();
    final maxRank = ranks.reduce((a, b) => a > b ? a : b);
    final minRank = ranks.reduce((a, b) => a < b ? a : b);

    return LineChartData(
      minX: 0,
      maxX: (history.length - 1).toDouble(),
      minY: -(maxRank + 1).toDouble(),
      maxY: -(minRank - 1).toDouble(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey[200]!, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (value, _) {
              final rank = (-value).toInt();
              if (rank <= 0) return const SizedBox.shrink();
              return Text('$rank위',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[600]));
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (value, _) {
              final idx = value.toInt();
              if (idx < 0 || idx >= history.length) {
                return const SizedBox.shrink();
              }
              final date = history[idx].checkedAt.toLocal();
              return Text('${date.month}/${date.day}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[600]));
            },
          ),
        ),
        rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: const Color(0xFF1E3A8A),
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, barIndex, bar, spotIndex) => FlDotCirclePainter(
              radius: 4,
              color: const Color(0xFF1E3A8A),
              strokeWidth: 2,
              strokeColor: Colors.white,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF1E3A8A).withOpacity(0.08),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFF1E3A8A),
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    '${(-s.y).toInt()}위',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ── 유틸 ─────────────────────────────────────────────────────────

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _dateStr(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// 섹션 카드 컨테이너
// ─────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 정보 행 (라벨 + 값)
// ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String     label;
  final String     value;
  final bool       bold;
  final bool       isLink;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.label,
    required this.value,
    this.bold   = false,
    this.isLink = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: isLink
              ? GestureDetector(
                  onTap: onTap,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E3A8A),
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        bold ? FontWeight.w600 : FontWeight.normal,
                    color: const Color(0xFF111827),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 통계 박스
// ─────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String  label;
  final String  value;
  final String? sub;
  final Color?  valueColor;

  const _StatBox({
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor ?? const Color(0xFF111827),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey[500])),
          ],
        ],
      ),
    );
  }
}
