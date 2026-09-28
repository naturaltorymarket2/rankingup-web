import 'package:flutter/material.dart';

import '../../../shared/utils/rank_api_client.dart';
import '../data/admin_campaign_repository.dart';
import '../domain/admin_campaign_model.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 키워드 수정 다이얼로그
//
// 광고주가 통합검색 8위 밖 키워드를 등록하면 리워드 유저가 상품을 찾지
// 못한다. 운영자가 키워드 이름을 직접 고치고, [순위 확인]으로 통합검색
// 순위를 바로 확인할 수 있다 (SerpApi 1회 소모, 같은 키워드는 24시간 캐시).
//
// 키워드 '이름'만 바꾼다 — 개수·일일 목표·예산·태그는 그대로다.
//
// 사용 예:
//   final changed = await showKeywordEditDialog(context, repo, record);
//   if (changed) ref.invalidate(...);
// ─────────────────────────────────────────────────────────────────

/// 저장했으면 true, 취소·변경 없음이면 false
Future<bool> showKeywordEditDialog(
  BuildContext              context,
  AdminCampaignRepository   repository,
  AdminCampaignRecord       record,
) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _KeywordEditDialog(repository: repository, record: record),
  );
  return saved == true;
}

/// 키워드 1개의 편집 상태
class _KeywordRow {
  final String                campaignId;
  final String                original;
  final TextEditingController ctrl;

  /// 순위 확인 결과 — null: 아직 확인 안 함
  String? rankLabel;
  Color?  rankColor;
  bool    checking = false;

  _KeywordRow(this.campaignId, this.original)
      : ctrl = TextEditingController(text: original);
}

class _KeywordEditDialog extends StatefulWidget {
  final AdminCampaignRepository repository;
  final AdminCampaignRecord     record;

  const _KeywordEditDialog({required this.repository, required this.record});

  @override
  State<_KeywordEditDialog> createState() => _KeywordEditDialogState();
}

class _KeywordEditDialogState extends State<_KeywordEditDialog> {
  static const _kBlue  = Color(0xFF1E3A8A);
  static const _kRed   = Color(0xFFB71C1C);
  static const _kGreen = Color(0xFF2E7D32);

  /// 리워드 유저가 상품을 찾을 수 있는 기준 순위 (랭킹 서버 TARGET_RANK 와 동일)
  static const _kTargetRank = 8;

  final _seedCtrl   = TextEditingController();
  final _rankClient = RankApiClient();

