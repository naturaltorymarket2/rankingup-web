import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/supabase_client.dart';
import '../../../shared/utils/rank_api_client.dart';
import 'campaign_provider.dart';
import 'keyword_select_modal.dart';

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
  final _urlCtrl  = TextEditingController();
  final _seedCtrl = TextEditingController(); // 순위 추적 키워드
  bool _seedTouched        = false;           // 포커스 해제 or [다음] 시도 후 에러 표시
  bool _isFetchingKeywords = false;
  List<KeywordRankResult> _selectedKeywords = [];

  // ── Step 2 ────────────────────────────────────────────────────
  final _tags            = <Map<String, dynamic>>[]; // {'name': String, 'order': int}
  final _newTagCtrl      = TextEditingController();  // 태그 이름 입력 필드
  final _newOrderCtrl    = TextEditingController();  // 태그 순서 입력 필드
  final _dailyTargetCtrl = TextEditingController(text: '100'); // 일일 유입 수량
  int _answerIndex  = -1;                         // 정답 태그 인덱스 (0-based, -1=미선택)
  DateTimeRange? _dateRange;

  // ── Step 3 ────────────────────────────────────────────────────
  bool _isSubmitting = false;

  // ── 스타일 상수 ──────────────────────────────────────────────
  static const _kBlue  = Color(0xFF1E3A8A);
  static const _kGreen = Color(0xFF2E7D32);
  static const _kLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111827),
  );

  // ── 파생 값 ──────────────────────────────────────────────────

  int get _durationDays => _dateRange != null
      ? _dateRange!.end.difference(_dateRange!.start).inDays + 1
      : 0;

  List<String> get _validTags =>
      List.unmodifiable(_tags.map((t) => t['name'] as String).toList());

  List<int> get _validSortOrders =>
      List.unmodifiable(_tags.map((t) => t['order'] as int).toList());

  /// 컨트롤러에서 파싱한 일일 목표 수 (파싱 실패 시 0)
  int get _dailyTarget => int.tryParse(_dailyTargetCtrl.text.trim()) ?? 0;

  /// 일일 목표 유효성 메시지 (null = 정상)
  String? get _dailyTargetError {
    final text = _dailyTargetCtrl.text.trim();
    if (text.isEmpty) return '일일 유입 수량을 입력해주세요';
    final v = int.tryParse(text);
    if (v == null) return '숫자를 입력해주세요';
    if (v < 100) return '최소 100명 이상 입력하세요';
    if (v > 3000) return '최대 3,000명까지 가능합니다';
    if (v % 100 != 0) return '100 단위로 입력해주세요 (예: 100, 500, 1000)';
    return null;
  }

  bool get _isDailyTargetValid => _dailyTargetError == null;

  /// 선택된 키워드 수 × 기간 × 일일목표 × 50P
  int get _totalCost =>
      _dailyTarget * _durationDays * 50 * _selectedKeywords.length;

  /// URL + 시드 키워드 입력 + 키워드 1개 이상 선택
  bool get _step1Valid =>
      _urlCtrl.text.trim().isNotEmpty &&
      _seedCtrl.text.trim().isNotEmpty &&
      _selectedKeywords.isNotEmpty;

  bool get _step2Valid =>
      _tags.isNotEmpty &&
      _answerIndex >= 0 &&
      _answerIndex < _tags.length &&
      _isDailyTargetValid &&
      _dateRange != null &&
      _durationDays >= 7;

  // ── 생명주기 ──────────────────────────────────────────────────

  @override
  void dispose() {
    _urlCtrl.dispose();
    _seedCtrl.dispose();
    _newTagCtrl.dispose();
    _newOrderCtrl.dispose();
    _dailyTargetCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Step 3에서 필요한 잔액 미리 로드 (step1/2에선 무시)
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
  // Step 1 — 상품 정보 / 순위 추적 키워드 / 미션 키워드
  // ─────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final seedEmpty  = _seedCtrl.text.trim().isEmpty;
    final showSeedError = _seedTouched && seedEmpty;
    final canFetch = _urlCtrl.text.trim().isNotEmpty &&
        !seedEmpty &&
        !_isFetchingKeywords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 섹션 A: 상품 정보 ────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('상품 정보', style: _kLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                onChanged: (_) => setState(() => _selectedKeywords = []),
                decoration: const InputDecoration(
                  hintText: 'https://smartstore.naver.com/...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 섹션 B: 순위 추적 키워드 ─────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('순위 추적 키워드', style: _kLabel),
              const SizedBox(height: 4),
              Text(
                '실제 네이버 쇼핑에서 내 상품의 순위를 추적할 대표 키워드입니다.\n'
                '미션 키워드와 달리 광고 효과 측정용으로만 사용됩니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              // Focus 위젯으로 포커스 해제 시 에러 표시 활성화
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) setState(() => _seedTouched = true);
                },
                child: TextField(
                  controller: _seedCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '예) 양파즙',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    errorText: showSeedError ? '순위 추적 키워드를 입력해주세요' : null,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 섹션 C: 미션 키워드 ──────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('미션 키워드', style: _kLabel),
              const SizedBox(height: 4),
              Text(
                '앱 유저가 네이버에서 실제로 검색할 키워드입니다. 여러 개 설정 가능합니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: canFetch ? _fetchKeywords : null,
                icon: _isFetchingKeywords
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(
                  _isFetchingKeywords ? '키워드 조회 중...' : '키워드 자동완성',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              if (_selectedKeywords.isNotEmpty) ...[
                const SizedBox(height: 12),
                ..._selectedKeywords.map(_buildKeywordChip),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  /// 선택된 키워드 1개를 순위 뱃지 + X 버튼과 함께 표시
  Widget _buildKeywordChip(KeywordRankResult kw) {
    final rank = kw.rank;
    final Color badgeColor;
    if (rank == null) {
      badgeColor = Colors.grey;
    } else if (rank <= 15) {
      badgeColor = _kGreen;
    } else {
      badgeColor = Colors.orange;
    }
    final rankText = rank == null ? '순위권 밖' : '$rank위';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              rankText,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              kw.keyword,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          GestureDetector(
            onTap: () => setState(
              () => _selectedKeywords =
                  _selectedKeywords.where((k) => k != kw).toList(),
            ),
            child: const Icon(Icons.close, size: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Step 2 — 태그 / 일일 수량 / 기간 / 예산 미리보기
  // ─────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 태그 입력 방법 안내 카드 ──────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '태그 입력 방법',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '① 네이버 스마트스토어 상품 페이지에서 상품명 아래 #태그를 확인하세요.\n'
                '② 태그 이름과 상품 페이지에서의 순서(몇 번째인지)를 함께 입력하세요.\n'
                '③ 정답 태그를 라디오 버튼으로 1개 선택하세요.',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const Divider(height: 20),
              Text(
                '입력 예시  |  태그명: #티비거치대   순서: 3',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                "→ 앱 유저에게 '3번째 태그를 입력하세요'로 안내됩니다",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 태그 ──────────────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('정답 태그', style: _kLabel),
              const SizedBox(height: 4),
              Text(
                '태그 이름과 네이버 상품 페이지에서의 실제 순서(몇 번째인지)를 함께 입력하세요. (최소 1개, 최대 10개)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                '★ 라디오 버튼으로 정답 태그를 선택하면 앱 유저에게 해당 순서가 안내됩니다.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 12),

              // 태그 추가 입력 행 (태그 이름 + 순서 + [추가] 버튼)
              if (_tags.length < 10)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagCtrl,
                        decoration: const InputDecoration(
                          hintText: '예) #티비거치대',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _newOrderCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '예) 3',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addTag,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: const Text('추가'),
                    ),
                  ],
                ),

              // 태그 목록 (라디오 + 텍스트 + 삭제 버튼)
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...List.generate(_tags.length, _buildTagRow),
              ],

              // 안내 메시지
              if (_tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '태그를 1개 이상 입력해주세요.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                )
              else if (_answerIndex < 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '정답 태그를 선택해주세요.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 일일 유입 수량 ────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('일일 유입 수량', style: _kLabel),
              const SizedBox(height: 4),
              Text(
                '하루 목표 미션 수행 인원 (100단위 입력, 최대 3,000명)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dailyTargetCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '예) 500 (100단위 입력, 최대 3,000)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  suffixText: '명',
                  errorText: _dailyTargetCtrl.text.trim().isEmpty
                      ? null
                      : _dailyTargetError,
                ),
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
                  foregroundColor:
                      _dateRange != null ? _kBlue : Colors.grey[700],
                ),
              ),
              if (_dateRange != null && _durationDays < 7)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '최소 7일 이상 선택해주세요.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        // ── 예산 미리보기 ─────────────────────────────────────
        if (_dateRange != null && _durationDays >= 7) ...[
          const SizedBox(height: 16),
          _WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('예산 미리보기', style: _kLabel),
                const SizedBox(height: 8),
                Text(
                  '${_selectedKeywords.length}개 키워드 × $_durationDays일'
                  ' × ${_isDailyTargetValid ? '$_dailyTarget명' : '?명'} × 50P',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 10),
                ..._selectedKeywords.map(
                  (kw) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            kw.keyword,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          _isDailyTargetValid
                              ? '${_fmtNum(_dailyTarget * _durationDays * 50)}P'
                              : '— P',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '예상 총 예산',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _isDailyTargetValid ? '${_fmtNum(_totalCost)}P' : '— P',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _kBlue,
                      ),
                    ),
                  ],
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
                value: _selectedKeywords.map((k) => k.keyword).join(', '),
                maxLines: 4,
              ),
              _SummaryRow(
                label: '상품 URL',
                value: _urlCtrl.text,
                maxLines: 2,
              ),
              _SummaryRow(label: '일일 유입', value: '$_dailyTarget명'),
              if (_dateRange != null)
                _SummaryRow(
                  label: '광고 기간',
                  value:
                      '${_fmtDate(_dateRange!.start)} ~ ${_fmtDate(_dateRange!.end)} ($_durationDays일)',
                ),
              _SummaryRow(
                label: '태그',
                value: _tags.map((t) => '${t['order']}번째: ${t['name']}').join(' / '),
                maxLines: 4,
              ),
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
                  label: '키워드 수',
                  value: '${_selectedKeywords.length}개'),
              _SummaryRow(label: '일일 유입', value: '$_dailyTarget명'),
              _SummaryRow(label: '광고 기간', value: '$_durationDays일'),
              _SummaryRow(label: '단가', value: '50P / 1명'),
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
                  '$_dailyTarget명 × $_durationDays일 × 50P × ${_selectedKeywords.length}개 키워드',
                  textAlign: TextAlign.end,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('현재 잔여 포인트')),
                      Text(
                        '${_fmtNum(balance)}P',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color:
                              isEnough ? Colors.black87 : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  if (!isEnough) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '포인트가 부족합니다. 충전 후 다시 시도해주세요.',
                      style:
                          TextStyle(color: Colors.red, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/web/charge'),
                      icon: const Icon(Icons.add_circle_outline,
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
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: SafeArea(
        top: false,
        child: switch (_step) {
          1 => ElevatedButton(
                // 항상 탭 가능 — 유효하지 않으면 에러 표시 후 이동 차단
                onPressed: () {
                  if (_step1Valid) {
                    setState(() => _step = 2);
                  } else {
                    setState(() => _seedTouched = true);
                  }
                },
                style: _step1Valid ? _primaryStyle : _disabledStyle,
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
                onPressed: _canRegister(balanceAsync) ? _submit : null,
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
                    : Text('${_selectedKeywords.length}개 캠페인 포인트 차감 후 등록'),
              ),
        },
      ),
    );
  }

  static final _primaryStyle = ElevatedButton.styleFrom(
    backgroundColor: _kBlue,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  static final _disabledStyle = ElevatedButton.styleFrom(
    backgroundColor: Color(0xFFBDBDBD),
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  /// 키워드 자동완성 버튼 처리:
  ///   1. fetchKeywords API 호출
  ///   2. KeywordSelectModal 표시
  ///   3. ON된 키워드를 _selectedKeywords 에 저장
  Future<void> _fetchKeywords() async {
    final url  = _urlCtrl.text.trim();
    final seed = _seedCtrl.text.trim();
    if (url.isEmpty || seed.isEmpty) return;

    setState(() => _isFetchingKeywords = true);
    try {
      final keywords = await RankApiClient().fetchKeywords(url, seed);
      if (!mounted) return;

      if (keywords.isEmpty) {
        _showSnack('연관 키워드를 찾을 수 없습니다.');
        return;
      }

      final selected = await showKeywordSelectModal(
        context,
        keywords,
        preSelected: _selectedKeywords,
        productUrl: _urlCtrl.text.trim(),
      );
      if (!mounted) return;

      if (selected != null) {
        setState(() => _selectedKeywords = selected);
      }
    } on RankTimeoutException {
      _showSnack('키워드 조회 시간이 초과되었습니다.');
    } on RankNetworkException {
      _showSnack('네트워크 연결을 확인해주세요.');
    } on RankApiException {
      _showSnack('키워드 조회에 실패했습니다.');
    } catch (e) {
      _showSnack('키워드 조회 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isFetchingKeywords = false);
    }
  }

  /// 태그 추가 (최대 10개, 이름 중복 불가, 순서 중복 불가)
  void _addTag() {
    final name = _newTagCtrl.text.trim();
    final orderStr = _newOrderCtrl.text.trim();

    if (name.isEmpty) {
      _showSnack('태그 이름을 입력해주세요.');
      return;
    }
    if (orderStr.isEmpty) {
      _showSnack('태그 순서(몇 번째인지)를 입력해주세요.');
      return;
    }
    final order = int.tryParse(orderStr);
    if (order == null || order < 1) {
      _showSnack('순서는 1 이상의 숫자를 입력해주세요.');
      return;
    }
    if (_tags.length >= 10) {
      _showSnack('태그는 최대 10개까지 추가할 수 있습니다.');
      return;
    }
    if (_tags.any((t) => t['name'] == name)) {
      _showSnack('이미 추가된 태그입니다.');
      return;
    }
    if (_tags.any((t) => t['order'] == order)) {
      _showSnack('$order번째 순서에 태그가 이미 등록되어 있습니다.');
      return;
    }
    setState(() {
      _tags.add({'name': name, 'order': order});
      _newTagCtrl.clear();
      _newOrderCtrl.clear();
    });
  }

  /// 태그 삭제 — 정답 인덱스 자동 조정
  void _removeTag(int index) {
    setState(() {
      _tags.removeAt(index);
      if (_answerIndex == index) {
        _answerIndex = -1; // 정답 태그 삭제 시 초기화
      } else if (_answerIndex > index) {
        _answerIndex--; // 삭제된 항목 앞에 정답이 있으면 인덱스 조정
      }
    });
  }

  /// 태그 행 위젯 (라디오 버튼 + 순서/이름 + 삭제 버튼)
  Widget _buildTagRow(int index) {
    final tag = _tags[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Radio<int>(
            value: index,
            groupValue: _answerIndex,
            onChanged: (v) => setState(() => _answerIndex = v!),
            activeColor: _kBlue,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              '${tag['order']}번째 | ${tag['name']}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: () => _removeTag(index),
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
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

  /// 선택된 키워드 수만큼 register_campaign RPC 순차 호출
  ///
  /// - 전체 성공 → 대시보드 이동
  /// - 부분 성공 → 성공한 수 SnackBar + 대시보드 이동
  /// - 전부 실패 → 오류 SnackBar, 화면 유지
  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      _showSnack('로그인이 필요합니다. 다시 로그인해 주세요.');
      setState(() => _isSubmitting = false);
      return;
    }
    final userId = currentUser.id;
    final repo   = ref.read(campaignRepositoryProvider);
    int successCount = 0;

    for (int i = 0; i < _selectedKeywords.length; i++) {
      final kw = _selectedKeywords[i];
      try {
        await repo.registerCampaign(
          userId:      userId,
          productUrl:  _urlCtrl.text.trim(),
          keyword:     kw.keyword,
          dailyTarget: _dailyTarget,
          startDate:   _dateRange!.start,
          endDate:     _dateRange!.end,
          tags:        _validTags,
          sortOrders:  _validSortOrders,
          answerIndex: _tags[_answerIndex]['order'] as int, // 광고주 입력 실제 순서값
          seedKeyword: _seedCtrl.text.trim().isEmpty ? null : _seedCtrl.text.trim(),
        );
        successCount++;
      } catch (e) {
        if (!mounted) return;
        _showSnack(
          '${i + 1}번째 키워드(${kw.keyword}) 등록 실패: ${_mapRpcError(e.toString())}',
        );
        break; // 이후 키워드 등록 중단
      }
    }

    if (!mounted) return;

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount개 광고가 등록되었습니다.'),
          backgroundColor: _kGreen,
        ),
      );
      context.go('/web/dashboard');
    } else {
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
    if (err.contains('INVALID_ANSWER_INDEX')) {
      return '정답 태그를 선택해주세요.';
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
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
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
