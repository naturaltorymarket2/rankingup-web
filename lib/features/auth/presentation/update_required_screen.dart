import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/utils/app_update_gate.dart';

// ─────────────────────────────────────────────────────────────────
// 업데이트 안내 화면 (/update)
//
// 서버가 요구하는 최소 버전보다 낮을 때 스플래시에서 이리로 보낸다.
// force 면 닫을 수 없고, 아니면 [나중에]로 넘어갈 수 있다.
// ─────────────────────────────────────────────────────────────────

class UpdateRequiredScreen extends StatelessWidget {
  final AppUpdateInfo info;

  /// 건너뛰었을 때 이어서 갈 경로 (스플래시가 판단한 목적지)
  final String nextLocation;

  const UpdateRequiredScreen({
    super.key,
    required this.info,
    required this.nextLocation,
  });

  static const _kBlue = Color(0xFF1E3A8A);

  Future<void> _openStore(BuildContext context) async {
    final url = info.storeUrl.isEmpty
        ? 'https://play.google.com/store/apps/details?id=com.storetrafficbooster.app'
        : info.storeUrl;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('스토어를 열지 못했습니다. Play 스토어에서 "퀴즈캐시나우"를 검색해 주세요.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // force 면 뒤로가기로 빠져나가지 못하게 막는다
    return PopScope(
      canPop: !info.force,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.system_update, size: 56, color: _kBlue),
                  const SizedBox(height: 20),
                  const Text(
                    '업데이트가 필요합니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    info.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, height: 1.6, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _openStore(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Play 스토어에서 업데이트',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (!info.force) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go(nextLocation),
                      child: Text(
                        '나중에 하기',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(
                      '업데이트 후 앱을 다시 실행해 주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
