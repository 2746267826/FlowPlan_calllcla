import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/features/task/presentation/unscheduled_task_panel.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  group('UnscheduledTaskPanel worker 09 gaps', () {
    testWidgets('shows loading and error provider states', (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final loadingTasks = StreamController<List<TaskItem>>();
      addTearDown(loadingTasks.close);

      await _pumpPanel(
        tester,
        db,
        overrides: [
          allTasksProvider.overrideWith(
            (ref) => loadingTasks.stream,
          ),
          allTaskListsProvider.overrideWith(
            (ref) => const Stream<List<TaskList>>.empty(),
          ),
        ],
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester);
      await _pumpPanel(
        tester,
        db,
        overrides: [
          allTasksProvider.overrideWith(
            (ref) => Stream<List<TaskItem>>.error(Exception('task boom')),
          ),
          allTaskListsProvider.overrideWith(
            (ref) => const Stream<List<TaskList>>.empty(),
          ),
        ],
      );
      await tester.pump();
      expect(find.textContaining('task boom'), findsOneWidget);
    });

    testWidgets('shows empty state when every task is scheduled',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db);
      final scheduled = await TaskRepository(db).create(
        fixtureTask(
          uid: 'scheduled-only',
          summary: 'Scheduled only',
          taskListId: taskListId,
        ).copyWith(dtstart: Value(fixtureNow())),
        audit: false,
      );
      final task = await TaskRepository(db).getById(scheduled);

      await _pumpPanel(
        tester,
        db,
        overrides: [
          allTasksProvider.overrideWith(
            (ref) => Stream.value(<TaskItem>[task!]),
          ),
          allTaskListsProvider.overrideWith(
            (ref) => Stream.value(const <TaskList>[]),
          ),
        ],
      );
      await _pumpFrames(tester);

      expect(find.text('所有任务均已排入日程'), findsOneWidget);
      expect(find.text('Scheduled only'), findsNothing);
    });

    testWidgets('renders unscheduled task metadata with fallback list color',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await CalendarBooksRepository(db).createTaskList(
        TaskListsCompanion.insert(
          name: 'Odd color list',
          colorHex: const Value('not-a-color'),
          emoji: const Value('O'),
          createdAt: fixtureNow(),
        ),
        audit: false,
      );
      final taskId = await TaskRepository(db).create(
        fixtureTask(
          uid: 'unscheduled-tile',
          summary: 'Unscheduled tile',
          taskListId: taskListId,
        ).copyWith(
          durationMinutes: const Value(45),
          due: Value(fixtureNow().add(const Duration(days: 2))),
          priorityLocal: const Value(1),
        ),
        audit: false,
      );
      final task = await TaskRepository(db).getById(taskId);
      final taskList = await CalendarBooksRepository(db).getTaskListById(
        taskListId,
      );

      await _pumpPanel(
        tester,
        db,
        overrides: [
          allTasksProvider.overrideWith(
            (ref) => Stream.value(<TaskItem>[task!]),
          ),
          allTaskListsProvider.overrideWith(
            (ref) => Stream.value(<TaskList>[taskList!]),
          ),
        ],
      );
      await _pumpFrames(tester);

      expect(find.text('Unscheduled tile'), findsOneWidget);
      expect(find.text('O Odd color list'), findsOneWidget);
      expect(find.text('45 分钟'), findsOneWidget);
      expect(find.text('6/10'), findsOneWidget);
    });

    testWidgets('opens default task detail dialog from unscheduled tile',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId =
          await insertFixtureTaskList(db, name: 'Default detail');
      final taskId = await TaskRepository(db).create(
        fixtureTask(
          uid: 'default-detail-dialog',
          summary: 'Open default detail',
          taskListId: taskListId,
        ),
        audit: false,
      );
      final task = await TaskRepository(db).getById(taskId);
      final taskList = await CalendarBooksRepository(db).getTaskListById(
        taskListId,
      );

      await _pumpPanel(
        tester,
        db,
        overrides: [
          allTasksProvider.overrideWith(
            (ref) => Stream.value(<TaskItem>[task!]),
          ),
          allTaskListsProvider.overrideWith(
            (ref) => Stream.value(<TaskList>[taskList!]),
          ),
        ],
      );
      await _pumpFrames(tester);

      await tester.tap(find.text('Open default detail'));
      await _pumpUntilFound(tester, find.byType(TaskDetailPage));

      final detailPage = tester.widget<TaskDetailPage>(
        find.byType(TaskDetailPage),
      );
      expect(detailPage.taskId, taskId);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);
      expect(find.text('Open default detail'), findsWidgets);

      Navigator.of(tester.element(find.byType(TaskDetailPage))).pop();
      await _pumpUntilNoDialog(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester);
    });
  });

  group('CalendarBooksPage worker 09 gaps', () {
    testWidgets('canceling a delete confirmation leaves calendar untouched',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = CalendarBooksRepository(db);
      final calendarId = await repository.createEventCalendar(
        EventCalendarsCompanion.insert(
          name: 'Cancel delete calendar',
          createdAt: fixtureNow(),
        ),
        audit: false,
      );

      final streams = await _pumpCalendarBooks(tester, db);
      await _pumpUntilText(tester, 'Cancel delete calendar');
      await _openTileMenu(tester, 'Cancel delete calendar');
      await _tapPopupValue(tester, 'delete');
      await _pumpUntilDialog(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            )
            .first,
      );
      await _pumpUntilNoDialog(tester);
      await streams.refresh(tester);

      expect(await repository.getEventCalendarById(calendarId), isNotNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('missing active default target shows failure snackbar',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = CalendarBooksRepository(db);
      final missingId = await repository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Missing default fail',
          createdAt: fixtureNow(),
        ),
        audit: false,
      );

      await _pumpCalendarBooks(tester, db);
      await _pumpUntilText(tester, 'Missing default fail');
      await db.delete(db.taskLists).delete(
            TaskListsCompanion(id: Value(missingId)),
          );
      await _openTileMenu(tester, 'Missing default fail');
      await _tapPopupValue(tester, 'set_default');
      await _pumpFrames(tester);

      expect(await repository.getTaskListById(missingId), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  AppDatabase db, {
  List<Override> overrides = const <Override>[],
}) async {
  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(700, 900),
    overrides: overrides,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 320, child: UnscheduledTaskPanel()),
      ),
    ),
  );
  await tester.pump();
}

