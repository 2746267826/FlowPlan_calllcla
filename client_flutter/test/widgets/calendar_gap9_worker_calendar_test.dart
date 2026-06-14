import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/theme/app_theme.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_shell.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/scheduler/plan_feedback_service.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/task_detail_workflow_harness.dart'
    show writableOnlinePrimaryPolicy;
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

class _MockSchedulerEngine extends Mock implements SchedulerEngine {}

class _MockPlanFeedbackService extends Mock implements PlanFeedbackService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 12));
    registerFallbackValue(const PlanDeviationSnapshot.none());
    registerFallbackValue(_scheduleResult());
  });

  testWidgets('calendar book edit dialogs accept palette taps and cancel',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Gap9 calendar');
    await insertFixtureTaskList(db, name: 'Gap9 tasks');

    final streams = await _pumpCalendarBooks(tester, db);
    await _pumpUntilText(tester, 'Gap9 calendar');

    await _selectMenuValueForTile(tester, 'Gap9 calendar', 'edit');
    await _pumpUntilDialog(tester);
    await tester.tap(_paletteDot().last);
    await _pumpFrames(tester);
    await _cancelDialog(tester);

    await _selectMenuValueForTile(tester, 'Gap9 tasks', 'edit');
    await _pumpUntilDialog(tester);
    await tester.tap(_paletteDot().last);
    await _pumpFrames(tester);
    await _cancelDialog(tester);

    await streams.refresh(tester);
    expect(find.text('Gap9 calendar'), findsOneWidget);
    expect(find.text('Gap9 tasks'), findsOneWidget);
  });

  testWidgets('Outlook calendar books render without edit actions',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Gap9 Outlook',
            createdAt: fixtureNow(),
            source: const Value('outlook'),
            syncUrl: const Value('remote-calendar'),
          ),
        );

    await _pumpCalendarBooks(tester, db);
    await _pumpUntilText(tester, 'Gap9 Outlook');

    final tile = find.ancestor(
      of: find.text('Gap9 Outlook'),
      matching: find.byType(ListTile),
    );
    expect(tile, findsOneWidget);
    expect(
      find.descendant(
        of: tile,
        matching: find.byType(PopupMenuButton<String>),
      ),
      findsNothing,
    );
    expect(find.textContaining('Outlook'), findsWidgets);
  });

  testWidgets('future manual schedule range can be rejected without applying',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final futureDate = DateTime.now().add(const Duration(days: 7));
    final selectedDate = DateTime(
      futureDate.year,
      futureDate.month,
      futureDate.day,
    );
    final scheduler = _MockSchedulerEngine();
    final result = _scheduleResult(scheduledTaskCount: 1);
    when(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        until: any(named: 'until'),
        trigger: any(named: 'trigger'),
      ),
    ).thenAnswer((_) async => result);
    when(() => scheduler.applyRunResult(any())).thenAnswer((_) async {});

    await _pumpShell(
      tester,
      db: db,
      selectedDate: selectedDate,
      overrides: [
        schedulerEngineProvider.overrideWithValue(scheduler),
      ],
    );

    await tester.tap(find.byIcon(Icons.auto_awesome));
    await _pumpFrames(tester);
    await tester.tap(find.byType(SimpleDialogOption).first);
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await _pumpFrames(tester);

    final captured = verify(
      () => scheduler.autoScheduleDetailed(
        selectedDate,
        from: captureAny(named: 'from'),
        until: captureAny(named: 'until'),
        trigger: 'manual_range_reschedule',
      ),
    ).captured;
    expect(captured.first, selectedDate.add(const Duration(hours: 8)));
    verifyNever(() => scheduler.applyRunResult(any()));

    final logs = await _operationLogs(db);
    expect(logs, contains('scheduler_draft_decision'));
    expect(logs, contains('"decision":"rejected"'));
    await _disposeTestApp(tester);
  });

  testWidgets('plan deviation draft can be rejected from the report',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final feedback = _MockPlanFeedbackService();
    final scheduler = _MockSchedulerEngine();
    final result = _scheduleResult(scheduledTaskCount: 1);
    when(() => feedback.evaluateNow())
        .thenAnswer((_) async => const PlanDeviationSnapshot.none());
    when(
      () => feedback.markDecision(
        any(),
        decision: any(named: 'decision'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        forceMovableTaskIds: any(named: 'forceMovableTaskIds'),
        trigger: any(named: 'trigger'),
      ),
    ).thenAnswer((_) async => result);
    when(() => scheduler.applyRunResult(any())).thenAnswer((_) async {});

    await _pumpShell(
      tester,
      db: db,
      selectedDate: DateTime(2026, 6, 12),
      overrides: [
        planFeedbackServiceProvider.overrideWithValue(feedback),
        planDeviationSnapshotProvider.overrideWith(
          (ref) async => _deviationSnapshot(),
        ),
        schedulerEngineProvider.overrideWithValue(scheduler),
      ],
    );
    await _pumpFrames(tester);

    await tester.tap(find.text('生成重排预案'));
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await _pumpFrames(tester);

    verifyNever(() => scheduler.applyRunResult(any()));
    final logs = await _operationLogs(db);
    expect(logs, contains('scheduler_draft_decision'));
    expect(logs, contains('"decision":"rejected"'));
    await _disposeTestApp(tester);
  });

  testWidgets('desktop sidebar hides provider errors without losing shell',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await _pumpShell(
      tester,
      db: db,
      selectedDate: DateTime(2026, 6, 12),
      overrides: [
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream<List<EventCalendar>>.error(StateError('calendars')),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.error(StateError('tasks')),
        ),
      ],
    );

    expect(find.text('gap9 shell child'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);
    await _disposeTestApp(tester);
  });

  testWidgets('Outlook event detail remains read only for save and delete',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Gap9 Outlook',
            createdAt: fixtureNow(),
            source: const Value('outlook'),
            syncUrl: const Value('remote-gap9'),
          ),
        );
    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'gap9-outlook-event',
            dtstamp: fixtureNow(),
            summary: 'Gap9 remote event',
            dtstart: DateTime.utc(2026, 6, 12, 9),
            dtend: Value(DateTime.utc(2026, 6, 12, 10)),
            eventCalendarId: Value(calendarId),
            source: const Value('outlook'),
          ),
        );

    await _pumpEventDetail(
      tester,
      db: db,
      eventId: eventId,
      fakeStore: fakeStore,
    );
    await _pumpUntil(
      tester,
      () {
        final field = tester.widget<TextField>(
          find.byKey(AppKeys.eventSummaryField),
        );
        return field.controller?.text == 'Gap9 remote event';
      },
    );

    final saveButton = tester.widget<TextButton>(
      find.byKey(AppKeys.eventSaveButton),
    );
    expect(saveButton.onPressed, isNull);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.textContaining('Outlook'), findsWidgets);
    expect(fakeStore.updatedEvents, isEmpty);
    expect(fakeStore.deletedEventIds, isEmpty);
  });

  testWidgets('timeline hover paints the plan drop target overlay',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await _pumpTimeline(tester, db: db);

    final targetFinder =
        find.byWidgetPredicate((widget) => widget is DragTarget<TaskItem>);
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);
    target.onMove?.call(
      DragTargetDetails<TaskItem>(
        data: _task(id: 901, summary: 'Gap9 hover'),
        offset: tester.getRect(targetFinder).center,
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) {
          final decoration =
              widget is Container ? widget.decoration as BoxDecoration? : null;
          return decoration?.color == AppColors.primary.withValues(alpha: 0.15);
        },
      ),
      findsOneWidget,
    );
  });

  testWidgets('timeline drag hover paints the translucent target wash',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final hoverTask = _task(id: 902, summary: 'Gap9 translucent hover');

    await _pumpTimeline(
      tester,
      db: db,
      overlay: Positioned(
        top: 80,
        left: 24,
        child: Draggable<TaskItem>(
          data: hoverTask,
          feedback: const Material(child: Text('Gap9 drag feedback')),
          childWhenDragging: const Text('Gap9 dragging'),
          child: const Text('Gap9 drag source'),
        ),
      ),
    );

    final targetFinder =
        find.byWidgetPredicate((widget) => widget is DragTarget<TaskItem>);
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);

    await tester.pumpWidget(
      MaterialApp(
        home: target.builder(
          tester.element(targetFinder),
          <TaskItem>[hoverTask],
          const <dynamic>[],
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.color == AppColors.primary.withValues(alpha: 0.06),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDatabase db,
  required DateTime selectedDate,
  List<Override> overrides = const <Override>[],
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: [
      ShellRoute(
        builder: (context, state, child) => CalendarShell(
          currentRoute: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.timeline,
            builder: (context, state) => const Text('gap9 shell child'),
          ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await _disposeTestApp(tester);
    router.dispose();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(1300, 900),
    overrides: [
      quickAddEmptyScheduleSegmentsOverride(),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(AppKeys.shellCreateTask)),
  );
  final dynamic notifier = container.read(selectedDateProvider.notifier);
  notifier.setDate(selectedDate);
  await tester.pump();
}

Future<_CalendarBookStreams> _pumpCalendarBooks(
  WidgetTester tester,
  AppDatabase db,
) async {
  final streams = _CalendarBookStreams(db);
  addTearDown(() async {
    await _disposeTestApp(tester);
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
            (calendar) => OrderingTerm(expression: calendar.name),
          ]))
        .get());
    _taskListsController.add(await (_db.select(_db.taskLists)
          ..where((taskList) => taskList.isArchived.equals(false))
          ..orderBy([
            (taskList) => OrderingTerm(expression: taskList.name),
          ]))
        .get());
    _archivedTaskListsController.add(await (_db.select(_db.taskLists)
          ..where((taskList) => taskList.isArchived.equals(true)))
        .get());
    await tester.pump();
  }

  Future<void> close() async {
    await _eventCalendarsController.close();
    await _taskListsController.close();
    await _archivedTaskListsController.close();
  }
}

Future<void> _pumpEventDetail(
  WidgetTester tester, {
  required AppDatabase db,
  required int eventId,
  required FakeTaskEventServerFirstStore fakeStore,
}) async {
  final calendars = await db.select(db.eventCalendars).get();
  final router = GoRouter(
    initialLocation: '/event/$eventId',
    routes: [
      GoRoute(
        path: AppRoutes.timeline,
        builder: (context, state) => const Text('timeline fallback'),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return EventDetailPage(eventId: id);
        },
      ),
    ],
  );
  addTearDown(() async {
    await _disposeTestApp(tester);
    router.dispose();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 1200),
    overrides: [
      allEventCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
      taskEventServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  Widget? overlay,
}) async {
  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 860),
    overrides: [
      tasksForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskItem>>.value(const <TaskItem>[]),
      ),
      eventsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<CalendarEvent>>.value(const <CalendarEvent>[]),
      ),
      taskScheduleSegmentsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskScheduleSegmentWithTask>>.value(
          const <TaskScheduleSegmentWithTask>[],
        ),
      ),
      activityRecordsForDateProvider.overrideWith(
        (ref) async => const <ActivityRecord>[],
      ),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => FakeTaskEventServerFirstStore(),
      ),
      onlinePrimaryPolicyProvider.overrideWith(
        (ref) => writableOnlinePrimaryPolicy,
      ),
    ],
    child: MaterialApp(
      home: overlay == null
          ? const TimelineView()
          : Stack(
              children: [
                const TimelineView(),
                overlay,
              ],
            ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Finder _paletteDot() {
  return find.byWidgetPredicate((widget) {
    if (widget is! GestureDetector || widget.child is! Container) {
      return false;
    }
    final child = widget.child! as Container;
    return child.constraints ==
        const BoxConstraints.tightFor(
          width: 28,
          height: 28,
        );
  });
}

Future<void> _selectMenuValueForTile(
  WidgetTester tester,
  String tileText,
  String value,
) async {
  final tile = find.ancestor(
    of: find.text(tileText),
    matching: find.byType(ListTile),
  );
  expect(tile, findsOneWidget);
  final menuFinder = find.descendant(
    of: tile,
    matching: find.byType(PopupMenuButton<String>),
  );
  expect(menuFinder, findsOneWidget);
  final menuElement = tester.element(menuFinder);
  final menu = tester.widget<PopupMenuButton<String>>(menuFinder);
  final items = menu.itemBuilder(menuElement);
  expect(
    items.whereType<PopupMenuItem<String>>().any((item) => item.value == value),
    isTrue,
  );
  menu.onSelected?.call(value);
  await _pumpFrames(tester);
}

Future<void> _cancelDialog(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        )
        .first,
  );
  await _pumpUntilNoDialog(tester);
}

