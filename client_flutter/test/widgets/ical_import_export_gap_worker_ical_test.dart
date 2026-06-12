import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/ical_import_export_harness.dart';

void main() {
  testWidgets('iCal import reads path files and reports malformed bytes', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Path imports',
      isDefault: true,
    );
    await pumpIcalFrames(tester);

    final pathFile = harness.tempFile('path-import.ics')
      ..writeAsStringSync(
        _ics([
          _vevent(
            uid: 'path-uid',
            summary: 'Read from path',
            start: '20260610T090000',
            end: '20260610T100000',
          ),
        ]),
      );
    harness.filePicker.queuePickPath(pathFile);

    await _tapIcalButtonWithRealAsync(tester, '选择文件');
    await pumpIcalFrames(tester);

    final events = await harness.eventsInCalendar(calendarId);
    expect(events.map((event) => event.summary), contains('Read from path'));
    expect(harness.filePicker.pickRequests.last.withData, isTrue);
    expect(find.textContaining('成功导入 1 条日程'), findsOneWidget);

    harness.filePicker.queuePickText(
      name: 'latin1.ics',
      content: _ics([
        _vevent(
          uid: 'latin-1',
          summary: 'Fallback import',
          start: '20260611T090000',
          end: '20260611T100000',
        ),
      ]),
      malformedUtf8: true,
    );

    await _tapIcalButtonWithRealAsync(tester, '选择文件');
    await pumpIcalFrames(tester);

    final afterFallback = await harness.eventsInCalendar(calendarId);
    expect(
      afterFallback.map((event) => event.summary),
      contains('Fallback import'),
    );
  });

  testWidgets('empty iCal export and save failures leave status messages', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final emptyCalendarId = await harness.createCalendar(
      name: 'Empty/Bad Save',
      isDefault: true,
    );
    await pumpIcalFrames(tester);

    await _tapIcalButtonWithRealAsync(tester, '导出当前日历本');
    await pumpIcalFrames(tester);

    expect(find.text('「Empty/Bad Save」中没有可导出的日程'), findsOneWidget);
    expect(harness.filePicker.saveRequests, isEmpty);

    await harness.createEvent(
      calendarId: emptyCalendarId,
      uid: 'export-fail',
      summary: 'Cannot save this',
    );
    await pumpIcalFrames(tester);

    final missingParent = harness.tempFile('missing-parent/out.ics');
    harness.filePicker.queueSavePath(missingParent.path);
    await _tapIcalButtonWithRealAsync(tester, '导出当前日历本');
    await pumpIcalFrames(tester);

    expect(find.textContaining('导出失败：'), findsOneWidget);
    expect(find.textContaining('missing-parent'), findsOneWidget);
  });

  testWidgets('structured archive export handles empty and write failures', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Structured Empty', isDefault: true);
    await harness.createTaskList(name: 'Inbox', emoji: 'I');
    await pumpIcalFrames(tester);

    await _tapSelectorTextButton(tester, '选择日历本', '清空');
    await _tapSelectorTextButton(tester, '选择任务本', '清空');
    await pumpIcalFrames(tester);
    expect(find.text('请至少选择一个日历本或任务本。'), findsOneWidget);

    await _tapSelectorTextButton(tester, '选择日历本', '全选');
    await _tapSelectorTextButton(tester, '选择任务本', '全选');
    await pumpIcalFrames(tester);

    harness.filePicker
        .queueSavePath(harness.tempFile('should-not-write.json').path);
    await _tapIcalButtonWithRealAsync(tester, '导出结构化归档');
    await pumpIcalFrames(tester);

    expect(find.textContaining('已导出结构化归档到'), findsOneWidget);
    await pumpIcalFrames(tester);
    final missingParent = harness.tempFile('missing-parent/archive.json');
    harness.filePicker.queueSavePath(missingParent.path);

    await _tapIcalButtonWithRealAsync(tester, '导出结构化归档');
    await pumpIcalFrames(tester);

    expect(find.textContaining('导出结构化归档失败：'), findsOneWidget);
    expect(find.textContaining('missing-parent'), findsOneWidget);
  });

  testWidgets('structured import reads path content and reports parse errors', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await pumpIcalFrames(tester);

    final archive = harness.tempFile('path.flowplanv2.json')
      ..writeAsStringSync(_archiveJson());
    harness.filePicker.queuePickPath(archive);

    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogButtonWithRealAsync(tester, '查看导入预览');
    await pumpUntilIcalFound(tester, find.text('确认结构化导入预览'));
    await _tapDialogButtonWithRealAsync(tester, '生成备份并导入');
    await pumpUntilIcalFound(tester, find.textContaining('结构化归档导入完成'));

    expect(
      find.textContaining('日程新增 1 条、更新 0 条、跳过 0 条、移除 0 条'),
      findsOneWidget,
    );
    expect(harness.filePicker.pickRequests.last.allowedExtensions, ['json']);

    harness.filePicker.queuePickText(
      name: 'broken.flowplanv2.json',
      content: '{"schema":',
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpIcalFrames(tester);

    expect(find.textContaining('导入结构化归档失败：'), findsOneWidget);
  });
}

Future<void> _tapSelectorTextButton(
  WidgetTester tester,
  String selectorTitle,
  String buttonLabel,
) async {
  final selector = find.ancestor(
    of: find.text(selectorTitle),
    matching: find.byType(Column),
  );
  expect(selector, findsWidgets);
  final button = find.descendant(
    of: selector.first,
    matching: find.widgetWithText(TextButton, buttonLabel),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _tapDialogButtonWithRealAsync(
  WidgetTester tester,
  String label,
) async {
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  final buttonLabel = find.descendant(
    of: dialog,
    matching: find.text(label),
  );
  expect(buttonLabel, findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(buttonLabel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
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

String _ics(List<String> events) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    ...events.map((event) => event.trim()),
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

String _vevent({
  required String uid,
  required String summary,
  required String start,
  required String end,
}) {
  return '''
BEGIN:VEVENT
UID:$uid
SUMMARY:$summary
DTSTART:$start
DTEND:$end
STATUS:CONFIRMED
END:VEVENT
''';
}

String _archiveJson() {
  return const JsonEncoder.withIndent('  ').convert({
    'schema': 'flowplanv2.container_archive.v1',
    'version': 1,
    'exported_at': '2026-06-08T09:00:00.000Z',
    'calendars': [
      {
        'name': 'Path Archive',
        'color_hex': '#6B5EE4',
        'description': null,
        'is_visible': true,
        'is_default': true,
        'default_is_block': false,
        'events': [
          {
            'uid': 'archive-event-path',
            'dtstamp': '2026-06-08T09:00:00.000Z',
            'summary': 'Path archive event',
            'description': null,
            'location': null,
            'dtstart': '2026-06-09T09:00:00.000Z',
            'dtend': '2026-06-09T10:00:00.000Z',
            'rrule': null,
            'status': 'CONFIRMED',
            'transp': 'OPAQUE',
            'source': 'local',
            'color_hex': '#6B5EE4',
            'is_block': false,
          },
        ],
      },
    ],
    'task_lists': [],
  });
}
