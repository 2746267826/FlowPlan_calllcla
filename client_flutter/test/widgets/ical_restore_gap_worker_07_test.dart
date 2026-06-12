import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/ical_import_export_harness.dart';

void main() {
  testWidgets('database export treats blank save path as cancel without audit',
      (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Work', isDefault: true);
    await pumpIcalFrames(tester);

    harness.filePicker.queueSavePath('   ');
    await _tapIcalButtonWithRealAsync(
      tester,
      '\u5bfc\u51fa\u6570\u636e\u5e93',
    );
    await pumpIcalFrames(tester);

    expect(
      find.text('\u5df2\u53d6\u6d88\u5bfc\u51fa\u6570\u636e\u5e93'),
      findsOneWidget,
    );
    expect(
      harness.filePicker.saveRequests.last.allowedExtensions,
      ['db', 'sqlite', 'sqlite3'],
    );

    final logs = await DataOperationLogRepository(harness.db).listRecent();
    expect(logs.where((log) => log.action == 'export_database'), isEmpty);
  });
}

Future<void> _tapIcalButtonWithRealAsync(
  WidgetTester tester,
  String text,
) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.runAsync(() async {
    await tester.tap(finder.last);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}
