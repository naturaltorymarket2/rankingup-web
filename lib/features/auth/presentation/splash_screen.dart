import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';

// ─────────────────────────────────────────────────────────────────
// 스플래시 화면 — Supabase 세션 복원 후 자동 이동
// ─────────────────────────────────────────────────────────────────
//
// 웹:  세션 있음 → /web/dashboard   세션 없음 → /web/login
// 앱:  세션 있음 → /home            세션 없음 → /login
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
      context.go(kIsWeb ? '/web/dashboard' : '/home');
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
              '겟머니',
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
