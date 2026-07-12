import '../../app/supabase_client.dart';

/// 현재 계정의 역할이 ADVERTISER(광고주)인지 확인한다.
///
/// users.role을 "유저 vs 광고주" 구분의 단일 진실 공급원으로 사용한다.
/// (이전에는 business_info 존재 여부로 추정했으나, 사업자 등록 완료 시점에
/// register_advertiser RPC가 role을 ADVERTISER로 명시적으로 고정하므로
/// role을 직접 보는 것이 더 정확함)
/// users_self_select RLS 정책(`auth.uid() = id`)이 본인 row만 반환하도록
/// 보장하므로, 호출자는 항상 본인 userId로만 호출해야 한다.
Future<bool> isRegisteredAdvertiser(String userId) async {
  final row = await supabase
      .from('users')
      .select('role')
      .eq('id', userId)
      .maybeSingle();
  return row?['role'] == 'ADVERTISER';
}

/// 웹(/web/login)으로 로그인/이메일 인증한 계정의 role을 ADVERTISER로 확정한다.
///
/// /web/login은 광고주 전용 화면이므로(앱 유저는 /login 사용), 여기를 통해
/// 세션이 확보된 계정은 곧 광고주 계정이다. 사업자 정보(business_info) 등록은
/// 더 이상 필요 없다 — role만이 단일 진실 공급원이다.
///
/// 반드시 세션이 존재하는 시점(로그인 직후/이메일 인증 완료 직후)에 호출해야
/// 한다 — RLS(users_self_update: auth.uid() = id)가 auth.uid()를 요구하기
/// 때문에, 세션 없이 호출하면 0건 업데이트로 조용히 실패한다.
Future<void> finalizeAdvertiserRole(String userId) async {
  await supabase.from('users').update({'role': 'ADVERTISER'}).eq('id', userId);
}

/// 해당 이메일로 이미 가입된 계정이 있는지(인증 여부 무관) 확인한다.
///
/// 가입 전(미인증) 상태에서 호출하므로 public.users를 직접 조회할 수 없다
/// (RLS가 본인 row만 허용) — SECURITY DEFINER RPC(check_email_exists)로
/// boolean 1개만 받아온다.
Future<bool> checkEmailExists(String email) async {
  final result = await supabase.rpc(
    'check_email_exists',
    params: {'p_email': email},
  );
  return result == true;
}
