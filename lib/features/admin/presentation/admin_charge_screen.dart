import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/admin_charge_model.dart';
import 'admin_charge_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 충전 승인 화면  (/admin/charge)
//
// 접근 제한: role = ADMIN 인 경우만 허용
//   → 미인증 / role ≠ ADMIN 이면 /web/login 리다이렉트
//
// 구성:
//   1. PENDING 충전 신청 목록 — [승인] / [거절] 버튼
//   2. COMPLETED/REJECTED 처리 완료 내역 (최근 20건)
// ─────────────────────────────────────────────────────────────────

class AdminChargeScreen extends ConsumerStatefulWidget {
  const AdminChargeScreen({super.key});

  @override
  ConsumerState<AdminChargeScreen> createState() =>
      _AdminChargeScreenState();
}

class _AdminChargeScreenState extends ConsumerState<AdminChargeScreen> {
  /// 현재 처리 중인 tx_id 집합 (버튼 중복 클릭 방지)
  final Set<String> _loadingIds = {};

  static const _kBlue = Color(0xFF1E3A8A);
  static const _kRed  = Color(0xFFB71C1C);

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(currentUserRoleProvider);

    return roleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => context.go('/web/login'));
        return const Scaffold(body: SizedBox.shrink());
      },
      data: (role) {
        if (role != 'ADMIN') {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.go('/web/login'));
          return const Scaffold(body: SizedBox.shrink());
        }
        return _buildAdminBody(context);
      },
    );
  }

  Widget _buildAdminBody(BuildContext context) {
    final pendingAsync   = ref.watch(pendingChargesProvider);
    final processedAsync = ref.watch(processedChargesProvider);

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
                // ── PENDING 목록 ────────────────────────────────
                _PendingSection(
                  asyncData:    pendingAsync,
                  loadingIds:   _loadingIds,
                  onApprove:    _handleApprove,
                  onReject:     _handleReject,
                ),
                const SizedBox(height: 24),

                // ── 처리 완료 내역 ──────────────────────────────
                _ProcessedSection(asyncData: processedAsync),
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
        '어드민 — 충전 승인',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _kBlue,
          fontSize: 18,
        ),
      ),
      actions: [
        // C-008: 새로고침 버튼
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '새로고침',
          onPressed: () {
            ref.invalidate(pendingChargesProvider);
            ref.invalidate(processedChargesProvider);
          },
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
  // 액션 핸들러
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleApprove(AdminChargeRecord record) async {
    if (_loadingIds.contains(record.id)) return;
    setState(() => _loadingIds.add(record.id));

    try {
      final result = await ref
          .read(adminChargeRepositoryProvider)
          .approveCharge(record.id);

      if (!mounted) return;

      if (result['success'] == true) {
        ref.invalidate(pendingChargesProvider);
        ref.invalidate(processedChargesProvider);
        _showSnack(
          '${record.userEmail} 충전 승인 완료'
          ' (+${_fmtNum(record.amount)}P)',
          const Color(0xFF2E7D32),
        );
      } else {
        _showSnack('승인 오류: ${result['error'] ?? 'UNKNOWN'}',
            Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().toLowerCase();
      if (err.contains('jwt') || err.contains('session') || err.contains('401')) {
        context.go('/web/login');
        return;
      }
      _showSnack('오류: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(record.id));
    }
  }

  Future<void> _handleReject(AdminChargeRecord record) async {
    // 확인 다이얼로그
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('충전 거절'),
        content: Text(
          '${record.userEmail} 의 충전 신청\n'
          '(${_fmtNum(record.amount)}P)을 거절하시겠습니까?',
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

    if (ok != true) return;
    if (_loadingIds.contains(record.id)) return;
    setState(() => _loadingIds.add(record.id));

    try {
      final result = await ref
          .read(adminChargeRepositoryProvider)
          .rejectCharge(record.id);

      if (!mounted) return;

      if (result['success'] == true) {
        ref.invalidate(pendingChargesProvider);
        ref.invalidate(processedChargesProvider);
        _showSnack(
          '${record.userEmail} 충전 신청 거절 완료',
          _kRed,
        );
      } else {
        _showSnack('거절 오류: ${result['error'] ?? 'UNKNOWN'}',
            Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().toLowerCase();
      if (err.contains('jwt') || err.contains('session') || err.contains('401')) {
        context.go('/web/login');
        return;
      }
      _showSnack('오류: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loadingIds.remove(record.id));
    }
  }

  // ── 유틸 ─────────────────────────────────────────────────────

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
// PENDING 충전 신청 섹션
// ─────────────────────────────────────────────────────────────────

class _PendingSection extends StatelessWidget {
  final AsyncValue<List<AdminChargeRecord>> asyncData;
  final Set<String>                         loadingIds;
  final Future<void> Function(AdminChargeRecord) onApprove;
  final Future<void> Function(AdminChargeRecord) onReject;

  const _PendingSection({
    required this.asyncData,
    required this.loadingIds,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 ───────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Text(
                  '충전 대기 목록',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              asyncData.whenOrNull(
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
              ) ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),

          // ── 목록 ───────────────────────────────────────────
          asyncData.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '조회 오류: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
            data: (records) => records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '대기 중인 충전 신청이 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      _PendingTableHeader(),
                      const Divider(height: 1),
                      ...records.map(
                        (r) => _PendingRow(
                          record:    r,
                          isLoading: loadingIds.contains(r.id),
                          onApprove: () => onApprove(r),
                          onReject:  () => onReject(r),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── PENDING 테이블 헤더 ──────────────────────────────────────────

class _PendingTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF6B7280),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Row(
        children: const [
          SizedBox(width: 110, child: Text('신청일시', style: style)),
          Expanded(flex: 3, child: Text('유저 이메일', style: style)),
          Expanded(flex: 2, child: Text('입금자명', style: style)),
          SizedBox(
            width: 52,
            child: Text('세금계산서', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 90,
            child: Text('신청금액', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 100,
            child: Text('총 입금액', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 140),
        ],
      ),
    );
  }
}

// ── PENDING 행 ────────────────────────────────────────────────────

class _PendingRow extends StatelessWidget {
  final AdminChargeRecord record;
  final bool              isLoading;
  final VoidCallback      onApprove;
  final VoidCallback      onReject;

  const _PendingRow({
    required this.record,
    required this.isLoading,
    required this.onApprove,
    required this.onReject,
  });

  static const _kBlue = Color(0xFF1E3A8A);
  static const _kRed  = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 신청일시
              SizedBox(
                width: 110,
                child: Text(
                  _fmtDateTime(record.createdAt),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600], height: 1.5),
                ),
              ),

              // 유저 이메일
              Expanded(
                flex: 3,
                child: Text(
                  record.userEmail,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 입금자명
              Expanded(
                flex: 2,
                child: Text(
                  record.depositorName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 세금계산서
              SizedBox(
                width: 52,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: record.hasTaxInvoice
                          ? const Color(0xFFE8F5E9)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      record.hasTaxInvoice ? 'Y' : 'N',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: record.hasTaxInvoice
                            ? const Color(0xFF2E7D32)
                            : Colors.grey[500],
                      ),
                    ),
                  ),
                ),
              ),

              // 신청금액 (포인트)
              SizedBox(
                width: 90,
                child: Text(
                  '${_fmtNum(record.amount)}P',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              // 총 입금액 (원)
              SizedBox(
                width: 100,
                child: Text(
                  '${_fmtNum(record.totalTransferAmount)}원',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[700]),
                ),
              ),

              const SizedBox(width: 8),

              // 승인 / 거절 버튼
              SizedBox(
                width: 132,
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 승인
                          SizedBox(
                            height: 34,
                            child: ElevatedButton(
                              onPressed: onApprove,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                elevation: 0,
                              ),
                              child: const Text('승인',
                                  style: TextStyle(fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 거절
                          SizedBox(
                            height: 34,
                            child: OutlinedButton(
                              onPressed: onReject,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kRed,
                                side: const BorderSide(color: _kRed),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: const Text('거절',
                                  style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ],
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

  String _fmtNum(int n) {
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
// 처리 완료 내역 섹션
// ─────────────────────────────────────────────────────────────────

class _ProcessedSection extends StatelessWidget {
  final AsyncValue<List<AdminChargeRecord>> asyncData;
  const _ProcessedSection({required this.asyncData});

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '처리 완료 내역 (최근 20건)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          asyncData.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '조회 오류: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
            data: (records) => records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '처리 완료 내역이 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: records
                        .map((r) => _ProcessedRow(record: r))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 처리 완료 행 ─────────────────────────────────────────────────

class _ProcessedRow extends StatelessWidget {
  final AdminChargeRecord record;
  const _ProcessedRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 신청일시
              SizedBox(
                width: 110,
                child: Text(
                  _fmtDateTime(record.createdAt),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600], height: 1.5),
                ),
              ),

              // 유저 이메일
              Expanded(
                child: Text(
                  record.userEmail,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 금액
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '${_fmtNum(record.amount)}P',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(width: 16),

              // 상태 뱃지
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
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

  String _fmtNum(int n) {
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
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}
