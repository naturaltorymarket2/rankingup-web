import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'wallet_provider.dart';
import 'withdraw_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 출금 신청 화면 (/withdraw)
// ─────────────────────────────────────────────────────────────────
//
// 출금 조건:
//   - 최소 출금 금액: 5,000P
//   - 출금 수수료: 500P
//   - 실제 이체 금액 = 신청 금액 - 500P
//   - 잔액 부족 시 버튼 비활성화
//
// 주의: 신청 시점에 wallets.balance 차감 안 함 — 어드민 RPC에서 처리

class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  static const int _minAmount  = 5000;
  static const int _fee        = 500;

  final _bankCtrl    = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _holderCtrl  = TextEditingController();
  final _amountCtrl  = TextEditingController();

  int _parsedAmount = 0; // 입력 금액 (int)

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() {
      setState(() {
        _parsedAmount = int.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
      });
    });
    // A-011: 계좌번호 변경 시 버튼/경고 즉시 반영
    _accountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _bankCtrl.dispose();
    _accountCtrl.dispose();
    _holderCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  int get _netAmount => _parsedAmount - _fee;

  bool _canSubmit(int balance) =>
      _parsedAmount >= _minAmount &&
      _parsedAmount <= balance &&
      _bankCtrl.text.trim().isNotEmpty &&
      _accountCtrl.text.trim().length >= 10 && // A-011: 계좌번호 최소 10자리
      _holderCtrl.text.trim().isNotEmpty;

  Future<void> _onSubmit(int balance) async {
    if (!_canSubmit(balance)) return;

    final success = await ref.read(withdrawProvider.notifier).submit(
      amount:  _parsedAmount,
      bank:    _bankCtrl.text.trim(),
      account: _accountCtrl.text.trim(),
      holder:  _holderCtrl.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('출금 신청이 완료되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/mypage');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('오류가 발생했습니다. 다시 시도해 주세요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync  = ref.watch(walletBalanceProvider);
    final isSubmitting  = ref.watch(withdrawProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('출금 신청'),
        centerTitle: false,
      ),
      body: balanceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('잔액을 불러오지 못했습니다')),
        data: (balance) => SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 잔액 표시
                      _BalanceSummary(balance: balance),
                      const SizedBox(height: 28),

                      // 계좌 정보 입력
                      _SectionLabel('계좌 정보'),
                      const SizedBox(height: 12),
                      _InputField(
                        controller: _bankCtrl,
                        label: '은행명',
                        hint: '예) 카카오뱅크',
                        inputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      _InputField(
                        controller: _accountCtrl,
                        label: '계좌번호',
                        hint: '숫자만 입력 (10자리 이상)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(20),
                        ],
                        inputAction: TextInputAction.next,
                      ),
                      // A-011: 계좌번호 최소 길이 경고
                      if (_accountCtrl.text.isNotEmpty &&
                          _accountCtrl.text.trim().length < 10)
                        _WarningBanner('계좌번호는 10자리 이상 입력해주세요'),
                      const SizedBox(height: 12),
                      _InputField(
                        controller: _holderCtrl,
                        label: '예금주',
                        hint: '실명 입력',
                        inputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 24),

                      // 출금 금액
                      _SectionLabel('출금 금액'),
                      const SizedBox(height: 12),
                      _InputField(
                        controller: _amountCtrl,
                        label: '출금 금액 (P)',
                        hint: '최소 5,000P',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        inputAction: TextInputAction.done,
                      ),

                      // 잔액 부족 안내
                      if (_parsedAmount > 0 && _parsedAmount > balance)
                        _WarningBanner('잔액이 부족합니다 (보유: ${balance}P)'),

                      if (_parsedAmount > 0 && _parsedAmount < _minAmount)
                        _WarningBanner('최소 출금 금액은 ${_minAmount}P입니다'),

                      // 금액 계산 표시
                      if (_parsedAmount >= _minAmount && _parsedAmount <= balance) ...[
                        const SizedBox(height: 16),
                        _AmountSummary(amount: _parsedAmount, fee: _fee),
                      ],
                    ],
                  ),
                ),
              ),

              // 하단 신청 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _canSubmit(balance) && !isSubmitting
                        ? () => _onSubmit(balance)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            '출금 신청',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 서브 위젯들
// ─────────────────────────────────────────────────────────────────

class _BalanceSummary extends StatelessWidget {
  final int balance;
  const _BalanceSummary({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '보유 포인트',
            style: TextStyle(color: Colors.indigo.shade700, fontSize: 14),
          ),
          Text(
            '$balance P',
            style: TextStyle(
              color: Colors.indigo.shade800,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade700,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction inputAction;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
    required this.inputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: inputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.indigo.shade400, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text(
            message,
            style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AmountSummary extends StatelessWidget {
  final int amount;
  final int fee;
  const _AmountSummary({required this.amount, required this.fee});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _Row('신청 금액', '${amount}P'),
          const SizedBox(height: 6),
          _Row('출금 수수료', '-${fee}P', color: Colors.red.shade400),
          const Divider(height: 16),
          _Row('실 이체 금액', '${amount - fee}P',
              color: Colors.indigo.shade700, bold: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _Row(this.label, this.value, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
