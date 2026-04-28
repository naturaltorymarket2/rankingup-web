import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/device_util.dart';

// ─────────────────────────────────────────────────────────────────
// 앱 유저 로그인 / 회원가입 화면 (/login)
// ─────────────────────────────────────────────────────────────────
//
// 탭 0: 로그인  — 이메일 + 비밀번호 → /home
// 탭 1: 회원가입 — 이메일 + 비밀번호 → /home
//
// 공통 처리:
//   - Supabase Auth 완료 후 device_id를 users 테이블에 기록
//   - device_id UNIQUE 충돌(타 계정 기기) → 조용히 무시 (start_mission RPC에서 서버 검증)
// ─────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int  _tabIndex  = 0;
  bool _isLoading = false;

  // ── 로그인 폼 ────────────────────────────────────────────────
  final _loginEmailCtrl    = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool  _loginObscure      = true;

  // ── 회원가입 폼 ──────────────────────────────────────────────
  final _signupEmailCtrl    = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  bool  _signupObscure      = true;

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPasswordCtrl.dispose();
    super.dispose();
  }

  // ── 로그인 ───────────────────────────────────────────────────

  Future<void> _onLogin() async {
    final email    = _loginEmailCtrl.text.trim();
    final password = _loginPasswordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await _saveDeviceId();
      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 회원가입 ─────────────────────────────────────────────────

  Future<void> _onSignUp() async {
    final email    = _signupEmailCtrl.text.trim();
    final password = _signupPasswordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요.');
      return;
    }
    if (password.length < 6) {
      _showError('비밀번호는 6자 이상이어야 합니다.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Supabase Auth 회원가입
      //    → handle_new_user 트리거: users + wallets 자동 생성
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (res.user == null) {
        _showError('회원가입에 실패했습니다. 다시 시도해주세요.');
        return;
      }

      // 이메일 인증 필요한 경우 (Supabase 설정에 따라)
      if (res.session == null) {
        _showError(
          '가입 확인 이메일을 발송했습니다.\n'
          '이메일 인증 완료 후 로그인해주세요.',
        );
        setState(() => _tabIndex = 0);
        return;
      }

      // 2. handle_new_user 트리거 결과 확인 (public.users row 존재 여부)
      //    트리거 실패 시 orphaned account 방지: signOut + 오류 안내
      final userId = res.user!.id;
      final row = await supabase
          .from('users')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (row == null) {
        await supabase.auth.signOut();
        if (mounted) {
          _showError(
            '계정 초기화 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
          );
        }
        return;
      }

      // 3. Device ID 기록
      await _saveDeviceId();

      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Device ID 저장 ───────────────────────────────────────────
  //
  // UNIQUE 충돌(다른 계정이 이미 이 기기를 사용) → 조용히 무시.
  // 실제 어뷰징 차단은 start_mission RPC에서 서버 측으로 처리.
  // getDeviceId() 는 shared/utils/device_util.dart 에서 제공.

  Future<void> _saveDeviceId() async {
    try {
      final userId   = supabase.auth.currentUser?.id;
      final deviceId = await getDeviceId();
      if (userId == null || deviceId.isEmpty) return;

      await supabase
          .from('users')
          .update({'device_id': deviceId})
          .eq('id', userId);
    } catch (_) {
      // UNIQUE 위반 등 — 무시
    }
  }

  // ── 에러 메시지 매핑 ─────────────────────────────────────────

  String _mapAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (lower.contains('email not confirmed') ||
        lower.contains('email_not_confirmed')) {
      return '이메일 인증이 필요합니다. 이메일함을 확인해주세요.';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already been registered')) {
      return '이미 가입된 이메일입니다.';
    }
    if (lower.contains('password should be') ||
        lower.contains('weak_password')) {
      return '비밀번호는 6자 이상이어야 합니다.';
    }
    return '오류가 발생했습니다: $msg';
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

  // ── 빌드 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            children: [
              // ── 로고 ──────────────────────────────────────────
              const Icon(
                Icons.store_mall_directory_rounded,
                color: Colors.white,
                size: 56,
              ),
              const SizedBox(height: 14),
              const Text(
                '겟머니',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '미션을 완료하고 포인트를 받아보세요',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 36),

              // ── 카드 ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTabToggle(),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _tabIndex == 0
                          ? _buildLoginForm()
                          : _buildSignUpForm(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 탭 토글 ──────────────────────────────────────────────────

  Widget _buildTabToggle() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _tabBtn(label: '로그인',   index: 0),
          _tabBtn(label: '회원가입', index: 1),
        ],
      ),
    );
  }

  Widget _tabBtn({required String label, required int index}) {
    final active = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: _isLoading ? null : () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active
                  ? const Color(0xFF1E3A8A)
                  : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  // ── 로그인 폼 ────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label('이메일'),
        _field(
          controller: _loginEmailCtrl,
          hint: 'example@email.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _label('비밀번호'),
        _field(
          controller: _loginPasswordCtrl,
          hint: '비밀번호 입력',
          obscure: _loginObscure,
          onObscureToggle: () =>
              setState(() => _loginObscure = !_loginObscure),
          onSubmitted: (_) { if (!_isLoading) _onLogin(); },
        ),
        const SizedBox(height: 24),
        _submitBtn(label: '로그인', onPressed: _isLoading ? null : _onLogin),
      ],
    );
  }

  // ── 회원가입 폼 ──────────────────────────────────────────────

  Widget _buildSignUpForm() {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label('이메일'),
        _field(
          controller: _signupEmailCtrl,
          hint: 'example@email.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _label('비밀번호 (6자 이상)'),
        _field(
          controller: _signupPasswordCtrl,
          hint: '6자 이상 입력',
          obscure: _signupObscure,
          onObscureToggle: () =>
              setState(() => _signupObscure = !_signupObscure),
        ),
        const SizedBox(height: 24),
        _submitBtn(label: '가입하기', onPressed: _isLoading ? null : _onSignUp),
      ],
    );
  }

  // ── 공통 위젯 ────────────────────────────────────────────────

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? onObscureToggle,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Color(0xFF1E3A8A), width: 1.5),
        ),
        suffixIcon: onObscureToggle != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: Colors.grey.shade400,
                ),
                onPressed: onObscureToggle,
              )
            : null,
      ),
    );
  }

  Widget _submitBtn({
    required String label,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1E3A8A),
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
