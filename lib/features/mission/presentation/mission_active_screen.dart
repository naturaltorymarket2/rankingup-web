import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/admob_interstitial.dart';
import '../data/mission_session_storage.dart';
import '../domain/mission_model.dart';
import 'mission_active_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 미션 진행 화면 (/mission/:id/active)
// ─────────────────────────────────────────────────────────────────
//
// go_router extra 수신 (정상 진입 시):
//   - log_id      : start_mission RPC 응답의 log_id (UUID)
//   - keyword     : 사용자가 검색한 키워드 (안내 표시용)
//   - tag_index   : 정답 태그 순서 (1-based, 없으면 null)
//   - product_url : 캠페인 상품 URL (null이면 미사용)
//   - product_name: 상품명 (null이면 미표시)
//   - brand_name  : 브랜드명 (null이면 미표시)
//
// extra가 비어 있으면(logId.isEmpty) — 네이버 앱에 가 있는 동안 OS가
// 백그라운드 Flutter 프로세스를 종료해 go_router의 메모리상 extra가
// 사라진 경우다. 이때는 widget.id(campaign_id)로 SharedPreferences에서
// 복원을 시도하고, 그마저 없으면 /home으로 리다이렉트한다.
//
// AppLifecycleState.resumed 감지로 네이버 앱 복귀를 확인하며,
// 데이터 복원(_resolved)이 끝나기 전에는 resumed 콜백을 무시한다.

class MissionActiveScreen extends ConsumerStatefulWidget {
  final String  id;           // campaign_id (path param)
  final String  logId;        // mission_logs.id (UUID) — 비어 있으면 복원 시도
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // ── 실제 사용 데이터 (extra 또는 SharedPreferences 복원 결과) ──
  String? _logId;
  String? _keyword;
  int?    _tagIndex;
  String? _productUrl;
  String? _productName;
  String? _brandName;

  bool _resolved      = false; // 데이터 준비 완료 (extra 정상 또는 복원 성공)
  bool _resolveFailed = false; // 복원도 실패 — /home 리다이렉트 진행 중

  // ── 네이버 앱 복귀 감지 ────────────────────────────────────
  bool _isResumed      = false; // 네이버 앱에서 복귀 여부
  bool _isButtonLocked = false; // 복귀 후 3초 잠금
  bool _isSuccess      = false;
  Timer? _lockTimer;

  final _tagController = TextEditingController();

  // 폭죽 애니메이션
  late AnimationController _confettiCtrl;
  late Animation<double>   _confettiAnim;

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

    _resolveMissionData();
  }

  // ── extra 정상 사용 또는 SharedPreferences 복원 ────────────
  Future<void> _resolveMissionData() async {
    if (widget.logId.isNotEmpty) {
      setState(() {
        _logId       = widget.logId;
        _keyword     = widget.keyword;
        _tagIndex    = widget.tagIndex;
        _productUrl  = widget.productUrl;
        _productName = widget.productName;
        _brandName   = widget.brandName;
        _resolved    = true;
      });
      return;
    }

    final restored = await MissionSessionStorage.restore(widget.id);
    if (!mounted) return;

    if (restored == null) {
      setState(() => _resolveFailed = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('진행 중인 미션 정보를 찾을 수 없습니다. 다시 시작해주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/home');
      });
      return;
    }

    setState(() {
      _logId       = restored['log_id']       as String?;
      _keyword     = restored['keyword']      as String?;
      _tagIndex    = restored['tag_index']    as int?;
      _productUrl  = restored['product_url']  as String?;
      _productName = restored['product_name'] as String?;
      _brandName   = restored['brand_name']   as String?;
      _resolved    = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 화면을 벗어나는 시점(성공 또는 명시적 뒤로가기) 정리.
    // OS가 프로세스를 강제 종료하는 경우엔 dispose()가 호출되지 않으므로
    // 백그라운드 강제 종료 시에는 저장값이 그대로 남아 복원에 사용된다.
    MissionSessionStorage.clear();
    _lockTimer?.cancel();
    _tagController.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ── AppLifecycle 복귀 감지 ────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 데이터 복원이 끝나기 전에는 무시 — null 참조 방지
    if (!_resolved) return;
    if (state == AppLifecycleState.resumed && !_isResumed) {
      _onResumedFromNaver();
    }
  }

  void _onResumedFromNaver() {
    setState(() {
      _isResumed      = true;
      _isButtonLocked = true;
    });

    // 복귀 후 3초 버튼 잠금 (오작동/연타 방지)
    _lockTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isButtonLocked = false);
    });
  }

  // ── verify_mission 호출 ───────────────────────────────────
  Future<void> _onRewardTapped() async {
    final logId = _logId;
    if (logId == null || logId.isEmpty) {
      _showSnackBar('미션 정보를 불러오지 못했습니다. 다시 시도해주세요');
      return;
    }

    final tag = _tagController.text.trim();
    if (tag.isEmpty) {
      _showSnackBar('정답을 입력해주세요');
      return;
    }

    final result = await ref.read(missionVerifyProvider.notifier).verifyMission(
      logId:        logId,
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
    final canPress = _isResumed && !_isButtonLocked && !isVerifying;

    if (!_resolved) {
      // 복원 진행 중(또는 실패 후 /home 리다이렉트 대기 중) — 빈 로딩 화면
      return Scaffold(
        appBar: AppBar(title: const Text('미션 진행 중')),
        body: Center(
          child: _resolveFailed
              ? const SizedBox.shrink()
              : const CircularProgressIndicator(),
        ),
      );
    }

    return PopScope(
      canPop: !isVerifying && !_isSuccess,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('미션 진행 중'),
              automaticallyImplyLeading: !isVerifying && !_isSuccess,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: _isResumed
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: _ActiveBody(
                              keyword:     _keyword ?? '',
                              tagIndex:    _tagIndex,
                              productUrl:  _productUrl,
                              productName: _productName,
                              brandName:   _brandName,
                              tagController: _tagController,
                            ),
                          )
                        : const _WaitingBody(),
                  ),

                  // 하단 고정: [리워드 받기] 버튼 (복귀 후만 표시)
                  if (_isResumed)
                    _RewardButton(
                      isVerifying: isVerifying,
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
      ),
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
