import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 이메일 인증 완료 안내 화면 (/auth/confirm)
// Supabase 인증 메일의 리다이렉트 URL로 사용
// ─────────────────────────────────────────────────────────────────

class EmailConfirmScreen extends StatelessWidget {
  const EmailConfirmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 72,
              ),
              SizedBox(height: 24),
              Text(
                '이메일 인증 완료',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '이메일 인증이 완료되었습니다.\n로그인 화면으로 돌아가 로그인해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
