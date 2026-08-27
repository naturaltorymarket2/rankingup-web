import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/admin_campaign_model.dart';
import 'admin_campaign_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 광고 승인 화면  (/admin/campaign)
//
// 접근 제한: role = ADMIN (서버 RPC에서 검증)
//
// 흐름:
//   1. 광고주가 광고를 등록하면 approval_status = 'PENDING' 으로 대기
//   2. 어드민이 [상품 페이지 열기]로 실제 스마트스토어 페이지를 확인하고
//      상품명 아래 #태그를 그대로 긁어 붙여넣는다 ("#AAA#BBB#CCC")
//   3. '#' 기준으로 분리 → 붙여넣은 순서가 그대로 태그 순서(sort_order)
//   4. [승인] → approve_campaign RPC
//      = 태그 등록 + 포인트 차감 + status ACTIVE 전환 (앱 미션 보드 노출 시작)
//
// 앱은 이 태그 풀에서 매 미션마다 랜덤으로 1개를 출제하고
// ("N번째 태그를 입력하세요"), 유저 입력값을 서버에서 대조해 정답을 판정한다.
// ─────────────────────────────────────────────────────────────────

class AdminCampaignScreen extends ConsumerStatefulWidget {
  const AdminCampaignScreen({super.key});

  @override
  ConsumerState<AdminCampaignScreen> createState() =>
      _AdminCampaignScreenState();
}

class _AdminCampaignScreenState extends ConsumerState<AdminCampaignScreen> {
  /// group_id → 태그 붙여넣기 입력 컨트롤러
  final Map<String, TextEditingController> _tagCtrls = {};

  /// 처리 중인 group_id (버튼 중복 클릭 방지)
  final Set<String> _loadingIds = {};

  static const _kBlue = Color(0xFF1E3A8A);
  static const _kRed  = Color(0xFFB71C1C);

  static const int kMaxTags = 10;

