import 'dart:async';

import 'package:drift/native.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/ical/ical_import_export_page_body.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fake_path_provider.dart';
import '../test_support/ical_import_export_harness.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

final _stamp = DateTime.utc(2026, 6, 8, 9);

void main() {
  testWidgets('calendar provider errors render a bounded error state', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      overrides: [
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream<List<EventCalendar>>.error(
            StateError('calendar stream boom'),
          ),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
        archivedTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
      ],
    );

    expect(find.textContaining('calendar stream boom'), findsOneWidget);
  });

  testWidgets('task list provider errors render after calendars load', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      overrides: [
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream<List<EventCalendar>>.value(const <EventCalendar>[]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.error(
            StateError('task list stream boom'),
          ),
        ),
        archivedTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
      ],
    );

    expect(find.textContaining('task list stream boom'), findsOneWidget);
  });

  testWidgets('stale selected calendar is cleared when local calendars vanish', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Temporary', isDefault: true);
    await pumpIcalFrames(tester);

    expect(find.text('Temporary'), findsWidgets);

    await harness.db.delete(harness.db.eventCalendars).go();
    await harness.refreshProviderSnapshots();
    await pumpIcalFrames(tester);

    expect(
      find.textContaining(
        '\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c',
      ),
      findsOneWidget,
    );
  });

  testWidgets('structured archive chips can be removed and reselected', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Chip calendar', isDefault: true);
    await harness.createTaskList(name: 'Chip tasks');
    await pumpIcalFrames(tester);

    expect(find.text(_selectedContainerText(1, 1)), findsOneWidget);

    await _tapFilterChip(tester, 'Chip calendar');
    await pumpIcalFrames(tester);
    expect(find.text(_selectedContainerText(0, 1)), findsOneWidget);

    await _tapFilterChip(tester, 'Chip calendar');
    await pumpIcalFrames(tester);
    expect(find.text(_selectedContainerText(1, 1)), findsOneWidget);

    await _tapFilterChip(tester, 'Chip tasks');
    await pumpIcalFrames(tester);
    expect(find.text(_selectedContainerText(1, 0)), findsOneWidget);

    await _tapFilterChip(tester, 'Chip tasks');
    await pumpIcalFrames(tester);
    expect(find.text(_selectedContainerText(1, 1)), findsOneWidget);
  });

  testWidgets('structured archive export reports an empty built archive', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      overrides: [
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream<List<EventCalendar>>.value([
            EventCalendar(
              id: 404,
              name: 'Ghost calendar',
              colorHex: '#6B5EE4',
              isVisible: true,
              isDefault: false,
              source: 'local',
              createdAt: _stamp,
            ),
          ]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
        archivedTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
      ],
    );

    await _tapIcalButtonWithRealAsync(
      tester,
      '\u5bfc\u51fa\u7ed3\u6784\u5316\u5f52\u6863',
    );
    await pumpIcalFrames(tester);

    expect(
      find.text(
        '\u6ca1\u6709\u53ef\u5bfc\u51fa\u7684\u65e5\u5386\u672c\u6216\u4efb\u52a1\u672c\u3002',
      ),
      findsOneWidget,
    );
  });

  testWidgets('iCal import reports path read failures through the catch branch', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Broken import path',
      isDefault: true,
    );
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickPath(harness.tempFile('missing.ics'));

    await _tapIcalButtonWithRealAsync(
      tester,
      '\u9009\u62e9\u6587\u4ef6',
    );
    await pumpIcalFrames(tester);

    expect(
      find.textContaining('\u5bfc\u5165\u5931\u8d25\uff1a'),
      findsOneWidget,
    );
    expect(await harness.eventsInCalendar(calendarId), isEmpty);
  });

  testWidgets('database export reports failures from invalid output targets', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await pumpIcalFrames(tester);
    harness.filePicker.queueSavePath(harness.documentsDirectory.path);

    await _tapIcalButtonWithRealAsync(
      tester,
      '\u5bfc\u51fa\u6570\u636e\u5e93',
    );
    await pumpIcalFrames(tester);

    expect(
      find.textContaining(
        '\u5bfc\u51fa\u5b8c\u6574\u6570\u636e\u5e93\u5931\u8d25\uff1a',
      ),
      findsOneWidget,
    );
  });

  testWidgets('open database folder reports path lookup failures', (
    tester,
  ) async {
    final db = _DelayedPathDatabase();
    await _pumpPage(
      tester,
      database: db,
      overrides: [
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream<List<EventCalendar>>.value(const <EventCalendar>[]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
        archivedTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
      ],
    );

    final idleLabel =
        find.text('\u6253\u5f00\u76ee\u5f55').evaluate().isNotEmpty
            ? '\u6253\u5f00\u76ee\u5f55'
            : '\u663e\u793a\u8def\u5f84';
    final idleButton = find.text(idleLabel);
    await tester.ensureVisible(idleButton.last);
    await tester.tap(idleButton.last);
    await tester.pump();

    final progressLabel =
        find.text('\u6253\u5f00\u4e2d...').evaluate().isNotEmpty
            ? '\u6253\u5f00\u4e2d...'
            : '\u8bfb\u53d6\u4e2d...';
    expect(find.text(progressLabel), findsOneWidget);

    db.completePathLookupWithError(StateError('db path boom'));
    await pumpIcalFrames(tester);

    expect(
      find.textContaining(
        '\u8bfb\u53d6\u6570\u636e\u5e93\u4f4d\u7f6e\u5931\u8d25\uff1a',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  AppDatabase? database,
  required List<Override> overrides,
}) async {
  final documentsDirectory = await setFakePathProviderDocumentsDirectory(
    'ical_gap3_worker_page_',
  );
  final db = database ?? createTestDatabase();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 1400),
    overrides: overrides,
    child: const MaterialApp(
      home: ICalImportExportPage(),
    ),
  );
  await pumpIcalFrames(tester);
}

class _DelayedPathDatabase extends AppDatabase {
  _DelayedPathDatabase() : super(NativeDatabase.memory());

  final Completer<String> _pathCompleter = Completer<String>();

  @override
  Future<String> getDatabasePath() => _pathCompleter.future;

  void completePathLookupWithError(Object error) {
    if (!_pathCompleter.isCompleted) {
      _pathCompleter.completeError(error);
    }
  }
}

Future<void> _tapFilterChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
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

String _selectedContainerText(int calendars, int taskLists) {
  return '\u5df2\u9009\u62e9 $calendars \u4e2a\u65e5\u5386\u672c\u3001'
      '$taskLists \u4e2a\u4efb\u52a1\u672c\u3002';
}
