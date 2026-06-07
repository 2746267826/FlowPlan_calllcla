import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('report draft upsert replaces the same period draft', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = ReportRepository(db);
    final start = fixtureNow();
    final end = start.add(const Duration(days: 1));

    final first = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: 'Daily report',
      summaryMarkdown: 'Initial',
      metrics: const <String, Object?>{'tasks': 1},
      sourceSnapshot: const <String, Object?>{'source': 'test'},
    );
    final second = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: 'Daily report revised',
      summaryMarkdown: 'Revised',
      metrics: const <String, Object?>{'tasks': 2},
      sourceSnapshot: const <String, Object?>{'source': 'test'},
    );

    expect(second.id, first.id);
    expect(second.title, 'Daily report revised');
    expect(await repository.listRecentReports(), hasLength(1));
  });
}
