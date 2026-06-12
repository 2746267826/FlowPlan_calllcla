import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/scheduler/plan_feedback_service.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

class _MockSchedulerEngine extends Mock implements SchedulerEngine {}

class _MockPlanFeedbackService extends Mock implements PlanFeedbackService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 8));
    registerFallbackValue(const PlanDeviationSnapshot.none());
    registerFallbackValue(_scheduleResult());
  });

  testWidgets('plan deviation prompt can be snoozed without scheduling',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final feedback = _MockPlanFeedbackService();
    final scheduler = _MockSchedulerEngine();
    final decisions = <String>[];
    when(() => feedback.evaluateNow())
        .thenAnswer((_) async => const PlanDeviationSnapshot.none());
    when(
      () => feedback.markDecision(
        any(),
        decision: any(named: 'decision'),
      ),
    ).thenAnswer((invocation) async {
      decisions.add(invocation.namedArguments[#decision]! as String);
    });

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

    expect(find.text('检测到计划偏离'), findsOneWidget);

    await tester.tap(find.text('暂不处理'));
    await pumpQuickAddFrames(tester);

    expect(decisions, ['snoozed']);
    verifyNever(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        until: any(named: 'until'),
        forceMovableTaskIds: any(named: 'forceMovableTaskIds'),
        trigger: any(named: 'trigger'),
      ),
    );

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('plan deviation confirmation shows report and applies draft',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final feedback = _MockPlanFeedbackService();
    final scheduler = _MockSchedulerEngine();
    final result = _scheduleResult(scheduledTaskCount: 1);
    final decisions = <String>[];
    when(() => feedback.evaluateNow())
        .thenAnswer((_) async => const PlanDeviationSnapshot.none());
    when(
      () => feedback.markDecision(
        any(),
        decision: any(named: 'decision'),
      ),
    ).thenAnswer((invocation) async {
      decisions.add(invocation.namedArguments[#decision]! as String);
    });
    when(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        forceMovableTaskIds: any(named: 'forceMovableTaskIds'),
        trigger: any(named: 'trigger'),
      ),
    ).thenAnswer((_) async => result);
    when(() => scheduler.applyRunResult(any())).thenAnswer((_) async {});

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

    expect(decisions, ['accepted']);
    verify(
      () => scheduler.autoScheduleDetailed(
        DateTime(2026, 6, 8, 9),
        from: any(named: 'from'),
        forceMovableTaskIds: {42},
        trigger: 'plan_deviation_confirmed',
      ),
    ).called(1);
    expect(find.text('确认应用重排预案'), findsOneWidget);
    expect(find.textContaining('Moved from deviation'), findsWidgets);

    await tester.tap(find.text('确认应用'));
    await pumpQuickAddFrames(tester);

    verify(() => scheduler.applyRunResult(result)).called(1);
    expect(find.byType(SnackBar), findsOneWidget);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('tablet shell keeps quick add but omits desktop side lists',
      (tester) async {
    await pumpShellNavigationHarness(
      tester,
      size: const Size(900, 900),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(AppKeys.shellCreateTask), findsOneWidget);
    expect(find.text('日历'), findsNothing);
    expect(find.text('任务清单'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await disposeCurrentQuickAddApp(tester);
  });
}

PlanDeviationSnapshot _deviationSnapshot() {
  final start = DateTime(2026, 6, 8, 9);
  final task = TaskItem(
    id: 42,
    uid: 'deviation-task',
    dtstamp: start,
    summary: 'Planned focus task',
    priority: 0,
    status: 'needsAction',
    percentComplete: 0,
    categories: '',
    durationMinutes: 60,
    isSplittable: true,
    priorityLocal: 2,
    isAutoScheduled: true,
    isLocked: false,
    reminderMinutesBefore: 0,
  );
  final record = ActivityRecord(
    id: 77,
    startTime: start.add(const Duration(minutes: 30)),
    durationMinutes: 15,
    keyCount: 12,
    mouseClicks: 3,
    mouseMovePx: 100,
    scrollPx: 20,
    manualLabel: 'Unplanned browsing',
    processName: 'browser.exe',
    category: 'research',
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
      label: 'Unplanned browsing',
      category: record.category,
      processName: record.processName,
      packageName: record.packageName,
      linkedTaskId: record.linkedTaskId,
    ),
    reason: 'Activity is not linked to the planned task',
    promptKey: '42:${start.toIso8601String()}:77',
    shouldPrompt: true,
  );
}

SchedulerRunResult _scheduleResult({
  int scheduledTaskCount = 0,
}) {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 8),
    planRunId: 'deviation-run',
    trigger: 'plan_deviation_confirmed',
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
          taskId: 42,
          taskSummary: 'Moved from deviation',
          wasRescheduled: true,
          isSplit: false,
          originalDurationMinutes: 60,
          actualWorkedMinutes: 15,
          remainingMinutes: 45,
          reason: 'Plan deviation confirmed',
          requiredConfirmation: true,
          segments: [
            SchedulerTaskSegmentPlan(
              start: DateTime(2026, 6, 8, 10),
              end: DateTime(2026, 6, 8, 10, 45),
            ),
          ],
        ),
    ],
    clearedTaskIds: const <int>[],
    unscheduledTasks: const <SchedulerUnscheduledTask>[],
    logEntries: const [
      SchedulerRunLogEntry(
        level: 'success',
        message: 'Deviation draft ready',
        taskId: 42,
        taskSummary: 'Moved from deviation',
      ),
    ],
    context: SchedulerContextSnapshot(
      date: DateTime(2026, 6, 8),
      effectiveStart: DateTime(2026, 6, 8, 9),
      effectiveEnd: DateTime(2026, 6, 8, 18),
      fixedBlockCount: 0,
      confirmedActualCount: 1,
      taskEvidence: const <SchedulerTaskEvidence>[],
      deviationReason: 'Activity is not linked to the planned task',
      usesWeatherContext: false,
      usesLocationContext: false,
      usesFileContext: false,
    ),
  );
}
