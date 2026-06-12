import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_shell.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/scheduler/plan_feedback_service.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../test_support/fixtures.dart';
import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

class _MockSchedulerEngine extends Mock implements SchedulerEngine {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 6, 12));
  });

  tearDown(() {
    CalendarBooksPage.debugTreatOutlookTaskMirrorsAsServerManaged = true;
    CalendarBooksPage.debugLoadOutlookConfig = OutlookAuthService.loadConfig;
  });

  testWidgets(
      'shell timer, future range picker and cancelled draft are covered',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final scheduler = _MockSchedulerEngine();
    final result = _scheduleResult();
    when(
      () => scheduler.autoScheduleDetailed(
        any(),
        from: any(named: 'from'),
        until: any(named: 'until'),
        trigger: any(named: 'trigger'),
      ),
    ).thenAnswer((_) async => result);

    await _pumpShell(
      tester,
      db: db,
      size: const Size(1300, 900),
      selectedDate: DateTime(2026, 6, 12),
      overrides: [
        schedulerEngineProvider.overrideWithValue(scheduler),
      ],
    );

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(AppKeys.shellCreateTask)));
    final before = container.read(planFeedbackRefreshTickProvider);
    await tester.pump(const Duration(minutes: 1));
    expect(container.read(planFeedbackRefreshTickProvider), before + 1);
    expect(find.byKey(const ValueKey<String>('flowplan.shell./gap7-extra')),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.auto_awesome));
    await _pumpFrames(tester);
    await tester.tap(find.byType(SimpleDialogOption).first);
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Unscoped warning'), findsOneWidget);

    await tester.tap(find.byType(TextButton).last);
    await _pumpFrames(tester);
    verify(
      () => scheduler.autoScheduleDetailed(
        DateTime(2026, 6, 12),
        from: any(named: 'from'),
        until: any(named: 'until'),
        trigger: 'manual_range_reschedule',
      ),
    ).called(1);
    await _disposeTestApp(tester);
  });

  testWidgets('timeline hover and wide detail dialogs are reachable',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = DateTime(2026, 6, 10);
    final task = _task(
      id: 701,
      summary: 'Gap7 wide task',
      start: DateTime(2026, 6, 10, 10),
    );
    final event = _event(
      id: 801,
      summary: 'Gap7 wide event',
      start: DateTime(2026, 6, 10, 11),
    );

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: day,
      size: const Size(980, 1300),
      tasks: [task],
      events: [event],
    );

    final targetFinder =
        find.byWidgetPredicate((widget) => widget is DragTarget<TaskItem>);
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);
    target.onMove?.call(
      DragTargetDetails<TaskItem>(
        data: _task(id: 777, summary: 'Hover gap7', start: null),
        offset: tester.getRect(targetFinder).center,
      ),
    );
    await tester.pump();
    expect(
        find.byWidgetPredicate((widget) => widget is Positioned), findsWidgets);

    await tester.ensureVisible(find.text('Gap7 wide event'));
    await tester.pump();
    await tester.tap(find.text('Gap7 wide event'));
    await _pumpFrames(tester);
    expect(find.byType(EventDetailPage), findsOneWidget);
    await tester.tap(find.byType(EventDetailPage));
    Navigator.of(tester.element(find.byType(EventDetailPage))).pop();
    await _pumpFrames(tester);

    await tester.ensureVisible(find.text('Gap7 wide task'));
    await tester.pump();
    await tester.tap(find.text('Gap7 wide task'));
    await _pumpFrames(tester);
    expect(find.byType(TaskDetailPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(TaskDetailPage))).pop();
    await _pumpFrames(tester);
    await _disposeTestApp(tester);
  });

  testWidgets('calendar books dialogs and archived menu branches are reachable',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Gap7 calendar');
    await insertFixtureTaskList(db, name: 'Gap7 tasks');
    final archivedId = await insertFixtureTaskList(db, name: 'Gap7 archived');
    await (db.update(db.taskLists)..where((row) => row.id.equals(archivedId)))
        .write(const TaskListsCompanion(isArchived: Value(true)));

    await _pumpBooksPage(tester, db);

    await _selectMenuValueForTile(tester, 'Gap7 calendar', 'edit');
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await _closeActiveDialog(tester);

    await _selectMenuValueForTile(tester, 'Gap7 tasks', 'edit');
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await _closeActiveDialog(tester);

    await _selectMenuValueForTile(tester, 'Gap7 archived', 'restore');
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await _closeActiveDialog(tester);
    await _disposeTestApp(tester);
  });

  testWidgets('Outlook read-only tile and default binding factory are covered',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Outlook gap7',
            createdAt: fixtureNow(),
            source: const Value('outlook'),
          ),
        );

    await _pumpBooksPage(tester, db);
    expect(find.text('Outlook gap7'), findsOneWidget);
    expect(find.text('Outlook（只读）'), findsOneWidget);
    final outlookTile = find.ancestor(
      of: find.text('Outlook gap7'),
      matching: find.byType(ListTile),
    );
    expect(outlookTile, findsOneWidget);
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
        matching: find.byType(PopupMenuButton<String>),
      ),
      findsNothing,
    );

    final taskList = TaskList(
      id: 88,
      name: 'Bound tasks',
      colorHex: '#0EA8A0',
      emoji: 'B',
      isVisible: true,
      isDefault: false,
      isArchived: false,
      createdAt: fixtureNow(),
    );
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: taskList.id,
        remoteCalendarId: 'remote-existing',
        remoteCalendarName: 'Existing remote',
        linkedAt: DateTime.utc(2026, 6, 11),
      ),
    );

    final binding =
        await CalendarBooksPage.debugEnsureOutlookTaskListMirrorBinding(
      taskList,
      const OutlookConfig(clientId: 'gap7-client'),
      bindingsRepository,
    );

    expect(binding.remoteCalendarName, 'Existing remote');
    await _disposeTestApp(tester);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDatabase db,
  required Size size,
  required DateTime selectedDate,
  List<Override> overrides = const <Override>[],
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: [
      ShellRoute(
        builder: (context, state, child) => CalendarShell(
          currentRoute: state.uri.path,
          debugAdditionalRoutesForKeys: const ['/gap7-extra'],
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.timeline,
            builder: (context, state) => const Text('gap7 shell child'),
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
    size: size,
    overrides: [
      quickAddEmptyScheduleSegmentsOverride(),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
      tester.element(find.byKey(AppKeys.shellCreateTask)));
  final dynamic notifier = container.read(selectedDateProvider.notifier);
  notifier.setDate(selectedDate);
  await tester.pump();
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  required DateTime selectedDate,
  required Size size,
  List<TaskItem> tasks = const <TaskItem>[],
  List<CalendarEvent> events = const <CalendarEvent>[],
}) async {
  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    overrides: [
      tasksForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskItem>>.value(tasks),
      ),
      eventsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<CalendarEvent>>.value(events),
      ),
      taskScheduleSegmentsForSelectedDateProvider.overrideWith(
        (ref) => const Stream<List<TaskScheduleSegmentWithTask>>.empty(),
      ),
      activityRecordsForDateProvider.overrideWith(
        (ref) async => const <ActivityRecord>[],
      ),
    ],
    child: const MaterialApp(home: TimelineView()),
  );
  await tester.pump();
  final dynamic notifier = ProviderScope.containerOf(
    tester.element(find.byType(TimelineView)),
  ).read(selectedDateProvider.notifier);
  notifier.setDate(selectedDate);
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _pumpBooksPage(WidgetTester tester, AppDatabase db) async {
  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(1300, 1000),
    child: const MaterialApp(home: CalendarBooksPage()),
  );
  await _pumpFrames(tester);
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

