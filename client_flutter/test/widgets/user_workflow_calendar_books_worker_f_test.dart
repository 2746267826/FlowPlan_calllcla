import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets(
    'calendar books page creates books, saves defaults and changes defaults',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = CalendarBooksRepository(db);
      final streams = _CalendarBookStreams(repository);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await streams.close();
      });
      final baseCalendarId = await insertFixtureCalendar(
        db,
        name: 'Base calendar',
      );
      final baseTaskListId = await insertFixtureTaskList(
        db,
        name: 'Base tasks',
      );

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1100),
        overrides: [
          allEventCalendarsProvider.overrideWith(
            (ref) => streams.eventCalendars,
          ),
          allTaskListsProvider.overrideWith(
            (ref) => streams.taskLists,
          ),
          archivedTaskListsProvider.overrideWith(
            (ref) => streams.archivedTaskLists,
          ),
          outlookTaskListBindingsProvider.overrideWith(
            (ref) async => const {},
          ),
        ],
        child: const MaterialApp(home: CalendarBooksPage()),
      );
      await streams.refresh(tester);
      await _pumpUntilText(tester, 'Base calendar');

      await _tapSectionAdd(tester, 0);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Planning Blocks',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Switch),
        ),
      );
      await _tapDialogSave(tester);
      await streams.refresh(tester);
      await _pumpUntilText(tester, 'Planning Blocks');

      final planningCalendar = await _calendarByName(db, 'Planning Blocks');
      expect(planningCalendar, isNotNull);
      expect(planningCalendar!.isDefault, isFalse);
      expect(
        (await repository.getEventCalendarDefaults(planningCalendar.id))
            .defaultIsBlock,
        isTrue,
      );

      await _openTileMenu(tester, 'Planning Blocks');
      await _tapPopupValue(tester, 'set_default');
      await _pumpUntil(
        tester,
        () async {
          final selected = await repository.getEventCalendarById(
            planningCalendar.id,
          );
          return selected?.isDefault == true;
        },
      );
      expect(
        (await repository.getEventCalendarById(baseCalendarId))?.isDefault,
        isFalse,
      );

      await _tapSectionAdd(tester, 1);
      final taskFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(taskFields.at(0), 'P');
      await tester.enterText(taskFields.at(1), 'Project Tasks');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Switch),
        ),
      );
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ChoiceChip),
            )
            .at(3),
      );
      await _tapDialogSave(tester);
      await streams.refresh(tester);
      await _pumpUntilText(tester, 'Project Tasks');

      final projectTasks = await _taskListByName(db, 'Project Tasks');
      expect(projectTasks, isNotNull);
      expect(projectTasks!.emoji, 'P');
      expect(projectTasks.isDefault, isFalse);
      final projectDefaults = await repository.getTaskListDefaults(
        projectTasks.id,
      );
      expect(projectDefaults.defaultIsAutoScheduled, isFalse);
      expect(projectDefaults.defaultReminderMinutesBefore, 30);

      await _openTileMenu(tester, 'Project Tasks');
      await _tapPopupValue(tester, 'set_default');
      await _pumpUntil(
        tester,
        () async {
          final selected = await repository.getTaskListById(projectTasks.id);
          return selected?.isDefault == true;
        },
      );
      expect(
        (await repository.getTaskListById(baseTaskListId))?.isDefault,
        isFalse,
      );
    },
  );

  testWidgets(
    'calendar books page renders loading, empty and provider errors',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final loadingCalendars = StreamController<List<EventCalendar>>();
      final loadingTaskLists = StreamController<List<TaskList>>();
      addTearDown(loadingCalendars.close);
      addTearDown(loadingTaskLists.close);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 900),
        overrides: [
          allEventCalendarsProvider.overrideWith(
            (ref) => loadingCalendars.stream,
          ),
          allTaskListsProvider.overrideWith(
            (ref) => loadingTaskLists.stream,
          ),
          archivedTaskListsProvider.overrideWith(
            (ref) => Stream.value(const <TaskList>[]),
          ),
          outlookTaskListBindingsProvider.overrideWith(
            (ref) async => const {},
          ),
        ],
        child: const MaterialApp(home: CalendarBooksPage()),
      );
      await _pumpFrames(tester);
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

      loadingCalendars.add(const <EventCalendar>[]);
      loadingTaskLists.addError(StateError('task list boom'));
      await _pumpFrames(tester);

      expect(
        find.text(
          '\u6682\u65e0\u65e5\u5386\u672c\uff0c\u70b9\u51fb\u53f3\u4e0a\u89d2\u521b\u5efa',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('task list boom'), findsOneWidget);
    },
  );
}

class _CalendarBookStreams {
  _CalendarBookStreams(this._repository);

  final CalendarBooksRepository _repository;
  final _eventCalendarsController =
      StreamController<List<EventCalendar>>.broadcast(sync: true);
  final _taskListsController =
      StreamController<List<TaskList>>.broadcast(sync: true);
  final _archivedTaskListsController =
      StreamController<List<TaskList>>.broadcast(sync: true);

  Stream<List<EventCalendar>> get eventCalendars =>
      _eventCalendarsController.stream;

  Stream<List<TaskList>> get taskLists => _taskListsController.stream;

  Stream<List<TaskList>> get archivedTaskLists =>
      _archivedTaskListsController.stream;

  Future<void> refresh(WidgetTester tester) async {
    _eventCalendarsController.add(await _repository.getAllEventCalendars());
    _taskListsController.add(await _repository.getAllTaskLists());
    _archivedTaskListsController.add(await _repository.getArchivedTaskLists());
    await tester.pump();
  }

  Future<void> close() async {
    await _eventCalendarsController.close();
    await _taskListsController.close();
    await _archivedTaskListsController.close();
  }
}

Future<void> _tapSectionAdd(WidgetTester tester, int index) async {
  final addButton = find.byIcon(Icons.add_circle_outline).at(index);
  await tester.ensureVisible(addButton);
  await tester.pump();
  await tester.tap(addButton);
  await _pumpUntilDialog(tester);
}

Future<void> _openTileMenu(WidgetTester tester, String title) async {
  await tester.ensureVisible(_tileFor(title));
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: _tileFor(title),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _tapPopupValue(WidgetTester tester, String value) async {
  final menuItem = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem && widget.value == value,
  );
  expect(menuItem, findsOneWidget);
  await tester.tap(
    find.descendant(of: menuItem, matching: find.byType(Text)).first,
  );
  await _pumpFrames(tester);
}

Future<void> _tapDialogSave(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ElevatedButton),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(AlertDialog).evaluate().isEmpty) {
      await _pumpFrames(tester);
      return;
    }
  }
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> _pumpUntilDialog(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () async => find.byType(AlertDialog).evaluate().isNotEmpty,
  );
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  await _pumpUntil(
    tester,
    () async => find.text(text).evaluate().isNotEmpty,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (await condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(await condition(), isTrue);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _tileFor(String title) {
  return find
      .ancestor(
        of: find.text(title).first,
        matching: find.byType(ListTile),
      )
      .first;
}

Future<EventCalendar?> _calendarByName(AppDatabase db, String name) {
  return (db.select(db.eventCalendars)..where((row) => row.name.equals(name)))
      .getSingleOrNull();
}

Future<TaskList?> _taskListByName(AppDatabase db, String name) {
  return (db.select(db.taskLists)..where((row) => row.name.equals(name)))
      .getSingleOrNull();
}
