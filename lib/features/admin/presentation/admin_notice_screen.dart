import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/notice_model.dart';
import 'admin_notice_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 공지사항 관리 화면  (/admin/notice)
//
// 구성:
//   상단 — 공지 등록 폼 (제목 + 내용 + [등록] 버튼)
//   하단 — 등록된 공지 목록 (최신순)
// ─────────────────────────────────────────────────────────────────

class AdminNoticeScreen extends ConsumerStatefulWidget {
  const AdminNoticeScreen({super.key});

  @override
  ConsumerState<AdminNoticeScreen> createState() => _AdminNoticeScreenState();
}

class _AdminNoticeScreenState extends ConsumerState<AdminNoticeScreen> {
  final _titleCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool  _isSubmitting = false;

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final noticesAsync = ref.watch(adminNoticesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: _buildAppBar(context),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 등록 폼 ─────────────────────────────────────
                _NoticeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '공지 등록',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 제목
                      TextField(
                        controller: _titleCtrl,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          hintText: '공지 제목을 입력하세요',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 내용
                      TextField(
                        controller: _contentCtrl,
                        maxLines:   6,
                        maxLength:  2000,
                        decoration: const InputDecoration(
                          labelText:   '내용',
                          hintText:    '공지 내용을 입력하세요',
                          border:      OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          counterText: '',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 등록 버튼
                      SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  '등록',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── 공지 목록 ────────────────────────────────────
                _NoticeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '등록된 공지',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          noticesAsync.whenOrNull(
                            data: (list) => Text(
                              '${list.length}건',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[500]),
                            ),
                          ) ?? const SizedBox.shrink(),
                        ],
                      ),
                      const SizedBox(height: 16),

                      noticesAsync.when(
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
                        data: (notices) => notices.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text(
                                    '등록된 공지가 없습니다.',
                                    style: TextStyle(color: Colors.grey[500]),
                                  ),
                                ),
                              )
                            : Column(
                                children: notices
                                    .map((n) => _NoticeListTile(notice: n))
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      title: const Text(
        '어드민 — 공지사항',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _kBlue,
          fontSize: 18,
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/admin/charge'),
          icon: const Icon(Icons.approval_outlined, size: 18),
          label: const Text('충전 승인'),
          style: TextButton.styleFrom(foregroundColor: _kBlue),
        ),
        TextButton.icon(
          onPressed: () => context.go('/admin/withdraw'),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('출금 처리'),
          style: TextButton.styleFrom(foregroundColor: _kBlue),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 등록 핸들러
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    final title   = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (title.isEmpty) {
      _showSnack('제목을 입력해 주세요.', Colors.orange);
      return;
    }
    if (content.isEmpty) {
      _showSnack('내용을 입력해 주세요.', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref.read(noticeRepositoryProvider).createNotice(
            title:   title,
            content: content,
          );

      if (!mounted) return;

      _titleCtrl.clear();
      _contentCtrl.clear();
      ref.invalidate(adminNoticesProvider);
      _showSnack('공지가 등록되었습니다.', const Color(0xFF2E7D32));
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().toLowerCase();
      if (err.contains('jwt') || err.contains('session') || err.contains('401')) {
        context.go('/admin/login');
        return;
      }
      _showSnack('등록 오류: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: bg,
      duration:        const Duration(seconds: 3),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────
// 공지 목록 아이템
// ─────────────────────────────────────────────────────────────────

class _NoticeListTile extends StatelessWidget {
  final NoticeModel notice;
  const _NoticeListTile({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notice.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _fmtDate(notice.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                notice.content,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[700], height: 1.5),
                maxLines:  3,
                overflow:  TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey[100]),
      ],
    );
  }

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────
// 카드 컨테이너
// ─────────────────────────────────────────────────────────────────

class _NoticeCard extends StatelessWidget {
  final Widget child;
  const _NoticeCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}
