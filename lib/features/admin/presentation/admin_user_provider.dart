import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_user_repository.dart';
import '../domain/admin_user_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 회원 관리 프로바이더
// ─────────────────────────────────────────────────────────────────

final adminUserRepositoryProvider = Provider<AdminUserRepository>(
  (_) => AdminUserRepository(),
);

/// 검색어 (빈 문자열이면 전체)
final adminUserSearchProvider = StateProvider.autoDispose<String>((_) => '');

/// 회원 목록 — 검색어가 바뀌면 다시 읽는다
final adminUsersProvider =
    FutureProvider.autoDispose<List<AdminUserRecord>>((ref) {
  final search = ref.watch(adminUserSearchProvider);
  return ref.read(adminUserRepositoryProvider).fetchUsers(search: search);
});
