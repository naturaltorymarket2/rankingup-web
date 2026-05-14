import 'package:flutter/material.dart';
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
  final _urlCtrl     = TextEditingController();
  final _seedCtrl    = TextEditingController(); // 대표 키워드 (시드)
  bool _isFetchingKeywords = false;
  List<KeywordRankResult> _selectedKeywords = [];

  // ── Step 2 ────────────────────────────────────────────────────
  final _tags       = <String>[];          // 입력된 태그 목록
  final _newTagCtrl = TextEditingController(); // 태그 추가 입력 필드
  int _answerIndex  = -1;                  // 정답 태그 인덱스 (0-based, -1=미선택)
  int          _dailyTarget = 100;
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

  List<String> get _validTags => List.unmodifiable(_tags);

  /// 선택된 키워드 수 × 기간 × 일일목표 × 50P
  int get _totalCost =>
      _dailyTarget * _durationDays * 50 * _selectedKeywords.length;

  /// URL + 시드 키워드 입력 + 키워드 1개 이상 선택
  bool get _step1Valid =>
      _urlCtrl.text.trim().isNotEmpty &&
      _seedCtrl.text.trim().isNotEmpty &&
      _selectedKeywords.isNotEmpty;

  bool get _step2Valid =>
      _tags.length >= 2 &&
      _answerIndex >= 0 &&
      _dateRange != null &&
      _durationDays >= 7;

  // ── 생명주기 ──────────────────────────────────────────────────

  @override
  void dispose() {
    _urlCtrl.dispose();
    _seedCtrl.dispose();
    _newTagCtrl.dispose();
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
  // Step 1 — 상품 URL + 키워드 자동완성
  // ─────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final canFetch = _urlCtrl.text.trim().isNotEmpty &&
        _seedCtrl.text.trim().isNotEmpty &&
        !_isFetchingKeywords;

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
                // URL 변경 시 기존 선택 키워드 초기화
                onChanged: (_) => setState(() => _selectedKeywords = []),
                decoration: const InputDecoration(
                  hintText: 'https://smartstore.naver.com/...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('대표 키워드', style: _kLabel),
              const SizedBox(height: 4),
              Text(
                '상품을 대표하는 키워드를 입력하세요. 이를 기반으로 연관 키워드를 자동 생성합니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _seedCtrl,
                onChanged: (_) => setState(() => _selectedKeywords = []),
                decoration: const InputDecoration(
                  hintText: '예: 무선 블루투스 이어폰',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
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
            ],
          ),
        ),

        // ── 선택된 키워드 목록 ────────────────────────────────
        if (_selectedKeywords.isNotEmpty) ...[
          const SizedBox(height: 16),
          _WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '선택된 키워드 (${_selectedKeywords.length}개)',
                  style: _kLabel,
                ),
                const SizedBox(height: 12),
                ..._selectedKeywords.map(_buildKeywordChip),
              ],
            ),
          ),
        ],

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
        // ── 태그 ──────────────────────────────────────────────
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('정답 태그', style: _kLabel),
              const SizedBox(height: 4),
              Text(
                '상품 페이지에 있는 네이버 태그를 입력하세요. (최소 2개, 최대 10개)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                '★ 라디오 버튼으로 정답 태그 1개를 선택해주세요. '
                '유저에게 몇 번째 태그인지 안내됩니다.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 12),

              // 태그 추가 입력 행
              if (_tags.length < 10)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagCtrl,
                        decoration: const InputDecoration(
                          hintText: '태그를 입력하고 추가 버튼을 누르세요',
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
              if (_tags.length < 2)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '태그를 2개 이상 입력해주세요.',
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
                      style: TextStyle(fontSize: 12, color: Colors.grey),
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
                onChanged: (v) => setState(() => _dailyTarget = v!),
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
                  '${_selectedKeywords.length}개 키워드 × $_durationDays일 × $_dailyTarget명 × 50P',
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
                          '${_fmtNum(_dailyTarget * _durationDays * 50)}P',
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
                      '${_fmtNum(_totalCost)}P',
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
              _SummaryRow(label: '태그', value: _validTags.join(', ')),
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

  /// 태그 추가 (최대 10개, 중복 불가)
  void _addTag() {
    final tag = _newTagCtrl.text.trim();
    if (tag.isEmpty) return;
    if (_tags.length >= 10) {
      _showSnack('태그는 최대 10개까지 추가할 수 있습니다.');
      return;
    }
    if (_tags.contains(tag)) {
      _showSnack('이미 추가된 태그입니다.');
      return;
    }
    setState(() {
      _tags.add(tag);
      _newTagCtrl.clear();
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

  /// 태그 행 위젯 (라디오 버튼 + 태그 텍스트 + 삭제 버튼)
  Widget _buildTagRow(int index) {
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
              '${index + 1}. ${_tags[index]}',
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
          answerIndex: _answerIndex + 1, // 0-based → 1-based
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
      return '태그를 2개 이상 입력해주세요.';
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
