import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/file_download.dart';
import '../data/campaign_repository.dart';
import '../domain/bulk_campaign_model.dart';
import 'campaign_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 광고 대량 등록 (/web/campaign/bulk)
// ─────────────────────────────────────────────────────────────────
//
// 흐름: 템플릿 내려받기 → 작성 → 업로드 → 행별 검증 결과 확인 → 일괄 등록
//
// 업로드 즉시 등록하지 않는다. 한 번에 수십 건이 나가는 기능이라
// 무엇이 등록되는지, 포인트가 얼마나 빠지는지 먼저 보여주고 확인받는다.
//
// 개별 등록과 달리 키워드 추천(SerpApi)을 하지 않는다 — 1건당 5회를 쓰기
// 때문에 대량으로 돌리면 월 한도가 바로 소진된다.

class CampaignBulkScreen extends ConsumerStatefulWidget {
  const CampaignBulkScreen({super.key});

  @override
  ConsumerState<CampaignBulkScreen> createState() => _CampaignBulkScreenState();
}

class _CampaignBulkScreenState extends ConsumerState<CampaignBulkScreen> {
  BulkParseResult? _parsed;
  String?          _fileName;
  bool             _isSubmitting = false;

  /// 등록 진행 상황 (n번째 / 전체)
  int _doneCount = 0;

  // ── 템플릿 내려받기 ──────────────────────────────────────────
  void _downloadTemplate() {
    try {
      downloadBytes(buildBulkTemplate(), '퀴즈캐시나우_광고등록_템플릿.xlsx');
    } catch (e) {
      _toast('템플릿을 내려받지 못했습니다: $e', isError: true);
    }
  }

