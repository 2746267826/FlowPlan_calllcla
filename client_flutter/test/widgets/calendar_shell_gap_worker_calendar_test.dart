import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

class _MockSchedulerEngine extends Mock implements SchedulerEngine {}

class _FailingTaskEventStore extends FakeTaskEventServerFirstStore {
  @override
  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload,
  ) async {
    throw StateError('calendar worker failure');
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 8));
  });

  testWidgets('mobile shell switches routes and opens quick add from the FAB',
      (tester) async {
    await pumpShellNavigationHarness(
      tester,
      size: const Size(390, 844),
    );

    expect(find.text('timeline route'), findsWidgets);

    await tapShellDestination(tester, AppKeys.shellWeek);
    expect(find.text('week route'), findsWidgets);

    await tapShellDestination(tester, AppKeys.shellMonth);
    expect(find.text('month route'), findsWidgets);

    await openQuickAdd(tester);
    expect(find.byKey(AppKeys.quickAddTaskTab), findsOneWidget);
    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('auto schedule without confirmation exposes its detail report',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final scheduler = _MockSchedulerEngine();
    final result = _scheduleResult(
      unscheduledTaskCount: 1,
      splitSuggestedTaskCount: 2,
      unscheduledTasks: [
        const SchedulerUnscheduledTask(
          taskId: 7,
          taskSummary: 'Overflow task',
          reason: 'No open focus block',
          originalDurationMinutes: 90,
          actualWorkedMinutes: 15,
          remainingMinutes: 75,
        ),
      ],
      logEntries: const [
        SchedulerRunLogEntry(
          level: 'warning',
          message: 'No slot was available',
          taskId: 7,
          taskSummary: 'Overflow task',
        ),
      ],
    );
    when(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        until: any(named: 'until'),
        trigger: any(named: 'trigger'),
      ),
    ).thenAnswer((_) async => result);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(1300, 900),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        schedulerEngineProvider.overrideWithValue(scheduler),
      ],
    );

    await tester.tap(find.byIcon(Icons.auto_awesome));
    await pumpQuickAddFrames(tester);
    await tester.tap(find.byType(SimpleDialogOption).first);
    await pumpQuickAddFrames(tester);

    verify(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        until: any(named: 'until'),
        trigger: 'manual_range_reschedule',
      ),
    ).called(1);
    expect(find.textContaining('Overflow task'), findsNothing);

    await tester.tap(find.text('详情'));
    await pumpQuickAddFrames(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Overflow'), findsWidgets);
    expect(find.textContaining('2 个可拆分任务'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsWidgets);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('quick add keeps the sheet open and reports create failures',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureTaskList(db, name: 'Failure tasks');
    final failingStore = _FailingTaskEventStore();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(900, 1000),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        taskEventServerFirstStoreProvider
            .overrideWith((ref) async => failingStore),
      ],
    );

    await openQuickAdd(tester);
    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Failing quick task',
    );
    await tapQuickAddReachable(tester, find.byKey(AppKeys.taskSaveButton));
    await pumpQuickAddFrames(tester);

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.textContaining('calendar worker failure'), findsOneWidget);
    expect(failingStore.createdTasks, isEmpty);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('quick add task dropdowns are written into the create payload',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureTaskList(db, name: 'Dropdown tasks');
    final fakeStore = FakeTaskEventServerFirstStore();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(900, 1000),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        taskEventServerFirstStoreProvider
            .overrideWith((ref) async => fakeStore),
      ],
    );

    await openQuickAdd(tester);
    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Dropdown configured task',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: find.byType(DropdownButtonFormField<int>).first,
      valueFragment: '30',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: find.byType(DropdownButtonFormField<int>).last,
      valueFragment: '1',
    );

    await tapQuickAddReachable(tester, find.byKey(AppKeys.taskSaveButton));
    await pumpQuickAddUntil(
      tester,
      () => fakeStore.createdTasks.isNotEmpty,
      reason: 'task create should include changed dropdown values',
    );

    expect(
        fakeStore.createdTasks.single['summary'], 'Dropdown configured task');
    expect(fakeStore.createdTasks.single['durationMinutes'], 30);
    expect(fakeStore.createdTasks.single['priorityLocal'], 1);

    await waitForQuickAddClosed(tester);
    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('quick add event pickers update selected date and payload',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Picker calendar');
    final fakeStore = FakeTaskEventServerFirstStore();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(900, 1000),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        taskEventServerFirstStoreProvider
            .overrideWith((ref) async => fakeStore),
      ],
    );

    await openQuickAdd(tester);
    await tapQuickAddEventTab(tester);
    await tester.enterText(
      find.byKey(AppKeys.eventSummaryField),
      'Picked calendar time',
    );

    final startPicker = find.byWidgetPredicate(
      (widget) =>
          widget is InputDecorator && widget.decoration.labelText == '开始',
    );
    await Scrollable.ensureVisible(
      startPicker.evaluate().single,
      alignment: 0.55,
      duration: Duration.zero,
    );
    await pumpQuickAddFrames(tester);
    await tester.tapAt(tester.getCenter(startPicker));
    await pumpQuickAddFrames(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15').last);
    await pumpQuickAddFrames(tester);
    await tester.tap(find.byType(TextButton).last);
    await pumpQuickAddFrames(tester);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byType(TextButton).last);
    await pumpQuickAddFrames(tester);

    await tapQuickAddReachable(tester, find.byKey(AppKeys.eventSaveButton));
    await pumpQuickAddUntil(
      tester,
      () => fakeStore.createdEvents.isNotEmpty,
      reason: 'event create should include the picked start time',
    );

    final startAt =
        DateTime.parse(fakeStore.createdEvents.single['startAt']! as String);
    final endAt =
        DateTime.parse(fakeStore.createdEvents.single['endAt']! as String);
    expect(startAt.day, 15);
    expect(endAt, startAt.add(const Duration(hours: 1)));
    expect(_selectedDate(tester), DateTime(startAt.year, startAt.month, 15));

    await waitForQuickAddClosed(tester);
    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('desktop sidebar toggles calendar and task list visibility',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'Sidebar calendar',
    );
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Sidebar tasks',
    );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(1300, 900),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
      ],
    );
    await pumpQuickAddFrames(tester);

    expect(find.text('Sidebar calendar'), findsOneWidget);
    expect(find.textContaining('Sidebar tasks'), findsOneWidget);

    await tester.tap(find.text('Sidebar calendar'));
    await pumpQuickAddFrames(tester);
    await tester.tap(find.textContaining('Sidebar tasks'));
    await pumpQuickAddFrames(tester);

    final calendar = await (db.select(db.eventCalendars)
          ..where((row) => row.id.equals(calendarId)))
        .getSingle();
    final taskList = await (db.select(db.taskLists)
          ..where((row) => row.id.equals(taskListId)))
        .getSingle();
    expect(calendar.isVisible, isFalse);
    expect(taskList.isVisible, isFalse);

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable().last);
    await pumpQuickAddFrames(tester);
    expect(find.byType(CalendarBooksPage), findsOneWidget);

    await disposeCurrentQuickAddApp(tester);
  });
}

