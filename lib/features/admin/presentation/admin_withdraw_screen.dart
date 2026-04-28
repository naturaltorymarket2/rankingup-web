import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/admin_withdraw_model.dart';
import 'admin_charge_provider.dart';   // currentUserRoleProvider 재사용
import 'admin_withdraw_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 출금 처리 화면  (/admin/withdraw)
//
// 접근 제한: role = ADMIN 인 경우만 허용
//   → 미인증 / role ≠ ADMIN 이면 /web/login 리다이렉트
//
// 구성:
//   1. PENDING 출금 신청 목록 — [처리완료] / [거절] 버튼
//   2. COMPLETED/REJECTED 처리 완료 내역 (최근 20건)
// ─────────────────────────────────────────────────────────────────

class AdminWithdrawScreen extends ConsumerStatefulWidget {
  const AdminWithdrawScreen({super.key});

  @override
  ConsumerState<AdminWithdrawScreen> createState() =>
      _AdminWithdrawScreenState();
}

class _AdminWithdrawScreenState
    extends ConsumerState<AdminWithdrawScreen> {
  /// 현재 처리 중인 tx_id 집합 (버튼 중복 클릭 방지)
  final Set<String> _loadingIds = {};

  static const _kBlue  = Color(0xFF1E3A8A);
  static const _kRed   = Color(0xFFB71C1C);
  static const _kGreen = Color(0xFF2E7D32);

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
    final pendingAsync   = ref.watch(pendingWithdrawsProvider);
    final processedAsync = ref.watch(processedWithdrawsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: _buildAppBar(context),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── PENDING 출금 신청 목록 ──────────────────────
                _PendingWithdrawSection(
                  asyncData:  pendingAsync,
                  loadingIds: _loadingIds,
                  onProcess:  _handleProcess,
                  onReject:   _handleReject,
                ),
                const SizedBox(height: 24),

                // ── 처리 완료 내역 ──────────────────────────────
                _ProcessedWithdrawSection(asyncData: processedAsync),
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
        '어드민 — 출금 처리',
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
            ref.invalidate(pendingWithdrawsProvider);
            ref.invalidate(processedWithdrawsProvider);
          },
        ),
        TextButton.icon(
          onPressed: () => context.go('/admin/charge'),
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('충전 승인'),
          style: TextButton.styleFrom(foregroundColor: _kBlue),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 액션 핸들러
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleProcess(AdminWithdrawRecord record) async {
    // 처리완료 확인 다이얼로그
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('출금 처리완료'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${record.userEmail} 의 출금 신청을 처리완료 하시겠습니까?'),
            const SizedBox(height: 12),
            _DialogInfoRow('은행', record.bankName),
            _DialogInfoRow('계좌번호', record.accountNumber),
            _DialogInfoRow('예금주', record.holderName),
            const Divider(height: 16),
            _DialogInfoRow(
              '실이체 금액',
              '${_fmtNum(record.netAmount)}P',
              bold: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('처리완료'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (_loadingIds.contains(record.id)) return;
    setState(() => _loadingIds.add(record.id));

    try {
      final result = await ref
          .read(adminWithdrawRepositoryProvider)
          .processWithdraw(record.id);

      if (!mounted) return;

      if (result['success'] == true) {
        ref.invalidate(pendingWithdrawsProvider);
        ref.invalidate(processedWithdrawsProvider);
        _showSnack(
          '${record.userEmail} 출금 처리완료'
          ' (실이체: ${_fmtNum(record.netAmount)}P)',
          _kGreen,
        );
      } else {
        _showSnack('처리 오류: ${result['error'] ?? 'UNKNOWN'}',
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

  Future<void> _handleReject(AdminWithdrawRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('출금 거절'),
        content: Text(
          '${record.userEmail} 의 출금 신청\n'
          '(${_fmtNum(record.amount)}P)을 거절하시겠습니까?\n\n'
          '거절 시 잔액은 변동 없습니다.',
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
          .read(adminWithdrawRepositoryProvider)
          .rejectWithdraw(record.id);

      if (!mounted) return;

      if (result['success'] == true) {
        ref.invalidate(pendingWithdrawsProvider);
        ref.invalidate(processedWithdrawsProvider);
        _showSnack('${record.userEmail} 출금 신청 거절 완료', _kRed);
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
// 다이얼로그 정보 행
// ─────────────────────────────────────────────────────────────────

class _DialogInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   bold;

  const _DialogInfoRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PENDING 출금 신청 섹션
// ─────────────────────────────────────────────────────────────────

class _PendingWithdrawSection extends StatelessWidget {
  final AsyncValue<List<AdminWithdrawRecord>> asyncData;
  final Set<String>                           loadingIds;
  final Future<void> Function(AdminWithdrawRecord) onProcess;
  final Future<void> Function(AdminWithdrawRecord) onReject;

  const _PendingWithdrawSection({
    required this.asyncData,
    required this.loadingIds,
    required this.onProcess,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 ─────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Text(
                  '출금 대기 목록',
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

          // ── 목록 ─────────────────────────────────────────────
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '대기 중인 출금 신청이 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: records
                        .map((r) => _PendingWithdrawCard(
                              record:    r,
                              isLoading: loadingIds.contains(r.id),
                              onProcess: () => onProcess(r),
                              onReject:  () => onReject(r),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── PENDING 출금 신청 카드 ────────────────────────────────────────

class _PendingWithdrawCard extends StatelessWidget {
  final AdminWithdrawRecord record;
  final bool                isLoading;
  final VoidCallback        onProcess;
  final VoidCallback        onReject;

  const _PendingWithdrawCard({
    required this.record,
    required this.isLoading,
    required this.onProcess,
    required this.onReject,
  });

  static const _kGreen = Color(0xFF2E7D32);
  static const _kRed   = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 좌측: 날짜 + 이메일 + 계좌 정보 ─────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 날짜 + 이메일
                    Row(
                      children: [
                        Text(
                          _fmtDate(record.createdAt),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            record.userEmail,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 계좌 정보 칩 행
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _InfoChip(
                          icon: Icons.account_balance_outlined,
                          label: record.bankName,
                        ),
                        _InfoChip(
                          icon: Icons.credit_card_outlined,
                          label: record.accountNumber,
                        ),
                        _InfoChip(
                          icon: Icons.person_outline,
                          label: record.holderName,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 금액 정보
                    Row(
                      children: [
                        _AmountBadge(
                          label: '신청',
                          value: '${_fmtNum(record.amount)}P',
                          bgColor: Colors.grey[100]!,
                          textColor: Colors.grey[700]!,
                        ),
                        const SizedBox(width: 6),
                        _AmountBadge(
                          label: '수수료',
                          value: '-${_fmtNum(AdminWithdrawRecord.fee)}P',
                          bgColor: const Color(0xFFFFF3E0),
                          textColor: const Color(0xFFE65100),
                        ),
                        const SizedBox(width: 6),
                        _AmountBadge(
                          label: '실이체',
                          value: '${_fmtNum(record.netAmount)}P',
                          bgColor: const Color(0xFFE8F5E9),
                          textColor: _kGreen,
                          bold: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // ── 우측: 처리완료 / 거절 버튼 ────────────────────
              SizedBox(
                width: 120,
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // netAmount <= 0: 수수료 초과 경고
                          if (record.netAmount <= 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '출금 금액이\n수수료보다 적습니다',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red.shade700,
                                  height: 1.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              // netAmount <= 0이면 처리완료 버튼 비활성화
                              onPressed: record.netAmount > 0 ? onProcess : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kGreen,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                elevation: 0,
                              ),
                              child: const Text('처리완료',
                                  style: TextStyle(fontSize: 13)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: OutlinedButton(
                              onPressed: onReject,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kRed,
                                side: const BorderSide(color: _kRed),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6),
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

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}';
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

class _ProcessedWithdrawSection extends StatelessWidget {
  final AsyncValue<List<AdminWithdrawRecord>> asyncData;
  const _ProcessedWithdrawSection({required this.asyncData});

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
                    padding:
                        const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '처리 완료 내역이 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: records
                        .map((r) => _ProcessedWithdrawRow(record: r))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 처리 완료 행 ─────────────────────────────────────────────────

class _ProcessedWithdrawRow extends StatelessWidget {
  final AdminWithdrawRecord record;
  const _ProcessedWithdrawRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 2),
          child: Row(
            children: [
              // 신청일시
              SizedBox(
                width: 110,
                child: Text(
                  _fmtDateTime(record.createdAt),
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      height: 1.5),
                ),
              ),

              // 이메일
              Expanded(
                child: Text(
                  record.userEmail,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 실이체 금액
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${_fmtNum(record.netAmount)}P',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

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
// 계좌 정보 칩
// ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 금액 뱃지
// ─────────────────────────────────────────────────────────────────

class _AmountBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color  bgColor;
  final Color  textColor;
  final bool   bold;

  const _AmountBadge({
    required this.label,
    required this.value,
    required this.bgColor,
    required this.textColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: textColor),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
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
