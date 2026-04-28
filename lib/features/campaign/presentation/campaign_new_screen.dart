import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/rank_api_client.dart';
import 'campaign_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 광고 등록 웹 화면  (/web/campaign/new)  —  Step 1 ~ 3
// ─────────────────────────────────────────────────────────────────

class CampaignNewScreen extends ConsumerStatefulWidget {
  const CampaignNewScreen({super.key});

  @override
  ConsumerState<CampaignNewScreen> createState() =>
      _CampaignNewScreenState();
}

class _CampaignNewScreenState extends ConsumerState<CampaignNewScreen> {
  // ── 스텝 ──────────────────────────────────────────────────────
  int _step = 1;

  // ── Step 1 ────────────────────────────────────────────────────
  final _urlCtrl     = TextEditingController();
  final _keywordCtrl = TextEditingController();
  bool _isCheckingRank = false;
  int?  _fetchedRank;
  bool  _rankNotFound  = false;

  // ── Step 2 ────────────────────────────────────────────────────
  final List<TextEditingController> _tagCtls = [TextEditingController()];
  int          _dailyTarget = 100;
  DateTimeRange? _dateRange;

  // ── Step 3 ────────────────────────────────────────────────────
  bool _isSubmitting = false;

  // ── 스타일 상수 ──────────────────────────────────────────────
  static const _kBlue   = Color(0xFF1E3A8A);
  static const _kGreen  = Color(0xFF2E7D32);
  static const _kLabel  = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111827),
  );

  // ── 파생 값 ──────────────────────────────────────────────────

  int get _durationDays => _dateRange != null
      ? _dateRange!.end.difference(_dateRange!.start).inDays + 1
      : 0;

  List<String> get _validTags => _tagCtls
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  int get _totalCost => _dailyTarget * _durationDays * 50;

  bool get _step1Valid =>
      _urlCtrl.text.trim().isNotEmpty &&
      _keywordCtrl.text.trim().isNotEmpty; // URL+키워드 입력만 되면 진행 허용 (순위 조회 선택사항)

  bool get _step2Valid =>
      _validTags.isNotEmpty &&
      _dateRange != null &&
      _durationDays >= 7;

  // ── 생명주기 ──────────────────────────────────────────────────

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keywordCtrl.dispose();
    for (final c in _tagCtls) { c.dispose(); }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Step 3에서 필요한 잔액을 미리 로드 (step1/2에선 무시)
    final balanceAsync = ref.watch(walletBalanceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _step > 1
              ? () => setState(() => _step--)
              : () => context.pop(),
        ),
        title: const Text(
          '광고 등록',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _kBlue,
            fontSize: 18,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              _buildStepIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: switch (_step) {
                    1 => _buildStep1(),
                    2 => _buildStep2(),
                    _ => _buildStep3(balanceAsync),
                  },
                ),
              ),
              _buildBottomButton(balanceAsync),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 스텝 인디케이터
  // ─────────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      child: Row(
        children: [
          _StepCircle(number: 1, isActive: _step >= 1),
          Expanded(
            child: Container(
              height: 2,
              color: _step > 1 ? _kBlue : Colors.grey[300],
            ),
          ),
          _StepCircle(number: 2, isActive: _step >= 2),
          Expanded(
            child: Container(
              height: 2,
              color: _step > 2 ? _kBlue : Colors.grey[300],
            ),
          ),
          _StepCircle(number: 3, isActive: _step >= 3),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Step 1 — 상품 URL + 키워드 + 순위 조회
  // ─────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('상품 URL', style: _kLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                onChanged: (_) => setState(() {
                  _fetchedRank   = null;
                  _rankNotFound  = false;
                }),
                decoration: const InputDecoration(
                  hintText:
                      'https://smartstore.naver.com/...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('타겟 키워드', style: _kLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _keywordCtrl,
                onChanged: (_) => setState(() {
                  _fetchedRank   = null;
                  _rankNotFound  = false;
                }),
                decoration: const InputDecoration(
                  hintText: '예: 무선이어폰',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed:
                    _isCheckingRank ? null : _checkRank,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: _isCheckingRank
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('순위 조회'),
              ),
            ],
          ),
        ),

        // ── 순위 결과 ─────────────────────────────────────────
        if (_fetchedRank != null || _rankNotFound) ...[
          const SizedBox(height: 16),
          _WebCard(
            child: _rankNotFound
                ? Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '검색 결과에서 상품을 찾을 수 없습니다.\n'
                          '순위 확인 없이 광고 등록을 진행할 수 있습니다.',
                          style: TextStyle(
                            color: Colors.orange,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  )
                : _fetchedRank! <= 15
                    ? Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: _kGreen, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            '현재 순위: $_fetchedRank위 — 등록 가능',
                            style: const TextStyle(
                              color: _kGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.orange, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '현재 순위 $_fetchedRank위 — 등록은 가능하나\n'
                              '15위 이내 상품의 효과가 더 높습니다.',
                              style: const TextStyle(
                                color: Colors.orange,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Step 2 — 태그 / 일일 수량 / 기간
  // ─────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 태그 ──────────────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('정답 태그', style: _kLabel),
                  ),
                  if (_tagCtls.length < 3)
                    TextButton.icon(
                      onPressed: _addTag,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('태그 추가'),
                      style: TextButton.styleFrom(
                          foregroundColor: _kBlue),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '미션 유저가 상품에 달아야 할 네이버 쇼핑 태그입니다. (최대 3개)',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              ...List.generate(
                _tagCtls.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagCtls[i],
                          decoration: InputDecoration(
                            hintText: '태그 ${i + 1}',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_tagCtls.length > 1) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                              size: 22),
                          onPressed: () => _removeTag(i),
                          tooltip: '태그 삭제',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 일일 유입 수량 ────────────────────────────────────
        _WebCard(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('일일 유입 수량', style: _kLabel),
                    SizedBox(height: 2),
                    Text(
                      '하루 목표 미션 수행 인원',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: _dailyTarget,
                underline: const SizedBox.shrink(),
                items: const [100, 200, 300, 400, 500]
                    .map((v) => DropdownMenuItem<int>(
                          value: v,
                          child: Text('$v명'),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _dailyTarget = v!),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 광고 기간 ─────────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('광고 기간', style: _kLabel),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _dateRange != null
                      ? '${_fmtDate(_dateRange!.start)}'
                          ' ~ ${_fmtDate(_dateRange!.end)}'
                          ' ($_durationDays일)'
                      : '기간 선택 (최소 7일)',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  foregroundColor: _dateRange != null
                      ? _kBlue
                      : Colors.grey[700],
                ),
              ),
              if (_dateRange != null && _durationDays < 7)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '최소 7일 이상 선택해주세요.',
                    style: TextStyle(
                        color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Step 3 — 결제 확인 및 등록
  // ─────────────────────────────────────────────────────────────

  Widget _buildStep3(AsyncValue<int> balanceAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 등록 정보 요약 ────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('등록 정보 요약', style: _kLabel),
              const SizedBox(height: 12),
              _SummaryRow(
                  label: '키워드',
                  value: _keywordCtrl.text),
              _SummaryRow(
                  label: '상품 URL',
                  value: _urlCtrl.text,
                  maxLines: 2),
              _SummaryRow(
                  label: '일일 유입',
                  value: '$_dailyTarget명'),
              if (_dateRange != null)
                _SummaryRow(
                  label: '광고 기간',
                  value:
                      '${_fmtDate(_dateRange!.start)} ~ ${_fmtDate(_dateRange!.end)} ($_durationDays일)',
                ),
              _SummaryRow(
                  label: '태그',
                  value: _validTags.join(', ')),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 예상 금액 ─────────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('결제 정보', style: _kLabel),
              const SizedBox(height: 12),
              _SummaryRow(
                  label: '일일 유입',
                  value: '$_dailyTarget명'),
              _SummaryRow(
                  label: '광고 기간',
                  value: '$_durationDays일'),
              _SummaryRow(
                  label: '단가',
                  value: '50P / 1명'),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '총 예상 금액',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${_fmtNum(_totalCost)}P',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _kBlue,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$_dailyTarget명 × $_durationDays일 × 50P',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 잔액 확인 ─────────────────────────────────────────
        balanceAsync.when(
          loading: () => const Center(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          )),
          error: (e, _) => _WebCard(
            child: Text(
              '잔액 조회 오류: $e',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          data: (balance) {
            final isEnough = balance >= _totalCost;
            return _WebCard(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                          child: Text('현재 잔여 포인트')),
                      Text(
                        '${_fmtNum(balance)}P',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isEnough
                              ? Colors.black87
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  if (!isEnough) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '포인트가 부족합니다. 충전 후 다시 시도해주세요.',
                      style: TextStyle(
                          color: Colors.red, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/web/charge'),
                      icon: const Icon(
                          Icons.add_circle_outline,
                          size: 16),
                      label: const Text('포인트 충전하기'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _kBlue),
                    ),
                  ],
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 하단 버튼
  // ─────────────────────────────────────────────────────────────

  Widget _buildBottomButton(AsyncValue<int> balanceAsync) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
            top: BorderSide(color: Colors.grey[200]!)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: SafeArea(
        top: false,
        child: switch (_step) {
          1 => ElevatedButton(
                onPressed: _step1Valid
                    ? () => setState(() => _step = 2)
                    : null,
                style: _primaryStyle,
                child: const Text('다음 단계 (2/3)'),
              ),
          2 => ElevatedButton(
                onPressed: _step2Valid
                    ? () => setState(() => _step = 3)
                    : null,
                style: _primaryStyle,
                child: const Text('다음 단계 (3/3)'),
              ),
          _ => ElevatedButton(
                onPressed: _canRegister(balanceAsync)
                    ? _submit
                    : null,
                style: _primaryStyle,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('포인트 차감 후 광고 등록'),
              ),
        },
      ),
    );
  }

  static final _primaryStyle = ElevatedButton.styleFrom(
    backgroundColor: _kBlue,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 48),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10)),
  );

  bool _canRegister(AsyncValue<int> balanceAsync) {
    if (_isSubmitting) return false;
    final balance = balanceAsync.valueOrNull;
    if (balance == null) return false;
    return balance >= _totalCost;
  }

  // ─────────────────────────────────────────────────────────────
  // 액션 메서드
  // ─────────────────────────────────────────────────────────────

  Future<void> _checkRank() async {
    final url     = _urlCtrl.text.trim();
    final keyword = _keywordCtrl.text.trim();
    if (url.isEmpty || keyword.isEmpty) {
      _showSnack('상품 URL과 키워드를 모두 입력해주세요.');
      return;
    }
    setState(() {
      _isCheckingRank = true;
      _fetchedRank    = null;
      _rankNotFound   = false;
    });
    try {
      final rank = await ref
          .read(campaignRepositoryProvider)
          .fetchProductRank(url, keyword);
      setState(() {
        if (rank == null) {
          _rankNotFound = true;
        } else {
          _fetchedRank = rank;
        }
      });
    } on RankTimeoutException {
      _showSnack('순위 조회 시간이 초과되었습니다.');
    } on RankNetworkException {
      _showSnack('네트워크 연결을 확인해주세요.');
    } on RankApiException {
      _showSnack('순위 조회에 실패했습니다.');
    } catch (e) {
      _showSnack('순위 조회 중 오류가 발생했습니다.');
    } finally {
      setState(() => _isCheckingRank = false);
    }
  }

  void _addTag() {
    setState(() => _tagCtls.add(TextEditingController()));
  }

  void _removeTag(int index) {
    setState(() {
      _tagCtls[index].dispose();
      _tagCtls.removeAt(index);
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      helpText: '광고 기간 선택 (최소 7일)',
      saveText: '확인',
    );
    if (picked == null) return;

    final days = picked.end.difference(picked.start).inDays + 1;
    if (days < 7) {
      _showSnack('최소 7일 이상 선택해주세요.');
      return;
    }
    setState(() => _dateRange = picked);
  }

  Future<void> _submit() async {
    // B-008: 중복 태그 검사
    final rawTags = _tagCtls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (rawTags.length != rawTags.toSet().length) {
      _showSnack('중복된 태그가 있습니다. 서로 다른 태그를 입력해주세요.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await ref.read(campaignRepositoryProvider).registerCampaign(
            userId:      userId,
            productUrl:  _urlCtrl.text.trim(),
            keyword:     _keywordCtrl.text.trim(),
            dailyTarget: _dailyTarget,
            startDate:   _dateRange!.start,
            endDate:     _dateRange!.end,
            tags:        _validTags,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('광고가 성공적으로 등록되었습니다.'),
          backgroundColor: _kGreen,
        ),
      );
      context.go('/web/dashboard');
    } catch (e) {
      if (!mounted) return;
      _showSnack(_mapRpcError(e.toString()));
      setState(() => _isSubmitting = false);
    }
  }

  String _mapRpcError(String err) {
    if (err.contains('INSUFFICIENT_BALANCE')) {
      return '포인트가 부족합니다. 충전 후 다시 시도해주세요.';
    }
    if (err.contains('TAGS_REQUIRED')) {
      return '태그를 1개 이상 입력해주세요.';
    }
    if (err.contains('DURATION_TOO_SHORT')) {
      return '광고 기간은 최소 7일 이상이어야 합니다.';
    }
    if (err.contains('INVALID_PARAMS')) {
      return '입력값을 확인해주세요.';
    }
    if (err.contains('UNAUTHORIZED')) {
      return '인증 오류가 발생했습니다. 다시 로그인해주세요.';
    }
    return '등록 중 오류가 발생했습니다. 다시 시도해주세요.';
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────
// 카드 컨테이너
// ─────────────────────────────────────────────────────────────────

class _WebCard extends StatelessWidget {
  final Widget child;
  const _WebCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
          padding: const EdgeInsets.all(20), child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 요약 행 (label: value)
// ─────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final int    maxLines;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 스텝 원형 인디케이터
// ─────────────────────────────────────────────────────────────────

class _StepCircle extends StatelessWidget {
  final int  number;
  final bool isActive;

  const _StepCircle({required this.number, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF1E3A8A)
            : Colors.grey[300],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey[500],
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
