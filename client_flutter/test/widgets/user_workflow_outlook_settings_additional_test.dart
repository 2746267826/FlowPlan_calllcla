import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/outlook_settings_test_harness.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets(
    'diagnostics export skips blank paths and writes selected reports',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
          includeLastSuccess: true,
        ),
        seedData: true,
      );

      await _expandSection(tester, '诊断与冲突');

      harness.filePicker.queueSavePath('   ');
      await _tapText(tester, '导出 Outlook 同步诊断报告');

      expect(harness.filePicker.saveRequests, hasLength(1));
      expect(
        harness.filePicker.saveRequests.single.allowedExtensions,
        <String>['md', 'txt'],
      );
      expect(harness.diagnosticsWrites, isEmpty);
      expect(
        find.textContaining('已取消导出 Outlook 同步诊断报告'),
        findsOneWidget,
      );

      const exportPath = 'C:/fake/additional-outlook-diagnostics.md';
      harness.filePicker.queueSavePath(exportPath);
      await _tapText(tester, '导出 Outlook 同步诊断报告');

      await _waitForTextContaining(tester, '已导出 Outlook 同步诊断报告');
      expect(harness.filePicker.saveRequests, hasLength(2));
      expect(harness.diagnosticsWrites, hasLength(1));
      expect(harness.diagnosticsWrites.single.outputPath, exportPath);
      expect(
        harness.diagnosticsWrites.single.report,
        contains(outlookMirrorTaskListName),
      );
    },
  );

  testWidgets(
    'diagnostics export surfaces fake writer errors',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
          includeLastSuccess: true,
        ),
        seedData: true,
        diagnosticsWriteError: StateError('additional-writer-failed'),
      );

      harness.filePicker.queueSavePath('C:/fake/additional-failing.md');
      await _expandSection(tester, '诊断与冲突');
      await _tapText(tester, '导出 Outlook 同步诊断报告');

      await _waitForTextContaining(tester, '导出 Outlook 同步诊断报告失败');
      expect(find.textContaining('additional-writer-failed'), findsOneWidget);
      expect(harness.diagnosticsWrites, isEmpty);
    },
  );

  testWidgets(
    'hidden seeded calendar can be shown and reset cancellation preserves data',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
        hideExternalCalendar: true,
      );

      await _expandSection(tester, '同步对象');
      expect(await harness.countVisibleOutlookCalendars(), 1);
      expect(find.textContaining('已隐藏'), findsWidgets);

      await _tapTileAction(tester, outlookExternalCalendarName, '显示');
      expect(
        await harness.isCalendarVisible(harness.externalCalendarId),
        isTrue,
      );
      expect(find.textContaining('已在 FlowPlanV2 中显示'), findsOneWidget);

      await _tapText(tester, '完全重置已同步的 Outlook 日历本');
      expect(find.text('完全重置 Outlook 日历本'), findsOneWidget);
      await _tapDialogButton(tester, '取消');

      expect(find.text('完全重置 Outlook 日历本'), findsNothing);
      expect(await harness.countOutlookCalendars(), 2);
      expect(await harness.countOutlookEvents(), 2);
    },
  );
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  final button = _buttonWithText(text);
  final target = button?.first ?? finder;
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

Future<void> _tapTileAction(
  WidgetTester tester,
  String tileTitle,
  String actionLabel,
) async {
  final title = find.text(tileTitle).last;
  await _bringIntoView(tester, title);
  final titleCenter = tester.getCenter(title);
  final candidates = find.widgetWithText(TextButton, actionLabel).evaluate();
  expect(candidates, isNotEmpty);

  Element? closest;
  var closestDistance = double.infinity;
  for (final candidate in candidates) {
    final center = tester.getCenter(find.byWidget(candidate.widget));
    final distance = (center.dy - titleCenter.dy).abs();
    if (distance < closestDistance) {
      closest = candidate;
      closestDistance = distance;
    }
  }

  final action = find.byWidget(closest!.widget);
  await _bringIntoView(tester, action);
  await tester.tap(action);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _tapDialogButton(WidgetTester tester, String text) async {
  final textButton = find.widgetWithText(TextButton, text);
  final filledButton = find.widgetWithText(FilledButton, text);
  if (textButton.evaluate().isNotEmpty) {
    await tester.tap(textButton.last);
  } else {
    await tester.tap(filledButton.last);
  }
  await pumpOutlookSettingFrames(tester);
}

Future<void> _waitForTextContaining(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (find.textContaining(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.textContaining(text), findsOneWidget);
}

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}
