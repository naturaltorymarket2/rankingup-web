import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/supabase_client.dart';
import '../domain/wallet_model.dart';

final walletRepositoryProvider = Provider.autoDispose<WalletRepository>(
  (_) => WalletRepository(),
);

class WalletRepository {
  static const int pageSize = 20;

  // ─────────────────────────────────────────────────────────────
  // 참여 내역 조회 (mission_logs JOIN campaigns, 페이지네이션)
  // ─────────────────────────────────────────────────────────────

  /// 미션 참여 내역 목록 (최신순)
  ///
  /// - mission_logs.user_id = userId
  /// - campaigns.keyword JOIN
  /// - started_at DESC, 20건씩 페이지네이션
  Future<List<MissionLogModel>> fetchHistory({
    required String userId,
    required int page,
  }) async {
    final start = page * pageSize;
    final end   = start + pageSize - 1;

    final raw = await supabase
        .from('mission_logs')
        .select('id, status, started_at, campaigns(keyword)')
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .range(start, end) as List<dynamic>;

    return raw
        .map((m) => MissionLogModel.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  // ─────────────────────────────────────────────────────────────
  // 출금 신청
  // ─────────────────────────────────────────────────────────────

  /// 출금 신청 INSERT
  ///
  /// - transactions 테이블: type=WITHDRAW, status=PENDING
  /// - description: 은행 정보 JSON {"bank", "account", "holder"}
  ///   (transactions 테이블에 memo 컬럼 없음 — description에 JSON 저장)
  ///   어드민 get_pending_withdraws RPC는 description AS memo 로 반환하여
  ///   admin_withdraw_model._memoMap 이 파싱함
  /// - 잔액 차감은 어드민 process_withdraw RPC에서 처리 — 여기서 하지 않음
  ///
  /// ⚠️ 이 수정 이전에 생성된 PENDING 출금 건은 description='출금 신청'(고정 텍스트)으로
  ///    저장되어 있어 어드민 화면에서 계좌 정보가 '-'로 표시됨.
  ///    Supabase Studio > Table Editor > transactions 에서 해당 PENDING 건의
  ///    description 컬럼을 수동으로 JSON 형식으로 업데이트해야 함.
  Future<void> submitWithdraw({
    required String userId,
    required int amount,
    required String bank,
    required String account,
    required String holder,
  }) async {
    // ── 중복 출금 신청 방지 ──────────────────────────────────────
    // PENDING 상태의 출금 건이 이미 존재하면 신청 차단
    final pending = await supabase
        .from('transactions')
        .select('id')
        .eq('user_id', userId)
        .eq('type', 'WITHDRAW')
        .eq('status', 'PENDING') as List<dynamic>;

    if (pending.isNotEmpty) {
      throw Exception('이미 출금 신청이 진행 중입니다');
    }

    final memoJson = jsonEncode({
      'bank':    bank,
      'account': account,
      'holder':  holder,
    });

    await supabase.from('transactions').insert({
      'user_id':     userId,
      'type':        'WITHDRAW',
      'amount':      amount,
      'status':      'PENDING',
      'description': memoJson,
    });
  }
}
