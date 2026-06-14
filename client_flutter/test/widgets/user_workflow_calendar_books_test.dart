import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets('calendar books page manages calendar and task list actions',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Primary Calendar');
    final projectCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Project Calendar',
            colorHex: const Value('#43A047'),
            isDefault: const Value(false),
            createdAt: fixtureNow(),
          ),
        );
    await insertFixtureTaskList(db, name: 'Inbox Tasks');
    final workTaskListId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Work Tasks',
            colorHex: const Value('#0EA8A0'),
            emoji: const Value('W'),
            isDefault: const Value(false),
            createdAt: fixtureNow(),
          ),
        );

    final streams = await _pumpCalendarBooks(tester, db);
    await _pumpUntilText(tester, 'Project Calendar');
    await _pumpUntilText(tester, 'Work Tasks');

    await tester.tap(
      find.descendant(
        of: _tileFor('Project Calendar'),
        matching: find.byType(Switch),
      ),
    );
    await _pumpFrames(tester);
    await streams.refresh(tester);
    expect((await _calendarById(db, projectCalendarId))?.isVisible, isFalse);

    await _openTileMenu(tester, 'Project Calendar');
    await _tapPopupValue(tester, 'edit');
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Renamed Calendar',
    );
    await _tapDialogSave(tester);
    await streams.refresh(tester);

    expect(
        (await _calendarById(db, projectCalendarId))?.name, 'Renamed Calendar');
    expect(find.text('Renamed Calendar'), findsOneWidget);

    await _openTileMenu(tester, 'Renamed Calendar');
    await _tapPopupValue(tester, 'delete');
    await _confirmDialog(tester);
    await streams.refresh(tester);

    expect(await _calendarById(db, projectCalendarId), isNull);

    await _openTileMenu(tester, 'Work Tasks');
    await _tapPopupValue(tester, 'set_default');
    await streams.refresh(tester);
    expect((await _taskListById(db, workTaskListId))?.isDefault, isTrue);

    await _openTileMenu(tester, 'Work Tasks');
    await _tapPopupValue(tester, 'edit');
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .at(1),
      'Renamed Tasks',
    );
    await _tapDialogSave(tester);
    await streams.refresh(tester);
    expect((await _taskListById(db, workTaskListId))?.name, 'Renamed Tasks');

    await _openTileMenu(tester, 'Renamed Tasks');
    await _tapPopupValue(tester, 'archive');
    await _confirmDialog(tester);
    await streams.refresh(tester);
    expect((await _taskListById(db, workTaskListId))?.isArchived, isTrue);

    final restoreButton = find.descendant(
      of: _tileFor('Renamed Tasks'),
      matching: find.byType(TextButton),
    );
    await tester.ensureVisible(restoreButton);
    await tester.pump();
    await tester.tap(restoreButton);
    await _confirmDialog(tester);
    await streams.refresh(tester);
    expect((await _taskListById(db, workTaskListId))?.isArchived, isFalse);

    await _openTileMenu(tester, 'Renamed Tasks');
    await _tapPopupValue(tester, 'delete');
    await _confirmDialog(tester);
    await streams.refresh(tester);
    expect(await _taskListById(db, workTaskListId), isNull);
  });

  testWidgets('read-only Outlook calendars only expose visibility controls',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);
    final outlookCalendarId = await repository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Outlook Readonly',
        colorHex: const Value('not-a-color'),
        source: const Value('outlook'),
        syncUrl: const Value('remote-calendar'),
        createdAt: fixtureNow(),
      ),
      audit: false,
    );

    final streams = await _pumpCalendarBooks(tester, db);
    await _pumpUntilText(tester, 'Outlook Readonly');
    final outlookTile = _tileFor('Outlook Readonly');

    expect(
      find.descendant(
        of: outlookTile,
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: outlookTile,
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
      ),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: outlookTile,
        matching: find.byType(Switch),
      ),
    );
    await _pumpFrames(tester);
    await streams.refresh(tester);

    expect(
      (await repository.getEventCalendarById(outlookCalendarId))?.isVisible,
      isFalse,
    );
  });

  testWidgets('Outlook calendar edit action is guarded when invoked',
      (tester) async {
    CalendarBooksPage.debugExposeOutlookCalendarEditAction = true;
    addTearDown(() {
      CalendarBooksPage.debugExposeOutlookCalendarEditAction = false;
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);
    await repository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Outlook Guarded',
        source: const Value('outlook'),
        syncUrl: const Value('remote-guarded-calendar'),
        createdAt: fixtureNow(),
      ),
      audit: false,
    );

    await _pumpCalendarBooks(tester, db);
    await _pumpUntilText(tester, 'Outlook Guarded');

    await _openTileMenu(tester, 'Outlook Guarded');
    await _tapPopupValue(tester, 'edit');

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('不能在 FlowPlanV2 中直接编辑'),
      findsOneWidget,
    );
  });

  testWidgets(
      'bound task lists explain Outlook mirror impact when archived and deleted',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    final mirrorRepository = OutlookTaskMirrorRepository(db);
    await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Fallback Tasks',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final boundTaskListId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Bound Tasks',
        colorHex: const Value('#0EA8A0'),
        emoji: const Value('B'),
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    await repository.setDefaultTaskList(boundTaskListId, audit: false);
    final taskId = await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'bound-task',
            summary: 'Mirrored task',
            taskListId: boundTaskListId,
          ),
        );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: boundTaskListId,
        remoteCalendarId: 'remote-bound',
        remoteCalendarName: 'Remote Bound Tasks',
        linkedAt: fixtureNow(),
      ),
    );
    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: taskId,
        localTaskListId: boundTaskListId,
        remoteCalendarId: 'remote-bound',
        remoteCalendarName: 'Remote Bound Tasks',
        remoteEventId: 'remote-task',
        syncedAt: fixtureNow(),
      ),
    );

    final streams = await _pumpCalendarBooks(
      tester,
      db,
      loadBindings: bindingsRepository.loadTaskListBindings,
    );
    await _pumpUntilText(tester, 'Bound Tasks');
    expect(find.textContaining('Remote Bound Tasks'), findsOneWidget);

    await _openTileMenu(tester, 'Bound Tasks');
    await _tapPopupValue(tester, 'archive');
    await _pumpUntilDialog(tester);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Remote Bound Tasks'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1'), findsWidgets);
    await _confirmDialog(tester);
    await streams.refresh(tester);

    final archived = await repository.getTaskListById(boundTaskListId);
    expect(archived?.isArchived, isTrue);
    expect(
        await bindingsRepository.getTaskListBinding(boundTaskListId), isNull);
    expect(
      await mirrorRepository.countTaskMirrorBindingsForTaskList(
        boundTaskListId,
      ),
      1,
    );
    final movedTask = await (db.select(db.taskItems)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    expect(movedTask.taskListId, isNot(boundTaskListId));

    await _openTileMenu(tester, 'Bound Tasks');
    await _tapPopupValue(tester, 'delete');
    await _pumpUntilDialog(tester);
    expect(find.textContaining('1'), findsWidgets);
    await _confirmDialog(tester);
    await streams.refresh(tester);

    expect(await repository.getTaskListById(boundTaskListId), isNull);
  });

  testWidgets('task list Outlook bind and unbind menu actions update mappings',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    final taskListId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Sync Menu Tasks',
        createdAt: fixtureNow(),
      ),
      audit: false,
    );
    final boundTaskListId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Bound Menu Tasks',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: boundTaskListId,
        remoteCalendarId: 'remote-sync-menu',
        remoteCalendarName: 'Remote Sync Menu',
        linkedAt: fixtureNow(),
      ),
    );
    final streams = await _pumpCalendarBooks(
      tester,
      db,
      loadBindings: bindingsRepository.loadTaskListBindings,
    );

    await _pumpUntilText(tester, 'Sync Menu Tasks');
    await _openTileMenu(tester, 'Sync Menu Tasks');
    await _tapPopupValue(tester, 'bind_outlook');
    await _pumpFrames(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(await bindingsRepository.getTaskListBinding(taskListId), isNull);

    await _pumpUntilText(tester, 'Bound Menu Tasks');
    await _openTileMenu(tester, 'Bound Menu Tasks');
    await _tapPopupValue(tester, 'unbind_outlook');
    await _confirmDialog(tester);
    await streams.refresh(tester);

    expect(
      await bindingsRepository.getTaskListBinding(boundTaskListId),
      isNull,
    );
  });
}

Future<_CalendarBookStreams> _pumpCalendarBooks(
  WidgetTester tester,
  AppDatabase db, {
  Future<Map<int, OutlookTaskListBinding>> Function()? loadBindings,
}) async {
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
        (ref) => loadBindings?.call() ?? Future.value(const {}),
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

Future<void> _tapDialogSave(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ElevatedButton),
    ),
  );
  await _pumpUntilNoDialog(tester);
}

Future<void> _confirmDialog(WidgetTester tester) async {
  await _pumpUntilDialog(tester);
  await tester.tap(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        )
        .last,
  );
  await _pumpUntilNoDialog(tester);
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

Future<EventCalendar?> _calendarById(AppDatabase db, int id) {
  return (db.select(db.eventCalendars)..where((row) => row.id.equals(id)))
      .getSingleOrNull();
}

Future<TaskList?> _taskListById(AppDatabase db, int id) {
  return (db.select(db.taskLists)..where((row) => row.id.equals(id)))
      .getSingleOrNull();
}
