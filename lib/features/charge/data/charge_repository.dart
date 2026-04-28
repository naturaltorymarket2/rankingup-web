import '../../../app/supabase_client.dart';
import '../domain/charge_model.dart';

// ─────────────────────────────────────────────────────────────────
// 충전 데이터 접근 레이어
// ─────────────────────────────────────────────────────────────────

class ChargeRepository {
  /// 충전 신청 — transactions 테이블 직접 INSERT
  ///
  /// RLS 정책(transactions_charge_insert)에 의해
  /// type=CHARGE, status=PENDING 조건이 서버에서 강제됨
  Future<void> submitCharge({
    required int    amount,     // 지급될 포인트
    required String depositor,  // 입금자명
    required bool   taxInvoice, // 세금계산서 요청 여부
  }) async {
    final userId      = supabase.auth.currentUser!.id;
    final totalAmount = taxInvoice ? (amount * 1.1).round() : amount;

    // ── 중복 충전 신청 방지 ──────────────────────────────────────
    // PENDING 상태의 충전 건이 이미 존재하면 신청 차단
    final pending = await supabase
        .from('transactions')
        .select('id')
        .eq('user_id', userId)
        .eq('type', 'CHARGE')
        .eq('status', 'PENDING') as List<dynamic>;

    if (pending.isNotEmpty) {
      throw Exception('이미 충전 신청이 진행 중입니다');
    }

    await supabase.from('transactions').insert({
      'user_id':     userId,
      'type':        'CHARGE',
      'amount':      amount,
      'status':      'PENDING',
      'description': '입금자명: $depositor'
          ' | 세금계산서: ${taxInvoice ? "Y" : "N"}'
          ' | 입금금액: $totalAmount',
    });
  }

  /// 현재 유저의 CHARGE 내역 목록 (최신순, 최대 30건)
  Future<List<ChargeRecord>> fetchChargeHistory() async {
    final res = await supabase
        .from('transactions')
        .select('id, amount, status, description, created_at')
        .eq('type', 'CHARGE')
        .order('created_at', ascending: false)
        .limit(30);

    return (res as List<dynamic>)
        .map((e) => ChargeRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 현재 유저의 전체 거래 내역 (최신순, 최대 100건)
  ///
  /// [filterType]: null이면 전체 조회, 값 지정 시 서버에서 type 필터 적용
  ///   ('CHARGE' / 'SPEND' / 'EARN' / 'WITHDRAW')
  Future<List<TransactionRecord>> fetchAllTransactions({
    String? filterType,
  }) async {
    final List<dynamic> res;
    if (filterType != null) {
      res = await supabase
          .from('transactions')
          .select(
              'id, type, amount, status, description, created_at, balance_after')
          .eq('type', filterType)
          .order('created_at', ascending: false)
          .limit(100);
    } else {
      res = await supabase
          .from('transactions')
          .select(
              'id, type, amount, status, description, created_at, balance_after')
          .order('created_at', ascending: false)
          .limit(100);
    }

    return res
        .map((e) => TransactionRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// 현재 유저의 포인트 잔액
  Future<int> fetchCurrentBalance() async {
    final userId = supabase.auth.currentUser!.id;
    final res    = await supabase
        .from('wallets')
        .select('balance')
        .eq('user_id', userId)
        .single();
    return (res['balance'] as num).toInt();
  }
}
