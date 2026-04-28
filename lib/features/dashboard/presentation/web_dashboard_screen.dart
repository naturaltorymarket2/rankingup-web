import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import '../domain/dashboard_model.dart';
import 'dashboard_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 광고주 대시보드 웹 화면  (/web/dashboard)
// ─────────────────────────────────────────────────────────────────

class WebDashboardScreen extends ConsumerStatefulWidget {
  const WebDashboardScreen({super.key});

  @override
  ConsumerState<WebDashboardScreen> createState() =>
      _WebDashboardScreenState();
}

class _WebDashboardScreenState extends ConsumerState<WebDashboardScreen> {
  String? _selectedCampaignId;

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(dashboardDataProvider);

    // 첫 로드 시 첫 번째 캠페인 자동 선택
    ref.listen<AsyncValue<DashboardData>>(dashboardDataProvider, (_, next) {
      if (next is AsyncData<DashboardData> && _selectedCampaignId == null) {
        final campaigns = next.value.campaigns;
        if (campaigns.isNotEmpty) {
          setState(() => _selectedCampaignId = campaigns.first.id);
        }
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: _buildAppBar(context),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('오류: $e',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.read(dashboardDataProvider.notifier).refresh(),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (data) => _buildBody(context, data),
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      title: const Text(
        '겟머니',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E3A8A),
          fontSize: 18,
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => context.push('/web/charge'),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('포인트 충전'),
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A8A)),
        ),
        const SizedBox(width: 2),
        TextButton.icon(
          onPressed: () => context.push('/web/transactions'),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('포인트 내역'),
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A8A)),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _confirmLogout(context),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('로그아웃'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await supabase.auth.signOut();
      if (mounted) context.go('/web/login');
    }
  }

  // ── 본문 ────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, DashboardData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummaryRow(data),
              const SizedBox(height: 24),
              _buildRankChartSection(data),
              const SizedBox(height: 24),
              _buildCampaignListSection(context, data),
            ],
          ),
        ),
      ),
    );
  }

  // ── 요약 카드 3개 ───────────────────────────────────────────

  Widget _buildSummaryRow(DashboardData data) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.account_balance_wallet_outlined,
            label: '잔여 포인트',
            value: '${_fmt(data.balance)}P',
            iconColor: const Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SummaryCard(
            icon: Icons.campaign_outlined,
            label: '진행중 광고',
            value: '${data.activeCount}건',
            iconColor: const Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SummaryCard(
            icon: Icons.people_outline,
            label: '오늘 총 유입',
            value: '${_fmt(data.todayTraffic)}명',
            iconColor: const Color(0xFFE65100),
          ),
        ),
      ],
    );
  }

  // ── 순위 차트 섹션 ──────────────────────────────────────────

  Widget _buildRankChartSection(DashboardData data) {
    final rankAsync = _selectedCampaignId != null
        ? ref.watch(rankHistoryProvider(_selectedCampaignId!))
        : const AsyncData<List<RankHistory>>([]);

    return _SectionCard(
      title: '순위 추이 (최근 7일)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.campaigns.isNotEmpty)
            DropdownButton<String>(
              value: _selectedCampaignId,
              underline: const SizedBox.shrink(),
              isDense: true,
              hint: const Text('캠페인 선택'),
              items: data.campaigns
                  .map((c) => DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(c.keyword,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedCampaignId = v),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: rankAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('오류: $e')),
              data: (history) => history.isEmpty
                  ? const _EmptyState(
                      message:
                          '순위 데이터가 없습니다.\n랭킹 모듈 연동 후 표시됩니다.')
                  : LineChart(_buildLineChartData(history)),
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildLineChartData(List<RankHistory> history) {
    // y축 반전: 1위가 상단에 오도록 rank 값을 음수로 변환
    final spots = history.asMap().entries
        .map((e) => FlSpot(
              e.key.toDouble(),
              -e.value.rank.toDouble(),
            ))
        .toList();

    final ranks = history.map((h) => h.rank).toList();
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
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
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

  // ── 캠페인 목록 섹션 ────────────────────────────────────────

  Widget _buildCampaignListSection(
      BuildContext context, DashboardData data) {
    return _SectionCard(
      title: '내 광고 목록',
      trailing: ElevatedButton.icon(
        onPressed: () => context.push('/web/campaign/new'),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('광고 등록'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      child: data.campaigns.isEmpty
          ? const _EmptyState(message: '등록된 광고가 없습니다.')
          : Column(
              children: [
                const _ColumnHeader(),
                const Divider(height: 1),
                ...data.campaigns.map(
                  (c) => _CampaignRow(
                    campaign: c,
                    onTap: () =>
                        context.push('/web/campaign/${c.id}'),
                  ),
                ),
              ],
            ),
    );
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────
// 요약 카드
// ─────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String  label;
  final String  value;
  final Color   iconColor;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 섹션 카드 (차트·목록 공통 컨테이너)
// ─────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String  title;
  final Widget? trailing;
  final Widget  child;

  const _SectionCard({
    required this.title,
    this.trailing,
    required this.child,
  });

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
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
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
// 캠페인 목록 헤더
// ─────────────────────────────────────────────────────────────────

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey[600]);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 3,
              child: Text('키워드', style: style)),
          SizedBox(
              width: 60,
              child: Text('현재 순위',
                  textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2,
              child: Text('오늘 유입',
                  textAlign: TextAlign.center, style: style)),
          SizedBox(
              width: 72,
              child: Text('상태',
                  textAlign: TextAlign.center, style: style)),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 캠페인 행
// ─────────────────────────────────────────────────────────────────

class _CampaignRow extends StatelessWidget {
  final DashboardCampaign campaign;
  final VoidCallback       onTap;

  const _CampaignRow({required this.campaign, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = campaign.dailyTarget > 0
        ? (campaign.todaySuccess / campaign.dailyTarget)
            .clamp(0.0, 1.0)
        : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            // 키워드
            Expanded(
              flex: 3,
              child: Text(
                campaign.keyword,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 현재 순위
            SizedBox(
              width: 60,
              child: Text(
                campaign.rankLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: campaign.currentRank != null
                      ? const Color(0xFF1E3A8A)
                      : Colors.grey,
                ),
              ),
            ),

            // 오늘 유입 + 프로그레스
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${campaign.todaySuccess} / ${campaign.dailyTarget}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      color: const Color(0xFF2E7D32),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),
            ),

            // 상태 뱃지
            SizedBox(
              width: 72,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: campaign.statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    campaign.statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: campaign.statusColor,
                    ),
                  ),
                ),
              ),
            ),

            // 화살표
            const Icon(Icons.chevron_right,
                size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 빈 상태 위젯
// ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.grey[500], fontSize: 14, height: 1.6),
        ),
      ),
    );
  }
}
