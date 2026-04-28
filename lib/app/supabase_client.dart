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
  );
}

/// 앱 전역에서 사용하는 Supabase 클라이언트
SupabaseClient get supabase => Supabase.instance.client;
