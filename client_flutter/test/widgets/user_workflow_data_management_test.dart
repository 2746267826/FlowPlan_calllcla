import 'dart:async';

import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/features/data_management/presentation/data_management_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

const _writablePolicy = OnlinePrimaryPolicy(
  serverReachable: true,
  authenticated: true,
  level: ServerConnectionLevel.online,
);

const _readOnlyPolicy = OnlinePrimaryPolicy(
  serverReachable: false,
  authenticated: true,
  level: ServerConnectionLevel.localCacheOnly,
);

void main() {
  testWidgets('data management filters and confirms multi-select delete',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'Design calendar',
    );
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Task inbox',
    );

    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'event-beta',
            dtstamp: fixtureNow(),
            summary: 'Beta Calendar Review',
            dtstart: DateTime.utc(2026, 6, 10, 10),
            eventCalendarId: Value(calendarId),
            location: const Value('Room Beta'),
            description: const Value('calendar fixture'),
            status: const Value('CONFIRMED'),
          ),
        );
    final alphaTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-alpha',
            dtstamp: fixtureNow(),
            summary: 'Alpha Planning Task',
            taskListId: Value(taskListId),
            description: const Value('searchable planning note'),
            status: const Value('NEEDS-ACTION'),
          ),
        );
    final gammaTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-gamma',
            dtstamp: fixtureNow(),
            summary: 'Gamma Completed Task',
            taskListId: Value(taskListId),
            status: const Value('COMPLETED'),
          ),
        );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 1000),
      overrides: [
        ...await _dataManagementSnapshotOverrides(db),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Alpha Planning Task'));

    expect(find.text('Alpha Planning Task'), findsOneWidget);
    expect(find.text('Beta Calendar Review'), findsOneWidget);
    expect(find.text('Gamma Completed Task'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'planning');
    await tester.pump();

    expect(find.text('Alpha Planning Task'), findsOneWidget);
    expect(find.text('Beta Calendar Review'), findsNothing);
    expect(find.text('Gamma Completed Task'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(0),
      valueFragment: 'tasks',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(3),
      valueFragment: 'COMPLETED',
    );

    expect(find.text('Gamma Completed Task'), findsOneWidget);
    expect(find.text('Alpha Planning Task'), findsNothing);
    expect(find.text('Beta Calendar Review'), findsNothing);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(0),
      valueFragment: 'all',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(3),
      valueFragment: 'all',
    );
    expect(find.text('Alpha Planning Task'), findsOneWidget);
    expect(find.text('Beta Calendar Review'), findsOneWidget);
    expect(find.text('Gamma Completed Task'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpUntilFound(tester, find.byType(AlertDialog));

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await _pumpUntilNoDialog(tester);
    expect(fakeStore.deletedTaskIds, isEmpty);
    expect(fakeStore.deletedEventIds, isEmpty);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await _pumpUntilDeleted(
      tester,
      fakeStore,
      taskIds: [alphaTaskId, gammaTaskId],
      eventId: eventId,
    );

    expect(fakeStore.deletedTaskIds, contains(alphaTaskId));
    expect(fakeStore.deletedTaskIds, contains(gammaTaskId));
    expect(fakeStore.deletedEventIds, contains(eventId));
  });

  testWidgets('data management completes tasks and clears current selection',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Action inbox');
    await insertFixtureCalendar(db, name: 'Action calendar');

    final firstTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-action-1',
            dtstamp: fixtureNow(),
            summary: 'First selected task',
            taskListId: Value(taskListId),
            status: const Value('NEEDS-ACTION'),
          ),
        );
    final secondTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-action-2',
            dtstamp: fixtureNow(),
            summary: 'Second selected task',
            taskListId: Value(taskListId),
            status: const Value('IN-PROCESS'),
          ),
        );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 1000),
      overrides: [
        ...await _dataManagementSnapshotOverrides(db),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('First selected task'));

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(0),
      valueFragment: 'tasks',
    );
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await _pumpUntilCompleted(
      tester,
      fakeStore,
      taskIds: [firstTaskId, secondTaskId],
    );

    expect(fakeStore.completedTaskIds, contains(firstTaskId));
    expect(fakeStore.completedTaskIds, contains(secondTaskId));
    expect(fakeStore.deletedTaskIds, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_done_outlined));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline), warnIfMissed: false);
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fakeStore.deletedTaskIds, isEmpty);
  });

  testWidgets(
      'data management read-only cache disables complete and delete batches',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Cached inbox',
    );
    await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-read-only-batch',
            dtstamp: fixtureNow(),
            summary: 'Cached batch task',
            taskListId: Value(taskListId),
            status: const Value('NEEDS-ACTION'),
          ),
        );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 1000),
      overrides: [
        ...await _dataManagementSnapshotOverrides(
          db,
          readOnlyCache: true,
        ),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Cached batch task'));

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();

    expect(find.text('Offline cache is read-only'), findsOneWidget);
    expect(
      _filledButtonByIcon(tester, Icons.check_circle_outline).onPressed,
      null,
    );
    expect(
      _filledButtonByIcon(tester, Icons.delete_outline).onPressed,
      null,
    );

    await tester.tap(find.byIcon(Icons.check_circle_outline),
        warnIfMissed: false);
    await tester.tap(find.byIcon(Icons.delete_outline), warnIfMissed: false);
    await tester.pump();

    expect(fakeStore.completedTaskIds, isEmpty);
    expect(fakeStore.deletedTaskIds, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('stale data management delete re-checks read-only cache policy',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Stale inbox');
    await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-stale-read-only-delete',
            dtstamp: fixtureNow(),
            summary: 'Stale batch delete',
            taskListId: Value(taskListId),
            status: const Value('NEEDS-ACTION'),
          ),
        );
    var policy = _writablePolicy;

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 1000),
      overrides: [
        ...await _dataManagementSnapshotOverrides(
          db,
          policyProvider: () => policy,
        ),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Stale batch delete'));
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    expect(
      _filledButtonByIcon(tester, Icons.delete_outline).onPressed,
      isNotNull,
    );

    policy = _readOnlyPolicy;
    ProviderScope.containerOf(
      tester.element(find.byType(DataManagementPage)),
    ).invalidate(onlinePrimaryPolicyProvider);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(
      find.text('Offline cache is read-only. Reconnect to save changes.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(fakeStore.deletedTaskIds, isEmpty);
  });

  testWidgets('stale data management complete re-checks read-only cache policy',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Stale inbox');
    await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-stale-read-only-complete',
            dtstamp: fixtureNow(),
            summary: 'Stale batch complete',
            taskListId: Value(taskListId),
            status: const Value('NEEDS-ACTION'),
          ),
        );
    var policy = _writablePolicy;

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 1000),
      overrides: [
        ...await _dataManagementSnapshotOverrides(
          db,
          policyProvider: () => policy,
        ),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Stale batch complete'));
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    expect(
      _filledButtonByIcon(tester, Icons.check_circle_outline).onPressed,
      isNotNull,
    );

    policy = _readOnlyPolicy;
    ProviderScope.containerOf(
      tester.element(find.byType(DataManagementPage)),
    ).invalidate(onlinePrimaryPolicyProvider);
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pump();

    expect(
      find.text('Offline cache is read-only. Reconnect to save changes.'),
      findsOneWidget,
    );
    expect(fakeStore.completedTaskIds, isEmpty);
  });

  testWidgets(
      'data management delete failure keeps selection and reports error',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = _FailingDeleteStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Failure inbox');
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-delete-fails',
            dtstamp: fixtureNow(),
            summary: 'Delete failure task',
            taskListId: Value(taskListId),
            status: const Value('NEEDS-ACTION'),
          ),
        );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 900),
      overrides: [
        ...await _dataManagementSnapshotOverrides(db),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Delete failure task'));

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );

    await _pumpUntilSnackBar(tester);

    expect(fakeStore.failedTaskDeleteIds, [taskId]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('data management shows loading and provider errors', (
    tester,
  ) async {
    final loadingTasks = StreamController<List<TaskItem>>();
    addTearDown(loadingTasks.close);

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: [
        onlinePrimaryPolicyProvider.overrideWith((ref) => _writablePolicy),
        managementTasksProvider.overrideWith((ref) => loadingTasks.stream),
        managementEventsProvider.overrideWith(
          (ref) => Stream.value(const <CalendarEvent>[]),
        ),
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream.value(const <EventCalendar>[]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream.value(const <TaskList>[]),
        ),
      ],
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: [
        onlinePrimaryPolicyProvider.overrideWith((ref) => _writablePolicy),
        managementTasksProvider.overrideWith(
          (ref) => Stream<List<TaskItem>>.error(StateError('tasks offline')),
        ),
        managementEventsProvider.overrideWith(
          (ref) => Stream.value(const <CalendarEvent>[]),
        ),
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream.value(const <EventCalendar>[]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream.value(const <TaskList>[]),
        ),
      ],
    );
    await tester.pump();

    expect(find.textContaining('tasks offline'), findsOneWidget);
  });

  testWidgets('data management refresh invalidates all list providers',
      (tester) async {
    var taskLoads = 0;
    var eventLoads = 0;
    var calendarLoads = 0;
    var taskListLoads = 0;

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: [
        onlinePrimaryPolicyProvider.overrideWith((ref) => _writablePolicy),
        managementTasksProvider.overrideWith((ref) {
          taskLoads += 1;
          return Stream.value(const <TaskItem>[]);
        }),
        managementEventsProvider.overrideWith((ref) {
          eventLoads += 1;
          return Stream.value(const <CalendarEvent>[]);
        }),
        allEventCalendarsProvider.overrideWith((ref) {
          calendarLoads += 1;
          return Stream.value(const <EventCalendar>[]);
        }),
        allTaskListsProvider.overrideWith((ref) {
          taskListLoads += 1;
          return Stream.value(const <TaskList>[]);
        }),
      ],
    );

    await pumpUntilFound(tester, find.text('当前筛选条件下没有任务或日程。'));
    expect(taskLoads, 1);
    expect(eventLoads, 1);
    expect(calendarLoads, 1);
    expect(taskListLoads, 1);

    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();

    expect(taskLoads, 2);
    expect(eventLoads, 2);
    expect(calendarLoads, 2);
    expect(taskListLoads, 2);
  });

  testWidgets(
      'data management filters by source time status and opens item routes', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'Calendar Ops',
    );
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Ops Inbox',
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));

    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'event-outlook-today',
            dtstamp: fixtureNow(),
            summary: 'Outlook Today Review',
            dtstart: today,
            dtend: Value(today.add(const Duration(hours: 1))),
            eventCalendarId: Value(calendarId),
            source: const Value('outlook'),
            status: const Value('TENTATIVE'),
            location: const Value('Remote Room'),
            description: const Value('source filter note'),
          ),
        );
    final overdueTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-overdue-action',
            dtstamp: fixtureNow(),
            summary: 'Overdue Action',
            taskListId: Value(taskListId),
            due: Value(yesterday),
            status: const Value('NEEDS-ACTION'),
          ),
        );
    await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-completed-yesterday',
            dtstamp: fixtureNow(),
            summary: 'Completed Yesterday',
            taskListId: Value(taskListId),
            due: Value(yesterday),
            status: const Value('COMPLETED'),
          ),
        );
    await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-no-time',
            dtstamp: fixtureNow(),
            summary: 'Untimed Backlog',
            taskListId: Value(taskListId),
            status: const Value('IN-PROCESS'),
          ),
        );

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: await _dataManagementSnapshotOverrides(db),
    );
    await pumpUntilFound(tester, find.text('Outlook Today Review'));

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(1),
      valueFragment: 'outlook',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(2),
      valueFragment: 'today',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(3),
      valueFragment: 'TENTATIVE',
    );

    expect(find.text('Outlook Today Review'), findsOneWidget);
    expect(find.text('Overdue Action'), findsNothing);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(1),
      valueFragment: 'local',
    );
    expect(find.text('Outlook Today Review'), findsNothing);
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(1),
      valueFragment: 'outlook',
    );
    expect(find.text('Outlook Today Review'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('opened event'), findsOneWidget);

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: await _dataManagementSnapshotOverrides(db),
    );
    await pumpUntilFound(tester, find.text('Overdue Action'));
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(2),
      valueFragment: 'overdue',
    );

    expect(find.text('Overdue Action'), findsOneWidget);
    expect(find.text('Completed Yesterday'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(find.text('opened task $overdueTaskId'), findsOneWidget);

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: await _dataManagementSnapshotOverrides(db),
    );
    await pumpUntilFound(tester, find.text('Untimed Backlog'));
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(2),
      valueFragment: 'noTime',
    );

    expect(find.text('Untimed Backlog'), findsOneWidget);
    expect(find.text('Outlook Today Review'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'not-present');
    await tester.pump();
    expect(find.text('当前筛选条件下没有任务或日程。'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.text('Untimed Backlog'), findsOneWidget);
  });

  testWidgets('data management complete failure keeps task selection', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = _FailingCompleteStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Recover inbox');
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-complete-fails',
            dtstamp: fixtureNow(),
            summary: 'Complete failure task',
            taskListId: Value(taskListId),
            status: const Value('NEEDS-ACTION'),
          ),
        );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.dataManagement,
      size: const Size(800, 900),
      overrides: [
        ...await _dataManagementSnapshotOverrides(db),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Complete failure task'));

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await _pumpUntilSnackBar(tester);

    expect(fakeStore.failedTaskCompleteIds, [taskId]);
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('data management covers next-week and manual row toggles', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'External Calendar',
    );
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Timed Tasks',
    );
    final now = DateTime.now();
    final nextWeek =
        DateTime(now.year, now.month, now.day, 10).add(const Duration(days: 3));

    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'event-cancelled-external',
            dtstamp: fixtureNow(),
            summary: 'Cancelled External Review',
            dtstart: nextWeek,
            dtend: Value(nextWeek.add(const Duration(hours: 1))),
            eventCalendarId: Value(calendarId),
            source: const Value('external-feed'),
            status: const Value('CANCELLED'),
          ),
        );
    await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-planned-next-week',
            dtstamp: fixtureNow(),
            summary: 'Planned Next Week Task',
            taskListId: Value(taskListId),
            dtstart: Value(nextWeek.add(const Duration(hours: 2))),
            status: const Value('NEEDS-ACTION'),
          ),
        );

    await _pumpDataManagementRouteHarness(
      tester,
      overrides: await _dataManagementSnapshotOverrides(db),
    );
    await pumpUntilFound(tester, find.text('Planned Next Week Task'));

    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.textContaining('已选 1'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.textContaining('已选 0'), findsOneWidget);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(2),
      valueFragment: 'next7Days',
    );
    expect(find.text('Cancelled External Review'), findsOneWidget);
    expect(find.text('Planned Next Week Task'), findsOneWidget);
    expect(find.textContaining('计划：'), findsOneWidget);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(3),
      valueFragment: 'CANCELLED',
    );
    expect(find.text('Cancelled External Review'), findsOneWidget);
    expect(find.textContaining('external-feed'), findsOneWidget);
    expect(find.textContaining('已取消'), findsWidgets);
    expect(find.text('Planned Next Week Task'), findsNothing);
  });
}

