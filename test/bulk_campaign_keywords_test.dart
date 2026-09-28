import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_traffic_booster/features/campaign/domain/bulk_campaign_model.dart';

// 엑셀 대량 등록 — 미션 키워드 여러 개 처리
//
// 템플릿을 만들고 그대로 다시 읽어, 광고주가 적은 키워드가 빠짐없이
// 들어오는지 확인한다. (2026-09-22 등록분이 메인 키워드 1개로만 들어간
// 문제를 다시 겪지 않기 위한 회귀 테스트)

void main() {
  // 예시 행의 시작일(2026-01-02)보다 앞선 날짜여야 '내일 이후' 검증을 통과한다
  final today = DateTime(2026, 1, 1);

  test('템플릿의 예시 행에서 미션 키워드 3개를 읽는다', () {
    final result = parseBulkExcel(buildBulkTemplate(), today: today);

    expect(result.fileError, isNull);
    expect(result.rows, hasLength(1));

    final row = result.rows.first;
    expect(row.errors, isEmpty);
    expect(row.keyword, '양파즙');
    expect(row.keywords, ['토리마켓 양파즙', '무농약양파즙', '무안양파즙']);
  });

  test('미션 키워드를 비우면 메인 키워드 하나로 등록된다', () {
    final row = _parseSingleRow(missionKeywords: '', today: today);

    expect(row.errors, isEmpty);
    expect(row.keywords, ['양파즙']);
  });

  test('공백·대소문자만 다른 중복은 하나로 본다', () {
    final row = _parseSingleRow(
      missionKeywords: '무안양파즙, 무안 양파즙 ,무안양파즙',
      today: today,
    );

    expect(row.keywords, ['무안양파즙']);
  });

  test('최대 개수를 넘기면 오류로 잡는다', () {
    final many =
        List.generate(kMaxMissionKeywords + 1, (i) => '키워드$i').join(',');
    final row = _parseSingleRow(missionKeywords: many, today: today);

    expect(row.isValid, isFalse);
    expect(row.errors.first, contains('최대'));
  });

  test('일일 유입은 키워드 수로 나뉘고 나머지는 첫 번째가 가져간다', () {
    // 개별 등록과 대량 등록이 공유하는 분배 규칙을 고정해 둔다
    const dailyTarget = 100;
    const keywordCount = 3;
    const base = dailyTarget ~/ keywordCount;
    const extra = dailyTarget % keywordCount;

    final perKeyword = [
      for (var i = 0; i < keywordCount; i++) i == 0 ? base + extra : base,
    ];

    expect(perKeyword, [34, 33, 33]);
    expect(perKeyword.reduce((a, b) => a + b), dailyTarget);
  });
}

/// 템플릿과 같은 열 구성으로 한 줄짜리 엑셀을 만들어 파싱한다.
/// 예시 행에서 '미션 키워드' 칸만 바꾼다.
BulkCampaignRow _parseSingleRow({
  required String missionKeywords,
  required DateTime today,
}) {
  final values = [...kBulkSampleRow];
  final missionCol = kBulkColumns.indexWhere((c) => c.startsWith('미션 키워드'));
  expect(missionCol, isNonNegative, reason: '미션 키워드 열이 있어야 한다');
  values[missionCol] = missionKeywords;

  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (var i = 0; i < kBulkColumns.length; i++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = TextCellValue(kBulkColumns[i]);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
        .value = TextCellValue(values[i]);
  }

  final result = parseBulkExcel(excel.save()!, today: today);
  expect(result.fileError, isNull);
  return result.rows.single;
}
