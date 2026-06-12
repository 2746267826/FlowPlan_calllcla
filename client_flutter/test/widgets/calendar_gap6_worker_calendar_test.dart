import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/server_first/task_event_server_first_store.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_shell.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  tearDown(() {
    CalendarBooksPage.debugTreatOutlookTaskMirrorsAsServerManaged = true;
    CalendarBooksPage.debugLoadOutlookConfig = OutlookAuthService.loadConfig;
    CalendarBooksPage.debugEnsureOutlookTaskListMirrorBinding =
        _defaultFailingOutlookBinding;
  });

  testWidgets(
      'task list Outlook binding flow reports disabled, missing config, success and failure',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureTaskList(db, name: 'Outlook bind tasks');

    await _pumpBooksPage(tester, db);

    await _selectTaskListMenuValue(tester, 'bind_outlook');
    await tester.pump();
    expect(find.textContaining('Outlook 任务镜像写回已下线'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    CalendarBooksPage.debugTreatOutlookTaskMirrorsAsServerManaged = false;
    CalendarBooksPage.debugLoadOutlookConfig = () async => null;
    await _selectTaskListMenuValue(tester, 'bind_outlook');
    await tester.pump();
    expect(find.textContaining('OAuth'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    CalendarBooksPage.debugLoadOutlookConfig =
        () async => const OutlookConfig(clientId: 'gap6-client');
    CalendarBooksPage.debugEnsureOutlookTaskListMirrorBinding =
        (taskList, config, bindingsRepository) async => OutlookTaskListBinding(
              localTaskListId: taskList.id,
              remoteCalendarId: 'remote-gap6',
              remoteCalendarName: 'Gap6 remote tasks',
              linkedAt: DateTime.utc(2026, 6, 8),
            );
    await _selectTaskListMenuValue(tester, 'bind_outlook');
    await tester.pump();
    expect(find.textContaining('Gap6 remote tasks'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    CalendarBooksPage.debugEnsureOutlookTaskListMirrorBinding =
        (taskList, config, bindingsRepository) async {
      throw StateError('gap6 bind failed');
    };
    await _selectTaskListMenuValue(tester, 'bind_outlook');
    await tester.pump();
    expect(find.textContaining('gap6 bind failed'), findsOneWidget);
  });

  testWidgets(
      'quick add event end picker updates payload and mobile full editor navigates',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Gap6 calendar');
    final fakeStore = FakeTaskEventServerFirstStore();

    await _pumpShell(
      tester,
      db: db,
      size: const Size(390, 844),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        taskEventServerFirstStoreProvider
            .overrideWith((ref) async => fakeStore),
      ],
    );

    await openQuickAdd(tester);
    await tapQuickAddEventTab(tester);
    await tester.enterText(
        find.byKey(AppKeys.eventSummaryField), 'Gap6 end picker event');
    await _tapInputDecorator(tester, '结束');
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byType(TextButton).last);
    await pumpQuickAddFrames(tester);

    await tapQuickAddReachable(tester, find.byKey(AppKeys.eventSaveButton));
    await pumpQuickAddUntil(
      tester,
      () => fakeStore.createdEvents.isNotEmpty,
      reason: 'event create should use picked end time',
    );
    expect(
      DateTime.parse(fakeStore.createdEvents.single['endAt']! as String).day,
      15,
    );
    await waitForQuickAddClosed(tester);

    await openQuickAdd(tester);
    await tapQuickAddEventTab(tester);
    await tapQuickAddReachable(tester, find.text('更多设置'));
    await tester.pumpAndSettle();
    expect(find.text('event create route'), findsOneWidget);
    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('timeline hover overlay is reachable', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = DateTime(2026, 6, 10);
    final visibleHour = DateTime.now().hour.clamp(2, 20).toInt();
    final task = _task(
      id: 71,
      summary: 'Gap6 desktop task',
      start: DateTime(2026, 6, 10, visibleHour),
    );
    final event = _event(
      id: 81,
      summary: 'Gap6 desktop event',
      start: DateTime(2026, 6, 10, visibleHour + 1),
    );

    await _pumpTimeline(
      tester,
      db: db,
      selectedDate: day,
      size: const Size(980, 900),
      tasks: [task],
      events: [event],
    );

    final targetFinder =
        find.byWidgetPredicate((widget) => widget is DragTarget<TaskItem>);
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);
    target.onMove?.call(
      DragTargetDetails<TaskItem>(
        data: _task(
          id: 91,
          summary: 'Hover task',
          start: DateTime(2026, 6, 10, 11),
        ),
        offset: tester.getRect(targetFinder).center,
      ),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Container && widget.color != null,
      ),
      findsWidgets,
    );
    target.onLeave?.call(_task(
      id: 91,
      summary: 'Hover task',
      start: DateTime(2026, 6, 10, visibleHour + 2),
    ));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 2);
  });
}