Finder _dropdownAt(int index) {
  return find.byWidgetPredicate((widget) => widget is DropdownButton).at(index);
}

FilledButton _filledButtonByIcon(WidgetTester tester, IconData icon) {
  return tester.widget<FilledButton>(
    find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(FilledButton),
    ),
  );
}

Future<void> _pumpDataManagementRouteHarness(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.dataManagement,
    routes: [
      GoRoute(
        path: AppRoutes.dataManagement,
        builder: (context, state) => const DataManagementPage(),
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) =>
            Text('opened task ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) => const Text('opened event'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

Future<List<Override>> _dataManagementSnapshotOverrides(
  AppDatabase db, {
  bool readOnlyCache = false,
  OnlinePrimaryPolicy Function()? policyProvider,
}) async {
  final tasks = await db.select(db.taskItems).get();
  final events = await db.select(db.calendarEvents).get();
  final calendars = await db.select(db.eventCalendars).get();
  final taskLists = await db.select(db.taskLists).get();

  return [
    onlinePrimaryPolicyProvider.overrideWith(
      (ref) =>
          policyProvider?.call() ??
          (readOnlyCache ? _readOnlyPolicy : _writablePolicy),
    ),
    managementTasksProvider.overrideWith((ref) => Stream.value(tasks)),
    managementEventsProvider.overrideWith((ref) => Stream.value(events)),
    allEventCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
    allTaskListsProvider.overrideWith((ref) => Stream.value(taskLists)),
  ];
}

Future<void> _pumpUntilNoDialog(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(AlertDialog).evaluate().isEmpty) {
      return;
    }
  }
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> _pumpUntilDeleted(
  WidgetTester tester,
  FakeTaskEventServerFirstStore fakeStore, {
  required List<int> taskIds,
  required int eventId,
}) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (taskIds.every(fakeStore.deletedTaskIds.contains) &&
        fakeStore.deletedEventIds.contains(eventId)) {
      return;
    }
  }
  for (final taskId in taskIds) {
    expect(fakeStore.deletedTaskIds, contains(taskId));
  }
  expect(fakeStore.deletedEventIds, contains(eventId));
}

