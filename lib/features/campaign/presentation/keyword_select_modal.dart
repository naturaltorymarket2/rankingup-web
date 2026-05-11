import 'package:flutter/material.dart';

import '../../../shared/utils/rank_api_client.dart';

// ─────────────────────────────────────────────────────────────────
// 키워드 선택 모달
//
// 사용 예:
//   final selected = await showKeywordSelectModal(context, keywords,
//     preSelected: _selectedKeywords,
//     productUrl: _urlCtrl.text.trim());
//   if (selected != null) { /* 사용자가 확인을 눌렀을 때 */ }
// ─────────────────────────────────────────────────────────────────

Future<List<KeywordRankResult>?> showKeywordSelectModal(
  BuildContext context,
  List<KeywordRankResult> keywords, {
  List<KeywordRankResult> preSelected = const [],
  String productUrl = '',
}) {
  final maxH = MediaQuery.of(context).size.height * 0.85;
  return showModalBottomSheet<List<KeywordRankResult>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: _KeywordSelectModal(
        keywords: keywords,
        preSelected: preSelected,
        productUrl: productUrl,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────
// 모달 위젯
// ─────────────────────────────────────────────────────────────────

class _KeywordSelectModal extends StatefulWidget {
  final List<KeywordRankResult> keywords;
  final List<KeywordRankResult> preSelected;
  final String productUrl;
  const _KeywordSelectModal({
    required this.keywords,
    this.preSelected = const [],
    this.productUrl = '',
  });

  @override
  State<_KeywordSelectModal> createState() => _KeywordSelectModalState();
}

class _KeywordSelectModalState extends State<_KeywordSelectModal> {
  static const _maxOn   = 10;
  static const _kBlue   = Color(0xFF1E3A8A);

  late final List<bool> _toggles;

  // ── 직접 추가 키워드 ─────────────────────────────────────────────
  final List<KeywordRankResult> _customKeywords = [];
  final List<bool>              _customToggles  = [];
  final TextEditingController   _customController = TextEditingController();
  bool _isAddingKeyword = false;

  final _rankClient = RankApiClient();

  @override
  void initState() {
    super.initState();
    // 이전 선택 키워드(preSelected)와 키워드명이 일치하면 ON 상태로 초기화
    final preSelectedKeywords =
        widget.preSelected.map((k) => k.keyword).toSet();
    _toggles = widget.keywords
        .map((k) => preSelectedKeywords.contains(k.keyword))
        .toList();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  // 추천 + 직접 추가 합산 선택 수
  int get _selectedCount =>
      _toggles.where((t) => t).length +
      _customToggles.where((t) => t).length;

  // 현재 존재하는 모든 키워드 이름 (중복 체크용)
  Set<String> get _allKeywordNames => {
        ...widget.keywords.map((k) => k.keyword),
        ..._customKeywords.map((k) => k.keyword),
      };

  // ─────────────────────────────────────────────────────────────
  // 직접 추가 로직
  // ─────────────────────────────────────────────────────────────

  Future<void> _addCustomKeyword() async {
    final input = _customController.text.trim();
    if (input.isEmpty) return;

    if (_allKeywordNames.contains(input)) {
      _showToast('이미 추가된 키워드입니다');
      return;
    }
    if (_customKeywords.length >= _maxOn) {
      _showToast('직접 추가는 최대 ${_maxOn}개까지 가능합니다');
      return;
    }

    setState(() => _isAddingKeyword = true);

    int? rank;
    if (widget.productUrl.isNotEmpty) {
      try {
        final result = await _rankClient.fetchRank(widget.productUrl, input);
        rank = result.rank;
      } catch (_) {
        rank = null; // 타임아웃·네트워크 오류 → 순위권 밖으로 처리
      }
    }

    if (!mounted) return;

    setState(() {
      _customKeywords.add(KeywordRankResult(keyword: input, rank: rank));
      _customToggles.add(true); // 추가 즉시 선택 상태
      _customController.clear();
      _isAddingKeyword = false;
    });
  }

  void _removeCustomKeyword(int index) {
    setState(() {
      _customKeywords.removeAt(index);
      _customToggles.removeAt(index);
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 드래그 핸들 ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── 타이틀 + 선택 카운터 ────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '키워드 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '선택된 키워드: $_selectedCount/$_maxOn',
                style: TextStyle(
                  fontSize: 13,
                  color: _selectedCount >= _maxOn
                      ? Colors.red
                      : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),

        // ── 안내 박스 ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(color: Color(0xFF3B82F6), width: 4),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• 최소 키워드 1개는 ON해야 등록이 가능합니다',
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
                Text(
                  '• CPC 광고가 노출되는 키워드는 해제해주세요',
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
                Text(
                  '• 15위 이내의 키워드만 ON해주세요',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 1),

        // ── 스크롤 가능한 목록 영역 ──────────────────────────
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              // ── 추천 키워드 섹션 헤더 ──────────────────────
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '추천 키워드',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),

              // ── 추천 키워드 목록 ───────────────────────────
              for (var i = 0; i < widget.keywords.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                _RecommendedKeywordTile(
                  item: widget.keywords[i],
                  isOn: _toggles[i],
                  canToggle: _toggles[i] || _selectedCount < _maxOn,
                  onChanged: (v) => setState(() => _toggles[i] = v),
                ),
              ],

              const Divider(height: 1),

              // ── 직접 추가 섹션 헤더 ────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '직접 추가 (${_customKeywords.length}/$_maxOn)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),

              // ── 직접 추가 입력창 ───────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        enabled: !_isAddingKeyword,
                        decoration: InputDecoration(
                          hintText: '키워드 직접 입력',
                          hintStyle: const TextStyle(fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: (_) {
                          if (!_isAddingKeyword) _addCustomKeyword();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isAddingKeyword ? null : _addCustomKeyword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: _isAddingKeyword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('추가', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── 직접 추가 키워드 목록 ──────────────────────
              for (var i = 0; i < _customKeywords.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                _CustomKeywordTile(
                  item: _customKeywords[i],
                  isOn: _customToggles[i],
                  canToggle: _customToggles[i] || _selectedCount < _maxOn,
                  onChanged: (v) => setState(() => _customToggles[i] = v),
                  onDelete: () => _removeCustomKeyword(i),
                ),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── 하단 버튼 ────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _selectedCount == 0
                      ? null
                      : () {
                          final selected = [
                            for (var i = 0; i < widget.keywords.length; i++)
                              if (_toggles[i]) widget.keywords[i],
                            for (var i = 0; i < _customKeywords.length; i++)
                              if (_customToggles[i]) _customKeywords[i],
                          ];
                          Navigator.of(context).pop(selected);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: Text(
                    _selectedCount == 0
                        ? '키워드를 선택해주세요'
                        : '$_selectedCount개 선택 완료',
                  ),
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
// 추천 키워드 행
// ─────────────────────────────────────────────────────────────────

class _RecommendedKeywordTile extends StatelessWidget {
  final KeywordRankResult item;
  final bool isOn;
  final bool canToggle;
  final ValueChanged<bool> onChanged;

  const _RecommendedKeywordTile({
    required this.item,
    required this.isOn,
    required this.canToggle,
    required this.onChanged,
  });

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(item.keyword, style: const TextStyle(fontSize: 14)),
      subtitle: _RankBadge(rank: item.rank),
      trailing: Switch(
        value: isOn,
        activeThumbColor: _kBlue,
        onChanged: canToggle ? onChanged : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 직접 추가 키워드 행 (삭제 버튼 포함)
// ─────────────────────────────────────────────────────────────────

class _CustomKeywordTile extends StatelessWidget {
  final KeywordRankResult item;
  final bool isOn;
  final bool canToggle;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;

  const _CustomKeywordTile({
    required this.item,
    required this.isOn,
    required this.canToggle,
    required this.onChanged,
    required this.onDelete,
  });

  static const _kBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(item.keyword, style: const TextStyle(fontSize: 14)),
      subtitle: _RankBadge(rank: item.rank),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: isOn,
            activeThumbColor: _kBlue,
            onChanged: canToggle ? onChanged : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.grey[500],
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 순위 뱃지
// ─────────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final int? rank;
  const _RankBadge({this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank == null) {
      return const Text(
        '순위권 밖',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    final color = rank! <= 15
        ? const Color(0xFF2E7D32) // 15위 이내 — 초록
        : Colors.orange;          // 16위 이상 — 주황
    return Text(
      '$rank위',
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
