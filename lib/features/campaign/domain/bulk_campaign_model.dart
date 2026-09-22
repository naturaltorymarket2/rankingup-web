import 'package:excel/excel.dart';

// ─────────────────────────────────────────────────────────────────
// 엑셀 대량 등록 — 템플릿 정의 / 파싱 / 검증
// ─────────────────────────────────────────────────────────────────
//
// 광고주가 상품을 여러 개 운영하는 경우 한 건씩 등록하기 번거롭다.
// 등록 화면에서 받는 값을 그대로 엑셀 열로 옮겨 한 번에 올린다.
//
// 대량 등록에서는 키워드 추천(SerpApi)을 하지 않는다.
// 1건당 5회를 쓰는데 50건이면 250회라 월 한도(1,000회)가 금방 소진된다.
// 대량으로 올리는 광고주는 이미 자기 키워드를 알고 있고, 추천이 필요하면
// 개별 등록 화면을 쓰면 된다.

/// 템플릿 열 순서 — 다운로드·업로드가 같은 정의를 쓴다
const List<String> kBulkColumns = [
  '상품 URL',
  '상품명',
  '업체명',
  '메인 키워드',
  '일일 유입(명)',
  '시작일(YYYY-MM-DD)',
  '종료일(YYYY-MM-DD)',
];

/// 템플릿에 채워 넣는 예시 행 (사용하는 방법을 보여주기 위한 것)
const List<String> kBulkSampleRow = [
  'https://smartstore.naver.com/mystore/products/1234567890',
  '무농약 양파즙 100팩',
  '내추럴토리마켓',
  '양파즙',
  '100',
  '2026-01-02',
  '2026-01-08',
];

/// 광고 단가 (1명당 차감 포인트)
const int kPointPerVisitor = 50;

/// 최소 광고 기간 (일)
const int kMinDurationDays = 7;

/// 엑셀 한 줄 = 광고 1건
class BulkCampaignRow {
  final int     rowNumber;    // 엑셀 행 번호 (오류 안내용, 1-based)
  final String  productUrl;
  final String  productName;
  final String  brandName;
  final String  keyword;
  final int     dailyTarget;
  final DateTime? startDate;
  final DateTime? endDate;

  /// 검증에서 걸린 문제들. 비어 있으면 등록 가능하다.
  final List<String> errors;

  const BulkCampaignRow({
    required this.rowNumber,
    required this.productUrl,
    required this.productName,
    required this.brandName,
    required this.keyword,
    required this.dailyTarget,
    required this.startDate,
    required this.endDate,
    required this.errors,
  });

  bool get isValid => errors.isEmpty;

  /// 기간(일) — 시작일과 종료일을 모두 포함한다
  int get durationDays {
    if (startDate == null || endDate == null) return 0;
    return endDate!.difference(startDate!).inDays + 1;
  }

  /// 이 행의 차감 예정 포인트
  int get budget => dailyTarget * durationDays * kPointPerVisitor;
}

/// 파싱 결과
class BulkParseResult {
  final List<BulkCampaignRow> rows;

  /// 파일 자체의 문제 (열 구성이 다름, 시트가 비어 있음 등)
  final String? fileError;

  const BulkParseResult({required this.rows, this.fileError});

  List<BulkCampaignRow> get validRows   => rows.where((r) => r.isValid).toList();
  List<BulkCampaignRow> get invalidRows => rows.where((r) => !r.isValid).toList();

  /// 등록 가능한 행들의 합계 예산
  int get totalBudget =>
      validRows.fold(0, (sum, r) => sum + r.budget);
}

// ─────────────────────────────────────────────────────────────────
// 템플릿 생성
// ─────────────────────────────────────────────────────────────────

/// 빈 템플릿 엑셀 파일을 만든다 (헤더 + 예시 1행)
List<int> buildBulkTemplate() {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet()!;
  final sheet = excel[sheetName];

  final headerStyle = CellStyle(
    bold:            true,
    backgroundColorHex: ExcelColor.fromHexString('#E8EAF6'),
  );

  for (var i = 0; i < kBulkColumns.length; i++) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
    );
    cell.value = TextCellValue(kBulkColumns[i]);
    cell.cellStyle = headerStyle;
    sheet.setColumnWidth(i, i == 0 ? 46 : 18);
  }

  for (var i = 0; i < kBulkSampleRow.length; i++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
        .value = TextCellValue(kBulkSampleRow[i]);
  }

  // 예시 행 아래에 안내를 적어 둔다 (파싱 시 무시된다 — URL이 없는 행)
  const notes = [
    '※ 2행의 예시는 지우고 작성해 주세요.',
    '※ 일일 유입은 100명 단위로 입력합니다.',
    '※ 광고 시작일은 내일 이후로만 지정할 수 있습니다.',
    '※ 광고 기간은 최소 7일입니다.',
    '※ 차감 포인트 = 일일 유입 × 기간(일) × 50P',
  ];
  for (var i = 0; i < notes.length; i++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3 + i))
        .value = TextCellValue(notes[i]);
  }

  return excel.save() ?? <int>[];
}

// ─────────────────────────────────────────────────────────────────
// 파싱 + 검증
// ─────────────────────────────────────────────────────────────────

