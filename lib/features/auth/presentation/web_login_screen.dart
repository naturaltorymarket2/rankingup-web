import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/account_type.dart';

// ─────────────────────────────────────────────────────────────────
// 광고주 로그인 / 회원가입 웹 화면 (/web/login)
// ─────────────────────────────────────────────────────────────────
//
// 탭 구성:
//   0: 로그인  — 이메일 + 비밀번호 → /web/dashboard
//   1: 회원가입 — 2단계
//      Step 1:   이메일 + 비밀번호 → supabase.auth.signUp() → role=ADVERTISER 설정
//      Step 1.5: 이메일 인증 대기  → onAuthStateChange / fallback 버튼 → /web/dashboard
//
// ⚠ Supabase 설정 필요:
//   Authentication → Providers → Email → "Confirm email" 활성화
//   → Phase 12 이메일 인증 도입

class WebLoginScreen extends StatefulWidget {
  /// true이면 화면 진입 시 "이메일 인증이 완료되었습니다" 스낵바를 표시한다.
  /// Supabase 인증 콜백(/?code=xxxx)에서 리다이렉트될 때 router가 true로 전달.
  final bool showVerifiedBanner;

  /// null이 아니면 화면 진입 시 빨간 스낵바로 에러 메시지를 표시한다.
  /// Supabase 인증 에러 콜백(/?error=...&error_description=...)에서 router가 전달.
  final String? authError;

  const WebLoginScreen({
    super.key,
    this.showVerifiedBanner = false,
    this.authError,
  });

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  // ── 탭 / 단계 상태 ─────────────────────────────────────────────
  int  _tabIndex         = 0;     // 0: 로그인, 1: 회원가입
  bool _isEmailVerifyStep = false; // false: 계정정보 입력, true: 이메일 인증 대기
  bool _isLoading        = false;

  // ── 이메일 인증 단계 상태 ───────────────────────────────────────
  bool _isSendingEmail    = false;
  bool _isCheckingConfirm = false;
  StreamSubscription<AuthState>? _authSub;

  // ── 로그인 폼 ────────────────────────────────────────────────────
  final _loginEmailCtrl    = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool  _loginObscure      = true;

  // ── 회원가입 폼 ──────────────────────────────────────────────────
  final _signupEmailCtrl    = TextEditingController();
  final _signupPwCtrl       = TextEditingController();
  final _signupBizNumCtrl   = TextEditingController();
  final _signupTaxEmailCtrl = TextEditingController();
  bool  _signupObscure      = true;

