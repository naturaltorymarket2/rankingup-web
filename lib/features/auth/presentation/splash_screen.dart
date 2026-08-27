import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/account_type.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

// ─────────────────────────────────────────────────────────────────
// 스플래시 화면 — Supabase 세션 복원 후 자동 이동
// ─────────────────────────────────────────────────────────────────
//
// 웹:  세션 있음 + role=ADVERTISER → /web/dashboard   그 외 → 로그아웃 후 /web/login
// 앱:  세션 있음 + role!=ADVERTISER → /home            그 외 → 로그아웃 후 /login
//      세션 없음 → 각 플랫폼 로그인 화면
// ─────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
    // 세션 복원 대기.
    //
    // 기존에는 onAuthStateChange 첫 이벤트를 최대 3초 기다렸는데,
    // 로그인한 적이 없는 사용자는 이벤트가 오지 않아 매번 3초를 그냥 버렸다.
    // → 이미 복원된 세션이 있으면 기다리지 않고,
    //   없을 때만 짧게(1.2초) 기다린 뒤 넘어간다.
    if (supabase.auth.currentSession == null) {
      try {
        await supabase.auth.onAuthStateChange
            .first
            .timeout(const Duration(milliseconds: 1200));
      } catch (_) {
        // TimeoutException 또는 스트림 오류 — currentSession으로 fallback
      }
    }
    if (!mounted) return;

    final session = supabase.auth.currentSession;
    if (session != null) {
      final userId      = supabase.auth.currentUser!.id;
      final isAdvertiser = await isRegisteredAdvertiser(userId);
      if (!mounted) return;

      if (kIsWeb) {
        if (isAdvertiser) {
          context.go('/web/dashboard');
        } else {
          // 세션은 있지만 광고주가 아닌 계정 — 웹 접근 차단 (방어 코드)
          await supabase.auth.signOut();
          if (mounted) context.go('/web/login');
        }
      } else {
        if (isAdvertiser) {
          // 세션은 있지만 광고주 계정 — 앱 접근 차단 (방어 코드)
          await supabase.auth.signOut();
          if (mounted) context.go('/login');
        } else {
          final emailConfirmedAt = supabase.auth.currentUser?.emailConfirmedAt;
          context.go(emailConfirmedAt != null ? '/home' : '/email_verify');
        }
      }
    } else if (kIsWeb) {
      context.go('/web/login');
    } else {
      // 앱 첫 실행이면 사용법 안내(온보딩)를 먼저 보여준다
      final seen = await hasSeenOnboarding();
      if (!mounted) return;
      context.go(seen ? '/login' : '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/KakaoTalk_Photo_2026-07-20-09-28-12.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
