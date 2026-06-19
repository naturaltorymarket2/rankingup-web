import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ─────────────────────────────────────────────────────────────────
// 미션 검색 화면 (/mission/:id/search)  — 인앱 WebView
// ─────────────────────────────────────────────────────────────────
//
// go_router extra 수신:
//   - log_id      : start_mission RPC 응답의 log_id (UUID)
//   - keyword     : 검색 키워드 (WebView URL 생성 + 안내 표시용)
//   - tag_index   : 정답 태그 순서 (1-based, 없으면 null)
//   - product_url : 캠페인 상품 URL (null이면 미사용)
//   - product_name: 상품명 (null이면 미표시)
//   - brand_name  : 브랜드명 (null이면 미표시)

class MissionSearchScreen extends StatefulWidget {
  final String  id;
  final String  logId;
  final String  keyword;
  final int?    tagIndex;
  final String? productUrl;
  final String? productName;
  final String? brandName;

  const MissionSearchScreen({
    super.key,
    required this.id,
    required this.logId,
    required this.keyword,
    this.tagIndex,
    this.productUrl,
    this.productName,
    this.brandName,
  });

  @override
  State<MissionSearchScreen> createState() => _MissionSearchScreenState();
}

class _MissionSearchScreenState extends State<MissionSearchScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    final encoded = Uri.encodeComponent(widget.keyword);
    final url =
        'https://search.shopping.naver.com/search/all?query=$encoded';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  void _goToActive() {
    context.push(
      '/mission/${widget.id}/active',
      extra: {
        'log_id':       widget.logId,
        'keyword':      widget.keyword,
        'tag_index':    widget.tagIndex,
        'product_url':  widget.productUrl,
        'product_name': widget.productName,
        'brand_name':   widget.brandName,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.keyword,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          FilledButton(
            onPressed: _goToActive,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('태그 입력'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
