import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';

/// 현재 유저의 포인트 잔액
/// wallets.balance 를 단순 조회 (수정은 RPC만 허용)
final walletBalanceProvider = FutureProvider.autoDispose<int>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return 0;

  final response = await supabase
      .from('wallets')
      .select('balance')
      .eq('user_id', userId)
      .single();

  return (response['balance'] as num?)?.toInt() ?? 0;
});