Future<_CalendarBookStreams> _pumpCalendarBooks(
  WidgetTester tester,
  AppDatabase db,
) async {
  final streams = _CalendarBookStreams(db);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await streams.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 1100),
    overrides: [
      allEventCalendarsProvider.overrideWith((ref) => streams.eventCalendars),
      allTaskListsProvider.overrideWith((ref) => streams.taskLists),
      archivedTaskListsProvider.overrideWith(
        (ref) => streams.archivedTaskLists,
      ),
      outlookTaskListBindingsProvider.overrideWith(
        (ref) => Future.value(const {}),
      ),
    ],
    child: const MaterialApp(home: CalendarBooksPage()),
  );
  await streams.refresh(tester);
  return streams;
}

class _CalendarBookStreams {
  _CalendarBookStreams(this._db);

  final AppDatabase _db;
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
    _eventCalendarsController.add(await (_db.select(_db.eventCalendars)
          ..orderBy([
            (calendar) => OrderingTerm(
                  expression: calendar.isDefault,
                  mode: OrderingMode.desc,
                ),
            (calendar) => OrderingTerm(expression: calendar.name),
          ]))
        .get());
    _taskListsController.add(await (_db.select(_db.taskLists)
          ..where((taskList) => taskList.isArchived.equals(false))
          ..orderBy([
            (taskList) => OrderingTerm(
                  expression: taskList.isDefault,
                  mode: OrderingMode.desc,
                ),
            (taskList) => OrderingTerm(expression: taskList.name),
          ]))
        .get());
    _archivedTaskListsController.add(await (_db.select(_db.taskLists)
          ..where((taskList) => taskList.isArchived.equals(true))
          ..orderBy([
            (taskList) => OrderingTerm(expression: taskList.name),
          ]))
        .get());
    await tester.pump();
  }

  Future<void> close() async {
    await _eventCalendarsController.close();
    await _taskListsController.close();
    await _archivedTaskListsController.close();
  }
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.text(text), findsWidgets);
}

Finder _tileFor(String title) {
  return find
      .ancestor(
        of: find.text(title).first,
        matching: find.byType(ListTile),
      )
      .first;
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
  await _pumpFrames(tester, 8);
}

Future<void> _tapPopupValue(WidgetTester tester, String value) async {
  final menuItem = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem && widget.value == value,
  );
  expect(menuItem, findsOneWidget);
  await _pumpFrames(tester, 2);
  await tester.tap(
    find.descendant(of: menuItem, matching: find.byType(Text)).first,
  );
  await _pumpFrames(tester);
}

Future<void> _pumpUntilDialog(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _pumpUntilNoDialog(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(AlertDialog).evaluate().isEmpty) {
      await _pumpFrames(tester);
      return;
    }
  }
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsWidgets);
}
