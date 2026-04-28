import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/device_util.dart';
import '../domain/mission_model.dart';
import 'mission_detail_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 미션 상세 화면 (/mission/:id)
// ─────────────────────────────────────────────────────────────────

class MissionDetailScreen extends ConsumerWidget {
  final String campaignId;

  const MissionDetailScreen({super.key, required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignAsync = ref.watch(campaignDetailProvider(campaignId));
    final isStarting = ref.watch(missionStartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('미션 상세'),
        centerTitle: false,
      ),
      body: campaignAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(campaignDetailProvider(campaignId)),
        ),

        data: (campaign) => _DetailBody(
          campaign: campaign,
          isStarting: isStarting,
          onStartTapped: () => _onStartTapped(context, ref, campaign),
        ),
      ),
    );
  }

  // ── 미션 시작 버튼 액션 (순서 엄수) ─────────────────────────
  Future<void> _onStartTapped(
    BuildContext context,
    WidgetRef ref,
    CampaignMissionModel campaign,
  ) async {
    final userId   = supabase.auth.currentUser?.id ?? '';
    final deviceId = await getDeviceId();

    if (!context.mounted) return;

    // ── 1. start_mission RPC 호출 ─────────────────────────────
    StartMissionResult result;
    try {
      result = await ref.read(missionStartProvider.notifier).startMission(
        campaignId: campaignId,
        userId:     userId,
        deviceId:   deviceId,
      );
    } on StartMissionException catch (e) {
      if (context.mounted) {
        _showSnackBar(context, e.error.message);
      }
      return;
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, StartMissionError.unknown.message);
      }
      return;
    }

    // ── 2. 키워드 클립보드 복사 ───────────────────────────────
    //    실패해도 딥링크 실행은 계속 진행 (유저가 직접 키워드 입력 가능)
    try {
      await Clipboard.setData(ClipboardData(text: result.keyword));
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, '키워드를 직접 입력하세요: ${result.keyword}');
      }
    }

    // ── 3. 네이버 딥링크 실행 ─────────────────────────────────
    final encoded  = Uri.encodeComponent(result.keyword);
    final naverUri = Uri.parse(
      'naversearchapp://search?where=nexearch&query=$encoded',
    );

    bool launched = false;
    try {
      launched = await launchUrl(naverUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }

    if (!launched) {
      // 딥링크 실패 → /active 화면 이동 차단 (미션이 시작되지 않은 것과 동일)
      if (context.mounted) {
        _showSnackBar(context, '네이버 앱을 설치해주세요');
      }
      return;
    }

    // ── 4. 미션 진행 화면으로 이동 ────────────────────────────
    //      started_at: 서버 시각 기준 타이머 계산용 (UTC ISO 8601)
    if (context.mounted) {
      context.push(
        '/mission/$campaignId/active',
        extra: {
          'log_id':     result.logId,
          'keyword':    result.keyword,
          'started_at': result.startedAt.toIso8601String(),
        },
      );
    }
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 상세 바디
// ─────────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  final CampaignMissionModel campaign;
  final bool isStarting;
  final VoidCallback onStartTapped;

  const _DetailBody({
    required this.campaign,
    required this.isStarting,
    required this.onStartTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // RANK_OUT 경고 배너
                if (campaign.isRankOut) ...[
                  const _RankOutAlert(),
                  const SizedBox(height: 16),
                ],

                // 키워드 히어로 섹션
                _KeywordSection(campaign: campaign),
                const SizedBox(height: 24),

                const Divider(),
                const SizedBox(height: 20),

                // 미션 방법 안내
                const _InstructionSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // 하단 고정 시작 버튼
        _StartButton(
          isLoading: isStarting,
          onPressed: isStarting ? null : onStartTapped,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// RANK_OUT 경고 배너
// ─────────────────────────────────────────────────────────────────

class _RankOutAlert extends StatelessWidget {
  const _RankOutAlert();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '현재 상품 순위가 변동되었습니다. '
              '2~3페이지에서 상품을 찾아주세요.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 키워드 + 리워드 표시 섹션
// ─────────────────────────────────────────────────────────────────

class _KeywordSection extends StatelessWidget {
  final CampaignMissionModel campaign;

  const _KeywordSection({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 검색 키워드
        Row(
          children: [
            Icon(Icons.search, color: Colors.indigo.shade400, size: 22),
            const SizedBox(width: 8),
            Text(
              '검색 키워드',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          campaign.keyword,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade800,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 16),

        // 리워드 안내
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monetization_on_outlined,
                  color: Colors.green.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                '미션 성공 시 +7원 적립',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 오늘 달성 현황
        Text(
          '오늘 ${campaign.todaySuccessCount}/${campaign.dailyTarget}명 참여 완료',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 미션 방법 안내 (4단계 고정 문구)
// ─────────────────────────────────────────────────────────────────

class _InstructionSection extends StatelessWidget {
  const _InstructionSection();

  static const _steps = [
    '아래 [미션 시작] 버튼을 누르면 키워드가 자동 복사됩니다.',
    '네이버 앱이 열리면 복사된 키워드로 검색하세요.',
    '검색 결과에서 상품을 찾아 클릭하세요.',
    '이 앱으로 돌아와 정답을 입력하면 리워드가 지급됩니다.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '미션 방법',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        ..._steps.asMap().entries.map(
          (e) => _StepItem(step: e.key + 1, text: e.value),
        ),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  final int step;
  final String text;

  const _StepItem({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 번호 뱃지
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$step',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 미션 시작 버튼 (하단 고정)
// ─────────────────────────────────────────────────────────────────

class _StartButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _StartButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    '미션 시작',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
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
            const Text('캠페인 정보를 불러오지 못했습니다',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
