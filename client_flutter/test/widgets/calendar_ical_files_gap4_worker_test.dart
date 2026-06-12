import 'package:drift/drift.dart' hide isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/storage/database_restore_service.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/calendar/presentation/week_view.dart';
import 'package:flowplanv2/features/ical/ical_import_export_page_body.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/task/presentation/unscheduled_task_panel.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('iCal page consumes and displays database restore notice',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final restoreService = _FakeDatabaseRestoreService(
      notice: DatabaseRestoreNotice(
        restoredAt: DateTime.utc(2026, 6, 10, 8, 30),
        previousDatabaseBackupPath: 'C:/backup/before.sqlite',
        restoredDatabasePath: 'C:/data/flowplanv2.sqlite',
      ),
    );

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(900, 1200),
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
      child: MaterialApp(
        home: ICalImportExportPage(restoreService: restoreService),
      ),
    );
    await pumpUntilFound(
      tester,
      find.textContaining('before.sqlite'),
      maxPumps: 20,
    );

    expect(find.textContaining('before.sqlite'), findsOneWidget);
    expect(restoreService.getPendingRestoreCalls, 1);
    expect(restoreService.consumeRestoreNoticeCalls, 1);
    await _disposeWidgetTree(tester);
  });

  testWidgets('CalendarBooks blocks direct editing of Outlook calendars',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Read only Outlook',
            source: const Value('outlook'),
            isVisible: const Value(true),
            createdAt: fixtureNow(),
          ),
        );

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(900, 1000),
      overrides: [
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
        archivedTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
        ),
        outlookTaskListBindingsProvider.overrideWith(
          (ref) async => const <int, OutlookTaskListBinding>{},
        ),
      ],
      child: const MaterialApp(home: CalendarBooksPage()),
    );
    await pumpUntilFound(tester, find.text('Read only Outlook'));

    expect(find.text('Read only Outlook'), findsOneWidget);
    final outlookTile = find.ancestor(
      of: find.text('Read only Outlook'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: outlookTile,
        matching: find.textContaining('Outlook'),
      ),
      findsWidgets,
    );
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
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: outlookTile, matching: find.byType(Switch)),
      findsOneWidget,
    );
    await _disposeWidgetTree(tester);
  });

  testWidgets('UnscheduledTaskPanel accepts scheduled task drops into inbox',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
    final taskId = await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'scheduled-drop',
            summary: 'Scheduled drop task',
            taskListId: taskListId,
          ).copyWith(
            dtstart: Value(DateTime.utc(2026, 6, 10, 9)),
            durationMinutes: const Value(45),
          ),
        );
    final task = await (db.select(db.taskItems)
          ..where((item) => item.id.equals(taskId)))
        .getSingle();

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(900, 700),
      overrides: [
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: UnscheduledTaskPanel()),
      ),
    );
    await tester.pumpAndSettle();

    final targetFinder = find.byWidgetPredicate(
      (widget) => widget is DragTarget<TaskItem>,
    );
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);

    expect(
      target.onWillAcceptWithDetails?.call(
        DragTargetDetails<TaskItem>(data: task, offset: Offset.zero),
      ),
      isTrue,
    );
    target.onAcceptWithDetails?.call(
      DragTargetDetails<TaskItem>(data: task, offset: Offset.zero),
    );
    await tester.pumpAndSettle();

    expect(fakeStore.updatedTasks.single.localId, taskId);
    expect(fakeStore.updatedTasks.single.payload, containsPair('dtstart', null));
    expect(fakeStore.updatedTasks.single.changedFields, ['dtstart']);
    expect(find.byType(SnackBar), findsOneWidget);
    await _disposeWidgetTree(tester);
  });

  testWidgets('WeekView opens desktop dialogs for visible range items',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId = await insertFixtureCalendar(db, name: 'Visible calendar');
    final hiddenCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Hidden calendar',
            isVisible: const Value(false),
            createdAt: fixtureNow(),
          ),
        );
    final taskListId = await insertFixtureTaskList(db, name: 'Week tasks');
    await EventRepository(db).create(
      fixtureEvent(
        uid: 'visible-week-event',
        summary: 'Visible week event',
        calendarId: calendarId,
      ),
      audit: false,
    );
    await EventRepository(db).create(
      fixtureEvent(
        uid: 'hidden-week-event',
        summary: 'Hidden week event',
        calendarId: hiddenCalendarId,
      ),
      audit: false,
    );
    await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'week-task',
            summary: 'Visible week task',
            taskListId: taskListId,
          ).copyWith(
            dtstart: Value(DateTime.utc(2026, 6, 8, 10)),
            durationMinutes: const Value(30),
          ),
        );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const WeekView(),
        ),
        GoRoute(
          path: '/event/:id',
          builder: (context, state) => const Text('mobile event route'),
        ),
        GoRoute(
          path: '/task/:id',
          builder: (context, state) => const Text('mobile task route'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(900, 900),
      child: MaterialApp.router(routerConfig: router),
    );
    final dynamic dateNotifier = ProviderScope.containerOf(
      tester.element(find.byType(WeekView)),
    ).read(selectedDateProvider.notifier);
    dateNotifier.setDate(DateTime(2026, 6, 8));
    await tester.pumpAndSettle();

    expect(find.text('Visible week event'), findsOneWidget);
    expect(find.text('Hidden week event'), findsNothing);
    expect(find.text('Visible week task'), findsOneWidget);

    await tester.tap(find.text('Visible week event'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Visible week task'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await _disposeWidgetTree(tester);
  });
}

class _FakeDatabaseRestoreService extends DatabaseRestoreService {
  _FakeDatabaseRestoreService({
    this.notice,
  });

  DatabaseRestoreNotice? notice;
  int getPendingRestoreCalls = 0;
  int consumeRestoreNoticeCalls = 0;

  @override
  Future<PendingDatabaseRestore?> getPendingRestore() async {
    getPendingRestoreCalls += 1;
    return null;
  }

  @override
  Future<DatabaseRestoreNotice?> consumeRestoreNotice() async {
    consumeRestoreNoticeCalls += 1;
    final current = notice;
    notice = null;
    return current;
  }
}

Future<void> _disposeWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}