Future<void> _pumpUntilText(WidgetTester tester, String text) {
  return _pumpUntil(tester, () => find.text(text).evaluate().isNotEmpty);
}

Future<void> _pumpUntilDialog(WidgetTester tester) {
  return _pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
  );
}

Future<void> _pumpUntilNoDialog(WidgetTester tester) {
  return _pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isEmpty,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _disposeTestApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 1));
}

Future<String> _operationLogs(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT action, metadata_json FROM data_operation_logs')
      .get();
  return rows
      .map((row) => '${row.data['action']} ${row.data['metadata_json']}')
      .join('\n');
}

SchedulerRunResult _scheduleResult({
  int scheduledTaskCount = 0,
}) {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 14),
    planRunId: 'gap9-run',
    trigger: 'manual_range_reschedule',
    effectiveStart: DateTime(2026, 6, 14, 8),
    effectiveEnd: DateTime(2026, 6, 14, 18),
    scheduledTaskCount: scheduledTaskCount,
    rescheduledTaskCount: scheduledTaskCount,
    clearedTaskCount: 0,
    unscheduledTaskCount: 0,
    splitSuggestedTaskCount: 0,
    evidenceCompletedTaskCount: 0,
    placements: [
      if (scheduledTaskCount > 0)
        SchedulerTaskPlacement(
          taskId: 909,
          taskSummary: 'Gap9 scheduled task',
          wasRescheduled: true,
          isSplit: false,
          originalDurationMinutes: 60,
          actualWorkedMinutes: 0,
          remainingMinutes: 60,
          reason: 'Gap9 coverage',
          requiredConfirmation: true,
          segments: [
            SchedulerTaskSegmentPlan(
              start: DateTime(2026, 6, 14, 10),
              end: DateTime(2026, 6, 14, 11),
            ),
          ],
        ),
    ],
    clearedTaskIds: const <int>[],
    unscheduledTasks: const <SchedulerUnscheduledTask>[],
    logEntries: const [
      SchedulerRunLogEntry(
        level: 'success',
        message: 'Gap9 report row',
        taskId: 909,
        taskSummary: 'Gap9 scheduled task',
      ),
    ],
    context: SchedulerContextSnapshot(
      date: DateTime(2026, 6, 14),
      effectiveStart: DateTime(2026, 6, 14, 8),
      effectiveEnd: DateTime(2026, 6, 14, 18),
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

PlanDeviationSnapshot _deviationSnapshot() {
  final start = DateTime(2026, 6, 12, 9);
  final task = _task(id: 42, summary: 'Gap9 planned', start: start);
  final record = ActivityRecord(
    id: 77,
    startTime: start.add(const Duration(minutes: 15)),
    durationMinutes: 15,
    keyCount: 1,
    mouseClicks: 1,
    mouseMovePx: 1,
    scrollPx: 1,
    manualLabel: 'Gap9 activity',
    processName: 'editor.exe',
    category: 'work',
    linkedTaskId: null,
    isAuto: true,
    source: 'test',
  );
  return PlanDeviationSnapshot(
    detectedAt: start.add(const Duration(minutes: 20)),
    plan: PlanExecutionSnapshot(
      task: task,
      planStart: start,
      planEnd: start.add(const Duration(hours: 1)),
      source: 'schedule',
    ),
    activity: ActivityExecutionSnapshot(
      record: record,
      startedAt: record.startTime,
      label: 'Gap9 activity',
      category: record.category,
      processName: record.processName,
      packageName: record.packageName,
      linkedTaskId: record.linkedTaskId,
    ),
    reason: 'Gap9 deviation',
    promptKey: 'gap9:${start.toIso8601String()}:77',
    shouldPrompt: true,
  );
}

TaskItem _task({
  required int id,
  required String summary,
  DateTime? start,
}) {
  return TaskItem(
    id: id,
    uid: 'gap9-task-$id',
    dtstamp: DateTime(2026, 6, 12),
    summary: summary,
    description: null,
    location: null,
    dtstart: start,
    due: null,
    completed: null,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '[]',
    rrule: null,
    durationMinutes: 60,
    isSplittable: false,
    priorityLocal: 2,
    isAutoScheduled: true,
    taskListId: 1,
    tagId: null,
    isLocked: false,
    reminderMinutesBefore: 15,
  );
}
