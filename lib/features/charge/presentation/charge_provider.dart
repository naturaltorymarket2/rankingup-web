import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/charge_repository.dart';
import '../domain/charge_model.dart';

// ─────────────────────────────────────────────────────────────────
// 충전 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final chargeRepositoryProvider = Provider<ChargeRepository>(
  (_) => ChargeRepository(),
);

/// 현재 유저의 CHARGE 내역 목록
///
/// 충전 신청 성공 후 ref.invalidate(chargeHistoryProvider) 로 갱신
final chargeHistoryProvider =
    FutureProvider.autoDispose<List<ChargeRecord>>((ref) {
  return ref.read(chargeRepositoryProvider).fetchChargeHistory();
});

/// 현재 유저의 포인트 잔액
final currentBalanceProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.read(chargeRepositoryProvider).fetchCurrentBalance();
});

/// 전체 거래 내역 (CHARGE / SPEND / EARN / WITHDRAW)
///
/// transactionsFilterProvider 를 watch → 필터 변경 시 자동 재조회
/// 새로고침 버튼에서 ref.invalidate(transactionsProvider) 호출
final transactionsProvider =
    FutureProvider.autoDispose<List<TransactionRecord>>((ref) {
  final filter = ref.watch(transactionsFilterProvider);
  return ref.read(chargeRepositoryProvider)
      .fetchAllTransactions(filterType: filter);
});

/// 거래 내역 필터 (null = 전체, 'CHARGE' / 'SPEND' / 'EARN' / 'WITHDRAW')
final transactionsFilterProvider =
    StateProvider.autoDispose<String?>((ref) => null);
