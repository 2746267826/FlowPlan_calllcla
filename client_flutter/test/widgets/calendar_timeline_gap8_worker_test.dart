import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/core/theme/app_theme.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/scheduler/plan_feedback_service.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

class _MockPlanFeedbackService extends Mock implements PlanFeedbackService {}

class _MockSchedulerEngine extends Mock implements SchedulerEngine {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 8));
    registerFallbackValue(const PlanDeviationSnapshot.none());
    registerFallbackValue(_scheduleResult());
  });

  testWidgets('shell initializes and navigates to tracker with its keyed item',
      (tester) async {
    await pumpShellNavigationHarness(
      tester,
      size: const Size(390, 844),
    );

    await tapShellDestination(tester, AppKeys.shellTracker);

    expect(find.text('tracker route'), findsWidgets);
    expect(find.byKey(AppKeys.shellTracker), findsWidgets);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('desktop side list renders section rows and settings affordance',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Gap8 side calendar');
    await insertFixtureTaskList(db, name: 'Gap8 side tasks');

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

    expect(find.text('日历本'), findsWidgets);
    expect(find.text('任务本'), findsWidgets);
    expect(find.text('Gap8 side calendar'), findsOneWidget);
    expect(find.textContaining('Gap8 side tasks'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('auto schedule confirmation report renders log row spacing',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
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

    expect(find.text('确认应用重排预案'), findsOneWidget);
    expect(find.textContaining('Gap8 placed task'), findsWidgets);
    expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    expect(find.byType(AlertDialog), findsOneWidget);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('plan deviation without changes closes report then snacks',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final feedback = _MockPlanFeedbackService();
    final scheduler = _MockSchedulerEngine();
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
    ).thenAnswer((_) async => _scheduleResult());

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(1300, 900),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        planFeedbackServiceProvider.overrideWithValue(feedback),
        planDeviationSnapshotProvider.overrideWith(
          (ref) async => _deviationSnapshot(),
        ),
        schedulerEngineProvider.overrideWithValue(scheduler),
      ],
    );
    await pumpQuickAddFrames(tester);

    await tester.tap(find.text('生成重排预案'));
    await pumpQuickAddFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await pumpQuickAddFrames(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    verifyNever(() => scheduler.applyRunResult(any()));

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('timeline desktop taps open detail dialogs', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = _today();
    final hour = _visibleHour();

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(900, 860),
      tasks: [
        _task(
          id: 801,
          summary: 'Gap8 desktop task',
          start: _at(day, hour + 1),
        ),
      ],
      events: [
        _event(
          id: 802,
          summary: 'Gap8 desktop event',
          start: _at(day, hour),
          end: _at(day, hour, 45),
        ),
      ],
    );

    await tester.tap(find.text('Gap8 desktop event'));
    await pumpQuickAddFrames(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(EventDetailPage), findsOneWidget);

    await tester.tapAt(const Offset(12, 12));
    await pumpQuickAddFrames(tester);
    await tester.tap(find.text('Gap8 desktop task'));
    await pumpQuickAddFrames(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(TaskDetailPage), findsOneWidget);
    await _disposeTestApp(tester);
  });

  testWidgets('timeline drag target hover paints plan overlay', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(900, 860),
    );

    final targetFinder = find.byWidgetPredicate(
      (widget) => widget is DragTarget<TaskItem>,
    );
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);
    target.onMove?.call(
      DragTargetDetails<TaskItem>(
        data: _task(id: 803, summary: 'Hover task'),
        offset: tester.getRect(targetFinder).center,
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) {
          final decoration = widget is Container
              ? widget.decoration as BoxDecoration?
              : null;
          return decoration?.color ==
              AppColors.primary.withValues(alpha: 0.15);
        },
      ),
      findsOneWidget,
    );
    await _disposeTestApp(tester);
  });
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  required Size size,
  List<TaskItem> tasks = const <TaskItem>[],
  List<CalendarEvent> events = const <CalendarEvent>[],
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: [
      GoRoute(
        path: AppRoutes.timeline,
        builder: (context, state) => const TimelineView(),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) =>
            Text('event route ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) =>
            Text('task route ${state.pathParameters['id']}'),
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
    size: size,
    overrides: <Override>[
      tasksForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskItem>>.value(tasks),
      ),
      eventsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<CalendarEvent>>.value(events),
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
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _disposeTestApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 1));
}

