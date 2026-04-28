import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/admob_interstitial.dart';
import '../domain/mission_model.dart';
import 'mission_active_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 미션 진행 화면 (/mission/:id/active)
// ─────────────────────────────────────────────────────────────────
//
// go_router extra 수신:
//   - logId     : start_mission RPC 응답의 log_id (UUID)
//   - keyword   : 사용자가 검색한 키워드 (안내 표시용)
//   - startedAt : 서버 기록 미션 시작 시각 (UTC) — 타이머 기준값
//
// 화면 상태 흐름:
//   진입 → "네이버에서 검색 중..." 대기 화면
//   resumed → 타이머 시작 + 3초 버튼 잠금 → 정답 입력 활성화
//   타임아웃 → 버튼 비활성화 + 3초 후 /home
//   [리워드 받기] → verify_mission RPC → 성공/오답/타임아웃/오류 처리

class MissionActiveScreen extends ConsumerStatefulWidget {
  final String id;         // campaign_id (path param)
  final String logId;      // mission_logs.id (UUID)
  final String keyword;    // 안내 표시용 키워드
  final DateTime startedAt; // 서버 UTC 시각 — 타이머 기준

  const MissionActiveScreen({
    super.key,
    required this.id,
    required this.logId,
    required this.keyword,
    required this.startedAt,
  });

  @override
  ConsumerState<MissionActiveScreen> createState() =>
      _MissionActiveScreenState();
}

