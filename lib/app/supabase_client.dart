import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 연결 설정
/// 실행 시 --dart-define 플래그로 환경변수를 전달합니다:
///
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJxxxxx
///
/// VSCode launch.json 예시:
/// "args": [
///   "--dart-define=SUPABASE_URL=https://xxxx.supabase.co",
///   "--dart-define=SUPABASE_ANON_KEY=eyJxxxxx"
/// ]

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://wfxlihrqjtexuxvoajny.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndmeGxpaHJxanRleHV4dm9ham55Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NDc2MjUsImV4cCI6MjA4OTMyMzYyNX0.zZOnSyc5ijJGK2TS20p_y2C28MvSOV3WURAYDJy4-Nc',
);

/// Supabase 클라이언트 초기화
Future<void> initSupabase() async {
  assert(supabaseUrl.isNotEmpty, 'SUPABASE_URL이 설정되지 않았습니다.');
  assert(supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY가 설정되지 않았습니다.');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    // 메일 링크는 보낸 기기가 아닌 다른 브라우저에서 열린다.
    // 앱에서 비밀번호 찾기를 눌러도 링크는 휴대폰 브라우저(웹)에서 열리고,
    // 인증 메일도 PC에서 여는 경우가 많다.
    //
    // 기본값인 PKCE 는 링크를 '요청한 바로 그 클라이언트'에만 저장된 값
    // (code_verifier)이 있어야 로그인이 완성된다. 다른 브라우저에서 열면
    // 토큰을 받고도 세션을 만들지 못해 '링크를 사용할 수 없습니다'가 뜬다
    // (2026-10-11 실측 — 토큰은 정상 전달됐는데 세션이 생기지 않았다).
    //
    // implicit 은 링크 자체에 토큰이 담겨 어느 브라우저에서나 열린다.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );
}

/// 앱 전역에서 사용하는 Supabase 클라이언트
SupabaseClient get supabase => Supabase.instance.client;
