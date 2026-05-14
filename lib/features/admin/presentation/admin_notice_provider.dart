import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notice_repository.dart';
import '../domain/notice_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 공지사항 Riverpod 프로바이더
// ─────────────────────────────────────────────────────────────────

final noticeRepositoryProvider = Provider<NoticeRepository>(
  (_) => NoticeRepository(),
);

/// 전체 공지 목록 (최신순)
///
/// 등록 후 ref.invalidate(adminNoticesProvider) 로 갱신
final adminNoticesProvider =
    FutureProvider.autoDispose<List<NoticeModel>>((ref) {
  return ref.read(noticeRepositoryProvider).fetchNotices();
});