class _MissionActiveScreenState extends ConsumerState<MissionActiveScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // ── 상태 ────────────────────────────────────────────────────
  bool _isResumed       = false; // 네이버 앱에서 복귀 여부
  bool _isButtonLocked  = false; // 복귀 후 3초 잠금
  bool _isTimedOut      = false; // 10분 초과 여부
  bool _isSuccess       = false; // 성공 애니메이션 표시 여부
  int  _remainingSeconds = 600;  // 남은 시간 (초) — 표시용

  Timer? _countdownTimer;
  Timer? _lockTimer;

  final _tagController = TextEditingController();

  // ── 폭죽 애니메이션 컨트롤러 ──────────────────────────────
  late AnimationController _confettiCtrl;
  late Animation<double> _confettiAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _confettiAnim = CurvedAnimation(
      parent: _confettiCtrl,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _lockTimer?.cancel();
    _tagController.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ── AppLifecycle 복귀 감지 ────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isResumed && !_isTimedOut) {
      _onResumedFromNaver();
    }
  }

  void _onResumedFromNaver() {
    final remaining = _calcRemaining();
    setState(() {
      _isResumed      = true;
      _isButtonLocked = true;
      _remainingSeconds = remaining;
    });

    if (remaining <= 0) {
      _triggerTimeout();
      return;
    }

    // 타이머 시작
    _startCountdown();

    // 3초 버튼 잠금 해제
    _lockTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isTimedOut) {
        setState(() => _isButtonLocked = false);
      }
    });
  }

  // ── 카운트다운 (표시용) ───────────────────────────────────
  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _calcRemaining();
      setState(() => _remainingSeconds = remaining);
      if (remaining <= 0) {
        _countdownTimer?.cancel();
        _triggerTimeout();
      }
    });
  }

  /// 남은 초 계산 — 반드시 서버 startedAt 기준
  int _calcRemaining() {
    final deadline = widget.startedAt.add(const Duration(minutes: 10));
    final diff = deadline.difference(DateTime.now().toUtc()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  // ── 타임아웃 처리 ─────────────────────────────────────────
  void _triggerTimeout() {
    if (!mounted) return;
    setState(() {
      _isTimedOut     = true;
      _isButtonLocked = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) context.go('/home');
    });
  }

  // ── verify_mission 호출 ───────────────────────────────────
  Future<void> _onRewardTapped() async {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) {
      _showSnackBar('정답을 입력해주세요');
      return;
    }

    final result = await ref.read(missionVerifyProvider.notifier).verifyMission(
      logId:        widget.logId,
      submittedTag: tag,
    );

    if (!mounted) return;

    switch (result) {
      case VerifyMissionResult.success:
        _countdownTimer?.cancel();
        setState(() => _isSuccess = true);
        _confettiCtrl.forward();
        AdmobInterstitial.load(); // 폭죽 애니메이션 중 미리 로드 (fire and forget)
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          AdmobInterstitial.showAd(
            onDismissed: () {
              if (mounted) context.go('/home');
            },
          );
        }

      case VerifyMissionResult.wrongAnswer:
        HapticFeedback.vibrate();
        _showSnackBar('오답입니다. 다시 확인해주세요');

      case VerifyMissionResult.timeout:
        _countdownTimer?.cancel();
        setState(() {
          _isTimedOut     = true;
          _isButtonLocked = true;
        });
        _showSnackBar('시간이 초과되었습니다');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/home');

      case VerifyMissionResult.error:
        _showSnackBar('오류가 발생했습니다. 다시 시도해 주세요');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── 빌드 ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isVerifying = ref.watch(missionVerifyProvider);
    final canPress    = _isResumed && !_isButtonLocked && !_isTimedOut && !isVerifying;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('미션 진행 중'),
            automaticallyImplyLeading: false, // 뒤로가기 비활성화 (미션 중단 방지)
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  // 복귀 전: Center로 수직 중앙 정렬 가능 (Expanded 직접 자식)
                  // 복귀 후: 스크롤 가능 (정답 입력 + 키보드 고려)
                  child: _isResumed
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: _ActiveBody(
                            keyword:          widget.keyword,
                            remainingSeconds: _remainingSeconds,
                            isTimedOut:       _isTimedOut,
                            tagController:    _tagController,
                          ),
                        )
                      : const _WaitingBody(),
                ),

                // 하단 고정: [리워드 받기] 버튼 (복귀 후만 표시)
                if (_isResumed)
                  _RewardButton(
                    canPress:    canPress,
                    isVerifying: isVerifying,
                    isTimedOut:  _isTimedOut,
                    isLocked:    _isButtonLocked,
                    onPressed:   canPress ? _onRewardTapped : null,
                  ),
              ],
            ),
          ),
        ),

        // 성공 폭죽 오버레이
        if (_isSuccess)
          _ConfettiOverlay(animation: _confettiAnim),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 복귀 대기 화면 (네이버 앱 이동 후)
// ─────────────────────────────────────────────────────────────────

class _WaitingBody extends StatelessWidget {
  const _WaitingBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          // 로딩 인디케이터
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: Colors.indigo.shade400,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            '네이버에서 검색 중...',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '키워드로 검색하고 상품을 찾은 후\n이 앱으로 돌아오세요',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  '앱으로 돌아오면 타이머가 시작됩니다',
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 복귀 후 활성 화면 (타이머 + 정답 입력)
// ─────────────────────────────────────────────────────────────────

class _ActiveBody extends StatelessWidget {
  final String keyword;
  final int remainingSeconds;
  final bool isTimedOut;
  final TextEditingController tagController;