Future<void> _pumpUntilCompleted(
  WidgetTester tester,
  FakeTaskEventServerFirstStore fakeStore, {
  required List<int> taskIds,
}) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (taskIds.every(fakeStore.completedTaskIds.contains)) {
      return;
    }
  }
  for (final taskId in taskIds) {
    expect(fakeStore.completedTaskIds, contains(taskId));
  }
}

Future<void> _pumpUntilSnackBar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      return;
    }
  }
  expect(find.byType(SnackBar), findsOneWidget);
}

class _FailingDeleteStore extends FakeTaskEventServerFirstStore {
  final failedTaskDeleteIds = <int>[];

  @override
  Future<ServerFirstWriteResult> deleteLocalTask({
    required int localId,
    int? baseServerVersion,
  }) async {
    failedTaskDeleteIds.add(localId);
    throw StateError('delete failed for test');
  }
}

class _FailingCompleteStore extends FakeTaskEventServerFirstStore {
  final failedTaskCompleteIds = <int>[];

  @override
  Future<ServerFirstWriteResult> completeLocalTask({
    required int localId,
    Map<String, Object?> body = const <String, Object?>{},
    int? baseServerVersion,
  }) async {
    failedTaskCompleteIds.add(localId);
    throw StateError('complete failed for test');
  }
}
