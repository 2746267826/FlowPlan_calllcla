import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/outlook_settings_test_harness.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets('diagnostics export cancellation keeps report unwritten',
      (tester) async {
    final harness = await pumpLocalOutlookSettings(
      tester,
      preferences: outlookAuthPreferences(),
      seedData: true,
    );
    harness.filePicker.queueSavePath(null);

    await _expandSection(tester, '\u8bca\u65ad\u4e0e\u51b2\u7a81');
    await _tapText(
      tester,
      '\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a',
    );

    expect(harness.filePicker.saveRequests, hasLength(1));
    expect(harness.diagnosticsWrites, isEmpty);
    expect(
      find.textContaining(
        '\u5df2\u53d6\u6d88\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a',
      ),
      findsOneWidget,
    );
  });

  testWidgets('diagnostics export writer failures surface in status',
      (tester) async {
    final harness = await pumpLocalOutlookSettings(
      tester,
      preferences: outlookAuthPreferences(),
      seedData: true,
      diagnosticsWriteError: StateError('worker-02-disk-full'),
    );
    harness.filePicker.queueSavePath('C:\\temp\\outlook-worker-02.md');

    await _expandSection(tester, '\u8bca\u65ad\u4e0e\u51b2\u7a81');
    await _tapText(
      tester,
      '\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a',
    );

    expect(harness.filePicker.saveRequests, hasLength(1));
    expect(harness.diagnosticsWrites, isEmpty);
    expect(find.textContaining('worker-02-disk-full'), findsOneWidget);
    expect(
      find.textContaining(
        '\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a\u5931\u8d25',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mirror cleanup action first switches to bidirectional mode',
      (tester) async {
    await pumpLocalOutlookSettings(
      tester,
      preferences: outlookAuthPreferences(
        syncMode: OutlookSyncMode.readOnly,
        grantedMode: OutlookSyncMode.readOnly,
      ),
      seedData: true,
    );

    await _expandSection(tester, '\u540c\u6b65\u5bf9\u8c61');
    await _tapText(tester, '\u5207\u6362\u4e3a\u53cc\u5411\u540c\u6b65');

    expect(
      find.textContaining('\u8bf7\u91cd\u65b0\u8ba4\u8bc1\u4e00\u6b21'),
      findsOneWidget,
    );
    expect(
      find.text('\u91cd\u65b0\u8fdb\u884c\u8bfb\u5199\u6388\u6743'),
      findsOneWidget,
    );
  });
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final button = _buttonWithText(text);
  final target = button?.first ?? find.text(text).first;
  await _bringIntoView(tester, target);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(target);
  await pumpOutlookSettingFrames(tester);
}

Finder? _buttonWithText(String text) {
  for (final finder in <Finder>[
    find.widgetWithText(TextButton, text),
    find.widgetWithText(ElevatedButton, text),
    find.widgetWithText(FilledButton, text),
    find.widgetWithText(OutlinedButton, text),
  ]) {
    if (finder.evaluate().isNotEmpty) {
      return finder;
    }
  }
  return null;
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}
