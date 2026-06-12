import 'dart:async';

import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/outlook_settings_test_harness.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets(
    'empty last-sync breakdowns render safe diagnostics copy',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: _lastSyncWithoutBreakdownPreferences(),
      );

      expect(find.text('\u65e5\u5386\u672c\u7ea7\u6458\u8981'), findsOneWidget);
      expect(
        find.text(
          '\u672c\u6b21\u6ca1\u6709\u8bb0\u5f55\u5230 Outlook \u65e5\u5386\u672c\u660e\u7ec6\u3002',
        ),
        findsOneWidget,
      );
      expect(find.text('\u4efb\u52a1\u955c\u50cf\u7ea7\u6458\u8981'),
          findsOneWidget);
      expect(
        find.text(
          '\u672c\u6b21\u672a\u53d1\u751f\u4efb\u52a1\u955c\u50cf\u5199\u56de\u53d8\u66f4\u3002',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'diagnostics section shows provider loading states without fake data',
    (tester) async {
      final diagnosticsCompleter = Completer<OutlookTaskMirrorDiagnostics>();
      final conflictsCompleter = Completer<List<OutlookFieldConflictSummary>>();

      await pumpLocalOutlookSettings(
        tester,
        extraOverrides: <Override>[
          outlookTaskMirrorDiagnosticsProvider.overrideWith(
            (ref) => diagnosticsCompleter.future,
          ),
          outlookFieldConflictSummariesProvider.overrideWith(
            (ref) => conflictsCompleter.future,
          ),
        ],
      );

      await _expandSection(tester, '\u8bca\u65ad\u4e0e\u51b2\u7a81');

      expect(
        find.text(
          '\u6b63\u5728\u68c0\u67e5\u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009...',
        ),
        findsOneWidget,
      );
      expect(
        find.text('\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'wide layout opens calendar books in a dialog instead of navigation',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(),
        seedData: true,
        size: const Size(920, 900),
      );

      await _expandSection(tester, '\u540c\u6b65\u5bf9\u8c61');
      await _tapText(
        tester,
        '\u7ba1\u7406\u65e5\u5386\u672c\u4e0e\u4efb\u52a1\u672c',
      );

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(CalendarBooksPage), findsOneWidget);
      expect(find.text(outlookExternalCalendarName), findsWidgets);

      await tester.pageBack();
      await pumpOutlookSettingFrames(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'binding an unbound task list without OAuth config reports failure safely',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        seedData: true,
      );
      final before = await harness.countTaskListBindings();

      await _expandSection(tester, '\u540c\u6b65\u5bf9\u8c61');
      await _tapTileAction(
        tester,
        outlookUnboundTaskListName,
        '\u7ed1\u5b9a\u955c\u50cf',
      );

      expect(
        find.textContaining(
          '\u8bf7\u5148\u5728 Outlook \u540c\u6b65\u8bbe\u7f6e\u4e2d\u4fdd\u5b58 OAuth \u914d\u7f6e',
        ),
        findsOneWidget,
      );
      expect(await harness.countTaskListBindings(), before);
    },
  );

  testWidgets(
    'conflict actions confirm but stop at missing OAuth config',
    (tester) async {
      final preferences = outlookAuthPreferences(
        syncMode: OutlookSyncMode.bidirectional,
        grantedMode: OutlookSyncMode.bidirectional,
        scope: 'Calendars.Read Calendars.ReadWrite offline_access',
      )..remove('outlook_client_id');
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: preferences,
        seedData: true,
      );
      final before = await harness.countTaskMirrorBindings();

      await _expandSection(tester, '\u8bca\u65ad\u4e0e\u51b2\u7a81');
      await _tapTextContaining(
          tester, '\u6279\u91cf\u91cd\u5efa\u5df2\u5220\u9664\u955c\u50cf');
      expect(find.text('\u6279\u91cf\u91cd\u5efa\u8fdc\u7aef\u955c\u50cf'),
          findsWidgets);
      await _tapDialogButton(tester, '\u786e\u8ba4');

      expect(
        find.textContaining('\u8bf7\u5148\u914d\u7f6e OAuth \u51ed\u636e'),
        findsOneWidget,
      );
      expect(await harness.countTaskMirrorBindings(), before);

      await _tapText(tester, '\u89e3\u9664\u955c\u50cf\u7ed1\u5b9a');
      expect(find.text('\u89e3\u9664\u955c\u50cf\u7ed1\u5b9a'), findsWidgets);
      await _tapDialogButton(tester, '\u786e\u8ba4');

      expect(
        find.textContaining('\u8bf7\u5148\u914d\u7f6e OAuth \u51ed\u636e'),
        findsOneWidget,
      );
      expect(await harness.countTaskMirrorBindings(), before);
    },
  );

  testWidgets(
    'task-list binding provider errors are visible in sync objects',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        seedData: true,
        extraOverrides: <Override>[
          outlookTaskListBindingsProvider.overrideWith(
            (ref) => throw StateError('gap2-bindings-down'),
          ),
        ],
      );

      await _expandSection(tester, '\u540c\u6b65\u5bf9\u8c61');

      expect(
        find.textContaining('gap2-bindings-down'),
        findsOneWidget,
      );
      expect(find.text(outlookMirrorTaskListName), findsNothing);
    },
  );
}

Map<String, Object> _lastSyncWithoutBreakdownPreferences() {
  final attemptedAt = DateTime.utc(2026, 6, 8, 12, 30);
  return <String, Object>{
    ...outlookAuthPreferences(
      syncMode: OutlookSyncMode.bidirectional,
      grantedMode: OutlookSyncMode.bidirectional,
      scope: 'Calendars.Read Calendars.ReadWrite offline_access',
    ),
    'outlook_last_sync': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_status': 'success',
    'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
    'outlook_last_sync_report_calendar_books': 0,
    'outlook_last_sync_report_downloaded': 0,
    'outlook_last_sync_report_mirrored_created': 0,
    'outlook_last_sync_report_mirrored_updated': 0,
    'outlook_last_sync_report_mirrored_deleted': 0,
    'outlook_last_sync_report_mirrored_conflicted': 0,
    'outlook_last_sync_report_calendar_details': '[]',
    'outlook_last_sync_report_task_mirror_details': '[]',
  };
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

Future<void> _tapTextContaining(WidgetTester tester, String text) async {
  final finder = find.textContaining(text).first;
  final button = find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is TextButton ||
          widget is ElevatedButton ||
          widget is FilledButton ||
          widget is OutlinedButton,
    ),
  );
  final target = button.evaluate().isNotEmpty ? button.first : finder;
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