/// 업로드된 엑셀을 읽어 행별로 검증한다.
///
/// [today] 는 '내일부터' 규칙을 판단하는 기준일(KST 날짜)이다.
BulkParseResult parseBulkExcel(List<int> bytes, {required DateTime today}) {
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    return const BulkParseResult(
      rows: [],
      fileError: '엑셀 파일을 읽을 수 없습니다. 템플릿을 다시 내려받아 작성해 주세요.',
    );
  }

  if (excel.tables.isEmpty) {
    return const BulkParseResult(rows: [], fileError: '시트가 비어 있습니다.');
  }

  final sheet = excel.tables[excel.tables.keys.first]!;
  if (sheet.maxRows < 2) {
    return const BulkParseResult(
      rows: [],
      fileError: '등록할 내용이 없습니다. 2행부터 광고 정보를 입력해 주세요.',
    );
  }

  final rows = <BulkCampaignRow>[];
  final seenUrlKeyword = <String>{};

  // 0행은 헤더이므로 1행부터 읽는다
  for (var r = 1; r < sheet.maxRows; r++) {
    final cells = sheet.row(r);
    String at(int i) {
      if (i >= cells.length) return '';
      final v = cells[i]?.value;
      if (v == null) return '';
      return v.toString().trim();
    }

    final productUrl = at(0);

    // URL이 없는 줄은 빈 줄이거나 안내 문구다 — 조용히 건너뛴다
    if (productUrl.isEmpty) continue;

    final productName = at(1);
    final brandName   = at(2);
    final keyword     = at(3);
    final dailyRaw    = at(4);
    final startRaw    = at(5);
    final endRaw      = at(6);

    final errors = <String>[];

    if (!_looksLikeProductUrl(productUrl)) {
      errors.add('상품 URL 형식이 올바르지 않습니다');
    }
    if (productName.isEmpty) errors.add('상품명을 입력해 주세요');
    if (brandName.isEmpty)   errors.add('업체명을 입력해 주세요');
    if (keyword.isEmpty)     errors.add('메인 키워드를 입력해 주세요');

    final daily = int.tryParse(dailyRaw.replaceAll(RegExp(r'[^0-9]'), ''));
    if (daily == null || daily <= 0) {
      errors.add('일일 유입은 숫자로 입력해 주세요');
    } else if (daily % 100 != 0) {
      errors.add('일일 유입은 100명 단위로 입력해 주세요');
    }

    final start = _parseDate(startRaw);
    final end   = _parseDate(endRaw);

    if (start == null) {
      errors.add('시작일을 YYYY-MM-DD 형식으로 입력해 주세요');
    } else if (!start.isAfter(today)) {
      // 등록 당일에는 순위·썸네일 크롤링 정보가 없어 유저가 상품을 찾을
      // 단서가 없다. 그래서 시작일은 내일부터만 허용한다.
      errors.add('광고 시작일은 내일 이후로 지정해 주세요');
    }

    if (end == null) {
      errors.add('종료일을 YYYY-MM-DD 형식으로 입력해 주세요');
    } else if (start != null) {
      final days = end.difference(start).inDays + 1;
      if (days < kMinDurationDays) {
        errors.add('광고 기간은 최소 $kMinDurationDays일입니다');
      }
    }

    // 같은 파일 안에서 같은 (상품, 키워드)가 중복되면 예산이 두 번 나간다
    final dupKey = '$productUrl|$keyword';
    if (!seenUrlKeyword.add(dupKey)) {
      errors.add('같은 상품·키워드가 파일 안에 중복되어 있습니다');
    }

    rows.add(BulkCampaignRow(
      rowNumber:   r + 1,          // 엑셀 화면의 행 번호와 맞춘다
      productUrl:  productUrl,
      productName: productName,
      brandName:   brandName,
      keyword:     keyword,
      dailyTarget: daily ?? 0,
      startDate:   start,
      endDate:     end,
      errors:      errors,
    ));
  }

  if (rows.isEmpty) {
    return const BulkParseResult(
      rows: [],
      fileError: '등록할 내용이 없습니다. 2행부터 광고 정보를 입력해 주세요.',
    );
  }

  return BulkParseResult(rows: rows);
}

bool _looksLikeProductUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.host.contains('naver.com')) {
    return false;
  }
  // 스마트스토어/브랜드스토어 상품 URL 은 마지막에 상품 번호가 붙는다
  return RegExp(r'/\d{6,}').hasMatch(uri.path);
}

/// 'YYYY-MM-DD' / 'YYYY.MM.DD' / 'YYYY/MM/DD' 를 받는다.
/// 엑셀이 날짜 셀로 저장한 경우도 문자열로 들어오므로 앞 10자만 본다.
DateTime? _parseDate(String raw) {
  if (raw.isEmpty) return null;

  final normalized = raw
      .replaceAll('.', '-')
      .replaceAll('/', '-')
      .trim();

  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
  if (m == null) return null;

  final year  = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day   = int.parse(m.group(3)!);

  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  final date = DateTime(year, month, day);
  // 2월 31일 같은 값은 DateTime 이 다음 달로 넘겨 버린다 — 걸러낸다
  if (date.month != month || date.day != day) return null;

  return date;
}
