import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_client.dart';

// ─────────────────────────────────────────────────────────────────
// 앱 이메일 인증 대기 화면 (/email_verify)
// ─────────────────────────────────────────────────────────────────
//
// 진입 경로:
//   1. 회원가입 직후 → extra: {'email': email} 포함
//   2. splash 세션 복구 → emailConfirmedAt == null
//   3. 로그인 성공 → emailConfirmedAt == null
//
// 인증 감지 방식:
//   A. onAuthStateChange USER_UPDATED + emailConfirmedAt != null → 자동 이동
//   B. [인증 완료했어요] 버튼 → refreshSession → 수동 체크 (fallback)
// ─────────────────────────────────────────────────────────────────

class EmailVerifyScreen extends StatefulWidget {
  final String? email;

  const EmailVerifyScreen({super.key, this.email});

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  bool _isSending  = false;
  bool _isChecking = false;
  StreamSubscription<AuthState>? _authSub;

  String get _effectiveEmail =>
      supabase.auth.currentUser?.email ?? widget.email ?? '';

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event != AuthChangeEvent.userUpdated) return;
      final confirmedAt = data.session?.user.emailConfirmedAt;
      if (confirmedAt != null) {
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    final email = _effectiveEmail;
    if (email.isEmpty) return;
    setState(() => _isSending = true);
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
      _showInfo('인증 메일을 재발송했습니다.');
    } catch (_) {
      _showError('재발송에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _checkConfirmed() async {
    setState(() => _isChecking = true);
    try {
      await supabase.auth.refreshSession();
      final confirmedAt = supabase.auth.currentUser?.emailConfirmedAt;
      if (!mounted) return;
      if (confirmedAt != null) {
        context.go('/home');
      } else {
        _showError('아직 인증이 완료되지 않았습니다.');
      }
    } catch (_) {
      if (mounted) _showError('아직 인증이 완료되지 않았습니다.');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isSending || _isChecking;
    final email     = _effectiveEmail;

    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFF1E3A8A),
                  size: 56,
                ),
                const SizedBox(height: 20),
                const Text(
                  '이메일 인증',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '가입하신 이메일로 인증 링크를 보냈습니다.\n이메일을 확인해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: isLoading ? null : _checkConfirmed,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            '인증 완료했어요',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: isLoading ? null : _resend,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1E3A8A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Color(0xFF1E3A8A),
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            '인증 메일 재발송',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
