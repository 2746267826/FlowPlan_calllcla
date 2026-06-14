import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/widgets/task_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/task_detail_workflow_harness.dart'
    show writableOnlinePrimaryPolicy;
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('loading and error async branches keep timeline chrome usable',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await _pumpTimeline(
      tester,
      db: db,
      overrides: [
        tasksForSelectedDateProvider.overrideWith(
          (ref) => const Stream<List<TaskItem>>.empty(),
        ),
        eventsForSelectedDateProvider.overrideWith(
          (ref) => Stream<List<CalendarEvent>>.error(StateError('events down')),
        ),
        taskScheduleSegmentsForSelectedDateProvider.overrideWith(
          (ref) => Stream<List<TaskScheduleSegmentWithTask>>.error(
            StateError('segments down'),
          ),
        ),
        activityRecordsForDateProvider.overrideWith(
          (ref) =>
              Future<List<ActivityRecord>>.error(StateError('records down')),
        ),
      ],
    );

    expect(find.text('计划'), findsOneWidget);
    expect(find.text('实际'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.byType(TaskBlock), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date strip and header controls update selected day',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final selected = DateTime(2026, 6, 10);

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: selected,
      size: const Size(620, 860),
    );

    expect(_selectedDate(tester), selected);
    expect(find.text('6/10 星期三'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);

    await tester.tap(find.text('11').last);
    await tester.pump();
    expect(_selectedDate(tester), DateTime(2026, 6, 11));
    expect(find.text('6/11 星期四'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(_selectedDate(tester), selected);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(_selectedDate(tester), DateTime(2026, 6, 11));
  });

  testWidgets('cards expose actions and timeline block properties',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = DateTime(2026, 6, 10);
    final visibleHour = _visibleHour();
    final event = _event(
      id: 201,
      summary: 'Timeline design review',
      start: _at(day, visibleHour),
      end: _at(day, visibleHour + 1, 30),
      colorHex: '#123456',
      location: 'Room A',
    );
    final task = _task(
      id: 301,
      summary: 'Timeline focus task',
      start: _at(day, visibleHour + 1),
      durationMinutes: 45,
      priorityLocal: 1,
    );
    final segmentedTask = _task(
      id: 302,
      summary: 'Split timeline task',
      start: _at(day, visibleHour + 2),
      durationMinutes: 90,
      priorityLocal: 3,
    );
    final segment = TaskScheduleSegmentWithTask(
      task: segmentedTask,
      segment: _segment(
        id: 401,
        taskId: segmentedTask.id,
        index: 1,
        start: _at(day, visibleHour + 3),
        end: _at(day, visibleHour + 3, 30),
      ),
    );

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: day,
      size: const Size(980, 900),
      tasks: [task, segmentedTask],
      events: [event],
      segments: [segment],
    );

    final eventBlock = tester
        .widget<TaskBlock>(find.byKey(const ValueKey('timeline_event_201')));
    expect(eventBlock.color, const Color(0xFF123456));
    expect(eventBlock.durationText, allOf(contains('1'), contains('30')));
    expect(eventBlock.location, 'Room A');

    final taskBlock = _blockWithLabel(tester, 'Timeline focus task');
    expect(taskBlock.color, const Color(0xFFE53935));
    expect(taskBlock.durationText, contains('45'));
    expect(taskBlock.isDraggable, isTrue);

    expect(find.text('Split timeline task'), findsNothing);
    expect(find.text('Split timeline task (2)'), findsOneWidget);
    final segmentBlock = tester.widget<TaskBlock>(
      find.byKey(const ValueKey('timeline_task_segment_401')),
    );
    expect(segmentBlock.color, const Color(0xFF43A047));
    expect(segmentBlock.isDraggable, isFalse);
    expect(segmentBlock.onTap, isNotNull);
  });

  testWidgets(
      'external task drop shows hover preview and records confirmed write',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final day = DateTime(2026, 6, 10);
    final droppedTask = _task(
      id: 501,
      summary: 'Dropped task',
      start: null,
      durationMinutes: 0,
    );

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: day,
      size: const Size(900, 900),
      fakeStore: fakeStore,
      overlay: Positioned(
        top: 96,
        right: 24,
        child: Draggable<TaskItem>(
          data: droppedTask,
          feedback: const Material(child: Text('Dropped task feedback')),
          childWhenDragging: const Text('Dragging dropped task'),
          child: const Text('Drop me'),
        ),
      ),
    );

    final targetFinder = find.byWidgetPredicate(
      (widget) => widget is DragTarget<TaskItem>,
    );
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);
    final targetOffset = tester.getRect(targetFinder).center;

    target.onMove?.call(
      DragTargetDetails<TaskItem>(data: droppedTask, offset: targetOffset),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IgnorePointer && widget.ignoring,
      ),
      findsOneWidget,
    );

    target.onAcceptWithDetails?.call(
      DragTargetDetails<TaskItem>(data: droppedTask, offset: targetOffset),
    );
    await _pumpUntilFound(tester, find.text('确认安排任务'));
    expect(find.textContaining('Dropped task'), findsWidgets);

    await tester.tap(find.text('确认'));
    await _pumpUntil(tester, () => fakeStore.updatedTasks.isNotEmpty);

    expect(fakeStore.updatedTasks.single.localId, 501);
    expect(fakeStore.updatedTasks.single.payload['dtstart'], isA<String>());
    expect(fakeStore.updatedTasks.single.changedFields, contains('dtstart'));

    final actions = await _operationLogActions(db);
    expect(actions, contains('manual_schedule_task'));
    expect(actions, contains('replace_task_schedule_segments'));
  });

  testWidgets('cancelled drag confirmation does not call fake store',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final day = DateTime(2026, 6, 10);
    final visibleHour = _visibleHour();

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: day,
      size: const Size(620, 900),
      fakeStore: fakeStore,
      tasks: [
        _task(
          id: 601,
          summary: 'Cancel move task',
          start: _at(day, visibleHour),
        ),
      ],
    );

    await tester.drag(find.text('Cancel move task'), const Offset(0, 80));
    await _pumpUntilFound(tester, find.text('确认移动任务'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(fakeStore.updatedTasks, isEmpty);
    expect(await _operationLogActions(db), isEmpty);
  });

  testWidgets(
      'actual column renders tracker evidence labels and category colors',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = DateTime(2026, 6, 10);

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: day,
      records: [
        _record(
          id: 701,
          label: 'Manual office evidence',
          category: '办公',
          start: _at(day, 8),
          end: _at(day, 8, 30),
        ),
        _record(
          id: 702,
          label: null,
          category: '设计',
          processName: 'DesignApp',
          start: _at(day, 9),
          end: _at(day, 9, 30),
        ),
        _record(
          id: 703,
          label: null,
          category: null,
          processName: 'Browser.exe',
          start: _at(day, 10),
          end: _at(day, 10, 30),
        ),
        _record(
          id: 704,
          label: 'Tiny hidden evidence',
          category: '游戏',
          start: _at(day, 11),
          end: _at(day, 11),
        ),
      ],
    );

    expect(find.text('Manual office evidence'), findsOneWidget);
    expect(find.text('设计'), findsOneWidget);
    expect(find.text('Browser.exe'), findsOneWidget);
    expect(find.text('Tiny hidden evidence'), findsNothing);

    final officeText = tester.widget<Text>(find.text('Manual office evidence'));
    expect(officeText.style?.color, const Color(0xFF0EA8A0));
    final designText = tester.widget<Text>(find.text('设计'));
    expect(designText.style?.color, const Color(0xFFE91E63));
    final browserText = tester.widget<Text>(find.text('Browser.exe'));
    expect(browserText.style?.color, Colors.blueGrey);
  });
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  DateTime? selectedDate,
  Size size = const Size(420, 820),
  List<TaskItem> tasks = const <TaskItem>[],
  List<CalendarEvent> events = const <CalendarEvent>[],
  List<TaskScheduleSegmentWithTask> segments =
      const <TaskScheduleSegmentWithTask>[],
  List<ActivityRecord> records = const <ActivityRecord>[],
  FakeTaskEventServerFirstStore? fakeStore,
  List<Override> overrides = const <Override>[],
  Widget? overlay,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: [
      GoRoute(
        path: AppRoutes.timeline,
        builder: (context, state) => overlay == null
            ? const TimelineView()
            : Stack(
                children: [
                  const TimelineView(),
                  overlay,
                ],
              ),
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
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

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
        (ref) => Stream<List<TaskScheduleSegmentWithTask>>.value(segments),
      ),
      activityRecordsForDateProvider.overrideWith((ref) async => records),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => fakeStore ?? FakeTaskEventServerFirstStore(),
      ),
      onlinePrimaryPolicyProvider.overrideWith(
        (ref) => writableOnlinePrimaryPolicy,
      ),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  if (selectedDate != null) {
    final dynamic notifier =
        _container(tester).read(selectedDateProvider.notifier);
    notifier.setDate(selectedDate);
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 700));
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(TimelineView)));
}