Future<void> _closeActiveDialog(WidgetTester tester) async {
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  Navigator.of(tester.element(dialog)).pop();
  await _pumpFrames(tester);
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

SchedulerRunResult _scheduleResult() {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 12),
    planRunId: 'gap7-run',
    trigger: 'manual_range_reschedule',
    effectiveStart: DateTime(2026, 6, 12, 8),
    effectiveEnd: DateTime(2026, 6, 12, 18),
    scheduledTaskCount: 1,
    rescheduledTaskCount: 0,
    clearedTaskCount: 0,
    unscheduledTaskCount: 0,
    splitSuggestedTaskCount: 0,
    evidenceCompletedTaskCount: 0,
    placements: const <SchedulerTaskPlacement>[],
    clearedTaskIds: const <int>[],
    unscheduledTasks: const <SchedulerUnscheduledTask>[],
    logEntries: const [
      SchedulerRunLogEntry(
        level: 'success',
        message: 'Unscoped warning',
      ),
    ],
    context: SchedulerContextSnapshot(
      date: DateTime(2026, 6, 12),
      effectiveStart: DateTime(2026, 6, 12, 8),
      effectiveEnd: DateTime(2026, 6, 12, 18),
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

TaskItem _task({
  required int id,
  required String summary,
  DateTime? start,
}) {
  return TaskItem(
    id: id,
    uid: 'gap7-task-$id',
    dtstamp: DateTime(2026, 6, 10),
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

CalendarEvent _event({
  required int id,
  required String summary,
  required DateTime start,
}) {
  return CalendarEvent(
    id: id,
    uid: 'gap7-event-$id',
    dtstamp: DateTime(2026, 6, 10),
    summary: summary,
    description: null,
    location: null,
    dtstart: start,
    dtend: start.add(const Duration(hours: 1)),
    rrule: null,
    status: 'CONFIRMED',
    transp: 'OPAQUE',
    source: 'server',
    eventCalendarId: 1,
    colorHex: '#6B5EE4',
    isBlock: false,
  );
}
