import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/auth_error_text.dart';

// ─────────────────────────────────────────────────────────────────
// 비밀번호 찾기 — 재설정 메일 보내기
//
// 앱 로그인 화면과 광고주 웹 로그인 화면이 함께 쓴다.
// 메일의 링크는 웹의 /reset 화면으로 열리고, 거기서 새 비밀번호를
// 정한다(앱은 딥링크가 없어 메일에서 바로 앱을 열 수 없다).
// ─────────────────────────────────────────────────────────────────

/// 비밀번호 재설정 메일을 보내는 링크가 열리는 주소
const String kPasswordResetRedirect =
    'https://rankingup-web-production.up.railway.app/reset';

Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ForgotPasswordDialog(initialEmail: initialEmail),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  static const _kBlue = Color(0xFF1E3A8A);

  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail);

  bool    _isSending = false;
  bool    _isSent    = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = '이메일 주소를 정확히 입력해 주세요.');
      return;
    }

    setState(() {
      _isSending = true;
      _error     = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: kPasswordResetRedirect,
      );
      if (!mounted) return;
      // 가입되지 않은 주소여도 성공으로 응답한다(계정 존재 여부를 알려주지
      // 않는 Supabase 기본 동작). 안내 문구도 그에 맞춘다.
      setState(() {
        _isSending = false;
        _isSent    = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error     = authErrorText(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error     = '메일 발송에 실패했습니다. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isSent ? '메일을 보냈습니다' : '비밀번호 찾기'),
      content: SizedBox(
        width: 380,
        child: _isSent ? _buildSent() : _buildForm(),
      ),
      actions: _isSent
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ]
          : [
              TextButton(
                onPressed: _isSending ? null : () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: _isSending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('재설정 메일 받기'),
              ),
            ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '가입하신 이메일로 비밀번호 재설정 링크를 보내드립니다.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emailCtrl,
          enabled: !_isSending,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '이메일',
            hintText: 'example@email.com',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) { if (!_isSending) _send(); },
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_emailCtrl.text.trim()} 으로\n비밀번호 재설정 링크를 보냈습니다.',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '• 메일이 보이지 않으면 스팸함도 확인해 주세요.\n'
            '• 링크는 한 번만 사용할 수 있습니다.\n'
            '• 새 비밀번호를 정한 뒤 앱에서 다시 로그인해 주세요.',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ),
      ],
    );
  }
}
