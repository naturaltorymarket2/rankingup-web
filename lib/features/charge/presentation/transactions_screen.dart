import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/charge_model.dart';
import 'charge_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 포인트 내역 웹 화면  (/web/transactions)
//
// • 현재 잔액 카드
// • 타입 필터 칩 (전체 / 충전 / 지출 / 적립 / 출금)
// • 거래 내역 목록 (최신순, 최대 100건)
//   - 타입 뱃지 / 설명 / ±금액 / 잔액(balance_after) / 상태 뱃지
// ─────────────────────────────────────────────────────────────────

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(currentBalanceProvider);
    final txAsync      = ref.watch(transactionsProvider);
    final filter       = ref.watch(transactionsFilterProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '포인트 내역',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _kBlue,
            fontSize: 18,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 잔액 요약 카드 ──────────────────────────────
                _BalanceCard(balanceAsync: balanceAsync),
                const SizedBox(height: 16),

                // ── 거래 내역 카드 ──────────────────────────────
                _TransactionListCard(
                  txAsync: txAsync,
                  filter:  filter,
                  onRefresh: () => ref.invalidate(transactionsProvider),
                  onFilterChanged: (v) =>
                      ref.read(transactionsFilterProvider.notifier).state = v,
                ),
                const SizedBox(height: 24),

                // ── 대시보드 버튼 ───────────────────────────────
                OutlinedButton.icon(
                  onPressed: () => context.go('/web/dashboard'),
                  icon: const Icon(Icons.dashboard_outlined, size: 18),
                  label: const Text('대시보드로 돌아가기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBlue,
                    minimumSize: const Size(double.infinity, 48),
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
}

// ─────────────────────────────────────────────────────────────────
// 잔액 카드
// ─────────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final AsyncValue<int> balanceAsync;
  const _BalanceCard({required this.balanceAsync});

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: _kBlue,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 잔액',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  balanceAsync.when(
                    loading: () => const SizedBox(
                      height: 26,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5),
                    ),
                    error: (e, st) => const Text(
                      '잔액 조회 오류',
                      style:
                          TextStyle(color: Colors.red, fontSize: 16),
                    ),
                    data: (balance) => Text(
                      '${_fmtNum(balance)} P',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _kBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
// 거래 내역 카드 (필터 + 리스트)
// ─────────────────────────────────────────────────────────────────

class _TransactionListCard extends StatelessWidget {
  final AsyncValue<List<TransactionRecord>> txAsync;
  final String?                             filter;
  final VoidCallback                        onRefresh;
  final ValueChanged<String?>               onFilterChanged;

  const _TransactionListCard({
    required this.txAsync,
    required this.filter,
    required this.onRefresh,
    required this.onFilterChanged,
  });

  // 필터 칩 정의
  static const _chips = [
    (null,       '전체'),
    ('CHARGE',   '충전'),
    ('SPEND',    '지출'),
    ('EARN',     '적립'),
    ('WITHDRAW', '출금'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 제목 + 새로고침 ────────────────────────────────
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '거래 내역',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '새로고침',
                  color: Colors.grey[600],
                  onPressed: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── 필터 칩 ───────────────────────────────────────
            _buildFilterChips(),
            const SizedBox(height: 16),

            // ── 내역 목록 ─────────────────────────────────────
            txAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(36),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '내역 조회 오류: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
              data: (records) {
                // 서버에서 filterType 적용 완료 — 클라이언트 필터 불필요
                if (records.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        '거래 내역이 없습니다.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  );
                }

                return Column(
                  children: records
                      .map((r) => _TransactionItem(record: r))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _chips.map((chip) {
          final type      = chip.$1;
          final label     = chip.$2;
          final isSelected = filter == type;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => onFilterChanged(type),
              backgroundColor: Colors.grey[100],
              selectedColor: const Color(0xFFDCEAFF),
              checkmarkColor: const Color(0xFF1E3A8A),
              labelStyle: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? const Color(0xFF1E3A8A)
                    : Colors.grey[700],
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF93C5FD)
                      : Colors.grey[300]!,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 거래 내역 아이템 행
// ─────────────────────────────────────────────────────────────────

class _TransactionItem extends StatelessWidget {
  final TransactionRecord record;
  const _TransactionItem({required this.record});

  @override
  Widget build(BuildContext context) {
    final showStatus = record.status != 'COMPLETED';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 날짜 ────────────────────────────────────────
              SizedBox(
                width: 84,
                child: Text(
                  _fmtDateTime(record.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    height: 1.5,
                  ),
                ),
              ),

              // ── 타입 뱃지 ────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(right: 10, top: 1),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: record.typeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  record.typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: record.typeColor,
                  ),
                ),
              ),

              // ── 설명 ────────────────────────────────────────
              Expanded(
                child: Text(
                  record.description ?? '-',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(width: 10),

              // ── 금액 + 잔액 + 상태 ──────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    record.amountDisplay,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: record.isCredit
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFB71C1C),
                    ),
                  ),
                  if (record.balanceAfter != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '잔액 ${_fmtNum(record.balanceAfter!)}P',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  if (showStatus)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              record.statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          record.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: record.statusColor,
                          ),
                        ),
                      ),
                    ),
                ],
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
