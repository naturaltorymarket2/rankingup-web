import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app/router.dart';
import 'app/supabase_client.dart';

Future<void> main() async {
  usePathUrlStrategy(); // Hash URL (#/) 대신 Path URL (/경로) 전략 사용
  WidgetsFlutterBinding.ensureInitialized();

  await initSupabase();
  if (!kIsWeb) await MobileAds.instance.initialize();

  runApp(
    const ProviderScope(
      child: StoreTrafficBoosterApp(),
    ),
  );
}

class StoreTrafficBoosterApp extends StatelessWidget {
  const StoreTrafficBoosterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '겟머니',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