DateTime _selectedDate(WidgetTester tester) {
  return _container(tester).read(selectedDateProvider);
}

TaskBlock _blockWithLabel(WidgetTester tester, String label) {
  return tester.widget<TaskBlock>(
    find.ancestor(of: find.text(label), matching: find.byType(TaskBlock)),
  );
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
    dtstamp: DateTime(2026, 6, 10),
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
    dtstamp: DateTime(2026, 6, 10),
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
  required int index,
  required DateTime start,
  required DateTime end,
}) {
  return TaskScheduleSegment(
    id: id,
    taskId: taskId,
    segmentIndex: index,
    startAt: start,
    endAt: end,
    source: 'server',
    planRunId: 'plan-1',
    note: 'split',
    createdAt: DateTime(2026, 6, 10),
    updatedAt: DateTime(2026, 6, 10),
  );
}

ActivityRecord _record({
  required int id,
  required String? label,
  required DateTime start,
  required DateTime? end,
  String? category,
  String? processName,
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
    processName: processName,
    windowTitle: null,
    packageName: null,
    category: category,
    appUsageRuleId: null,
    linkedTaskId: null,
    isAuto: false,
    source: 'manual',
  );
}

DateTime _at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

int _visibleHour() => DateTime.now().hour.clamp(2, 20).toInt();

Future<List<String>> _operationLogActions(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT action FROM data_operation_logs ORDER BY id ASC',
      )
      .get();
  return rows.map((row) => row.read<String>('action')).toList();
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

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}
