import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/account_type.dart';

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
    // A-009: onAuthStateChange 스트림의 첫 이벤트로 세션 복원 완료를 감지
    // 3초 타임아웃: 이벤트 미수신 시 currentSession으로 fallback
    try {
      await supabase.auth.onAuthStateChange
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // TimeoutException 또는 스트림 오류 — currentSession으로 fallback
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
    } else {
      context.go(kIsWeb ? '/web/login' : '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E3A8A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '퀴즈캐시나우',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 32),
            CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}
