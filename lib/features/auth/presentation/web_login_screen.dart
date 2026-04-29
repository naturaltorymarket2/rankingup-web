import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_client.dart';

// ─────────────────────────────────────────────────────────────────
// 광고주 로그인 / 회원가입 웹 화면 (/web/login)
// ─────────────────────────────────────────────────────────────────
//
// 탭 구성:
//   0: 로그인  — 이메일 + 비밀번호 → /web/dashboard
//   1: 회원가입 — 2단계
//      Step 1: 이메일 + 비밀번호 → supabase.auth.signUp()
//      Step 2: 사업자 정보      → register_advertiser RPC → /web/dashboard
//
// ⚠ 권장 Supabase 설정:
//   Authentication → Providers → Email → "Confirm email" 비활성화
//   → 가입 즉시 세션 발급, 별도 이메일 인증 불필요

class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  // ── 탭 / 단계 상태 ─────────────────────────────────────────────
  int  _tabIndex   = 0;  // 0: 로그인, 1: 회원가입
  int  _signupStep = 1;  // 1: 계정정보, 2: 사업자정보
  bool _isLoading  = false;

  // ── 로그인 폼 ────────────────────────────────────────────────────
  final _loginEmailCtrl    = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool  _loginObscure      = true;

  // ── 회원가입 폼 ──────────────────────────────────────────────────
  final _signupEmailCtrl    = TextEditingController();
  final _signupPwCtrl       = TextEditingController();
  final _signupPhoneCtrl    = TextEditingController();
  final _signupCompanyCtrl  = TextEditingController();
  final _signupBizNumCtrl   = TextEditingController();
  final _signupTaxEmailCtrl = TextEditingController();
  bool  _signupObscure      = true;

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPwCtrl.dispose();
    _signupPhoneCtrl.dispose();
    _signupCompanyCtrl.dispose();
    _signupBizNumCtrl.dispose();
    _signupTaxEmailCtrl.dispose();
    super.dispose();
  }

  // ── 탭 전환 (step 리셋 포함) ──────────────────────────────────
  void _switchTab(int index) {
    setState(() {
      _tabIndex   = index;
      _signupStep = 1;
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
      if (mounted) context.go('/web/dashboard');
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
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (res.user == null) {
        _showError('회원가입에 실패했습니다. 다시 시도해주세요');
        return;
      }

      // 이메일 인증이 필요한 경우 (Supabase "Confirm email" ON)
      if (res.session == null) {
        _showSuccess(
          '가입 확인 이메일을 발송했습니다.\n'
          '이메일 인증 완료 후 로그인해주세요.',
        );
        setState(() => _tabIndex = 0);
        return;
      }

      // 세션 확보 완료 → Step 2 (사업자 정보) 로 이동
      setState(() => _signupStep = 2);
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('오류가 발생했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 회원가입 Step 2: 사업자 정보 등록 ───────────────────────────
  Future<void> _onSignUpStep2() async {
    final phone    = _signupPhoneCtrl.text.trim();
    final company  = _signupCompanyCtrl.text.trim();
    final bizNum   = _signupBizNumCtrl.text.trim();
    final taxEmail = _signupTaxEmailCtrl.text.trim();

    if (phone.isEmpty || company.isEmpty || bizNum.isEmpty) {
      _showError('필수 항목을 모두 입력해주세요 (*)');
      return;
    }
    // B-006: 사업자등록번호 10자리 검증
    if (bizNum.length != 10) {
      _showError('사업자등록번호는 10자리 숫자로 입력해주세요');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final rpcRes = await supabase.rpc(
        'register_advertiser',
        params: {
          'p_company_name':    company,
          'p_business_number': bizNum,
          'p_phone':           phone,
          'p_tax_email':       taxEmail.isEmpty ? null : taxEmail,
        },
      ) as Map<String, dynamic>;

      if (rpcRes['success'] != true) {
        final code = rpcRes['error'] as String? ?? 'UNKNOWN_ERROR';
        await supabase.auth.signOut();
        if (mounted) {
          _showError(_mapRpcError(code));
          setState(() => _signupStep = 1);
        }
        return;
      }

      if (mounted) context.go('/web/dashboard');
    } on AuthException catch (e) {
      await supabase.auth.signOut();
      if (mounted) {
        _showError(_mapAuthError(e.message));
        setState(() => _signupStep = 1);
      }
    } catch (_) {
      await supabase.auth.signOut();
      if (mounted) {
        _showError('회원가입 중 오류가 발생했습니다. 다시 시도해주세요');
        setState(() => _signupStep = 1);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  String _mapRpcError(String code) {
    return switch (code) {
      'ALREADY_REGISTERED' => '이미 등록된 사업자 정보입니다',
      'NOT_AUTHENTICATED'  => '인증 오류가 발생했습니다. 다시 시도해주세요',
      'INVALID_PARAMS'     => '입력값을 확인해주세요',
      _                    => '오류가 발생했습니다. 다시 시도해주세요',
    };
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
    if (_signupStep == 1) return _buildSignUpStep1();
    return _buildSignUpStep2();
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
          '겟머니',
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
  // 회원가입 Step 1: 계정 정보
  // ─────────────────────────────────────────────────────────────────

  Widget _buildSignUpStep1() {
    return Column(
      key: const ValueKey('signup-step1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStepIndicator(),
        const SizedBox(height: 24),
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

  Widget _buildSignUpStep2() {
    return Column(
      key: const ValueKey('signup-step2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStepIndicator(),
        const SizedBox(height: 24),
        _fieldLabel('휴대폰 번호 *'),
        _inputField(
          controller: _signupPhoneCtrl,
          hint: '010-0000-0000',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),
        _fieldLabel('상호명 *'),
        _inputField(
          controller: _signupCompanyCtrl,
          hint: '사업자 상호명 입력',
        ),
        const SizedBox(height: 14),
        _fieldLabel('사업자등록번호 * (10자리)'),
        _inputField(
          controller: _signupBizNumCtrl,
          hint: '숫자만 입력 (10자리)',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        const SizedBox(height: 14),
        _fieldLabel('세금계산서 이메일 (선택)'),
        _inputField(
          controller: _signupTaxEmailCtrl,
          hint: 'tax@company.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 28),
        _submitBtn(
          label: '가입 완료',
          onPressed: _isLoading ? null : _onSignUpStep2,
        ),
        const SizedBox(height: 12),
        Text(
          '* 표시는 필수 입력 항목입니다',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Step 인디케이터 (1 ── 2)
  // ─────────────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _stepDot(1, '계정 정보'),
        Expanded(
          child: Container(
            height: 2,
            color: _signupStep >= 2 ? Colors.indigo : Colors.grey.shade300,
          ),
        ),
        _stepDot(2, '사업자 정보'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _signupStep == step;
    final isDone   = _signupStep > step;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDone || isActive ? Colors.indigo : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive || isDone ? Colors.indigo : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // 하단 안내
  // ─────────────────────────────────────────────────────────────────

  Widget _buildFooterNote() {
    return Text(
      '앱 유저 로그인은 겟머니 앱에서 이용해주세요',
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
    List<TextInputFormatter>? inputFormatters, // B-006
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onSubmitted: onSubmitted,
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
  }) {
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