SchedulerRunResult _scheduleResult({
  int scheduledTaskCount = 0,
}) {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 8),
    planRunId: 'gap8-run',
    trigger: 'manual_range_reschedule',
    effectiveStart: DateTime(2026, 6, 8, 9),
    effectiveEnd: DateTime(2026, 6, 8, 18),
    scheduledTaskCount: scheduledTaskCount,
    rescheduledTaskCount: scheduledTaskCount,
    clearedTaskCount: 0,
    unscheduledTaskCount: 0,
    splitSuggestedTaskCount: 0,
    evidenceCompletedTaskCount: 0,
    placements: [
      if (scheduledTaskCount > 0)
        SchedulerTaskPlacement(
          taskId: 808,
          taskSummary: 'Gap8 placed task',
          wasRescheduled: false,
          isSplit: false,
          originalDurationMinutes: 60,
          actualWorkedMinutes: 10,
          remainingMinutes: 50,
          reason: 'Gap8 coverage placement',
          requiredConfirmation: true,
          segments: [
            SchedulerTaskSegmentPlan(
              start: DateTime(2026, 6, 8, 10),
              end: DateTime(2026, 6, 8, 10, 50),
            ),
          ],
        ),
    ],
    clearedTaskIds: const <int>[],
    unscheduledTasks: const <SchedulerUnscheduledTask>[],
    logEntries: [
      SchedulerRunLogEntry(
        level: scheduledTaskCount > 0 ? 'success' : 'info',
        message: 'Gap8 report log',
        taskId: scheduledTaskCount > 0 ? 808 : null,
        taskSummary: scheduledTaskCount > 0 ? 'Gap8 placed task' : null,
      ),
    ],
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

PlanDeviationSnapshot _deviationSnapshot() {
  final start = DateTime(2026, 6, 8, 9);
  final task = _task(
    id: 42,
    summary: 'Gap8 deviation task',
    start: start,
  );
  final record = ActivityRecord(
    id: 77,
    startTime: start.add(const Duration(minutes: 30)),
    durationMinutes: 15,
    keyCount: 12,
    mouseClicks: 3,
    mouseMovePx: 100,
    scrollPx: 20,
    keySequence: null,
    manualLabel: 'Gap8 unplanned work',
    processName: 'browser.exe',
    windowTitle: null,
    packageName: null,
    category: 'research',
    appUsageRuleId: null,
    linkedTaskId: null,
    isAuto: true,
    source: 'test',
  );
  return PlanDeviationSnapshot(
    detectedAt: start.add(const Duration(minutes: 45)),
    plan: PlanExecutionSnapshot(
      task: task,
      planStart: start,
      planEnd: start.add(const Duration(hours: 1)),
      source: 'schedule',
    ),
    activity: ActivityExecutionSnapshot(
      record: record,
      startedAt: record.startTime,
      label: 'Gap8 unplanned work',
      category: record.category,
      processName: record.processName,
      packageName: record.packageName,
      linkedTaskId: record.linkedTaskId,
    ),
    reason: 'Gap8 deviation reason',
    promptKey: 'gap8:${start.toIso8601String()}:77',
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
    uid: 'gap8-task-$id',
    dtstamp: _today(),
    summary: summary,
    description: 'Notes for $summary',
    location: 'Desk',
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

CalendarEvent _event({
  required int id,
  required String summary,
  required DateTime start,
  DateTime? end,
}) {
  return CalendarEvent(
    id: id,
    uid: 'gap8-event-$id',
    dtstamp: _today(),
    summary: summary,
    description: 'Notes for $summary',
    location: null,
    dtstart: start,
    dtend: end,
    rrule: null,
    status: 'CONFIRMED',
    transp: 'OPAQUE',
    source: 'server',
    eventCalendarId: 1,
    colorHex: '#6B5EE4',
    isBlock: false,
  );
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

int _visibleHour() => DateTime.now().hour.clamp(2, 20).toInt();
