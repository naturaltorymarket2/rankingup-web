// ─────────────────────────────────────────────────────────────────
// 공지사항 도메인 모델
//
// get_notices / create_notice RPC 응답 공용 모델.
// 어드민(등록), 광고주 대시보드(조회) 양쪽에서 사용.
// ─────────────────────────────────────────────────────────────────

class NoticeModel {
  final String   id;
  final String   title;
  final String   content;
  final DateTime createdAt;
  final String?  createdBy; // created_by uuid (nullable)

  const NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.createdBy,
  });

  factory NoticeModel.fromMap(Map<String, dynamic> map) => NoticeModel(
        id:        map['id']         as String,
        title:     map['title']      as String,
        content:   map['content']    as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        createdBy: map['created_by'] as String?,
      );
}
