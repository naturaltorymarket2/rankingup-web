import '../../app/supabase_client.dart';

/// 광고주 웹을 쓸 수 있는 계정인지 확인한다.
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
      .select('role, is_advertiser')
      .eq('id', userId)
      .maybeSingle();
  // is_advertiser 가 광고주 자격의 단일 기준이다.
  // role 비교는 이관 전 데이터를 위한 보조 조건으로만 남긴다.
  return row?['is_advertiser'] == true || row?['role'] == 'ADVERTISER';
}

/// 가입한 경로를 auth user_metadata 에 남기는 키.
///
/// 이메일 인증 링크는 앱 가입이든 웹 가입이든 같은 주소(웹)로 열린다.
/// 그래서 링크만 보고는 어느 쪽으로 가입했는지 알 수 없고, 앱으로 가입한
/// 계정까지 광고주로 승격되어 앱 로그인이 막히는 일이 있었다.
/// 가입 시점에 의도를 적어 두고, 승격 여부를 이 값으로 판단한다.
const String kAccountTypeKey = 'account_type';

/// 앱에서 가입한 계정(USER)이면 true.
///
/// 이 표시가 없는 계정은 이 기능이 들어오기 전에 가입한 것이다 —
/// 그때는 웹 가입만 이메일 인증 후 승격되는 구조였으므로, 표시가 없으면
/// 기존 동작(승격 허용)을 유지한다.
bool isAppSignup() {
  final type = supabase.auth.currentUser?.userMetadata?[kAccountTypeKey];
  return type == 'USER';
}

/// 광고주 자격을 켠다 — **가입을 마친 시점에만** 호출한다.
///
/// /web/login은 광고주 전용 화면이므로(앱 유저는 /login 사용), 여기를 통해
/// 세션이 확보된 계정은 곧 광고주 계정이다. 사업자 정보(business_info) 등록은
/// 더 이상 필요 없다 — role만이 단일 진실 공급원이다.
///
/// 반드시 세션이 존재하는 시점(로그인 직후/이메일 인증 완료 직후)에 호출해야
/// 한다 — RLS(users_self_update: auth.uid() = id)가 auth.uid()를 요구하기
/// 때문에, 세션 없이 호출하면 0건 업데이트로 조용히 실패한다.
Future<void> finalizeAdvertiserRole(String userId) async {
  // 로그인만으로 승격하지 않는다. 앱 유저가 광고주 웹에 한 번 들어갔다는
  // 이유로 앱 로그인이 막히던 문제가 있었다(2026-10-13).
  // role 은 건드리지 않는다 — 광고주이면서 앱 유저일 수 있다.
  await supabase.rpc('mark_self_advertiser');
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