  List<_KeywordRow> _rows = [];
  String  _originalSeed = '';
  bool    _loading = true;
  bool    _saving  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _seedCtrl.dispose();
    for (final r in _rows) {
      r.ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.repository
          .fetchCampaignKeywords(groupId: widget.record.groupId);
      if (!mounted) return;

      if (res['success'] != true) {
        setState(() {
          _loading = false;
          _error   = _errorMessage(res);
        });
        return;
      }

      final list = res['keywords'] as List<dynamic>? ?? const [];
      setState(() {
        _originalSeed  = res['seed_keyword'] as String? ?? '';
        _seedCtrl.text = _originalSeed;
        _rows = list.map((e) {
          final m = e as Map<String, dynamic>;
          return _KeywordRow(
            m['campaign_id'] as String,
            m['keyword'] as String? ?? '',
          );
        }).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = '키워드를 불러오지 못했습니다: $e';
      });
    }
  }

  bool get _hasChanges =>
      _seedCtrl.text.trim() != _originalSeed.trim() ||
      _rows.any((r) => r.ctrl.text.trim() != r.original.trim());

  bool get _hasEmpty => _rows.any((r) => r.ctrl.text.trim().isEmpty);

  // ─────────────────────────────────────────────────────────────
  // 순위 확인 (통합검색)
  // ─────────────────────────────────────────────────────────────

  Future<void> _checkRank(_KeywordRow row) async {
    final keyword = row.ctrl.text.trim();
    if (keyword.isEmpty || widget.record.productUrl.isEmpty) return;

    setState(() => row.checking = true);
    String label;
    Color  color;
    try {
      final result = await _rankClient.fetchRank(
        widget.record.productUrl,
        keyword,
        productName: widget.record.productName,
        brandName:   widget.record.brandName,
      );
      final rank = result.rank;
      label = '$rank위';
      color = rank <= _kTargetRank ? _kGreen : Colors.orange;
    } on RankNotFoundException {
      // 통합검색 쇼핑 블록(10위)에 노출되지 않음
      label = '순위권 밖';
      color = _kRed;
    } on RankTimeoutException {
      label = '시간 초과';
      color = Colors.grey;
    } catch (_) {
      label = '조회 실패';
      color = Colors.grey;
    }

    if (!mounted) return;
    setState(() {
      row.checking  = false;
      row.rankLabel = '$keyword → $label';
      row.rankColor = color;
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 저장
  // ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error  = null;
    });

    try {
      final seed = _seedCtrl.text.trim();
      final res  = await widget.repository.updateCampaignKeywords(
        groupId:     widget.record.groupId,
        campaignIds: _rows.map((r) => r.campaignId).toList(),
        keywords:    _rows.map((r) => r.ctrl.text.trim()).toList(),
        seedKeyword: seed.isEmpty ? null : seed,
      );
      if (!mounted) return;

      if (res['success'] == true) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _saving = false;
        _error  = _errorMessage(res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error  = '저장 오류: $e';
      });
    }
  }

  String _errorMessage(Map<String, dynamic> res) {
    final error = res['error'] as String? ?? 'UNKNOWN';
    return switch (error) {
      'DUPLICATE_KEYWORD' => '중복된 키워드가 있습니다: ${res['keyword']}',
      'KEYWORD_TOO_LONG'  => '키워드가 너무 깁니다 (최대 50자): ${res['keyword']}',
      'EMPTY_KEYWORD'     => '빈 키워드가 있습니다.',
      'NOT_IN_GROUP'      => '광고 정보가 바뀌었습니다. 목록을 새로고침해주세요.',
      'NOT_FOUND'         => '광고를 찾을 수 없습니다. 목록을 새로고침해주세요.',
      'FORBIDDEN'         => '어드민 권한이 없습니다.',
      _                   => '오류: $error',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final record = widget.record;

    return AlertDialog(
      title: const Text('키워드 수정'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${record.productName} / ${record.brandName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '• 통합검색 8위 이내에 이 상품이 나오는 키워드로 바꿔주세요.\n'
                        '• [순위 확인]은 SerpApi를 1회 사용합니다 (같은 키워드는 24시간 캐시).\n'
                        '• 키워드 이름만 바뀝니다. 개수·일일 목표·예산·태그는 그대로입니다.\n'
                        '• 바뀐 키워드의 위치 힌트는 다음 순위 수집 후부터 앱에 표시됩니다.',
                        style: TextStyle(fontSize: 12, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 메인(순위 추적) 키워드 ──────────────────
                    const Text(
                      '순위 추적 키워드',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _seedCtrl,
                      onChanged: (_) => setState(() {}),
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        helperText: '광고주 대시보드 순위 차트 기준 키워드',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 미션 키워드 ────────────────────────────
                    Text(
                      '미션 키워드 (${_rows.length}개)',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    for (final row in _rows) _buildRow(row),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(color: _kRed, fontSize: 13)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: (_loading || _saving || !_hasChanges || _hasEmpty)
              ? null
              : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('저장'),
        ),
      ],
    );
  }

  Widget _buildRow(_KeywordRow row) {
    final changed = row.ctrl.text.trim() != row.original.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.ctrl,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: changed ? '기존: ${row.original}' : null,
                    errorText: row.ctrl.text.trim().isEmpty
                        ? '키워드를 입력해주세요'
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                height: 40,
                child: OutlinedButton(
                  onPressed: (row.checking ||
                          _saving ||
                          row.ctrl.text.trim().isEmpty)
                      ? null
                      : () => _checkRank(row),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: row.checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('순위 확인'),
                ),
              ),
            ],
          ),
          if (row.rankLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                row.rankLabel!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: row.rankColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
