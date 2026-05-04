import 'package:flutter/material.dart';

import '../../../shared/utils/rank_api_client.dart';

// ─────────────────────────────────────────────────────────────────
// 키워드 선택 모달
//
// 사용 예:
//   final selected = await showKeywordSelectModal(context, keywords,
//     preSelected: _selectedKeywords);
//   if (selected != null) { /* 사용자가 확인을 눌렀을 때 */ }
// ─────────────────────────────────────────────────────────────────

Future<List<KeywordRankResult>?> showKeywordSelectModal(
  BuildContext context,
  List<KeywordRankResult> keywords, {
  List<KeywordRankResult> preSelected = const [],
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
      child: _KeywordSelectModal(keywords: keywords, preSelected: preSelected),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────
// 모달 위젯
// ─────────────────────────────────────────────────────────────────

class _KeywordSelectModal extends StatefulWidget {
  final List<KeywordRankResult> keywords;
  final List<KeywordRankResult> preSelected;
  const _KeywordSelectModal({
    required this.keywords,
    this.preSelected = const [],
  });

  @override
  State<_KeywordSelectModal> createState() => _KeywordSelectModalState();
}

class _KeywordSelectModalState extends State<_KeywordSelectModal> {
  static const _maxOn = 10;
  static const _kBlue = Color(0xFF1E3A8A);

  late final List<bool> _toggles;

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

  int get _selectedCount => _toggles.where((t) => t).length;

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

        // ── 키워드 목록 ──────────────────────────────────────
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.keywords.length,
            separatorBuilder: (_, i) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final item = widget.keywords[i];
              final isOn      = _toggles[i];
              final canToggle = isOn || _selectedCount < _maxOn;

              return ListTile(
                title: Text(
                  item.keyword,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: _RankBadge(rank: item.rank),
                trailing: Switch(
                  value: isOn,
                  activeThumbColor: _kBlue,
                  onChanged: canToggle
                      ? (v) => setState(() => _toggles[i] = v)
                      : null,
                ),
              );
            },
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
                            for (var i = 0;
                                i < widget.keywords.length;
                                i++)
                              if (_toggles[i]) widget.keywords[i],
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
        ? const Color(0xFF2E7D32)  // 15위 이내 — 초록
        : Colors.orange;            // 16위 이상 — 주황
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