  @override
  void initState() {
    super.initState();
    if (widget.authError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showError('인증 오류: ${Uri.decodeComponent(widget.authError!)}');
      });
    } else if (widget.showVerifiedBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSuccess('이메일 인증이 완료되었습니다. 로그인해주세요.');
      });
    }
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted || !_isEmailVerifyStep) return;
      if (data.event != AuthChangeEvent.userUpdated) return;
      final confirmedAt = data.session?.user.emailConfirmedAt;
      if (confirmedAt != null && mounted) {
        context.go('/web/dashboard');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPwCtrl.dispose();
    super.dispose();
  }

  // ── 탭 전환 (step 리셋 포함) ──────────────────────────────────
  void _switchTab(int index) {
    setState(() {
      _tabIndex          = index;
      _isEmailVerifyStep = false;
    });
  }

  // ── 로그인 처리 ──────────────────────────────────────────────────
  Future<void> _onLogin() async {
    final email    = _loginEmailCtrl.text.trim();
    final password = _loginPasswordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        _showError('오류가 발생했습니다. 다시 시도해주세요');
        return;
      }

      // role == ADVERTISER 여부로 사업자 등록 완료 여부 판단 (단일 진실 공급원)
      final isAdvertiser = await isRegisteredAdvertiser(userId);
      if (!mounted) return;

      if (isAdvertiser) {
        context.go('/web/dashboard');
      } else {
        // 가입 자체가 앱/웹으로 분리된 이후로는 정상적으로는 발생하지 않아야
        // 하는 케이스(이메일 중복 가입 차단으로 막힘) — 방어 코드로 차단.
        await supabase.auth.signOut();
        if (mounted) {
          _showError('사업자 정보 등록이 완료되지 않은 계정입니다. 회원가입을 다시 진행해주세요.');
        }
      }
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('오류가 발생했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 회원가입 Step 1: 계정 생성 ──────────────────────────────────
  Future<void> _onSignUpStep1() async {
    final email    = _signupEmailCtrl.text.trim();
    final password = _signupPwCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요');
      return;
    }
    if (password.length < 6) {
      _showError('비밀번호는 6자 이상이어야 합니다');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 이메일 중복 가입 사전 차단 (인증 여부 무관 — 앱 가입과 분리)
      if (await checkEmailExists(email)) {
        _showError('이미 가입된 이메일입니다. 일반 유저 계정이라면 웹에서는 가입할 수 없습니다.');
        return;
      }

      final res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (res.user == null) {
        _showError('회원가입에 실패했습니다. 다시 시도해주세요');
        return;
      }

      // 웹 가입 = 광고주 계정 — role을 ADVERTISER로 즉시 설정
      await supabase
          .from('users')
          .update({'role': 'ADVERTISER'})
          .eq('id', supabase.auth.currentUser!.id);

      // 가입 후 → 이메일 인증 대기 단계로 이동
      setState(() => _isEmailVerifyStep = true);
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('오류가 발생했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 이메일 인증 단계: 재발송 / 수동 확인 ──────────────────────────
  Future<void> _resendVerifyEmail() async {
    final email = _signupEmailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _isSendingEmail = true);
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
      _showSuccess('인증 메일을 재발송했습니다.');
    } catch (_) {
      _showError('재발송에 실패했습니다. 잠시 후 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  Future<void> _checkWebConfirmed() async {
    setState(() => _isCheckingConfirm = true);
    try {
      await supabase.auth.refreshSession();
      final confirmedAt = supabase.auth.currentUser?.emailConfirmedAt;
      if (!mounted) return;
      if (confirmedAt != null) {
        context.go('/web/dashboard');
      } else {
        _showError('아직 인증이 완료되지 않았습니다');
      }
    } catch (_) {
      if (mounted) _showError('아직 인증이 완료되지 않았습니다');
    } finally {
      if (mounted) setState(() => _isCheckingConfirm = false);
    }
  }

  // ── 에러/성공 메시지 매핑 ─────────────────────────────────────────
  String _mapAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다';
    }
    if (lower.contains('email not confirmed') ||
        lower.contains('email_not_confirmed')) {
      return '이메일 인증이 필요합니다. 이메일함을 확인해주세요';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already_registered') ||
        lower.contains('already been registered')) {
      return '이미 가입된 이메일입니다';
    }
    if (lower.contains('password should be') ||
        lower.contains('weak_password')) {
      return '비밀번호는 6자 이상이어야 합니다';
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

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.indigo.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ));
  }

  // ─────────────────────────────────────────────────────────────────
  // 빌드
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                _buildLogo(),
                const SizedBox(height: 24),
                const SizedBox(height: 12),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabToggle(),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _currentForm(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildFooterNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 현재 탭/단계에 맞는 폼 위젯 반환
  Widget _currentForm() {
    if (_tabIndex == 0) return _buildLoginForm();
    if (!_isEmailVerifyStep) return _buildSignUpStep1();
    return _buildEmailVerifyStep();
  }

  // ─────────────────────────────────────────────────────────────────
  // 로고 영역
  // ─────────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.indigo,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.store_mall_directory_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '퀴즈캐시나우',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '광고주 관리 플랫폼',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 카드 컨테이너
  // ─────────────────────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 탭 전환 토글
  // ─────────────────────────────────────────────────────────────────

  Widget _buildTabToggle() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _tabButton(label: '로그인',   index: 0),
          _tabButton(label: '회원가입', index: 1),
        ],
      ),
    );
  }

  Widget _tabButton({required String label, required int index}) {
    final isActive = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: _isLoading ? null : () => _switchTab(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.indigo.shade700 : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 로그인 폼
  // ─────────────────────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel('이메일'),
        _inputField(
          controller: _loginEmailCtrl,
          hint: 'example@company.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _fieldLabel('비밀번호'),
        _inputField(
          controller: _loginPasswordCtrl,
          hint: '비밀번호 입력',
          obscure: _loginObscure,
          onObscureToggle: () =>
              setState(() => _loginObscure = !_loginObscure),
          onSubmitted: (_) => _isLoading ? null : _onLogin(),
        ),
        const SizedBox(height: 28),
        _submitBtn(label: '로그인', onPressed: _isLoading ? null : _onLogin),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 회원가입 Step 1.5: 이메일 인증 대기
  // ─────────────────────────────────────────────────────────────────

  Widget _buildEmailVerifyStep() {
    final isVerifyLoading = _isSendingEmail || _isCheckingConfirm;
    final email = _signupEmailCtrl.text.trim();

    return Column(
      key: const ValueKey('signup-step-verify'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          color: Colors.indigo,
          size: 48,
        ),
        const SizedBox(height: 16),
        const Text(
          '이메일 인증',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
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
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.indigo.shade700,
            ),
          ),
        ],
        const SizedBox(height: 28),
        _submitBtn(
          label: '인증 완료했어요',
          onPressed: isVerifyLoading ? null : _checkWebConfirmed,
          isLoading: _isCheckingConfirm,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: isVerifyLoading ? null : _resendVerifyEmail,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.indigo.shade400),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSendingEmail
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.indigo.shade400,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    '인증 메일 재발송',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 회원가입 Step 1: 계정 정보
  // ─────────────────────────────────────────────────────────────────

  Widget _buildSignUpStep1() {
    return Column(
      key: const ValueKey('signup-step1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel('이메일 *'),
        _inputField(
          controller: _signupEmailCtrl,
          hint: 'example@company.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _fieldLabel('비밀번호 * (6자 이상)'),
        _inputField(
          controller: _signupPwCtrl,
          hint: '6자 이상 입력',
          obscure: _signupObscure,
          onObscureToggle: () =>
              setState(() => _signupObscure = !_signupObscure),
        ),
        const SizedBox(height: 28),
        _submitBtn(
          label: '다음 →',
          onPressed: _isLoading ? null : _onSignUpStep1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 회원가입 Step 2: 사업자 정보
  // ─────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────
  // 하단 안내
  // ─────────────────────────────────────────────────────────────────

  Widget _buildFooterNote() {
    return Text(
      '앱 유저 로그인은 퀴즈캐시나우 앱에서 이용해주세요',
      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      textAlign: TextAlign.center,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 공통 위젯 헬퍼
  // ─────────────────────────────────────────────────────────────────

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? onObscureToggle,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters, // B-006
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
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
          borderSide: BorderSide(color: Colors.indigo.shade400, width: 1.5),
        ),
        suffixIcon: onObscureToggle != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: Colors.grey.shade500,
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
    bool? isLoading,
  }) {
    final showSpinner = isLoading ?? _isLoading;
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.indigo,
          disabledBackgroundColor: Colors.grey.shade300,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: showSpinner
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
