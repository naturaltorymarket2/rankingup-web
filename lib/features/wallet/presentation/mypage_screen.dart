import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import 'wallet_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 마이페이지 화면 (/mypage)
// ─────────────────────────────────────────────────────────────────

class MypageScreen extends ConsumerWidget {
  const MypageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    final user         = supabase.auth.currentUser;
    final email        = user?.email ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('마이페이지'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 프로필 섹션 ────────────────────────────────────
              _ProfileSection(email: email),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),

              // ── 포인트 잔액 카드 ───────────────────────────────
              _BalanceCard(balanceAsync: balanceAsync),
              const SizedBox(height: 16),

              // ── 출금 신청 버튼 ────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/withdraw'),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('출금 신청'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.indigo.shade300),
                    foregroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // ── 로그아웃 버튼 ────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _onLogout(context),
                  icon: Icon(Icons.logout_rounded, color: Colors.red.shade400),
                  label: Text(
                    '로그아웃',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await supabase.auth.signOut();
    if (context.mounted) context.go('/login');
  }
}

// ─────────────────────────────────────────────────────────────────
// 프로필 섹션
// ─────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  final String email;
  const _ProfileSection({required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.indigo.shade100,
          child: Icon(Icons.person_rounded, color: Colors.indigo.shade700, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '앱 유저',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 포인트 잔액 카드
// ─────────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final AsyncValue<int> balanceAsync;
  const _BalanceCard({required this.balanceAsync});

  static String _formatBalance(int balance) {
    // 천 단위 구분자 (intl 없이)
    final str = balance.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write(',');
      buf.write(str[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              const Text(
                '보유 포인트',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          balanceAsync.when(
            loading: () => const SizedBox(
              height: 36,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
            error: (_, __) => const Text(
              '- P',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            data: (balance) => Text(
              '${_formatBalance(balance)} P',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
