// ─────────────────────────────────────────────────────────────────
// 인증 오류 문구 한글화
//
// Supabase(GoTrue)가 돌려주는 영문 메시지를 그대로 보여주면 고객이
// 무엇을 해야 하는지 알 수 없다. 특히 'Email link is invalid or has
// expired' 는 대부분 **이미 한 번 사용한 링크를 다시 누른 경우**인데,
// 영문만 보면 가입이 실패한 줄 알고 문의가 들어온다.
//
// 원인 문구가 아니라 '다음에 무엇을 하면 되는지'를 적는다.
// ─────────────────────────────────────────────────────────────────

/// GoTrue 오류 메시지를 고객용 한글 안내로 바꾼다.
///
/// 모르는 오류는 원문을 그대로 남긴다 — 숨기면 원인을 추적할 수 없다.
String authErrorText(String raw) {
  final msg = raw.toLowerCase();

  // 메일 링크는 1회용이다. 이미 썼거나 유효 기간이 지난 경우.
  if (msg.contains('invalid or has expired') ||
      msg.contains('token has expired') ||
      msg.contains('otp_expired') ||
      msg.contains('access_denied')) {
    return '이미 사용했거나 기간이 지난 링크입니다.\n'
        '인증 메일의 링크는 한 번만 사용할 수 있습니다.\n'
        '이미 인증을 마치셨다면 그대로 로그인해 주세요.';
  }

  if (msg.contains('email not confirmed')) {
    return '이메일 인증이 아직 끝나지 않았습니다. 메일함에서 인증을 완료해 주세요.';
  }
  if (msg.contains('invalid login credentials')) {
    return '이메일 또는 비밀번호가 올바르지 않습니다.';
  }
  if (msg.contains('user already registered') ||
      msg.contains('already been registered')) {
    return '이미 가입된 이메일입니다. 로그인하거나 비밀번호 찾기를 이용해 주세요.';
  }
  if (msg.contains('password should be at least')) {
    return '비밀번호는 6자 이상이어야 합니다.';
  }
  if (msg.contains('same password')) {
    return '기존과 다른 비밀번호를 입력해 주세요.';
  }
  if (msg.contains('rate limit') || msg.contains('too many requests') ||
      msg.contains('for security purposes')) {
    return '요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.';
  }
  if (msg.contains('network') || msg.contains('failed host lookup')) {
    return '네트워크 연결을 확인해 주세요.';
  }

  return raw;
}