  @override
  void dispose() {
    for (final c in _tagCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(String groupId) =>
      _tagCtrls.putIfAbsent(groupId, () => TextEditingController());

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingCampaignsProvider);
    final allAsync     = ref.watch(allCampaignsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: _buildAppBar(context),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGuideCard(),
                const SizedBox(height: 16),
                _buildPendingSection(pendingAsync),
                const SizedBox(height: 24),
                _buildAllSection(allAsync),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      title: const Text(
        '어드민 — 광고 승인',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _kBlue,
          fontSize: 18,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '새로고침',
          onPressed: () {
            ref.invalidate(pendingCampaignsProvider);
            ref.invalidate(allCampaignsProvider);
          },
        ),
        TextButton.icon(
          onPressed: () => context.go('/admin/charge'),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('충전 승인'),
          style: TextButton.styleFrom(foregroundColor: _kBlue),
        ),
        TextButton.icon(
          onPressed: () => context.go('/admin/withdraw'),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('출금 처리'),
          style: TextButton.styleFrom(foregroundColor: _kBlue),
        ),
        TextButton.icon(
          onPressed: () => context.go('/admin/notice'),
          icon: const Icon(Icons.campaign_outlined, size: 18),
          label: const Text('공지 등록'),
          style: TextButton.styleFrom(foregroundColor: _kBlue),
        ),
        TextButton.icon(
          onPressed: () async {
            await supabase.auth.signOut();
            if (context.mounted) context.go('/admin/login');
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('로그아웃'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── 안내 카드 ────────────────────────────────────────────────

  Widget _buildGuideCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Text(
                '태그 등록 방법',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '① [상품 페이지 열기]로 해당 광고주의 스마트스토어 상품 페이지를 연다.\n'
            '② 상품명 아래 #태그 영역을 그대로 드래그해 복사한다.\n'
            '③ 아래 입력창에 붙여넣으면 # 기준으로 자동 분리된다. (최대 $kMaxTags개)\n'
            '④ 붙여넣은 순서 = 상품 페이지 노출 순서로 저장되므로 순서를 바꾸지 않는다.\n'
            '⑤ [승인]을 누르면 태그 등록 + 광고주 포인트 차감 + 앱 노출이 함께 시작된다.',
            style: TextStyle(fontSize: 13, height: 1.7),
          ),
          const Divider(height: 20),
          Text(
            '앱 유저에게는 등록된 태그 중 랜덤으로 "N번째 태그를 입력하세요"가 출제되며, '
            '입력값은 여기에 등록된 태그와 대조해 정답이 판정됩니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── 승인 대기 섹션 ────────────────────────────────────────────

  Widget _buildPendingSection(AsyncValue<List<AdminCampaignRecord>> async) {
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '광고 승인 대기 목록',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              async.whenOrNull(
                    data: (list) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: list.isEmpty
                            ? Colors.grey[100]
                            : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${list.length}건',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: list.isEmpty
                              ? Colors.grey
                              : const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ) ??
                  const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('조회 오류: $e',
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
            data: (records) => records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '승인 대기 중인 광고가 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final r in records) ...[
                        _PendingCampaignCard(
                          record:     r,
                          controller: _ctrlFor(r.groupId),
                          isLoading:  _loadingIds.contains(r.groupId),
                          maxTags:    kMaxTags,
                          onChanged:  () => setState(() {}),
                          onOpenUrl:  () => _openUrl(r.productUrl),
                          onCopyUrl:  () => _copyUrl(r.productUrl),
                          onPaste:    () => _pasteFromClipboard(r.groupId),
                          onApprove:  () => _handleApprove(r),
                          onReject:   () => _handleReject(r),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── 처리 완료 섹션 ────────────────────────────────────────────

  Widget _buildAllSection(AsyncValue<List<AdminCampaignRecord>> async) {
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '전체 광고 목록 — 삭제 가능',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('조회 오류: $e',
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
            data: (records) => records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '등록된 광고가 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: records
                        .map((r) => _CampaignRow(
                              record:    r,
                              isLoading: _loadingIds.contains(r.groupId),
                              onDelete:  () => _handleDelete(r),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 액션 핸들러
  // ─────────────────────────────────────────────────────────────

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) {
      _showSnack('상품 URL이 등록되어 있지 않습니다.', _kRed);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('상품 URL 형식이 올바르지 않습니다.', _kRed);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _showSnack('상품 URL을 복사했습니다.', _kBlue);
  }

  /// 클립보드 내용을 태그 입력창에 붙여넣는다 (기존 내용은 교체)
  Future<void> _pasteFromClipboard(String groupId) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _showSnack('클립보드가 비어 있습니다.', _kRed);
      return;
    }
    _ctrlFor(groupId).text = text;
    setState(() {});
  }

  Future<void> _handleApprove(AdminCampaignRecord record) async {
    final tags = parsePastedTags(_ctrlFor(record.groupId).text);

    if (tags.isEmpty) {
      _showSnack('태그를 먼저 붙여넣어 주세요.', _kRed);
      return;
    }
    if (tags.length > kMaxTags) {
      _showSnack('태그는 최대 $kMaxTags개까지 등록할 수 있습니다. (현재 ${tags.length}개)',
          _kRed);
      return;
    }

    // 승인 확인 다이얼로그 — 태그 순서와 차감 포인트를 최종 확인
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('광고 승인'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${record.productName} / ${record.brandName}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('광고주: ${record.userEmail}',
                  style: const TextStyle(fontSize: 13)),
              Text('차감 포인트: ${_fmtNum(record.budget)}P',
                  style: const TextStyle(fontSize: 13)),
              const Divider(height: 20),
              const Text('등록될 태그 (순서 포함)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...List.generate(
                tags.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('${i + 1}번째 · ${tags[i]}',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('승인'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (_loadingIds.contains(record.groupId)) return;
    setState(() => _loadingIds.add(record.groupId));

    try {
      final result = await ref
          .read(adminCampaignRepositoryProvider)
          .approveCampaign(groupId: record.groupId, tags: tags);

      if (!mounted) return;

      if (result['success'] == true) {
        _tagCtrls.remove(record.groupId)?.dispose();
        ref.invalidate(pendingCampaignsProvider);
        ref.invalidate(allCampaignsProvider);
        _showSnack(
          '${record.productName} 광고 승인 완료 '
          '(태그 ${result['tag_count']}개 · '
          '${_fmtNum((result['charged'] as num?)?.toInt() ?? 0)}P 차감)',
          const Color(0xFF2E7D32),
        );
      } else {
        _showSnack(_approveErrorMessage(result), _kRed);
      }
    } catch (e) {
      if (!mounted) return;
      if (_isAuthError(e)) {
        context.go('/admin/login');
        return;
      }
      _showSnack('오류: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(record.groupId));
    }
  }

  Future<void> _handleReject(AdminCampaignRecord record) async {
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('광고 거절'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.productName} / ${record.brandName}\n'
                '(${record.userEmail}) 광고를 거절하시겠습니까?',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 4),
              const Text(
                '※ 등록 시점에 차감된 포인트가 없으므로 환불 처리는 필요하지 않습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: '거절 사유 (선택)',
                  hintText: '예) 상품 페이지에 태그가 없음',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('거절'),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (ok != true) return;
    if (_loadingIds.contains(record.groupId)) return;
    setState(() => _loadingIds.add(record.groupId));

    try {
      final result = await ref
          .read(adminCampaignRepositoryProvider)
          .rejectCampaign(
            groupId: record.groupId,
            reason:  reason.isEmpty ? null : reason,
          );

      if (!mounted) return;

      if (result['success'] == true) {
        _tagCtrls.remove(record.groupId)?.dispose();
        ref.invalidate(pendingCampaignsProvider);
        ref.invalidate(allCampaignsProvider);
        _showSnack('${record.productName} 광고 거절 완료', _kRed);
      } else {
        _showSnack('거절 오류: ${result['error'] ?? 'UNKNOWN'}', _kRed);
      }
    } catch (e) {
      if (!mounted) return;
      if (_isAuthError(e)) {
        context.go('/admin/login');
        return;
      }
      _showSnack('오류: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(record.groupId));
    }
  }

  Future<void> _handleDelete(AdminCampaignRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('광고 삭제'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${record.productName} / ${record.brandName}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('광고주: ${record.userEmail}',
                  style: const TextStyle(fontSize: 13)),
              Text('키워드 ${record.campaignCount}개 · 미션 이력 ${record.missionCount}건',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              const Text(
                '이 광고를 완전히 삭제합니다.\n'
                '미션 수행 이력, 순위 기록, 태그가 함께 지워지며 되돌릴 수 없습니다.',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                '※ 이미 차감된 포인트는 환불되지 않습니다. '
                '환불이 필요하면 충전 승인으로 별도 처리하세요.',
                style: TextStyle(fontSize: 12, color: Color(0xFFB71C1C)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (_loadingIds.contains(record.groupId)) return;
    setState(() => _loadingIds.add(record.groupId));

    try {
      final result = await ref
          .read(adminCampaignRepositoryProvider)
          .deleteCampaign(groupId: record.groupId);

      if (!mounted) return;

      if (result['success'] == true) {
        ref.invalidate(pendingCampaignsProvider);
        ref.invalidate(allCampaignsProvider);
        _showSnack(
          '${record.productName} 삭제 완료 '
          '(키워드 ${result['campaign_count']}개 · 미션 ${result['mission_count']}건)',
          _kRed,
        );
      } else {
        _showSnack('삭제 오류: ${result['error'] ?? 'UNKNOWN'}', _kRed);
      }
    } catch (e) {
      if (!mounted) return;
      if (_isAuthError(e)) {
        context.go('/admin/login');
        return;
      }
      _showSnack('오류: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(record.groupId));
    }
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  String _approveErrorMessage(Map<String, dynamic> result) {
    final error = result['error'] as String? ?? 'UNKNOWN';
    return switch (error) {
      'INSUFFICIENT_BALANCE' =>
        '광고주 잔액 부족 — 필요 ${_fmtNum((result['required'] as num?)?.toInt() ?? 0)}P / '
            '보유 ${_fmtNum((result['balance'] as num?)?.toInt() ?? 0)}P',
      'TOO_MANY_TAGS'  => '태그가 너무 많습니다 (${result['count']}개). 최대 $kMaxTags개.',
      'DUPLICATE_TAG'  => '중복된 태그가 있습니다: ${result['tag']}',
      'TAGS_REQUIRED'  => '등록할 태그가 없습니다.',
      'NOT_PENDING'    => '이미 처리된 광고입니다. 목록을 새로고침해주세요.',
      'FORBIDDEN'      => '어드민 권한이 없습니다.',
      _                => '승인 오류: $error',
    };
  }

  bool _isAuthError(Object e) {
    final err = e.toString().toLowerCase();
    return err.contains('jwt') || err.contains('session') || err.contains('401');
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      duration: const Duration(seconds: 3),
    ));
  }

  static String _fmtNum(int n) {
    final s   = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────
// 승인 대기 카드 (광고 그룹 1건)
// ─────────────────────────────────────────────────────────────────

class _PendingCampaignCard extends StatelessWidget {
  final AdminCampaignRecord   record;
  final TextEditingController controller;
  final bool                  isLoading;
  final int                   maxTags;
  final VoidCallback          onChanged;
  final VoidCallback          onOpenUrl;
  final VoidCallback          onCopyUrl;
  final VoidCallback          onPaste;
  final VoidCallback          onApprove;
  final VoidCallback          onReject;

  const _PendingCampaignCard({
    required this.record,
    required this.controller,
    required this.isLoading,
    required this.maxTags,
    required this.onChanged,
    required this.onOpenUrl,
    required this.onCopyUrl,
    required this.onPaste,
    required this.onApprove,
    required this.onReject,
  });

  static const _kBlue = Color(0xFF1E3A8A);
  static const _kRed  = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    final tags     = parsePastedTags(controller.text);
    final overflow = tags.length > maxTags;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더: 상품명 / 업체명 + 신청일시 ────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '업체명 ${record.brandName}  ·  ${record.userEmail}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Text(
                _fmtDateTime(record.createdAt),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600], height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 광고 정보 ────────────────────────────────────────
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _InfoItem(label: '순위 추적 키워드', value: record.displayKeyword),
              _InfoItem(
                label: '일일 목표',
                value: '${_fmtNum(record.groupDailyTarget)}명',
              ),
              _InfoItem(label: '기간', value: record.periodLabel),
              _InfoItem(
                label: '차감 예정',
                value: '${_fmtNum(record.budget)}P',
                emphasize: true,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── 서브키워드 ───────────────────────────────────────
          if (record.subKeywords.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: record.subKeywords
                  .map((k) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          k,
                          style: const TextStyle(
                              fontSize: 12, color: _kBlue),
                        ),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 12),

          // ── 상품 URL ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    record.productUrl.isEmpty ? '-' : record.productUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onCopyUrl,
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('URL 복사'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onOpenUrl,
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('상품 페이지 열기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── 태그 붙여넣기 ────────────────────────────────────
          Row(
            children: [
              const Text(
                '태그 붙여넣기',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '# 기준 자동 분리 · 붙여넣은 순서가 그대로 태그 순서',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste, size: 15),
                label: const Text('클립보드에서 붙여넣기'),
                style: TextButton.styleFrom(
                  foregroundColor: _kBlue,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: '예) #티비거치대#모니터암#벽걸이브라켓',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),

          // ── 파싱 결과 미리보기 ───────────────────────────────
          if (tags.isEmpty)
            Text(
              '아직 인식된 태그가 없습니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          else ...[
            Row(
              children: [
                Text(
                  '인식된 태그 ${tags.length}개',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: overflow ? _kRed : const Color(0xFF2E7D32),
                  ),
                ),
                if (overflow) ...[
                  const SizedBox(width: 8),
                  Text(
                    '최대 $maxTags개까지만 등록할 수 있습니다.',
                    style: const TextStyle(fontSize: 12, color: _kRed),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(tags.length, (i) {
                final isOver = i >= maxTags;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOver
                        ? const Color(0xFFFFEBEE)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${i + 1}번째 · ${tags[i]}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isOver ? _kRed : const Color(0xFF2E7D32),
                    ),
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 14),

          // ── 승인 / 거절 ──────────────────────────────────────
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: const BorderSide(color: _kRed),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  child: const Text('거절'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      (tags.isEmpty || overflow) ? null : onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('승인'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)}\n${_p(d.hour)}:${_p(d.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  static String _fmtNum(int n) {
    final s   = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── 정보 항목 ────────────────────────────────────────────────────

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final bool   emphasize;

  const _InfoItem({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: emphasize
                ? const Color(0xFFB71C1C)
                : const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 처리 완료 행
// ─────────────────────────────────────────────────────────────────

class _CampaignRow extends StatelessWidget {
  final AdminCampaignRecord record;
  final bool                isLoading;
  final VoidCallback        onDelete;

  const _CampaignRow({
    required this.record,
    required this.isLoading,
    required this.onDelete,
  });

  static const _kRed = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  _fmtDateTime(record.processedAt ?? record.createdAt),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600], height: 1.5),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record.productName} · ${record.brandName}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.userEmail}  ·  키워드 ${record.campaignCount}개'
                      '  ·  미션 ${record.missionCount}건',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (record.subKeywords.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        record.subKeywords.join('  ·  '),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((record.rejectReason ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '거절 사유: ${record.rejectReason}',
                        style: const TextStyle(fontSize: 11, color: _kRed),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: record.statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  record.statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: record.statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: const BorderSide(color: _kRed),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('삭제'),
                      ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey[100]),
      ],
    );
  }

  String _fmtDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)}\n${_p(d.hour)}:${_p(d.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────
// 카드 컨테이너
// ─────────────────────────────────────────────────────────────────

class _AdminCard extends StatelessWidget {
  final Widget child;
  const _AdminCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}
