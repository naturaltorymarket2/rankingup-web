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
