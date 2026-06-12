import 'dart:convert';

import 'package:flowplanv2/features/ical/ical_import_export_page_body.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/ical_import_export_harness.dart';
import '../test_support/provider_harness.dart';

void main() {
  testWidgets('database folder action opens on Windows and reports path',
      (tester) async {
    final openedFolders = <String>[];
    final harness = await ICalImportExportHarness.pump(tester);
    await _repumpIcalWithFolderOverrides(
      tester,
      harness,
      isWindows: true,
      openDatabaseFolder: (folderPath) async => openedFolders.add(folderPath),
    );

    await _tapIcalButtonWithRealAsync(tester, '打开目录');
    await pumpIcalFrames(tester);

    expect(openedFolders, hasLength(1));
    expect(find.textContaining('已打开数据库目录：'), findsOneWidget);
    expect(find.textContaining(openedFolders.single), findsOneWidget);
  });

  testWidgets('database folder action starts explorer when no opener is set',
      (tester) async {
    final started = <String, List<String>>{};
    final harness = await ICalImportExportHarness.pump(tester);
    await _repumpIcalWithFolderOverrides(
      tester,
      harness,
      isWindows: true,
      startProcess: (executable, arguments) async {
        started[executable] = arguments;
      },
    );

    await _tapIcalButtonWithRealAsync(tester, '鎵撳紑鐩綍');
    await pumpIcalFrames(tester);

    expect(started.keys, ['explorer.exe']);
    expect(started['explorer.exe'], hasLength(1));
    expect(find.textContaining(started['explorer.exe']!.single), findsOneWidget);
  });

  testWidgets('database folder action reports path on non-Windows platforms',
      (tester) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await _repumpIcalWithFolderOverrides(
      tester,
      harness,
      isWindows: false,
    );

    await _tapIcalButtonWithRealAsync(tester, '显示路径');
    await pumpIcalFrames(tester);

    expect(find.textContaining('当前数据库目录：'), findsOneWidget);
  });

  testWidgets('replace iCal import clears old events and shows final summary',
      (tester) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Gap6 Replace',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'old-gap6',
      summary: 'Old gap6 event',
    );
    await pumpIcalFrames(tester);

    await _tapChoiceChip(tester, '清空后导入');
    harness.filePicker.queuePickText(
      name: 'replace-gap6.ics',
      content: _ics([
        _vevent(
          uid: 'new-gap6',
          summary: 'New gap6 event',
          start: '20260612T090000',
          end: '20260612T100000',
        ),
      ]),
    );

    await _tapIcalButtonWithRealAsync(tester, '选择文件');
    await pumpUntilIcalFound(tester, find.byType(AlertDialog));
    await _tapDialogButtonWithRealAsync(tester, '继续');
    await pumpIcalFrames(tester);

    final events = await harness.eventsInCalendar(calendarId);
    expect(events, hasLength(1));
    expect(events.single.uid, 'new-gap6');
    expect(
      find.textContaining('已先清空「Gap6 Replace」中的 1 条原有日程，再导入 1 条新日程。'),
      findsOneWidget,
    );
  });

  testWidgets('replace structured import preview cancellation keeps data',
      (tester) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'old-structured-gap6',
      summary: 'Old structured gap6',
    );
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickText(
      name: 'replace-structured.flowplanv2.json',
      content: _archiveJson(),
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogRadio(tester, '替换同名容器内容');
    await _tapDialogButtonWithRealAsync(tester, '查看导入预览');
    await pumpUntilIcalFound(tester, find.text('确认结构化导入预览'));

    expect(find.text('导入策略：替换同名容器内容'), findsOneWidget);
    expect(find.textContaining('替换导入会先移除'), findsOneWidget);

    await _tapDialogButtonWithRealAsync(tester, '取消');
    await pumpIcalFrames(tester);

    final events = await harness.eventsInCalendar(calendarId);
    expect(events.single.uid, 'old-structured-gap6');
    expect(find.text('已取消结构化归档导入。'), findsOneWidget);
  });
}

Future<void> _repumpIcalWithFolderOverrides(
  WidgetTester tester,
  ICalImportExportHarness harness, {
  required bool isWindows,
  Future<void> Function(String folderPath)? openDatabaseFolder,
  Future<void> Function(String executable, List<String> arguments)?
      startProcess,
}) async {
  await pumpFlowPlanTestApp(
    tester,
    db: harness.db,
    size: const Size(900, 1400),
    overrides: [
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
      archivedTaskListsProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
    ],
    child: MaterialApp(
      home: ICalImportExportPage(
        isWindowsOverride: isWindows,
        openDatabaseFolder: openDatabaseFolder,
        startProcess: startProcess,
      ),
    ),
  );
  await pumpIcalFrames(tester);
}

Future<void> _tapChoiceChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _tapDialogRadio(WidgetTester tester, String label) async {
  final radioLabel = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
  expect(radioLabel, findsOneWidget);
  await tester.tap(radioLabel);
  await tester.pump();
}

Future<void> _tapDialogButtonWithRealAsync(
  WidgetTester tester,
  String label,
) async {
  final buttonLabel = find.descendant(
    of: find.byType(AlertDialog),
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
  final target = finder.evaluate().isNotEmpty
      ? finder.last
      : find.byType(ElevatedButton).last;
  await tester.ensureVisible(target);
  await tester.runAsync(() async {
    await tester.tap(target);
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
        'name': 'Work',
        'color_hex': '#6B5EE4',
        'description': null,
        'is_visible': true,
        'is_default': true,
        'default_is_block': false,
        'events': [
          {
            'uid': 'new-structured-gap6',
            'dtstamp': '2026-06-08T09:00:00.000Z',
            'summary': 'New structured gap6',
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
