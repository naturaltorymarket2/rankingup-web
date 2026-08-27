import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────
// 첫 실행 안내 화면 (온보딩)  —  /onboarding
//
// 앱을 처음 설치한 사용자에게 서비스 사용법을 3장으로 안내한다.
// 한 번 보고 나면 다시 표시하지 않는다 (SharedPreferences 플래그).
//
// 진입: 스플래시에서 세션이 없고 온보딩을 본 적이 없을 때
// 이탈: [시작하기] 또는 [건너뛰기] → /login
// ─────────────────────────────────────────────────────────────────

/// 온보딩 완료 여부 저장 키
const String kOnboardingSeenKey = 'onboarding_seen_v1';

/// 온보딩을 본 적이 있는지 확인
Future<bool> hasSeenOnboarding() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kOnboardingSeenKey) ?? false;
  } catch (_) {
    // 저장소 접근 실패 시 온보딩을 건너뛴다 (진입 자체를 막지 않기 위함)
    return true;
  }
}

Future<void> _markOnboardingSeen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingSeenKey, true);
  } catch (_) {
    // 저장 실패해도 흐름은 계속 진행한다
  }
}

// ─────────────────────────────────────────────────────────────────

class _Page {
  final IconData icon;
  final String   title;
  final String   body;
  const _Page({required this.icon, required this.title, required this.body});
}

const _pages = <_Page>[
  _Page(
    icon:  Icons.search,
    title: '키워드를 검색하세요',
    body:  '홈에서 미션을 고르면 키워드가 자동으로 복사됩니다.\n'
           '네이버에서 그 키워드로 검색해 주세요.',
  ),
  _Page(
    icon:  Icons.tag,
    title: '상품 태그를 확인하세요',
    body:  '검색 결과에서 상품을 열고,\n'
           '상품명 아래 #태그 중 안내된 순서의 태그를 확인합니다.',
  ),
  _Page(
    icon:  Icons.savings_outlined,
    title: '정답을 입력하면 적립',
    body:  '앱으로 돌아와 태그를 입력하면 바로 포인트가 쌓입니다.\n'
           '모은 포인트는 현금으로 출금할 수 있어요.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _finish() async {
    await _markOnboardingSeen();
    if (mounted) context.go('/login');
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── 건너뛰기 ─────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('건너뛰기'),
                ),
              ),
            ),

            // ── 페이지 ───────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _PageView(page: _pages[i]),
              ),
            ),

            // ── 인디케이터 ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? _kBlue : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // ── 다음 / 시작하기 ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isLast ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 개별 페이지 ───────────────────────────────────────────────────

class _PageView extends StatelessWidget {
  final _Page page;
  const _PageView({required this.page});

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF4FF),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 62, color: _kBlue),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
