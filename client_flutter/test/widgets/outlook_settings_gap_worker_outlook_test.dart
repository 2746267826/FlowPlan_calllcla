import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
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
    'long last-sync reports summarize overflow calendar and mirror details',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: _longLastSyncPreferences(),
        seedData: true,
      );

      expect(find.text('日历本级摘要'), findsOneWidget);
      expect(find.text('Overflow Calendar 08'), findsOneWidget);
      expect(find.text('Overflow Calendar 01'), findsNothing);
      expect(find.textContaining('其余 1 个有更新的 Outlook 日历'), findsOneWidget);

      expect(find.text('任务镜像级摘要'), findsOneWidget);
      expect(find.text('Overflow Tasks 08'), findsOneWidget);
      expect(find.text('Overflow Tasks 02'), findsNothing);
      expect(find.textContaining('其余 2 个发生变更的任务本'), findsOneWidget);
      expect(find.textContaining('即便在双向同步下'), findsOneWidget);
    },
  );

  testWidgets(
    'provider failures render diagnostics and object error banners',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
        extraOverrides: <Override>[
          outlookTaskMirrorDiagnosticsProvider.overrideWith(
            (ref) => throw StateError('mirror-diagnostics-down'),
          ),
          outlookFieldConflictSummariesProvider.overrideWith(
            (ref) => throw StateError('field-conflicts-down'),
          ),
          allEventCalendarsProvider.overrideWith(
            (ref) => Stream<List<EventCalendar>>.error(
              StateError('calendar-stream-down'),
            ),
          ),
          allTaskListsProvider.overrideWith(
            (ref) => Stream<List<TaskList>>.error(
              StateError('task-list-stream-down'),
            ),
          ),
          outlookTaskListBindingsProvider.overrideWith(
            (ref) => throw StateError('binding-provider-down'),
          ),
        ],
      );

      await _expandSection(tester, '诊断与冲突');
      expect(find.textContaining('field-conflicts-down'), findsOneWidget);

      await _expandSection(tester, '同步对象');
      expect(find.textContaining('calendar-stream-down'), findsOneWidget);
      expect(find.textContaining('task-list-stream-down'), findsOneWidget);
      expect(find.textContaining('mirror-diagnostics-down'), findsOneWidget);
    },
  );

  testWidgets(
    'unauthenticated mode switch and auth buttons show guarded user feedback',
    (tester) async {
      await pumpLocalOutlookSettings(tester);

      await _chooseSyncMode(tester, 'paused');
      expect(find.textContaining('同步模式已切换为“暂停同步”'), findsOneWidget);

      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNull,
      );

      await _chooseSyncMode(tester, 'bidirectional');
      expect(find.textContaining('连接 Outlook 后'), findsOneWidget);

      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNull,
      );

      await _tapText(tester, '连接 Outlook 日历');
      expect(find.textContaining('请先保存 OAuth 配置'), findsOneWidget);
    },
  );

  testWidgets(
    'disconnect and task-list unbind cancellation preserve local mappings',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
      );

      await _tapText(tester, '断开 Outlook 连接');
      expect(find.textContaining('已断开 Outlook 连接'), findsOneWidget);
      expect(find.textContaining('尚未连接 Outlook'), findsOneWidget);

      await _chooseSyncMode(tester, 'bidirectional');
      await _expandSection(tester, '同步对象');
      final before = await harness.countTaskListBindings();
      await _tapTileAction(tester, outlookMovedTaskListName, '解除绑定');
      expect(find.text('解除 Outlook 绑定'), findsOneWidget);
      await _tapDialogButton(tester, '取消');

      expect(find.text('解除 Outlook 绑定'), findsNothing);
      expect(await harness.countTaskListBindings(), before);
    },
  );

  testWidgets(
    'narrow layout opens calendar books as a pushed page',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(),
        seedData: true,
        size: const Size(520, 900),
      );

      await _expandSection(tester, '同步对象');
      await _tapText(tester, '管理日历本与任务本');

      expect(find.byType(CalendarBooksPage), findsOneWidget);
      expect(find.text(outlookExternalCalendarName), findsWidgets);

      await tester.pageBack();
      await pumpOutlookSettingFrames(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

Map<String, Object> _longLastSyncPreferences() {
  final attemptedAt = DateTime.utc(2026, 6, 8, 12, 15);
  final calendars = <Map<String, Object?>>[
    for (var i = 1; i <= 8; i++)
      <String, Object?>{
        'remote_calendar_id': 'overflow-calendar-$i',
        'local_calendar_id': i,
        'calendar_name': 'Overflow Calendar ${i.toString().padLeft(2, '0')}',
        'color_hex': '#0078D4',
        'downloaded': i == 1 ? 0 : i,
      },
  ];
  final taskMirrors = <Map<String, Object?>>[
    for (var i = 1; i <= 8; i++)
      <String, Object?>{
        'local_task_list_id': i,
        'task_list_name': 'Overflow Tasks ${i.toString().padLeft(2, '0')}',
        'remote_calendar_id': 'overflow-tasks-$i',
        'remote_calendar_name': 'Overflow Mirror $i',
        'created': i,
        'updated': 0,
        'deleted': 0,
        'conflicted': 0,
      },
  ];

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
    'outlook_last_sync_report_calendar_books': 8,
    'outlook_last_sync_report_downloaded': 35,
    'outlook_last_sync_report_mirrored_created': 36,
    'outlook_last_sync_report_mirrored_updated': 0,
    'outlook_last_sync_report_mirrored_deleted': 0,
    'outlook_last_sync_report_mirrored_conflicted': 0,
    'outlook_last_sync_report_calendar_details': jsonEncode(calendars),
    'outlook_last_sync_report_task_mirror_details': jsonEncode(taskMirrors),
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

Finder _elevatedButton(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(ElevatedButton),
  );
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

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _chooseSyncMode(WidgetTester tester, String valueFragment) async {
  final dropdown = find.byType(DropdownButtonFormField<OutlookSyncMode>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await pumpOutlookSettingFrames(tester, frames: 4);
  final menuItem = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownMenuItem<OutlookSyncMode> &&
        widget.value.toString().contains(valueFragment),
  );
  expect(menuItem, findsWidgets);
  final itemText = find
      .descendant(
        of: menuItem.last,
        matching: find.byType(Text),
      )
      .hitTestable();
  expect(itemText, findsWidgets);
  await tester.tap(itemText.last);
  await pumpOutlookSettingFrames(tester);
}
