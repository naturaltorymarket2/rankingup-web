import 'package:uuid/uuid.dart';

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
  final _urlCtrl         = TextEditingController();
  final _productNameCtrl = TextEditingController(); // 상품명
  final _brandNameCtrl   = TextEditingController(); // 브랜드명
  final _seedCtrl        = TextEditingController(); // 순위 추적 키워드
  bool _seedTouched        = false;           // 포커스 해제 or [다음] 시도 후 에러 표시
  bool _step1Touched       = false;           // [다음 단계] 시도 후 필수값 에러 표시
  bool _isFetchingKeywords = false;
  List<KeywordRankResult> _selectedKeywords = [];

  // ── Step 2 ────────────────────────────────────────────────────
  // 태그는 광고주가 입력하지 않는다 (Phase 22).
  // 어드민이 승인 단계에서 상품 페이지의 실제 #태그를 직접 등록한다.
  final _dailyTargetCtrl = TextEditingController(text: '100'); // 일일 유입 수량
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

  /// 그룹 일일목표 × 기간 × 50P (키워드 수 무관, 그룹 1회 과금)
  int get _totalCost => _dailyTarget * _durationDays * 50;

  /// URL + 상품명 + 브랜드명 + 시드 키워드 입력 + 키워드 1개 이상 선택
  bool get _step1Valid =>
      _urlCtrl.text.trim().isNotEmpty &&
      _productNameCtrl.text.trim().isNotEmpty &&
      _brandNameCtrl.text.trim().isNotEmpty &&
      _seedCtrl.text.trim().isNotEmpty &&
      _selectedKeywords.isNotEmpty;

  /// Step 1에서 비어 있는 필수 항목 목록 (없으면 빈 리스트)
  List<String> get _step1Missing => [
        if (_urlCtrl.text.trim().isEmpty)         '상품 URL',
        if (_productNameCtrl.text.trim().isEmpty) '상품명',
        if (_brandNameCtrl.text.trim().isEmpty)   '브랜드명',
        if (_seedCtrl.text.trim().isEmpty)        '순위 추적 키워드',
        if (_selectedKeywords.isEmpty)            '미션 키워드(1개 이상)',
      ];

  bool get _step2Valid =>
      _isDailyTargetValid &&
      _dateRange != null &&
      _durationDays >= 7;

  // ── 생명주기 ──────────────────────────────────────────────────

  @override
  void dispose() {
    _urlCtrl.dispose();
    _productNameCtrl.dispose();
    _brandNameCtrl.dispose();
    _seedCtrl.dispose();
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
    // [다음 단계]를 눌렀는데 비어 있던 항목은 빨간 에러로 표시
    String? requiredError(String value) =>
        (_step1Touched && value.trim().isEmpty) ? '필수 입력 항목입니다' : null;

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
                decoration: InputDecoration(
                  labelText: '상품 URL *',
                  hintText: 'https://smartstore.naver.com/...',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  errorText: requiredError(_urlCtrl.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _productNameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '상품명 *',
                  hintText: '예) 남성 레깅스 헬스 기능성 스판',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  errorText: requiredError(_productNameCtrl.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _brandNameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '브랜드명 *',
                  hintText: '예) 나이키',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  errorText: requiredError(_brandNameCtrl.text),
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
              ] else if (_step1Touched)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '미션 키워드를 1개 이상 선택해주세요.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
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
        // ── 승인 절차 안내 카드 ──────────────────────────────
        //    태그 입력은 Phase 22부터 운영자(어드민)가 담당한다.
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
                  Icon(Icons.verified_outlined,
                      color: Colors.amber.shade800, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '광고 승인 절차 안내',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '① 광고를 등록하면 운영자 검수(승인 대기) 상태로 접수됩니다.
'
                '② 운영자가 상품 페이지의 #태그를 직접 확인해 등록합니다.
'
                '③ 승인이 완료되면 광고가 시작되고, 그때 포인트가 차감됩니다.
'
                '④ 승인 상태는 대시보드에서 확인할 수 있습니다.',
                style: TextStyle(fontSize: 13, height: 1.7),
              ),
              const Divider(height: 20),
              Text(
                '태그는 광고주가 입력하지 않습니다. 상품 페이지의 태그를 임의로 '
                '변경하면 미션 정답이 맞지 않을 수 있으니 광고 기간 중에는 태그를 '
                '수정하지 말아 주세요.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[700], height: 1.5),
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
                  '${_isDailyTargetValid ? '$_dailyTarget명' : '?명'} × $_durationDays일 × 50P'
                  ' (그룹 1회 과금)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (_selectedKeywords.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedKeywords.length}개 서브키워드 균등 분배'
                    ' (각 ${_dailyTarget ~/ _selectedKeywords.length}명'
                    '${_dailyTarget % _selectedKeywords.length > 0 ? ', 첫 번째 +${_dailyTarget % _selectedKeywords.length}명' : ''})',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedKeywords.map((k) => k.keyword).join(' / '),
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _isDailyTargetValid
                            ? '${_fmtNum(_totalCost)}P'
                            : '— P',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
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
              if (_productNameCtrl.text.trim().isNotEmpty)
                _SummaryRow(label: '상품명', value: _productNameCtrl.text.trim()),
              if (_brandNameCtrl.text.trim().isNotEmpty)
                _SummaryRow(label: '브랜드명', value: _brandNameCtrl.text.trim()),
              _SummaryRow(label: '일일 유입', value: '$_dailyTarget명'),
              if (_dateRange != null)
                _SummaryRow(
                  label: '광고 기간',
                  value:
                      '${_fmtDate(_dateRange!.start)} ~ ${_fmtDate(_dateRange!.end)} ($_durationDays일)',
                ),
              _SummaryRow(
                label: '정답 태그',
                value: '운영자가 상품 페이지에서 직접 등록합니다.',
                maxLines: 2,
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
                  value: '${_selectedKeywords.length}개 (그룹 1회 과금)'),
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
                  '$_dailyTarget명 × $_durationDays일 × 50P',
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
                    // 어떤 항목이 비었는지 즉시 알려준다
                    final missing = _step1Missing;
                    setState(() {
                      _seedTouched  = true;
                      _step1Touched = true;
                    });
                    _showSnack('${missing.join(', ')}을(를) 입력해주세요.');
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
                    : const Text('광고 등록 (운영자 승인 후 1회 차감)'),
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      helpText: '광고 기간 선택 (최소 7일)',
      saveText: '선택 완료',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
              onPrimary: Colors.white,
              onSurface: Color(0xFF212121),
            ),
            // 우측 상단 [선택 완료] 버튼이 눈에 띄지 않는다는 피드백 반영:
            // 파란 배경 + 큰 글씨의 채워진 버튼 형태로 강조한다.
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF1976D2),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                minimumSize: const Size(110, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;

    final days = picked.end.difference(picked.start).inDays + 1;
    if (days < 7) {
      _showSnack('최소 7일 이상 선택해주세요.');
      return;
    }
    setState(() => _dateRange = picked);
  }

  /// 서브키워드 수만큼 register_campaign RPC 순차 호출 (그룹 1회 과금)
  ///
  /// - 동일 group_id로 순차 호출 → RPC가 첫 번째에만 포인트 차감
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

    final keywordCount = _selectedKeywords.length;
    if (keywordCount == 0) {
      setState(() => _isSubmitting = false);
      return;
    }

    final userId           = currentUser.id;
    final repo             = ref.read(campaignRepositoryProvider);
    final groupId          = const Uuid().v4();
    final groupDailyTarget = _dailyTarget;
    final base             = _dailyTarget ~/ keywordCount;
    final remainder        = _dailyTarget % keywordCount;

    int successCount = 0;

    for (int i = 0; i < keywordCount; i++) {
      final kw = _selectedKeywords[i];
      // 첫 번째 서브키워드에 나머지 추가 (균등 분배 후 잉여분)
      final perKeywordTarget = i == 0 ? base + remainder : base;
      try {
        await repo.registerCampaign(
          userId:           userId,
          productUrl:       _urlCtrl.text.trim(),
          keyword:          kw.keyword,
          dailyTarget:      perKeywordTarget,
          groupDailyTarget: groupDailyTarget,
          groupId:          groupId,
          startDate:        _dateRange!.start,
          endDate:          _dateRange!.end,
          seedKeyword:      _seedCtrl.text.trim().isEmpty ? null : _seedCtrl.text.trim(),
          productName:      _productNameCtrl.text.trim().isEmpty ? null : _productNameCtrl.text.trim(),
          brandName:        _brandNameCtrl.text.trim().isEmpty ? null : _brandNameCtrl.text.trim(),
        );
        successCount++;
      } catch (e) {
        if (!mounted) return;
        _showSnack(
          '${i + 1}번째 키워드(${kw.keyword}) 등록 실패: ${_mapRpcError(e.toString())}',
        );
        break;
      }
    }

    if (!mounted) return;

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$successCount개 키워드 광고 그룹이 등록되었습니다. '
            '운영자 승인 후 광고가 시작되며, 그때 포인트가 차감됩니다.',
          ),
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
