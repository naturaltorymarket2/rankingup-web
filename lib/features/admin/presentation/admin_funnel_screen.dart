import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';

// ─────────────────────────────────────────────────────────────────
// 미션 이탈 지점 (/admin/funnel)
// ─────────────────────────────────────────────────────────────────
//
// '완주율이 낮다'만으로는 무엇을 고쳐야 할지 알 수 없다.
// 단계별로 몇 명이 남았는지 보면 어디서 빠지는지가 드러난다.
//
//   상세 열람 → 미션 시작 → 네이버 이동 → 앱 복귀 → 태그 제출 → 적립
//
// 예) '네이버 이동'은 많은데 '앱 복귀'가 적다  → 딥링크나 복귀 안내 문제
//     '앱 복귀'는 많은데 '태그 제출'이 적다    → 상품을 못 찾는 문제

final _funnelDaysProvider = StateProvider.autoDispose<int>((ref) => 7);

final _funnelProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final days = ref.watch(_funnelDaysProvider);
  final res = await supabase.rpc('get_mission_funnel', params: {'p_days': days});
  return Map<String, dynamic>.from(res as Map);
});

class AdminFunnelScreen extends ConsumerWidget {
  const AdminFunnelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(_funnelProvider);
    final days      = ref.watch(_funnelDaysProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('미션 이탈 지점'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/admin/campaign'),
            icon:  const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('광고 승인'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  const Text('집계 기간',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 14),
                  for (final d in [1, 7, 30]) ...[
                    ChoiceChip(
                      label: Text(d == 1 ? '오늘' : '최근 $d일'),
                      selected: days == d,
                      onSelected: (_) =>
                          ref.read(_funnelDaysProvider.notifier).state = d,
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  IconButton(
                    onPressed: () => ref.invalidate(_funnelProvider),
                    icon: const Icon(Icons.refresh),
                    tooltip: '새로고침',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              asyncData.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _Box(
                  color: const Color(0xFFFEF2F2),
                  border: const Color(0xFFFECACA),
                  child: Text('불러오지 못했습니다: $e',
                      style: TextStyle(color: Colors.red.shade900)),
                ),
                data: (data) {
                  if (data['success'] != true) {
                    return _Box(
                      color: const Color(0xFFFEF2F2),
                      border: const Color(0xFFFECACA),
                      child: Text(
                        data['error'] == 'FORBIDDEN'
                            ? '관리자만 볼 수 있습니다.'
                            : '오류: ${data['error']}',
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    );
                  }
                  return _FunnelBody(data: data);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FunnelBody extends StatelessWidget {
  final Map<String, dynamic> data;

  const _FunnelBody({required this.data});

  static const _labels = {
    'VIEW_DETAIL':  '상세 열람',
    'START':        '미션 시작',
    'LAUNCH_NAVER': '네이버 이동',
    'RETURN_APP':   '앱 복귀',
    'SUBMIT':       '태그 제출',
    'SUCCESS':      '적립 완료',
  };

  /// 각 단계에서 다음 단계로 못 넘어갔을 때 볼 곳
  static const _hints = {
    'START':        '미션 시작 버튼을 누르지 않고 나갔습니다. 보상·난이도 안내를 살펴보세요.',
    'LAUNCH_NAVER': '네이버 앱이 열리지 않았을 수 있습니다. 기기별 딥링크 문제를 의심하세요.',
    'RETURN_APP':   '네이버에서 돌아오지 않았습니다. 복귀 안내가 잘 보이는지 확인하세요.',
    'SUBMIT':       '돌아왔지만 태그를 넣지 않았습니다. 상품을 못 찾았을 가능성이 큽니다.',
    'SUCCESS':      '제출했지만 적립되지 않았습니다. 오답이 많다는 뜻입니다.',
  };

  @override
  Widget build(BuildContext context) {
    final steps = (data['steps'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    if (steps.isEmpty || steps.every((s) => (s['mission_count'] ?? 0) == 0)) {
      return const _Box(
        color: Color(0xFFF8FAFC),
        border: Color(0xFFE5E7EB),
        child: Text(
          '아직 기록이 없습니다.\n'
          '앱에서 미션을 진행하면 단계별로 쌓입니다.',
          style: TextStyle(height: 1.6),
        ),
      );
    }

    int countOf(String step) {
      final row = steps.firstWhere((s) => s['step'] == step,
          orElse: () => <String, dynamic>{});
      // 미션 단위(log_id)가 없는 단계(상세 열람)는 건수로 센다
      final byMission = (row['mission_count'] as num?)?.toInt() ?? 0;
      final byEvent   = (row['event_count']   as num?)?.toInt() ?? 0;
      return byMission > 0 ? byMission : byEvent;
    }

    final order = _labels.keys.toList();
    final first = countOf(order.first);
    final wrong = (data['wrong_tag_count'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Box(
          color: Colors.white,
          border: const Color(0xFFE5E7EB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < order.length; i++) ...[
                _StepRow(
                  label:   _labels[order[i]]!,
                  count:   countOf(order[i]),
                  ratio:   first == 0 ? 0 : countOf(order[i]) / first,
                  dropped: i == 0 ? 0 : countOf(order[i - 1]) - countOf(order[i]),
                  hint:    i == 0 ? null : _hints[order[i]],
                ),
                if (i < order.length - 1) const SizedBox(height: 4),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        _Box(
          color: const Color(0xFFF8FAFC),
          border: const Color(0xFFE5E7EB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('오답 입력 $wrong회',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '제출 대비 오답이 많으면 태그가 잘못 등록됐거나, '
                '유저가 다른 상품(같은 판매자의 용량 다른 상품 등)을 보고 있을 수 있습니다.',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '최근 ${data['days']}일 기준 · 숫자는 해당 단계까지 도달한 미션 수입니다.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String  label;
  final int     count;
  final double  ratio;
  final int     dropped;
  final String? hint;

  const _StepRow({
    required this.label,
    required this.count,
    required this.ratio,
    required this.dropped,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0, 1),
                  minHeight: 26,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation(
                    Color.lerp(const Color(0xFF1E3A8A),
                        const Color(0xFF60A5FA), 1 - ratio)!,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Text(
                '$count건 · ${(ratio * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        if (dropped > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 90),
            child: Text(
              '↓ 여기서 $dropped건 이탈${hint == null ? '' : ' — $hint'}',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        ],
      ],
    );
  }
}

class _Box extends StatelessWidget {
  final Color  color;
  final Color  border;
  final Widget child;

  const _Box({required this.color, required this.border, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}
