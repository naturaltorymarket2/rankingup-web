import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'supabase_client.dart';
import '../features/admin/presentation/admin_charge_screen.dart';
import '../features/admin/presentation/admin_withdraw_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/web_login_screen.dart';
import '../features/campaign/presentation/campaign_detail_screen.dart';
import '../features/campaign/presentation/campaign_new_screen.dart';
import '../features/charge/presentation/charge_screen.dart';
import '../features/charge/presentation/transactions_screen.dart';
import '../features/dashboard/presentation/web_dashboard_screen.dart';
import '../features/mission/presentation/mission_active_screen.dart';
import '../features/mission/presentation/mission_detail_screen.dart';
import '../features/mission/presentation/mission_home_screen.dart';
import '../features/wallet/presentation/history_screen.dart';
import '../features/wallet/presentation/mypage_screen.dart';
import '../features/wallet/presentation/withdraw_screen.dart';
import '../shared/widgets/bottom_nav_bar.dart';

/// 앱 전체 라우터 (go_router)
///
/// 앱 (B2C Android)  : ShellRoute(/home, /history, /mypage) + /splash + /login
///                     + /mission/:id + /mission/:id/active + /withdraw
/// 웹 (B2B 광고주)   : /web/login, /web/dashboard, /web/campaign/*, /web/charge, /web/transactions
/// 어드민 웹 (운영자) : /admin/charge, /admin/withdraw
///
/// ShellRoute: /home, /history, /mypage 에 하단 탭 네비게이션 표시
/// 비-Shell:   /splash, /login, /mission/*, /withdraw, /web/*, /admin/* — 하단 탭 없음
final appRouter = GoRouter(
  initialLocation: '/splash',
  // 웹(/web/*) 및 어드민(/admin/*) 라우트는 인증 필수
  // /web/login 은 예외 (미인증 접근 허용)
  redirect: (context, state) {
    final path = state.uri.path;
    final needsAuth = (path.startsWith('/web/') && path != '/web/login') ||
        path.startsWith('/admin/');
    if (needsAuth && supabase.auth.currentSession == null) {
      // C-007: 어드민 경로 접근 시 ?from=admin 파라미터로 안내 배너 표시
      if (path.startsWith('/admin/')) return '/web/login?from=admin';
      return '/web/login';
    }
    return null;
  },
  routes: [
    // ── 인증 (비-Shell) ────────────────────────────────────────
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    // ── 하단 탭 Shell (홈 / 참여 내역 / 마이페이지) ───────────
    ShellRoute(
      builder: (context, state, child) =>
          _NavShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const MissionHomeScreen(),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/mypage',
          builder: (context, state) => const MypageScreen(),
        ),
      ],
    ),

    // ── 미션 (비-Shell, 하단 탭 없음) ─────────────────────────
    GoRoute(
      path: '/mission/:id',
      builder: (context, state) => MissionDetailScreen(
        campaignId: state.pathParameters['id']!,
      ),
      routes: [
        GoRoute(
          path: 'active',
          redirect: (context, state) {
            // extra 없거나 log_id 비어 있으면 잘못된 직접 진입 → 홈으로 이동
            final extra = state.extra as Map<String, dynamic>?;
            final logId = extra?['log_id'] as String? ?? '';
            if (extra == null || logId.isEmpty) return '/home';
            return null;
          },
          builder: (context, state) {
            final extra      = state.extra as Map<String, dynamic>?;
            final startedRaw = extra?['started_at'] as String?;
            return MissionActiveScreen(
              id:        state.pathParameters['id']!,
              logId:     extra?['log_id']  as String? ?? '',
              keyword:   extra?['keyword'] as String? ?? '',
              startedAt: startedRaw != null
                  ? DateTime.parse(startedRaw).toUtc()
                  : DateTime.now().toUtc(),
            );
          },
        ),
      ],
    ),

    // ── 출금 신청 (비-Shell) ───────────────────────────────────
    GoRoute(
      path: '/withdraw',
      builder: (context, state) => const WithdrawScreen(),
    ),

    // ── 웹 (B2B 광고주) ───────────────────────────────────────
    GoRoute(
      path: '/web/login',
      builder: (context, state) => WebLoginScreen(
        // C-007: ?from=admin 파라미터 전달
        fromAdmin: state.uri.queryParameters['from'] == 'admin',
      ),
    ),
    GoRoute(
      path: '/web/dashboard',
      builder: (context, state) => const WebDashboardScreen(),
    ),
    GoRoute(
      path: '/web/campaign/new',
      builder: (context, state) => const CampaignNewScreen(),
    ),
    GoRoute(
      path: '/web/campaign/:id',
      builder: (context, state) => CampaignDetailScreen(
        id: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/web/charge',
      builder: (context, state) => const ChargeScreen(),
    ),
    GoRoute(
      path: '/web/transactions',
      builder: (context, state) => const TransactionsScreen(),
    ),

    // ── 어드민 웹 (운영자) ────────────────────────────────────
    // role = ADMIN 검증은 각 화면 내에서 currentUserRoleProvider 로 처리
    // (비동기 role 체크를 지원하기 위해 화면 진입 후 리다이렉트 방식 사용)
    GoRoute(
      path: '/admin/charge',
      builder: (context, state) => const AdminChargeScreen(),
    ),
    GoRoute(
      path: '/admin/withdraw',
      builder: (context, state) => const AdminWithdrawScreen(),
    ),
  ],
);

// ─────────────────────────────────────────────────────────────────
// 하단 탭 Shell 위젯
// ─────────────────────────────────────────────────────────────────

class _NavShell extends StatelessWidget {
  final String location;
  final Widget child;

  const _NavShell({required this.location, required this.child});

  int get _currentIndex {
    if (location.startsWith('/history')) return 1;
    if (location.startsWith('/mypage'))  return 2;
    return 0; // /home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          switch (i) {
            case 1:  context.go('/history');
            case 2:  context.go('/mypage');
            default: context.go('/home');
          }
        },
      ),
    );
  }
}
