import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'supabase_client.dart';
import '../features/admin/presentation/admin_charge_screen.dart';
import '../features/admin/presentation/admin_notice_screen.dart';
import '../features/admin/presentation/admin_withdraw_screen.dart';
import '../features/auth/presentation/admin_login_screen.dart';
import '../features/auth/presentation/email_confirm_screen.dart';
import '../features/auth/presentation/email_verify_screen.dart';
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
import '../shared/utils/account_type.dart';
import '../shared/widgets/bottom_nav_bar.dart';

/// 앱 전체 라우터 (go_router)
///
/// 앱 (B2C Android)  : ShellRoute(/home, /history, /mypage) + /splash + /login
///                     + /mission/:id + /mission/:id/active + /withdraw
/// 웹 (B2B 광고주)   : /web/login, /web/dashboard, /web/campaign/*, /web/charge, /web/transactions
/// 어드민 웹 (운영자) : /admin/login, /admin/charge, /admin/withdraw
///
/// ShellRoute: /home, /history, /mypage 에 하단 탭 네비게이션 표시
/// 비-Shell:   /splash, /login, /mission/*, /withdraw, /web/*, /admin/* — 하단 탭 없음
final appRouter = GoRouter(
  initialLocation: '/splash',
  // 인증 가드:
  //   /web/* (/web/login 제외) → 세션 없으면 /web/login, role != ADVERTISER면 차단
  //   /admin/* (/admin/login 제외) → 세션 없으면 /admin/login
  redirect: (context, state) async {
    final location = state.matchedLocation;
    final params   = state.uri.queryParameters;

    // Supabase 인증 에러 콜백: /?error=...&error_description=... → 에러 스낵바
    if (params.containsKey('error')) {
      final desc = Uri.encodeComponent(params['error_description'] ?? 'unknown');
      return '/web/login?auth_error=$desc';
    }

    // Supabase 이메일 인증 콜백: /?code=xxxx
    // 새 페이지 로드이므로 가입 중이던 _signupStep 같은 메모리 상태는 보존되지 않는다.
    // "이메일 인증 완료 = 로그인된 상태"로 보고, users.role(서버 상태)로
    // 곧장 분기한다 — 작업 1(웹 로그인 가드)과 동일한 단일 진실 공급원(role) 사용.
    // 아직 Step2(사업자정보)를 거치지 않은 정상 가입 중 계정은 role이 USER이므로
    // Step2로 보내는 것이 맞다 — 차단 대상이 아니라 가입 완료 경로임.
    if (params.containsKey('code')) {
      return '/web/dashboard';
    }

    // 루트 경로 직접 접근: GoException 방지용 → 광고주 로그인으로 이동
    if (location == '/') return '/web/login';

    final path = state.uri.path;
    if (path.startsWith('/web/') && path != '/web/login') {
      if (supabase.auth.currentSession == null) return '/web/login';
      // 세션은 있지만 광고주(role=ADVERTISER)가 아닌 계정의 /web/* 직접 진입 차단
      // (로그인 가드를 거치지 않고 세션이 유지된 채 URL로 직접 들어오는 경로 방지)
      final userId = supabase.auth.currentUser!.id;
      if (!await isRegisteredAdvertiser(userId)) {
        return '/web/login?auth_error=${Uri.encodeComponent('유저 계정으로는 광고주 웹에 접근할 수 없습니다')}';
      }
    }
    if (path.startsWith('/admin/') && path != '/admin/login') {
      if (supabase.auth.currentSession == null) return '/admin/login';
    }
    return null;
  },
  routes: [
    // ── 루트 경로 폴백 (GoException 방지) ─────────────────────
    GoRoute(
      path: '/',
      redirect: (_, _) => '/web/login',
    ),

    // ── 인증 (비-Shell) ────────────────────────────────────────
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/email_verify',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return EmailVerifyScreen(email: extra?['email'] as String?);
      },
    ),
    GoRoute(
      path: '/auth/confirm',
      builder: (context, state) => const EmailConfirmScreen(),
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
          // redirect 없음 — extra가 비어 있어도(딥링크 후 프로세스 재시작 등)
          // MissionActiveScreen이 campaign_id로 SharedPreferences 복원을 직접 시도한다.
          // 복원도 실패하면 화면 내부에서 /home으로 리다이렉트한다.
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return MissionActiveScreen(
              id:          state.pathParameters['id']!,
              logId:       extra?['log_id']       as String? ?? '',
              keyword:     extra?['keyword']      as String? ?? '',
              tagIndex:    extra?['tag_index']    as int?,
              productUrl:  extra?['product_url']  as String?,
              productName: extra?['product_name'] as String?,
              brandName:   extra?['brand_name']   as String?,
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
      builder: (context, state) {
        final verified  = state.uri.queryParameters['verified'] == 'true';
        final authError = state.uri.queryParameters['auth_error'];
        return WebLoginScreen(
          showVerifiedBanner: verified,
          authError: authError,
        );
      },
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
    // 세션 인증은 redirect 가드에서 처리 (/admin/login 제외 경로)
    GoRoute(
      path: '/admin/login',
      builder: (context, state) => const AdminLoginScreen(),
    ),
    GoRoute(
      path: '/admin/charge',
      builder: (context, state) => const AdminChargeScreen(),
    ),
    GoRoute(
      path: '/admin/withdraw',
      builder: (context, state) => const AdminWithdrawScreen(),
    ),
    GoRoute(
      path: '/admin/notice',
      builder: (context, state) => const AdminNoticeScreen(),
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
