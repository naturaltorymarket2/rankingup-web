import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/auth_error_text.dart';

// ─────────────────────────────────────────────────────────────────
// 비밀번호 재설정 화면 (/reset)
//
// 재설정 메일의 링크로 열린다. 링크에는 일회용 토큰이 들어 있어
// 열리는 순간 Supabase 가 임시 세션을 만든다(passwordRecovery).
// 그 세션으로 새 비밀번호를 저장한 뒤 로그아웃한다.
//
// 링크를 이미 썼거나 기간이 지났으면 세션이 생기지 않는다 —
// 그때는 영문 오류 대신 무엇을 하면 되는지 한글로 안내한다.
// ─────────────────────────────────────────────────────────────────

class PasswordResetScreen extends StatefulWidget {
  /// 링크가 유효하지 않을 때 Supabase 가 전달한 오류(있으면)
  final String? linkError;

  const PasswordResetScreen({super.key, this.linkError});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  static const _kBlue = Color(0xFF1E3A8A);
  static const _kRed  = Color(0xFFB71C1C);

  final _pwCtrl      = TextEditingController();
  final _pwCheckCtrl = TextEditingController();

  StreamSubscription<AuthState>? _authSub;

  bool    _hasSession = false;
  bool    _obscure    = true;
  bool    _isSaving   = false;
  bool    _isDone     = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _hasSession = supabase.auth.currentSession != null;

    // 링크로 들어온 직후에는 토큰 처리가 끝나지 않았을 수 있다.
    // passwordRecovery / signedIn 이벤트를 기다린다.
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.session != null && !_hasSession) {
        setState(() => _hasSession = true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _pwCtrl.dispose();
    _pwCheckCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pw    = _pwCtrl.text;
    final check = _pwCheckCtrl.text;

    if (pw.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상이어야 합니다.');
      return;
    }
    if (pw != check) {
      setState(() => _error = '비밀번호가 서로 다릅니다.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error    = null;
    });

    try {
      await supabase.auth.updateUser(UserAttributes(password: pw));
      // 재설정이 끝나면 임시 세션은 정리한다 — 새 비밀번호로 다시 로그인한다.
      await supabase.auth.signOut();
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isDone   = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error    = authErrorText(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error    = '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isDone)              return _buildDone();
    if (widget.linkError != null || !_hasSession) return _buildLinkProblem();
    return _buildForm();
  }

  // ── 새 비밀번호 입력 ───────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, size: 40, color: _kBlue),
        const SizedBox(height: 12),
        const Text('새 비밀번호 설정',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('앞으로 사용할 비밀번호를 입력해 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 24),
        TextField(
          controller: _pwCtrl,
          obscureText: _obscure,
          enabled: !_isSaving,
          decoration: InputDecoration(
            labelText: '새 비밀번호 (6자 이상)',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwCheckCtrl,
          obscureText: _obscure,
          enabled: !_isSaving,
          decoration: const InputDecoration(
            labelText: '새 비밀번호 확인',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) { if (!_isSaving) _save(); },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: _kRed, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('비밀번호 변경'),
          ),
        ),
      ],
    );
  }

  // ── 변경 완료 ─────────────────────────────────────────────────
  Widget _buildDone() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, size: 44, color: Color(0xFF2E7D32)),
        const SizedBox(height: 12),
        const Text('비밀번호를 변경했습니다',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          '퀴즈캐시나우 앱에서 새 비밀번호로 로그인해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: () => context.go('/web/login'),
            child: const Text('광고주 로그인으로 이동'),
          ),
        ),
      ],
    );
  }

  // ── 링크가 유효하지 않을 때 ────────────────────────────────────
  Widget _buildLinkProblem() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.link_off, size: 40, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('링크를 사용할 수 없습니다',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          widget.linkError != null
              ? authErrorText(widget.linkError!)
              : '이미 사용했거나 기간이 지난 링크입니다.\n'
                '비밀번호 찾기를 다시 요청해 주세요.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: () => context.go('/web/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('로그인 화면으로'),
          ),
        ),
      ],
    );
  }
}