  const _ActiveBody({
    required this.keyword,
    required this.remainingSeconds,
    required this.isTimedOut,
    required this.tagController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 타이머
        _TimerSection(
          remainingSeconds: remainingSeconds,
          isTimedOut: isTimedOut,
        ),
        const SizedBox(height: 28),

        // 키워드 안내
        _KeywordReminder(keyword: keyword),
        const SizedBox(height: 28),

        // 정답 입력
        if (!isTimedOut) _TagInputSection(controller: tagController),

        // 타임아웃 메시지
        if (isTimedOut) _TimeoutMessage(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 타이머 섹션
// ─────────────────────────────────────────────────────────────────

class _TimerSection extends StatelessWidget {
  final int remainingSeconds;
  final bool isTimedOut;

  const _TimerSection({
    required this.remainingSeconds,
    required this.isTimedOut,
  });

  String get _timeLabel {
    if (isTimedOut) return '00:00';
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    if (isTimedOut) return Colors.red.shade700;
    if (remainingSeconds <= 60) return Colors.orange.shade700;
    return Colors.indigo.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: isTimedOut ? Colors.red.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTimedOut ? Colors.red.shade200 : Colors.indigo.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isTimedOut ? Icons.timer_off_rounded : Icons.timer_rounded,
            size: 28,
            color: _timerColor,
          ),
          const SizedBox(height: 8),
          Text(
            _timeLabel,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: _timerColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isTimedOut ? '시간 초과' : '남은 시간',
            style: TextStyle(
              fontSize: 13,
              color: _timerColor.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 키워드 안내
// ─────────────────────────────────────────────────────────────────

class _KeywordReminder extends StatelessWidget {
  final String keyword;
  const _KeywordReminder({required this.keyword});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '검색한 키워드',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          keyword,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade800,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 정답 태그 입력 섹션
// ─────────────────────────────────────────────────────────────────

class _TagInputSection extends StatelessWidget {
  final TextEditingController controller;
  const _TagInputSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정답 태그 입력',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '상품 페이지에서 찾은 태그를 입력하세요',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '태그 입력',
            prefixIcon: Icon(Icons.tag_rounded, color: Colors.indigo.shade400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.indigo.shade400, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 타임아웃 메시지
// ─────────────────────────────────────────────────────────────────

class _TimeoutMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '시간이 초과되었습니다',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '3초 후 홈으로 이동합니다',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// [리워드 받기] 버튼 (하단 고정)
// ─────────────────────────────────────────────────────────────────

class _RewardButton extends StatelessWidget {
  final bool canPress;
  final bool isVerifying;
  final bool isTimedOut;
  final bool isLocked;
  final VoidCallback? onPressed;

  const _RewardButton({
    required this.canPress,
    required this.isVerifying,
    required this.isTimedOut,
    required this.isLocked,
    required this.onPressed,
  });

  String get _label {
    if (isTimedOut) return '시간 초과';
    if (isLocked)   return '잠시 기다려주세요...';
    return '리워드 받기';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: canPress ? Colors.indigo : Colors.grey.shade400,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isVerifying
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  _label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 성공 폭죽 오버레이 (별도 패키지 없이 CustomPainter + 이모지)
// ─────────────────────────────────────────────────────────────────

class _ConfettiOverlay extends StatelessWidget {
  final Animation<double> animation;
  const _ConfettiOverlay({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 반투명 배경
              Opacity(
                opacity: (animation.value * 0.85).clamp(0.0, 0.85),
                child: const ColoredBox(color: Colors.black),
              ),

              // 파티클
              CustomPaint(
                painter: _ParticlePainter(progress: animation.value),
              ),

              // 중앙 성공 메시지
              Center(
                child: Opacity(
                  opacity: animation.value.clamp(0.0, 1.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 72)),
                      const SizedBox(height: 16),
                      const Text(
                        '+7원 적립!',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '미션 성공!',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 파티클 페인터 (간단한 원형 파티클 20개)
// ─────────────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double progress;

  // 고정 파티클 설정 (색상 + 각도)
  static const _colors = [
    Colors.yellow, Colors.pink, Colors.cyan, Colors.orange,
    Colors.green,  Colors.red,  Colors.purple, Colors.teal,
  ];

  _ParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    const count = 24;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final distance = 160.0 * progress;
      final x = cx + math.cos(angle) * distance;
      final y = cy + math.sin(angle) * distance - (80 * progress * progress);
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final radius = (8.0 * (1 - progress * 0.5)).clamp(2.0, 8.0);

      paint.color =
          _colors[i % _colors.length].withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
