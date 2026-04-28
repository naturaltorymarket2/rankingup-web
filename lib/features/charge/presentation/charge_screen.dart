import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/charge_model.dart';
import 'charge_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 포인트 충전 웹 화면  (/web/charge)
// ─────────────────────────────────────────────────────────────────

class ChargeScreen extends ConsumerStatefulWidget {
  const ChargeScreen({super.key});

  @override
  ConsumerState<ChargeScreen> createState() => _ChargeScreenState();
}

class _ChargeScreenState extends ConsumerState<ChargeScreen> {
  final _amountCtrl    = TextEditingController();
  final _depositorCtrl = TextEditingController();
  bool _taxInvoice  = false;
  bool _isSubmitting = false;

  // ── 색상 상수 ─────────────────────────────────────────────────
  static const _kBlue  = Color(0xFF1E3A8A);
  static const _kLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111827),
  );

  // ── 파생 값 ──────────────────────────────────────────────────

  int get _parsedAmount =>
      int.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  int get _totalAmount =>
      _taxInvoice ? (_parsedAmount * 1.1).round() : _parsedAmount;

  bool get _isFormValid =>
      _parsedAmount >= 10000 &&
      _depositorCtrl.text.trim().isNotEmpty &&
      !_isSubmitting;

  // ── 생명주기 ──────────────────────────────────────────────────

  @override
  void dispose() {
    _amountCtrl.dispose();
    _depositorCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(chargeHistoryProvider);

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
          '포인트 충전',
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
                _buildChargeForm(),
                const SizedBox(height: 24),
                _buildChargeHistory(historyAsync),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => context.go('/web/dashboard'),
                  icon: const Icon(Icons.dashboard_outlined,
                      size: 18),
                  label: const Text('대시보드로 돌아가기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBlue,
                    minimumSize:
                        const Size(double.infinity, 48),
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

  // ─────────────────────────────────────────────────────────────
  // 충전 신청 폼
  // ─────────────────────────────────────────────────────────────

  Widget _buildChargeForm() {
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('충전 신청', style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          )),
          const SizedBox(height: 20),

          // ── 충전 금액 ────────────────────────────────────────
          const Text('충전 금액', style: _kLabel),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              hintText: '최소 10,000',
              suffixText: '원',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_amountCtrl.text.isNotEmpty &&
              _parsedAmount < 10000)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '최소 10,000원 이상 입력해주세요.',
                style:
                    TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          const SizedBox(height: 16),

          // ── 입금자명 ─────────────────────────────────────────
          const Text('입금자명', style: _kLabel),
          const SizedBox(height: 8),
          TextField(
            controller: _depositorCtrl,
            decoration: const InputDecoration(
              hintText: '입금 시 사용할 이름',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 16),

          // ── 세금계산서 ───────────────────────────────────────
          InkWell(
            onTap: () =>
                setState(() => _taxInvoice = !_taxInvoice),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Checkbox(
                  value: _taxInvoice,
                  activeColor: _kBlue,
                  onChanged: (v) =>
                      setState(() => _taxInvoice = v!),
                ),
                const Expanded(
                  child: Text(
                    '세금계산서 발급 요청',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          if (_taxInvoice)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '세금계산서 발급 시 부가세 10%가 추가됩니다.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600]),
              ),
            ),

          const SizedBox(height: 20),

          // ── 입금 계좌 안내 ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFBFD0FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance,
                        size: 16,
                        color: Colors.blueGrey[600]),
                    const SizedBox(width: 6),
                    Text(
                      '입금 계좌 안내',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _AccountRow(
                    label: '은행', value: '카카오뱅크'),
                // TODO: 실제 입금 계좌 정보로 교체 필요
                const _AccountRow(
                    label: '계좌번호',
                    value: '3333-03-3855618'),
                const _AccountRow(
                    label: '예금주',
                    value: '최현석'),
                const SizedBox(height: 6),
                Text(
                  '입금자명을 반드시 위에 입력한 이름과 동일하게 입력해주세요.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey[500],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 총 입금액 ─────────────────────────────────────────
          if (_parsedAmount >= 10000) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _CalcRow(
                    label: '충전 포인트',
                    value: '${_fmtNum(_parsedAmount)}P',
                  ),
                  if (_taxInvoice) ...[
                    const SizedBox(height: 4),
                    _CalcRow(
                      label: '부가세 (10%)',
                      value:
                          '+${_fmtNum(_totalAmount - _parsedAmount)}원',
                      valueColor: Colors.orange[700]!,
                    ),
                  ],
                  const Divider(height: 16),
                  _CalcRow(
                    label: '실제 입금 금액',
                    value: '${_fmtNum(_totalAmount)}원',
                    bold: true,
                    valueColor: _kBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 신청 버튼 ─────────────────────────────────────────
          ElevatedButton(
            onPressed: _isFormValid ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('충전 신청'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 충전 내역
  // ─────────────────────────────────────────────────────────────

  Widget _buildChargeHistory(
      AsyncValue<List<ChargeRecord>> historyAsync) {
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '충전 내역',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          historyAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                '내역 조회 오류: $e',
                style:
                    const TextStyle(color: Colors.red),
              ),
            ),
            data: (records) => records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24),
                    child: Center(
                      child: Text(
                        '충전 내역이 없습니다.',
                        style: TextStyle(
                            color: Colors.grey[500]),
                      ),
                    ),
                  )
                : Column(
                    children: records
                        .map((r) => _ChargeHistoryItem(
                            record: r))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 충전 신청 제출
  // ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(chargeRepositoryProvider)
          .submitCharge(
            amount:     _parsedAmount,
            depositor:  _depositorCtrl.text.trim(),
            taxInvoice: _taxInvoice,
          );

      if (!mounted) return;

      // 폼 초기화
      _amountCtrl.clear();
      _depositorCtrl.clear();
      setState(() => _taxInvoice = false);

      // 내역 새로고침
      ref.invalidate(chargeHistoryProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '충전 신청이 완료되었습니다.\n'
            '입금 확인 후 어드민 승인 시 포인트가 지급됩니다.',
          ),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('submitCharge error: $e'); // B-007
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('오류가 발생했습니다. 잠시 후 다시 시도해주세요.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────
// 계좌 정보 행
// ─────────────────────────────────────────────────────────────────

class _AccountRow extends StatelessWidget {
  final String label;
  final String value;
  const _AccountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13, color: Colors.blueGrey[600]),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 금액 계산 행
// ─────────────────────────────────────────────────────────────────

class _CalcRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   bold;
  final Color? valueColor;

  const _CalcRow({
    required this.label,
    required this.value,
    this.bold       = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize:   bold ? 16 : 14,
      color:      valueColor,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: bold ? Colors.black87 : Colors.grey[600],
              fontWeight:
                  bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        Text(value, style: style),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 충전 내역 아이템
// ─────────────────────────────────────────────────────────────────

class _ChargeHistoryItem extends StatelessWidget {
  final ChargeRecord record;
  const _ChargeHistoryItem({required this.record});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 날짜
              SizedBox(
                width: 110,
                child: Text(
                  _fmtDateTime(record.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
              ),

              // 금액 + 상세
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_fmtNum(record.amount)}P',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '입금자명: ${record.depositorName}'
                      ' · 입금금액: ${_fmtNum(record.totalTransferAmount)}원'
                      '${record.hasTaxInvoice ? " (세금계산서)" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              // 상태 뱃지
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: record.statusColor.withOpacity(0.12),
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
    final s = n.toString();
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

class _WebCard extends StatelessWidget {
  final Widget child;
  const _WebCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
          padding: const EdgeInsets.all(20), child: child),
    );
  }
}
