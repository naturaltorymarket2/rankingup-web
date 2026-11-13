import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 키워드 자동완성 진행 창
//
// 순위 조회는 키워드 하나당 몇 초씩 걸려 전체로는 10~40초가 된다.
// 버튼 안 작은 스피너만 돌면 광고주는 멈춘 줄 알고 화면을 떠난다.
//
// 진행률은 **실제로 끝난 조회 수**로 계산한다(가짜 애니메이션 아님).
// 그래서 서버 호출을 셋으로 나눠 둔다:
//   1단계 상품·스토어 정보 확인   (/keywords/candidates)
//   2단계 추천 키워드 후보 생성   (같은 응답에서 목록을 받는다)
//   3단계 후보별 순위 조회        (/rank 를 키워드마다, 여기서 대부분의 시간이 간다)
// ─────────────────────────────────────────────────────────────────

enum KeywordStep { product, candidates, ranking, done }

class KeywordProgress {
  final KeywordStep step;

  /// 3단계에서 지금까지 조회를 마친 키워드 수
  final int checked;

  /// 3단계에서 조회할 전체 키워드 수 (후보를 받기 전에는 0)
  final int total;

  /// 지금 조회 중인 키워드 (표시용)
  final String current;

  const KeywordProgress({
    this.step = KeywordStep.product,
    this.checked = 0,
    this.total = 0,
    this.current = '',
  });

  /// 0.0 ~ 1.0
  ///
  /// 1·2단계에 25%를 주고, 나머지 75%를 조회 진행도에 비례해 채운다.
  /// 후보 수를 알기 전에는 조회 몫을 0으로 둔다 — 모르는 값을 지어내지 않는다.
  double get value {
    switch (step) {
      case KeywordStep.product:
        return 0.08;
      case KeywordStep.candidates:
        return 0.25;
      case KeywordStep.ranking:
        if (total <= 0) return 0.25;
        return 0.25 + 0.75 * (checked / total);
      case KeywordStep.done:
        return 1.0;
    }
  }

  String get label => switch (step) {
        KeywordStep.product    => '상품 및 스토어 정보 가져오는 중',
        KeywordStep.candidates => '추천 유입키워드 자동 생성',
        KeywordStep.ranking    => total > 0
            ? '추천 유입키워드 순위 조회 ($checked/$total)'
            : '추천 유입키워드 순위 조회',
        KeywordStep.done       => '완료',
      };
}

/// 진행 창을 띄운다. 진행 상태는 [progress] 로 갱신하고,
/// 작업이 끝나면 호출한 쪽에서 창을 닫는다.
Future<void> showKeywordProgressDialog(
  BuildContext context, {
  required ValueListenable<KeywordProgress> progress,
  required VoidCallback onCancel,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _KeywordProgressDialog(
      progress: progress,
      onCancel: onCancel,
    ),
  );
}

class _KeywordProgressDialog extends StatelessWidget {
  final ValueListenable<KeywordProgress> progress;
  final VoidCallback onCancel;

  const _KeywordProgressDialog({
    required this.progress,
    required this.onCancel,
  });

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    // 뒤로가기로 닫으면 작업은 도는데 창만 사라져 상태를 알 수 없다.
    // 닫으려면 [취소]를 쓰게 한다.
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
            child: ValueListenableBuilder<KeywordProgress>(
              valueListenable: progress,
              builder: (context, p, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('키워드 자동완성',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kBlue)),
                  const SizedBox(height: 6),
                  const Text('잠시만 기다려 주세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    '상품이 검색에서 몇 위에 나오는지 키워드마다 확인하고 있어요.\n'
                    '끝나면 자동으로 키워드 선택 화면이 열립니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.6, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 18),

                  // ── 이탈 주의 안내 ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '진행 중 다른 메뉴로 이동하거나 새로고침하면 '
                            '처음부터 다시 해야 합니다.',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── 진행률 ─────────────────────────────────
                  Row(
                    children: [
                      Text('진행률',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                      const Spacer(),
                      Text('${(p.value * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _kBlue)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: p.value),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFE5E7EB),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_kBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── 단계 ───────────────────────────────────
                  for (final s in const [
                    KeywordStep.product,
                    KeywordStep.candidates,
                    KeywordStep.ranking,
                  ])
                    _StepRow(
                      index: s.index + 1,
                      label: KeywordProgress(
                        step: s,
                        checked: p.checked,
                        total: p.total,
                      ).label,
                      state: p.step.index > s.index
                          ? _StepState.done
                          : (p.step == s
                              ? _StepState.running
                              : _StepState.waiting),
                    ),

                  if (p.step == KeywordStep.ranking && p.current.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 46),
                      child: Text(
                        '“${p.current}” 확인 중',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500]),
                      ),
                    ),

                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: onCancel,
                      child: Text('취소',
                          style: TextStyle(color: Colors.grey[600])),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StepState { waiting, running, done }

class _StepRow extends StatelessWidget {
  final int        index;
  final String     label;
  final _StepState state;

  const _StepRow({
    required this.index,
    required this.label,
    required this.state,
  });

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final running = state == _StepState.running;
    final done    = state == _StepState.done;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: running ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: running ? const Color(0xFFBFDBFE) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: done
                ? const Icon(Icons.check_circle, size: 20, color: Color(0xFF2E7D32))
                : running
                    ? const CircularProgressIndicator(
                        strokeWidth: 2, color: _kBlue)
                    : Icon(Icons.circle,
                        size: 10, color: Colors.grey.shade300),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STEP $index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: running
                          ? _kBlue
                          : (done ? Colors.grey[600] : Colors.grey[400]),
                    )),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: running ? FontWeight.w600 : FontWeight.w400,
                      color: running || done
                          ? const Color(0xFF111827)
                          : Colors.grey[500],
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
