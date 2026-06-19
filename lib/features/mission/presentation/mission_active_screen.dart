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
//   - log_id      : start_mission RPC 응답의 log_id (UUID)
//   - keyword     : 사용자가 검색한 키워드 (안내 표시용)
//   - tag_index   : 정답 태그 순서 (1-based, 없으면 null)
//   - product_url : 캠페인 상품 URL (null이면 미사용)
//   - product_name: 상품명 (null이면 미표시)
//   - brand_name  : 브랜드명 (null이면 미표시)
//
// Phase 16: WebView 전환으로 앱 이탈 없음 → 타이머/라이프사이클 제거
// 진입 즉시 태그 입력 활성화. AppBar에 "네이버 쇼핑 보기" 버튼으로 검색 화면 복귀.

class MissionActiveScreen extends ConsumerStatefulWidget {
  final String  id;           // campaign_id (path param)
  final String  logId;        // mission_logs.id (UUID)
  final String  keyword;      // 안내 표시용 키워드
  final int?    tagIndex;     // 정답 태그 순서 (1-based, null이면 안내 미표시)
  final String? productUrl;   // 캠페인 상품 URL (null이면 미표시)
  final String? productName;  // 상품명 (null이면 미표시)
  final String? brandName;    // 브랜드명 (null이면 미표시)

  const MissionActiveScreen({
    super.key,
    required this.id,
    required this.logId,
    required this.keyword,
    this.tagIndex,
    this.productUrl,
    this.productName,
    this.brandName,
  });

  @override
  ConsumerState<MissionActiveScreen> createState() =>
      _MissionActiveScreenState();
}

class _MissionActiveScreenState extends ConsumerState<MissionActiveScreen>
    with SingleTickerProviderStateMixin {

  bool _isSuccess = false;
  final _tagController = TextEditingController();

  // 폭죽 애니메이션
  late AnimationController _confettiCtrl;
  late Animation<double>   _confettiAnim;

  @override
  void initState() {
    super.initState();
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
    _tagController.dispose();
    _confettiCtrl.dispose();
    super.dispose();
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
        setState(() => _isSuccess = true);
        _confettiCtrl.forward();
        AdmobInterstitial.load();
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
        _showSnackBar('오류가 발생했습니다. 다시 시도해 주세요');

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

    return PopScope(
      canPop: !isVerifying && !_isSuccess,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('미션 진행 중'),
              automaticallyImplyLeading: !isVerifying && !_isSuccess,
              actions: [
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('네이버 쇼핑 보기'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _ActiveBody(
                        keyword:     widget.keyword,
                        tagIndex:    widget.tagIndex,
                        productUrl:  widget.productUrl,
                        productName: widget.productName,
                        brandName:   widget.brandName,
                        tagController: _tagController,
                      ),
                    ),
                  ),

                  // 하단 고정: [리워드 받기] 버튼
                  _RewardButton(
                    isVerifying: isVerifying,
                    onPressed:   isVerifying ? null : _onRewardTapped,
                  ),
                ],
              ),
            ),
          ),

          // 성공 폭죽 오버레이
          if (_isSuccess)
            _ConfettiOverlay(animation: _confettiAnim),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 활성 화면 (정답 입력)
// ─────────────────────────────────────────────────────────────────

class _ActiveBody extends StatelessWidget {
  final String  keyword;
  final int?    tagIndex;
  final String? productUrl;
  final String? productName;
  final String? brandName;
  final TextEditingController tagController;