  // ── 파일 선택 + 검증 ────────────────────────────────────────
  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type:           FileType.custom,
      allowedExtensions: ['xlsx'],
      withData:       true,   // 웹에서는 경로가 없으므로 바이트로 받는다
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast('파일을 읽지 못했습니다. 다시 선택해 주세요.', isError: true);
      return;
    }

    final now = DateTime.now().toUtc().add(const Duration(hours: 9)); // KST
    final today = DateTime(now.year, now.month, now.day);

    final result = parseBulkExcel(bytes, today: today);

    setState(() {
      _fileName  = file.name;
      _parsed    = result;
      _doneCount = 0;
    });
  }

  // ── 일괄 등록 ────────────────────────────────────────────────
  Future<void> _submit() async {
    final parsed = _parsed;
    if (parsed == null || parsed.validRows.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _toast('로그인이 필요합니다.', isError: true);
      return;
    }

    final rows = parsed.validRows;
    final ok = await _confirmDialog(rows.length, parsed.totalBudget);
    if (ok != true) return;

    setState(() {
      _isSubmitting = true;
      _doneCount    = 0;
    });

    final repo = CampaignRepository();
    final failures = <String>[];

    for (final row in rows) {
      try {
        // 대량 등록은 서브키워드를 나누지 않는다.
        // 엑셀에 적은 메인 키워드 하나가 그대로 그룹 전체가 된다.
        final groupId = const Uuid().v4();
        await repo.registerCampaign(
          userId:           userId,
          productUrl:       row.productUrl,
          keyword:          row.keyword,
          dailyTarget:      row.dailyTarget,
          groupDailyTarget: row.dailyTarget,
          groupId:          groupId,
          startDate:        row.startDate!,
          endDate:          row.endDate!,
          seedKeyword:      row.keyword,
          productName:      row.productName,
          brandName:        row.brandName,
        );
      } catch (e) {
        failures.add('${row.rowNumber}행 (${row.productName}): $e');
      }

      if (!mounted) return;
      setState(() => _doneCount++);
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // 잔액이 바뀌었을 수 있으니 대시보드 쪽 값을 새로 읽게 한다
    ref.invalidate(walletBalanceProvider);

    if (failures.isEmpty) {
      await _resultDialog(
        title: '등록 완료',
        body:  '광고 ${rows.length}건이 등록되었습니다.\n'
               '운영자 승인 후 앱에 노출되며, 포인트는 승인 시점에 차감됩니다.',
      );
      if (mounted) context.go('/web/dashboard');
    } else {
      await _resultDialog(
        title: '일부 등록 실패',
        body:  '${rows.length - failures.length}건 등록 / ${failures.length}건 실패\n\n'
               '${failures.take(5).join('\n')}'
               '${failures.length > 5 ? '\n… 외 ${failures.length - 5}건' : ''}',
      );
    }
  }

  Future<bool?> _confirmDialog(int count, int budget) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('광고를 등록할까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('등록 건수: $count건'),
            const SizedBox(height: 6),
            Text('차감 예정: ${_comma(budget)}P'),
            const SizedBox(height: 14),
            Text(
              '포인트는 등록 시점이 아니라 운영자 승인 시점에 차감됩니다.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
  }

  Future<void> _resultDialog({required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── 빌드 ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('광고 대량 등록'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/web/campaign/new'),
            icon:  const Icon(Icons.edit_outlined, size: 18),
            label: const Text('개별 등록'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _StepCard(
                step:  '1',
                title: '템플릿 내려받기',
                body:  '정해진 형식으로 작성해야 등록됩니다. '
                       '엑셀을 열어 2행의 예시를 지우고 광고 정보를 입력해 주세요.',
                action: OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon:  const Icon(Icons.download_outlined, size: 18),
                  label: const Text('엑셀 템플릿 내려받기'),
                ),
              ),
              const SizedBox(height: 16),

              _StepCard(
                step:  '2',
                title: '작성한 파일 올리기',
                body:  _fileName == null
                    ? '작성을 마친 xlsx 파일을 올려 주세요. 바로 등록되지 않고 '
                      '내용을 먼저 확인할 수 있습니다.'
                    : '선택한 파일: $_fileName',
                action: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _pickFile,
                  icon:  const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(_fileName == null ? '파일 선택' : '다른 파일 선택'),
                ),
              ),
              const SizedBox(height: 16),

              if (parsed != null) ...[
                if (parsed.fileError != null)
                  _ErrorBox(message: parsed.fileError!)
                else
                  _ResultSection(
                    parsed:       parsed,
                    isSubmitting: _isSubmitting,
                    doneCount:    _doneCount,
                    onSubmit:     _submit,
                  ),
                const SizedBox(height: 32),
              ],

              const _GuideCard(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 검증 결과
// ─────────────────────────────────────────────────────────────────

class _ResultSection extends StatelessWidget {
  final BulkParseResult parsed;
  final bool            isSubmitting;
  final int             doneCount;
  final VoidCallback    onSubmit;

  const _ResultSection({
    required this.parsed,
    required this.isSubmitting,
    required this.doneCount,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final valid   = parsed.validRows;
    final invalid = parsed.invalidRows;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('확인 결과',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              _Chip(
                label: '등록 가능 ${valid.length}건',
                color: Colors.green.shade700,
              ),
              if (invalid.isNotEmpty) ...[
                const SizedBox(width: 8),
                _Chip(
                  label: '확인 필요 ${invalid.length}건',
                  color: Colors.red.shade700,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          if (invalid.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '아래 행은 등록되지 않습니다. 엑셀에서 고친 뒤 다시 올려 주세요.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...invalid.take(20).map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${r.rowNumber}행 — ${r.errors.join(' / ')}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.red.shade800),
                        ),
                      )),
                  if (invalid.length > 20)
                    Text('… 외 ${invalid.length - 20}건',
                        style: TextStyle(
                            fontSize: 13, color: Colors.red.shade800)),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (valid.isNotEmpty) ...[
            _ValidTable(rows: valid),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('차감 예정 포인트',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(
                      '${_comma(parsed.totalBudget)}P',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 18),
                  ),
                  child: isSubmitting
                      ? Text('등록 중… ($doneCount/${valid.length})')
                      : Text('광고 ${valid.length}건 등록'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '포인트는 운영자 승인 시점에 차감됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}

class _ValidTable extends StatelessWidget {
  final List<BulkCampaignRow> rows;

  const _ValidTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 52,
        columns: const [
          DataColumn(label: Text('행')),
          DataColumn(label: Text('상품명')),
          DataColumn(label: Text('키워드')),
          DataColumn(label: Text('일일 유입')),
          DataColumn(label: Text('기간')),
          DataColumn(label: Text('차감 포인트')),
        ],
        rows: rows.map((r) {
          return DataRow(cells: [
            DataCell(Text('${r.rowNumber}')),
            DataCell(SizedBox(
              width: 240,
              child: Text(r.productName, overflow: TextOverflow.ellipsis),
            )),
            DataCell(Text(r.keyword)),
            DataCell(Text('${_comma(r.dailyTarget)}명')),
            DataCell(Text('${_fmtDate(r.startDate!)} ~ '
                '${_fmtDate(r.endDate!)} (${r.durationDays}일)')),
            DataCell(Text('${_comma(r.budget)}P')),
          ]);
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 보조 위젯
// ─────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String body;
  final Widget action;

  const _StepCard({
    required this.step,
    required this.title,
    required this.body,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.indigo.shade600,
              shape: BoxShape.circle,
            ),
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(body,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Colors.grey.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          action,
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      '일일 유입은 100명 단위로 입력합니다.',
      '광고 시작일은 내일 이후로만 지정할 수 있습니다. '
          '등록 당일에는 상품 순위·사진 정보가 없어 앱 사용자가 상품을 찾기 어렵습니다.',
      '광고 기간은 최소 7일입니다.',
      '차감 포인트 = 일일 유입 × 기간(일) × ${kPointPerVisitor}P',
      '대량 등록에서는 키워드 추천을 제공하지 않습니다. '
          '엑셀에 입력한 메인 키워드로 등록됩니다.',
      '등록 후 운영자가 상품 페이지를 확인하고 승인하면 앱에 노출됩니다. '
          '포인트는 승인 시점에 차감됩니다.',
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('작성 시 확인해 주세요',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: Colors.grey.shade600)),
                    Expanded(
                      child: Text(t,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: Colors.grey.shade700)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 14, color: Colors.red.shade900)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.'
    '${d.day.toString().padLeft(2, '0')}';

String _comma(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
