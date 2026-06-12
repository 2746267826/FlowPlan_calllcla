import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/widgets/task_block.dart';
import 'package:flowplanv2/shared/widgets/time_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('renders empty timeline chrome and current time indicator',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(360, 760),
    );

    expect(find.text('\u8ba1\u5212'), findsOneWidget);
    expect(find.text('\u5b9e\u9645'), findsOneWidget);
    expect(find.byType(TimeIndicator), findsOneWidget);
    expect(find.byType(TaskBlock), findsNothing);
    expect(find.text('09:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out overlapping, segmented, actual, and overnight items',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final today = _today();
    final splitTask = _task(
      id: 30,
      summary: 'Split task',
      start: _at(today, 12),
      durationMinutes: 90,
    );

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(480, 900),
      tasks: [
        _task(
          id: 10,
          summary: 'Focus task',
          start: _at(today, 9),
          durationMinutes: 75,
          priorityLocal: 1,
        ),
        splitTask,
        _task(
          id: 40,
          summary: 'Unscheduled task',
          start: null,
        ),
      ],
      events: [
        _event(
          id: 20,
          summary: 'Overlap event A',
          start: _at(today, 9, 30),
          end: _at(today, 10, 30),
          colorHex: '#123456',
        ),
        _event(
          id: 21,
          summary: 'Overlap event B',
          start: _at(today, 9, 45),
          end: _at(today, 10, 15),
          source: 'outlook',
          location: 'Room 2',
        ),
        _event(
          id: 22,
          summary: 'Overnight handoff',
          start: _at(today.subtract(const Duration(days: 1)), 23),
          end: _at(today, 1),
          colorHex: 'not-a-color',
        ),
      ],
      segments: [
        TaskScheduleSegmentWithTask(
          task: splitTask,
          segment: _segment(
            id: 60,
            taskId: splitTask.id,
            start: _at(today, 13),
            end: _at(today, 13, 45),
          ),
        ),
      ],
      records: [
        _record(
          id: 70,
          label: 'Actual coding',
          category: '\u7f16\u7a0b',
          start: _at(today, 11),
          end: _at(today, 11, 40),
        ),
        _record(
          id: 71,
          label: 'Open record is hidden',
          start: _at(today, 12),
          end: null,
        ),
      ],
    );

    expect(find.text('Focus task'), findsOneWidget);
    expect(find.text('Unscheduled task'), findsNothing);
    expect(find.text('Split task'), findsNothing);
    expect(find.text('Split task (1)'), findsOneWidget);
    expect(find.text('Overlap event A'), findsOneWidget);
    expect(find.text('Overlap event B'), findsOneWidget);
    expect(find.text('Overnight handoff'), findsOneWidget);
    expect(find.text('Actual coding'), findsOneWidget);
    expect(find.text('Open record is hidden'), findsNothing);
    expect(find.byType(TaskBlock), findsNWidgets(5));
  });

  testWidgets('taps task and event blocks through narrow-screen routes',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final today = _today();
    final visibleHour = _visibleHour();

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(420, 820),
      tasks: [
        _task(
          id: 101,
          summary: 'Tap task',
          start: _at(today, visibleHour + 1),
        ),
      ],
      events: [
        _event(
          id: 202,
          summary: 'Tap event',
          start: _at(today, visibleHour),
          end: _at(today, visibleHour, 45),
        ),
      ],
    );

    await tester.tap(find.text('Tap event'));
    await _pumpUntilFound(tester, find.text('event route 202'));
    expect(find.text('event route 202'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap task'));
    await _pumpUntilFound(tester, find.text('task route 101'));
    expect(find.text('task route 101'), findsOneWidget);
  });

  testWidgets('dragging and resizing blocks require confirmation callbacks',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final today = _today();
    final visibleHour = _visibleHour();

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(520, 920),
      fakeStore: fakeStore,
      tasks: [
        _task(
          id: 301,
          summary: 'Drag task',
          start: _at(today, visibleHour + 1),
          durationMinutes: 60,
        ),
      ],
      events: [
        _event(
          id: 401,
          summary: 'Drag event',
          start: _at(today, visibleHour),
          end: _at(today, visibleHour + 1),
        ),
      ],
    );

    await tester.drag(find.text('Drag event'), const Offset(0, 80));
    await _pumpUntilFound(
        tester, find.text('\u786e\u8ba4\u79fb\u52a8\u65e5\u7a0b'));
    await tester.tap(find.text('\u786e\u8ba4'));
    await _pumpUntil(tester, () => fakeStore.updatedEvents.isNotEmpty);
    await tester.pumpAndSettle();

    expect(fakeStore.updatedEvents.single.localId, 401);
    expect(
      fakeStore.updatedEvents.single.changedFields,
      containsAll(<String>['startAt', 'endAt']),
    );

    await _dragResizeHandle(tester, find.text('Drag event'));
    await _pumpUntilFound(
        tester, find.text('\u786e\u8ba4\u8c03\u6574\u65e5\u7a0b\u65f6\u957f'));
    await tester.tap(find.text('\u786e\u8ba4'));
    await _pumpUntil(tester, () => fakeStore.updatedEvents.length == 2);
    await tester.pumpAndSettle();

    expect(fakeStore.updatedEvents.last.localId, 401);
    expect(
      fakeStore.updatedEvents.last.changedFields,
      containsAll(<String>['startAt', 'endAt']),
    );

    await tester.drag(find.text('Drag task'), const Offset(0, 80));
    await _pumpUntilFound(
        tester, find.text('\u786e\u8ba4\u79fb\u52a8\u4efb\u52a1'));
    await tester.tap(find.text('\u786e\u8ba4'));
    await _pumpUntil(tester, () => fakeStore.updatedTasks.isNotEmpty);
    await tester.pumpAndSettle();

    expect(fakeStore.updatedTasks.single.localId, 301);
    expect(
      fakeStore.updatedTasks.single.changedFields,
      contains('dtstart'),
    );

    await _dragResizeHandle(tester, find.text('Drag task'));
    await _pumpUntilFound(
        tester, find.text('\u786e\u8ba4\u8c03\u6574\u4efb\u52a1\u65f6\u957f'));
    await tester.tap(find.text('\u786e\u8ba4'));
    await _pumpUntil(tester, () => fakeStore.updatedTasks.length == 2);

    expect(fakeStore.updatedTasks.last.localId, 301);
    expect(
      fakeStore.updatedTasks.last.changedFields,
      contains('durationMinutes'),
    );
  });

  testWidgets('long press currently leaves timeline blocks inert',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final today = _today();

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(420, 820),
      fakeStore: fakeStore,
      tasks: [
        _task(
          id: 501,
          summary: 'Long press task',
          start: _at(today, _visibleHour()),
        ),
      ],
    );

    await tester.longPress(find.text('Long press task'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('task route 501'), findsNothing);
    expect(fakeStore.updatedTasks, isEmpty);
  });
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  required Size size,
  List<TaskItem> tasks = const <TaskItem>[],
  List<CalendarEvent> events = const <CalendarEvent>[],
  List<TaskScheduleSegmentWithTask> segments =
      const <TaskScheduleSegmentWithTask>[],
  List<ActivityRecord> records = const <ActivityRecord>[],
  FakeTaskEventServerFirstStore? fakeStore,
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
        builder: (context, state) {
          return Text('event route ${state.pathParameters['id']}');
        },
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) {
          return Text('task route ${state.pathParameters['id']}');
        },
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
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
        (ref) => Stream<List<TaskScheduleSegmentWithTask>>.value(segments),
      ),
      activityRecordsForDateProvider.overrideWith(
        (ref) async => records,
      ),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => fakeStore ?? FakeTaskEventServerFirstStore(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

TaskItem _task({
  required int id,
  required String summary,
  DateTime? start,
  int durationMinutes = 60,
  int priorityLocal = 2,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
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
    durationMinutes: durationMinutes,
    isSplittable: false,
    priorityLocal: priorityLocal,
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
  String source = 'server',
  String colorHex = '#6B5EE4',
  String? location,
}) {
  return CalendarEvent(
    id: id,
    uid: 'event-$id',
    dtstamp: _today(),
    summary: summary,
    description: 'Notes for $summary',
    location: location,
    dtstart: start,
    dtend: end,
    rrule: null,
    status: 'CONFIRMED',
    transp: 'OPAQUE',
    source: source,
    eventCalendarId: 1,
    colorHex: colorHex,
    isBlock: false,
  );
}

TaskScheduleSegment _segment({
  required int id,
  required int taskId,
  required DateTime start,
  required DateTime end,
}) {
  return TaskScheduleSegment(
    id: id,
    taskId: taskId,
    segmentIndex: 0,
    startAt: start,
    endAt: end,
    source: 'server',
    planRunId: 'plan-1',
    note: 'split',
    createdAt: _today(),
    updatedAt: _today(),
  );
}

ActivityRecord _record({
  required int id,
  required String label,
  required DateTime start,
  required DateTime? end,
  String? category,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: end,
    durationMinutes: end == null ? 0 : end.difference(start).inMinutes,
    keyCount: 0,
    mouseClicks: 0,
    mouseMovePx: 0,
    scrollPx: 0,
    keySequence: null,
    manualLabel: label,
    processName: null,
    windowTitle: null,
    packageName: null,
    category: category,
    appUsageRuleId: null,
    linkedTaskId: null,
    isAuto: false,
    source: 'manual',
  );
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

int _visibleHour() => DateTime.now().hour.clamp(2, 21).toInt();

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 10,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 10,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

Future<void> _dragResizeHandle(WidgetTester tester, Finder labelFinder) async {
  final block = find.ancestor(
    of: labelFinder,
    matching: find.byType(TaskBlock),
  );
  expect(block, findsOneWidget);
  final resizeHandle = find.descendant(
    of: block,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector &&
          widget.onTap == null &&
          widget.onVerticalDragStart != null &&
          widget.onVerticalDragUpdate != null &&
          widget.onVerticalDragEnd != null,
    ),
  );
  expect(resizeHandle, findsOneWidget);
  final rect = tester.getRect(resizeHandle);
  await tester.dragFrom(
    rect.center,
    const Offset(0, 40),
  );
}