  const _ActiveBody({
    required this.keyword,
    required this.tagController,
    this.tagIndex,
    this.productUrl,
    this.productName,
    this.brandName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 키워드 안내
        _KeywordReminder(keyword: keyword),
        const SizedBox(height: 16),

        // 상품명/브랜드명 안내 (있을 경우)
        if (productName != null || brandName != null) ...[
          _ProductInfoCard(productName: productName, brandName: brandName),
          const SizedBox(height: 20),
        ],

        // 정답 입력
        _TagInputSection(
          controller: tagController,
          tagIndex:   tagIndex,
          productUrl: productUrl,
        ),
      ],
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
// 상품명/브랜드명 안내 카드
// ─────────────────────────────────────────────────────────────────

class _ProductInfoCard extends StatelessWidget {
  final String? productName;
  final String? brandName;

  const _ProductInfoCard({this.productName, this.brandName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 16, color: Colors.indigo.shade600),
              const SizedBox(width: 6),
              Text(
                '찾아야 할 상품',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.indigo.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (productName != null) ...[
            const SizedBox(height: 6),
            Text(
              productName!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.indigo.shade900,
              ),
            ),
          ],
          if (brandName != null) ...[
            const SizedBox(height: 2),
            Text(
              brandName!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.indigo.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 정답 태그 입력 섹션
// ─────────────────────────────────────────────────────────────────

class _TagInputSection extends StatelessWidget {
  final TextEditingController controller;
  final int?    tagIndex;
  final String? productUrl;

  const _TagInputSection({
    required this.controller,
    this.tagIndex,
    this.productUrl,
  });

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

        // 상품 URL 복사 버튼 (있을 경우)
        if (productUrl != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    productUrl!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy_rounded,
                      size: 18, color: Colors.indigo.shade400),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'URL 복사',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: productUrl!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('URL이 복사되었습니다'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

        // tagIndex 안내 박스
        if (tagIndex != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: Colors.indigo.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '상품 페이지에서 $tagIndex번째 태그를 입력하세요',
                    style: TextStyle(
                      color: Colors.indigo.shade800,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '상품 페이지에서 찾은 태그를 입력하세요',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ),

        // 태그 위치 힌트
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.lightbulb_outline,
                    size: 15, color: Colors.amber.shade700),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '태그는 상품명 아래 #으로 시작하는 키워드입니다',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7B5800)),
                ),
              ),
            ],
          ),
        ),

        // 태그 위치 안내 이미지
        const SizedBox(height: 8),
        Image.asset(
          'assets/images/mission_guide.png',
          width: double.infinity,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 8),

        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '예) #헬스장갑',
            prefixIcon:
                Icon(Icons.tag_rounded, color: Colors.indigo.shade400),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.indigo.shade400, width: 2),
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
// 리워드 받기 버튼 (하단 고정)
// ─────────────────────────────────────────────────────────────────

class _RewardButton extends StatelessWidget {
  final bool        isVerifying;
  final VoidCallback? onPressed;

  const _RewardButton({
    required this.isVerifying,
    required this.onPressed,
  });

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
            child: isVerifying
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    '리워드 받기',
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
// 성공 폭죽 오버레이
// ─────────────────────────────────────────────────────────────────

class _ConfettiOverlay extends StatelessWidget {
  final Animation<double> animation;
  const _ConfettiOverlay({required this.animation});

  static const _colors = [
    Colors.red, Colors.blue, Colors.green,
    Colors.yellow, Colors.orange, Colors.purple,
    Colors.pink, Colors.teal,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _ConfettiPainter(progress: animation.value),
        );
      },
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final _rnd = math.Random(42);

  static final _particles = List.generate(80, (i) => _Particle(
    x: _rnd.nextDouble(),
    y: _rnd.nextDouble() * 0.5,
    vx: (_rnd.nextDouble() - 0.5) * 0.4,
    vy: _rnd.nextDouble() * 0.6 + 0.4,
    color: _ConfettiOverlay._colors[i % _ConfettiOverlay._colors.length],
    size: _rnd.nextDouble() * 8 + 4,
  ));

  _ConfettiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final x = (p.x + p.vx * progress) * size.width;
      final y = (p.y + p.vy * progress) * size.height;
      final paint = Paint()..color = p.color.withOpacity(1 - progress);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _Particle {
  final double x, y, vx, vy, size;
  final Color color;
  const _Particle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.color, required this.size,
  });
}