Future<OutlookTaskListBinding> _defaultFailingOutlookBinding(
  TaskList taskList,
  OutlookConfig config,
  OutlookSyncBindingsRepository bindingsRepository,
) {
  throw StateError('default test hook should be replaced by production setup');
}

class FakeLocalServerWrite {
  const FakeLocalServerWrite({
    required this.localId,
    required this.payload,
    this.changedFields,
  });

  final int localId;
  final Map<String, Object?> payload;
  final List<String>? changedFields;
}

class FakeTaskEventServerFirstStore implements TaskEventServerFirstStore {
  final createdEvents = <Map<String, Object?>>[];
  final updatedTasks = <FakeLocalServerWrite>[];

  @override
  Future<Map<String, dynamic>> tasks({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> events({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload,
  ) async {
    return _canonical('task', 1, payload);
  }

  @override
  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload,
  ) async {
    createdEvents.add(Map<String, Object?>.from(payload));
    return _canonical('event', createdEvents.length, payload);
  }

  @override
  Future<ServerFirstWriteResult> updateLocalTask({
    required int localId,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    updatedTasks.add(
      FakeLocalServerWrite(
        localId: localId,
        payload: Map<String, Object?>.from(patch),
        changedFields: changedFields,
      ),
    );
    return _canonical('task', localId, patch);
  }

  ServerFirstWriteResult _canonical(
    String type,
    Object id,
    Map<String, Object?> payload,
  ) {
    return ServerFirstWriteResult.canonical(
      <String, dynamic>{
        'serverVersion': 1,
        'item': <String, dynamic>{
          'id': '$type-$id',
          'uid': payload['uid'],
          'payload': payload,
        },
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDatabase db,
  required Size size,
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
            builder: (context, state) => const Text('timeline route'),
          ),
          GoRoute(
            path: AppRoutes.eventCreate,
            builder: (context, state) => const Text('event create route'),
          ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    router.dispose();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> _pumpBooksPage(WidgetTester tester, AppDatabase db) async {
  final repository = CalendarBooksRepository(db);
  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 900),
    overrides: [
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream<List<EventCalendar>>.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) =>
            Stream<List<TaskList>>.fromFuture(repository.getAllTaskLists()),
      ),
      archivedTaskListsProvider.overrideWith(
        (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
      ),
      outlookTaskListBindingsProvider.overrideWith((ref) async => const {}),
    ],
    child: const MaterialApp(home: CalendarBooksPage()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _selectTaskListMenuValue(WidgetTester tester, String value) async {
  final menuButton =
      find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>);
  await tester.tap(menuButton.last);
  await tester.pumpAndSettle();
  final item = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == value,
  );
  expect(item, findsOneWidget);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _tapInputDecorator(WidgetTester tester, String labelText) async {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is InputDecorator && widget.decoration.labelText == labelText,
  );
  await Scrollable.ensureVisible(finder.evaluate().single);
  await tester.pump();
  await tester.tapAt(tester.getCenter(finder));
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  required DateTime selectedDate,
  required Size size,
  required List<TaskItem> tasks,
  required List<CalendarEvent> events,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: [
      GoRoute(
          path: AppRoutes.timeline,
          builder: (context, state) => const TimelineView()),
      GoRoute(
          path: AppRoutes.eventDetail,
          builder: (context, state) => const Text('event route')),
      GoRoute(
          path: AppRoutes.taskDetail,
          builder: (context, state) => const Text('task route')),
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
      tasksForSelectedDateProvider
          .overrideWith((ref) => Stream<List<TaskItem>>.value(tasks)),
      eventsForSelectedDateProvider
          .overrideWith((ref) => Stream<List<CalendarEvent>>.value(events)),
      taskScheduleSegmentsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskScheduleSegmentWithTask>>.value(
          const <TaskScheduleSegmentWithTask>[],
        ),
      ),
      activityRecordsForDateProvider
          .overrideWith((ref) async => const <ActivityRecord>[]),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => FakeTaskEventServerFirstStore(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  final dynamic notifier =
      ProviderScope.containerOf(tester.element(find.byType(TimelineView)))
          .read(selectedDateProvider.notifier);
  notifier.setDate(selectedDate);
  await tester.pump(const Duration(milliseconds: 700));
}

TaskItem _task({
  required int id,
  required String summary,
  required DateTime start,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
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
    durationMinutes: 45,
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
    uid: 'event-$id',
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