DateTime _selectedDate(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byKey(AppKeys.shellCreateTask)),
  ).read(selectedDateProvider);
}

SchedulerRunResult _scheduleResult({
  int unscheduledTaskCount = 0,
  int splitSuggestedTaskCount = 0,
  List<SchedulerUnscheduledTask> unscheduledTasks =
      const <SchedulerUnscheduledTask>[],
  List<SchedulerRunLogEntry> logEntries = const <SchedulerRunLogEntry>[],
}) {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 8),
    planRunId: 'worker-calendar-run',
    trigger: 'manual_range_reschedule',
    effectiveStart: DateTime(2026, 6, 8, 9),
    effectiveEnd: DateTime(2026, 6, 8, 18),
    scheduledTaskCount: 0,
    rescheduledTaskCount: 0,
    clearedTaskCount: 0,
    unscheduledTaskCount: unscheduledTaskCount,
    splitSuggestedTaskCount: splitSuggestedTaskCount,
    evidenceCompletedTaskCount: 0,
    placements: const <SchedulerTaskPlacement>[],
    clearedTaskIds: const <int>[],
    unscheduledTasks: unscheduledTasks,
    logEntries: logEntries,
    context: SchedulerContextSnapshot(
      date: DateTime(2026, 6, 8),
      effectiveStart: DateTime(2026, 6, 8, 9),
      effectiveEnd: DateTime(2026, 6, 8, 18),
      fixedBlockCount: 0,
      confirmedActualCount: 0,
      taskEvidence: const <SchedulerTaskEvidence>[],
      deviationReason: null,
      usesWeatherContext: false,
      usesLocationContext: false,
      usesFileContext: false,
    ),
  );
}
