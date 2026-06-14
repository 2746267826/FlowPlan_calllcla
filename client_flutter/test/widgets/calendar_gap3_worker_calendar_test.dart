import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_books_page.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/features/calendar/presentation/month_view.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/task_detail_workflow_harness.dart'
    show writableOnlinePrimaryPolicy;
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

const _timelineRoute = '/timeline';
const _eventCreateRoute = '/event/create';
const _eventDetailRoute = '/event/:id';

void main() {
  group('CalendarBooksPage gap worker H', () {
    testWidgets('renders calendar and archived-list provider errors',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1000),
        overrides: [
          allEventCalendarsProvider.overrideWith(
            (ref) => Stream<List<EventCalendar>>.error(
              StateError('calendar stream failed'),
            ),
          ),
          allTaskListsProvider.overrideWith(
            (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
          ),
          archivedTaskListsProvider.overrideWith(
            (ref) => Stream<List<TaskList>>.error(
              StateError('archived stream failed'),
            ),
          ),
          outlookTaskListBindingsProvider.overrideWith(
            (ref) async => const <int, OutlookTaskListBinding>{},
          ),
        ],
        child: const MaterialApp(home: CalendarBooksPage()),
      );
      await _pumpFrames(tester);

      expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
      expect(find.textContaining('calendar stream failed'), findsOneWidget);
      expect(find.textContaining('archived stream failed'), findsOneWidget);
    });

    testWidgets(
        'handles task visibility, cancelled delete, and failed default/delete actions',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final defaultCalendarId = await insertFixtureCalendar(
        db,
        name: 'Default calendar',
      );
      final otherCalendarId = await db.into(db.eventCalendars).insert(
            EventCalendarsCompanion.insert(
              name: 'Break calendar',
              createdAt: fixtureNow().add(const Duration(minutes: 1)),
              isDefault: const Value(false),
            ),
          );
      await db.into(db.calendarEvents).insert(
            fixtureEvent(
              uid: 'default-calendar-event',
              summary: 'Default calendar event',
              calendarId: defaultCalendarId,
            ),
          );
      await insertFixtureTaskList(db, name: 'Default tasks');
      final taskListId = await db.into(db.taskLists).insert(
            TaskListsCompanion.insert(
              name: 'Break tasks',
              createdAt: fixtureNow().add(const Duration(minutes: 1)),
              isDefault: const Value(false),
            ),
          );

      await _pumpCalendarBooks(
        tester,
        db: db,
        booksRepository: _FailingCalendarBooksRepository(
          db,
          failSetDefaultEvent: true,
          failSetDefaultTask: true,
          failDeleteEvent: true,
        ),
      );
      await _pumpUntilFound(tester, find.text('Break tasks'));

      await tester.tap(
        find.descendant(
          of: _tileFor('Break tasks'),
          matching: find.byType(Switch),
        ),
      );
      await _pumpFrames(tester);
      expect((await _taskListById(db, taskListId))?.isVisible, isFalse);

      await _openTileMenu(tester, 'Break calendar');
      await _tapPopupValue(tester, 'set_default');
      await _pumpUntilFound(tester, find.byType(SnackBar));
      expect((await _calendarById(db, otherCalendarId))?.isDefault, isFalse);
      await _dismissSnackBars(tester);

      await _openTileMenu(tester, 'Break tasks');
      await _tapPopupValue(tester, 'set_default');
      await _pumpUntilFound(tester, find.byType(SnackBar));
      expect((await _taskListById(db, taskListId))?.isDefault, isFalse);
      await _dismissSnackBars(tester);

      await _openTileMenu(tester, 'Default calendar');
      await _tapPopupValue(tester, 'delete');
      await _pumpUntilDialog(tester);
      expect(find.textContaining('1'), findsWidgets);
      await _tapDialogCancel(tester);
      expect(await _calendarById(db, defaultCalendarId), isNotNull);

      await _openTileMenu(tester, 'Default calendar');
      await _tapPopupValue(tester, 'delete');
      await _confirmDialog(tester);
      await _pumpUntilFound(tester, find.byType(SnackBar));
      expect(await _calendarById(db, defaultCalendarId), isNotNull);
      await _dismissSnackBars(tester);
      await _disposeWidgetTree(tester);
    });

    testWidgets(
        'covers task list mirror impact messages and Outlook unbind outcomes',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final booksRepository = CalendarBooksRepository(db);
      final bindingsRepository = OutlookSyncBindingsRepository(db);
      final mirrorRepository = OutlookTaskMirrorRepository(db);
      await booksRepository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Fallback tasks',
          createdAt: fixtureNow(),
          isDefault: const Value(true),
        ),
        audit: false,
      );
      final staleMirrorTaskListId = await booksRepository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Stale mirror tasks',
          createdAt: fixtureNow().add(const Duration(minutes: 1)),
        ),
        audit: false,
      );
      final boundEmptyTaskListId = await booksRepository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Bound empty tasks',
          createdAt: fixtureNow().add(const Duration(minutes: 2)),
        ),
        audit: false,
      );
      final boundMirrorTaskListId = await booksRepository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Bound mirror tasks',
          createdAt: fixtureNow().add(const Duration(minutes: 3)),
        ),
        audit: false,
      );
      final staleTaskId = await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'stale-mirror-task',
              summary: 'Stale mirror task',
              taskListId: staleMirrorTaskListId,
            ),
          );
      final boundTaskId = await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'bound-mirror-task',
              summary: 'Bound mirror task',
              taskListId: boundMirrorTaskListId,
            ),
          );
      await mirrorRepository.saveTaskMirrorBinding(
        _mirrorBinding(
          taskId: staleTaskId,
          taskListId: staleMirrorTaskListId,
          remoteCalendarName: 'Old mirror',
        ),
      );
      await mirrorRepository.saveTaskMirrorBinding(
        _mirrorBinding(
          taskId: boundTaskId,
          taskListId: boundMirrorTaskListId,
          remoteCalendarName: 'Remote mirror',
        ),
      );
      await bindingsRepository.saveTaskListBinding(
        _taskListBinding(
          taskListId: boundEmptyTaskListId,
          remoteCalendarName: 'Remote empty',
        ),
      );
      await bindingsRepository.saveTaskListBinding(
        _taskListBinding(
          taskListId: boundMirrorTaskListId,
          remoteCalendarName: 'Remote mirror',
        ),
      );

      await _pumpCalendarBooks(tester, db: db);
      await _pumpUntilFound(tester, find.text('Stale mirror tasks'));

      await _openTileMenu(tester, 'Stale mirror tasks');
      await _tapPopupValue(tester, 'archive');
      await _pumpUntilDialog(tester);
      expect(find.textContaining('1'), findsWidgets);
      expect(find.textContaining('Outlook'), findsWidgets);
      await _tapDialogCancel(tester);

      await _openTileMenu(tester, 'Bound empty tasks');
      await _tapPopupValue(tester, 'archive');
      await _pumpUntilDialog(tester);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Remote empty'),
        ),
        findsOneWidget,
      );
      await _tapDialogCancel(tester);

      await _openTileMenu(tester, 'Bound empty tasks');
      await _tapPopupValue(tester, 'unbind_outlook');
      await _pumpUntilDialog(tester);
      await _tapDialogCancel(tester);
      expect(
        await bindingsRepository.getTaskListBinding(boundEmptyTaskListId),
        isNotNull,
      );

      await _openTileMenu(tester, 'Bound mirror tasks');
      await _tapPopupValue(tester, 'unbind_outlook');
      await _confirmDialog(tester);
      await _pumpUntilFound(tester, find.byType(SnackBar));
      expect(
        await bindingsRepository.getTaskListBinding(boundMirrorTaskListId),
        isNull,
      );
      await _dismissSnackBars(tester);
      await _disposeWidgetTree(tester);
    });

    testWidgets('reports Outlook unbind failures without removing the binding',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final booksRepository = CalendarBooksRepository(db);
      final bindingsRepository = OutlookSyncBindingsRepository(db);
      final taskListId = await booksRepository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Unbind fails tasks',
          createdAt: fixtureNow(),
        ),
        audit: false,
      );
      await bindingsRepository.saveTaskListBinding(
        _taskListBinding(
          taskListId: taskListId,
          remoteCalendarName: 'Remote failure',
        ),
      );

      await _pumpCalendarBooks(
        tester,
        db: db,
        syncBindingsRepository: _FailingOutlookSyncBindingsRepository(db),
      );
      await _pumpUntilFound(tester, find.text('Unbind fails tasks'));

      await _openTileMenu(tester, 'Unbind fails tasks');
      await _tapPopupValue(tester, 'unbind_outlook');
      await _confirmDialog(tester);
      await _pumpUntilFound(tester, find.byType(SnackBar));

      expect(find.textContaining('unbind failed'), findsOneWidget);
      expect(
        await bindingsRepository.getTaskListBinding(taskListId),
        isNotNull,
      );
      await _dismissSnackBars(tester);
      await _disposeWidgetTree(tester);
    });
  });

  group('EventDetailPage gap worker H', () {
    testWidgets('close button uses router pop when detail was pushed',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await insertFixtureCalendar(db, name: 'Writable');
      final fakeStore = FakeTaskEventServerFirstStore();
      final router = _eventRouter(
        initialLocation: _timelineRoute,
      );
      addTearDown(router.dispose);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1000),
        overrides: _eventDetailOverrides(
          calendars: await db.select(db.eventCalendars).get(),
          fakeStore: fakeStore,
        ),
        child: MaterialApp.router(routerConfig: router),
      );
      await tester.pump();

      router.push(_eventCreateRoute);
      await _pumpUntilFound(tester, find.byType(EventDetailPage));
      await tester.tap(find.byIcon(Icons.close));
      await _pumpUntilFound(tester, find.text('timeline fallback'));
      expect(fakeStore.createdEvents, isEmpty);
    });

    testWidgets('close button falls back to the nearest Navigator pop',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await insertFixtureCalendar(db, name: 'Writable');
      final fakeStore = FakeTaskEventServerFirstStore();
      final router = GoRouter(
        initialLocation: '/nested',
        routes: [
          GoRoute(
            path: '/nested',
            builder: (context, state) => const _NestedNavigatorHost(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1000),
        overrides: _eventDetailOverrides(
          calendars: await db.select(db.eventCalendars).get(),
          fakeStore: fakeStore,
        ),
        child: MaterialApp.router(routerConfig: router),
      );
      await _pumpUntilFound(tester, find.byType(EventDetailPage));

      await tester.tap(find.byIcon(Icons.close));
      await _pumpUntil(
        tester,
        () => find.byType(EventDetailPage).evaluate().isEmpty,
      );
      expect(find.text('nested root'), findsOneWidget);
      expect(find.byType(EventDetailPage), findsNothing);
      expect(fakeStore.createdEvents, isEmpty);
    });

    testWidgets('calendar selector renders loading and error states',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final calendars = StreamController<List<EventCalendar>>();
      addTearDown(calendars.close);
      final fakeStore = FakeTaskEventServerFirstStore();
      final router = _eventRouter(
        initialLocation: _eventCreateRoute,
      );
      addTearDown(router.dispose);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1000),
        overrides: [
          allEventCalendarsProvider.overrideWith((ref) => calendars.stream),
          taskEventServerFirstStoreProvider.overrideWith(
            (ref) async => fakeStore,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
      await _pumpFrames(tester);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      calendars.addError(StateError('calendar load boom'));
      await _pumpFrames(tester);
      expect(find.textContaining('calendar load boom'), findsOneWidget);
    });

    testWidgets('creating without a local calendar validates before saving',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final fakeStore = FakeTaskEventServerFirstStore();
      final router = _eventRouter(
        initialLocation: _eventCreateRoute,
      );
      addTearDown(router.dispose);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1000),
        overrides: _eventDetailOverrides(
          calendars: const <EventCalendar>[],
          fakeStore: fakeStore,
        ),
        child: MaterialApp.router(routerConfig: router),
      );
      await _pumpUntilFound(tester, find.byKey(AppKeys.eventSummaryField));
      await tester.enterText(find.byKey(AppKeys.eventSummaryField), 'Draft');
      await tester.tap(find.byKey(AppKeys.eventSaveButton));
      await _pumpUntilFound(tester, find.byType(SnackBar));

      expect(fakeStore.createdEvents, isEmpty);
      expect(find.byType(EventDetailPage), findsOneWidget);
      await _dismissSnackBars(tester);
    });

    testWidgets(
        'all-day end date, manual block edits, color, status and repeat save in payload',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final fakeStore = FakeTaskEventServerFirstStore();
      final calendarId = await insertFixtureCalendar(db, name: 'Writable');
      final focusCalendarId = await db.into(db.eventCalendars).insert(
            EventCalendarsCompanion.insert(
              name: 'Focus',
              createdAt: fixtureNow().add(const Duration(minutes: 1)),
              isDefault: const Value(false),
            ),
          );
      await CalendarBooksRepository(db).saveEventCalendarDefaults(
        id: focusCalendarId,
        defaultIsBlock: false,
        audit: false,
      );
      final eventId = await db.into(db.calendarEvents).insert(
            CalendarEventsCompanion.insert(
              uid: 'all-day-edit',
              dtstamp: fixtureNow(),
              summary: 'All day edit',
              dtstart: DateTime(2026, 6, 10, 9),
              dtend: Value(DateTime(2026, 6, 10, 10)),
              eventCalendarId: Value(calendarId),
            ),
          );
      final router = _eventRouter(
        initialLocation: '/event/$eventId',
      );
      addTearDown(router.dispose);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1400),
        overrides: _eventDetailOverrides(
          calendars: await db.select(db.eventCalendars).get(),
          fakeStore: fakeStore,
        ),
        child: MaterialApp.router(routerConfig: router),
      );
      await _pumpUntilTextField(tester, 'All day edit');

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      await _tapCalendarChip(tester, 'Focus');
      await _tapChoiceChipAt(tester, 1);
      await _tapChoiceChipAt(tester, 6);
      await _tapLastColorSwatch(tester);
      await _tapDateTile(tester, 1);
      await _tapDatePickerDay(tester, '12');
      await _tapDatePickerOk(tester);
      await tester.pump();

      await tester.tap(find.byKey(AppKeys.eventSaveButton));
      await _pumpUntil(tester, () => fakeStore.updatedEvents.isNotEmpty);

      final payload = fakeStore.updatedEvents.single.payload;
      expect(payload['eventCalendarId'], focusCalendarId);
      expect(payload['status'], 'TENTATIVE');
      expect(payload['rrule'], 'FREQ=MONTHLY');
      expect(payload['isBlock'], isTrue);
      expect(payload['colorHex'], isA<String>());
      expect(
          DateTime.parse(payload['endAt']! as String), DateTime(2026, 6, 12));
    });

    testWidgets(
        'timed date picking covers cancel, adjusted start, and invalid end',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final fakeStore = FakeTaskEventServerFirstStore();
      final calendarId = await insertFixtureCalendar(db, name: 'Writable');
      final eventId = await db.into(db.calendarEvents).insert(
            CalendarEventsCompanion.insert(
              uid: 'timed-pickers',
              dtstamp: fixtureNow(),
              summary: 'Timed pickers',
              dtstart: DateTime(2026, 6, 10, 9),
              dtend: Value(DateTime(2026, 6, 10, 10)),
              eventCalendarId: Value(calendarId),
            ),
          );
      final router = _eventRouter(initialLocation: '/event/$eventId');
      addTearDown(router.dispose);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1400),
        overrides: _eventDetailOverrides(
          calendars: await db.select(db.eventCalendars).get(),
          fakeStore: fakeStore,
        ),
        child: MaterialApp.router(routerConfig: router),
      );
      await _pumpUntilTextField(tester, 'Timed pickers');

      await _tapDateTile(tester, 0);
      await _tapDatePickerDay(tester, '11');
      await _tapDatePickerOk(tester);
      await _tapTimePickerCancel(tester);

      await _tapDateTile(tester, 0);
      await _tapDatePickerDay(tester, '11');
      await _tapDatePickerOk(tester);
      await _tapTimePickerOk(tester);

      await _tapDateTile(tester, 1);
      await _tapDatePickerDay(tester, '11');
      await _tapDatePickerOk(tester);
      await _tapTimePickerOk(tester);

      await _tapDateTile(tester, 1);
      await _tapDatePickerDay(tester, '10');
      await _tapDatePickerOk(tester);
      await _tapTimePickerOk(tester);
      await _pumpUntilFound(tester, find.byType(SnackBar));

      await tester.tap(find.byKey(AppKeys.eventSaveButton));
      await _pumpUntil(tester, () => fakeStore.updatedEvents.isNotEmpty);

      final payload = fakeStore.updatedEvents.single.payload;
      expect(
        DateTime.parse(payload['startAt']! as String),
        DateTime(2026, 6, 11, 9),
      );
      expect(
        DateTime.parse(payload['endAt']! as String),
        DateTime(2026, 6, 11, 10),
      );
    });
  });

  group('MonthView gap worker H', () {
    testWidgets('uses real month providers and table calendar callbacks',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final selectedDay = DateTime(2026, 6, 10);
      final calendarId =
          await insertFixtureCalendar(db, name: 'Month calendar');
      final taskListId = await insertFixtureTaskList(db, name: 'Month tasks');
      for (var i = 0; i < 5; i++) {
        await _insertEvent(
          db,
          calendarId: calendarId,
          uid: 'dense-event-$i',
          summary: 'Dense event $i',
          start: DateTime(2026, 6, 10, 9 + i),
        );
      }
      await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'dense-task',
        summary: 'Dense task',
        start: DateTime(2026, 6, 10, 16),
      );
      await db.into(db.taskItems).insert(
            TaskItemsCompanion.insert(
              uid: 'unscheduled-task',
              dtstamp: fixtureNow(),
              summary: 'Unscheduled task',
              taskListId: Value(taskListId),
            ),
          );

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1100),
        child: const MaterialApp(home: MonthView()),
      );
      _setSelectedDate(tester, selectedDay);
      await _pumpUntilFound(tester, find.text('Dense event 0'));
      final tableCalendar = find.byWidgetPredicate(
        (widget) => widget is TableCalendar,
        description: 'TableCalendar',
        skipOffstage: false,
      );
      await _pumpUntilFound(tester, tableCalendar);

      var calendar = tester.widget<TableCalendar>(
        tableCalendar.first,
      );
      expect(calendar.eventLoader!(selectedDay), hasLength(4));

      calendar.onPageChanged!(DateTime(2026, 7, 1));
      await tester.pump();
      expect(_selectedDate(tester), DateTime(2026, 7, 1));

      calendar.onFormatChanged!(CalendarFormat.twoWeeks);
      await tester.pump();
      calendar = tester.widget<TableCalendar>(
        tableCalendar.first,
      );
      expect(calendar.calendarFormat, CalendarFormat.twoWeeks);
      await _disposeWidgetTree(tester);
    });

    testWidgets('renders month preview loading and error states',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final events = StreamController<List<CalendarEvent>>.broadcast(
        sync: true,
      );
      addTearDown(events.close);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1100),
        overrides: [
          monthEventsProvider.overrideWith((ref, range) => events.stream),
          monthTasksProvider.overrideWith(
            (ref, range) => Stream<List<TaskItem>>.value(const <TaskItem>[]),
          ),
        ],
        child: const MaterialApp(home: MonthView()),
      );
      await _pumpFrames(tester);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      events.addError(StateError('month preview failed'));
      await _pumpFrames(tester);
      expect(find.textContaining('month preview failed'), findsOneWidget);
    });

    testWidgets('uses an empty task list while task stream is still loading',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final tasks = StreamController<List<TaskItem>>.broadcast(sync: true);
      addTearDown(tasks.close);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        size: const Size(900, 1100),
        overrides: [
          monthEventsProvider.overrideWith(
            (ref, range) => Stream<List<CalendarEvent>>.value(
              const <CalendarEvent>[],
            ),
          ),
          monthTasksProvider.overrideWith((ref, range) => tasks.stream),
        ],
        child: const MaterialApp(home: MonthView()),
      );
      await _pumpFrames(tester);

      expect(find.textContaining('/'), findsWidgets);
      expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
    });
  });
}

Future<void> _pumpCalendarBooks(
  WidgetTester tester, {
  required AppDatabase db,
  CalendarBooksRepository? booksRepository,
  OutlookSyncBindingsRepository? syncBindingsRepository,
}) async {
  addTearDown(() async {
    await _disposeWidgetTree(tester);
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 1200),
    overrides: [
      if (booksRepository != null)
        calendarBooksRepositoryProvider.overrideWith(
          (ref) => booksRepository,
        ),
      if (syncBindingsRepository != null)
        outlookSyncBindingsRepositoryProvider.overrideWith(
          (ref) => syncBindingsRepository,
        ),
    ],
    child: const MaterialApp(home: CalendarBooksPage()),
  );
  await _pumpFrames(tester);
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

List<Override> _eventDetailOverrides({
  required List<EventCalendar> calendars,
  required FakeTaskEventServerFirstStore fakeStore,
}) {
  return [
    allEventCalendarsProvider.overrideWith(
      (ref) => Stream<List<EventCalendar>>.value(calendars),
    ),
    onlinePrimaryPolicyProvider.overrideWith(
      (ref) => writableOnlinePrimaryPolicy,
    ),
    taskEventServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
  ];
}

GoRouter _eventRouter({
  required String initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: _timelineRoute,
        builder: (context, state) => const Center(
          child: Text('timeline fallback'),
        ),
      ),
      GoRoute(
        path: _eventCreateRoute,
        builder: (context, state) => const EventDetailPage(eventId: null),
      ),
      GoRoute(
        path: _eventDetailRoute,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return EventDetailPage(eventId: id);
        },
      ),
    ],
  );
}

class _NestedNavigatorHost extends StatefulWidget {
  const _NestedNavigatorHost();

  @override
  State<_NestedNavigatorHost> createState() => _NestedNavigatorHostState();
}

class _NestedNavigatorHostState extends State<_NestedNavigatorHost> {
  var _showDetail = true;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: [
        const MaterialPage<void>(
          child: Center(child: Text('nested root')),
        ),
        if (_showDetail)
          const MaterialPage<void>(
            child: EventDetailPage(eventId: null),
          ),
      ],
      onDidRemovePage: (_) {
        if (_showDetail) {
          setState(() => _showDetail = false);
        }
      },
    );
  }
}

class _FailingCalendarBooksRepository extends CalendarBooksRepository {
  _FailingCalendarBooksRepository(
    super.db, {
    this.failSetDefaultEvent = false,
    this.failSetDefaultTask = false,
    this.failDeleteEvent = false,
  });

  final bool failSetDefaultEvent;
  final bool failSetDefaultTask;
  final bool failDeleteEvent;

  @override
  Future<void> setDefaultEventCalendar(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'set_default',
    String? summary,
    Object? metadata,
  }) async {
    if (failSetDefaultEvent) {
      throw StateError('default event failed');
    }
    return super.setDefaultEventCalendar(
      id,
      audit: audit,
      actor: actor,
      action: action,
      summary: summary,
      metadata: metadata,
    );
  }

  @override
  Future<void> setDefaultTaskList(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'set_default',
    String? summary,
    Object? metadata,
  }) async {
    if (failSetDefaultTask) {
      throw StateError('default task failed');
    }
    return super.setDefaultTaskList(
      id,
      audit: audit,
      actor: actor,
      action: action,
      summary: summary,
      metadata: metadata,
    );
  }

  @override
  Future<int> deleteEventCalendar(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'delete',
    String? summary,
    Object? metadata,
  }) async {
    if (failDeleteEvent) {
      throw StateError('delete calendar failed');
    }
    return super.deleteEventCalendar(
      id,
      audit: audit,
      actor: actor,
      action: action,
      summary: summary,
      metadata: metadata,
    );
  }
}

class _FailingOutlookSyncBindingsRepository
    extends OutlookSyncBindingsRepository {
  _FailingOutlookSyncBindingsRepository(super.db);

  @override
  Future<void> removeTaskListBinding(int taskListId) async {
    throw StateError('unbind failed');
  }
}

OutlookTaskListBinding _taskListBinding({
  required int taskListId,
  required String remoteCalendarName,
}) {
  return OutlookTaskListBinding(
    localTaskListId: taskListId,
    remoteCalendarId: 'remote-$taskListId',
    remoteCalendarName: remoteCalendarName,
    linkedAt: fixtureNow(),
  );
}

OutlookTaskMirrorBinding _mirrorBinding({
  required int taskId,
  required int taskListId,
  required String remoteCalendarName,
}) {
  return OutlookTaskMirrorBinding(
    localTaskId: taskId,
    localTaskListId: taskListId,
    remoteCalendarId: 'remote-$taskListId',
    remoteCalendarName: remoteCalendarName,
    remoteEventId: 'remote-task-$taskId',
    syncedAt: fixtureNow(),
  );
}

Future<int> _insertEvent(
  AppDatabase db, {
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime start,
}) {
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: fixtureNow(),
          summary: summary,
          dtstart: start,
          dtend: Value(start.add(const Duration(hours: 1))),
          eventCalendarId: Value(calendarId),
        ),
      );
}

Future<int> _insertTask(
  AppDatabase db, {
  required int taskListId,
  required String uid,
  required String summary,
  required DateTime start,
}) {
  return db.into(db.taskItems).insert(
        TaskItemsCompanion.insert(
          uid: uid,
          dtstamp: fixtureNow(),
          summary: summary,
          dtstart: Value(start),
          taskListId: Value(taskListId),
        ),
      );
}

Future<EventCalendar?> _calendarById(AppDatabase db, int id) {
  return (db.select(db.eventCalendars)..where((row) => row.id.equals(id)))
      .getSingleOrNull();
}

Future<TaskList?> _taskListById(AppDatabase db, int id) {
  return (db.select(db.taskLists)..where((row) => row.id.equals(id)))
      .getSingleOrNull();
}

Finder _tileFor(String title) {
  return find
      .ancestor(
        of: find.text(title).first,
        matching: find.byType(ListTile),
      )
      .first;
}

Future<void> _openTileMenu(WidgetTester tester, String title) async {
  await tester.ensureVisible(_tileFor(title));
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: _tileFor(title),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _tapPopupValue(WidgetTester tester, String value) async {
  final menuItem = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem && widget.value == value,
  );
  expect(menuItem, findsOneWidget);
  await tester.tap(
    find.descendant(of: menuItem, matching: find.byType(Text)).first,
  );
  await _pumpFrames(tester);
}

Future<void> _tapDialogCancel(WidgetTester tester) async {
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

Future<void> _confirmDialog(WidgetTester tester) async {
  await _pumpUntilDialog(tester);
  await tester.tap(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        )
        .last,
  );
  await _pumpUntilNoDialog(tester);
}

Future<void> _tapCalendarChip(WidgetTester tester, String text) async {
  final target = find.ancestor(
    of: find.text(text),
    matching: find.byType(GestureDetector),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _tapChoiceChipAt(WidgetTester tester, int index) async {
  final chip = find.byType(ChoiceChip).at(index);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _tapLastColorSwatch(WidgetTester tester) async {
  final swatches = find.byWidgetPredicate(
    (widget) =>
        widget is GestureDetector &&
        widget.child is Container &&
        (widget.child! as Container).constraints?.maxWidth == 32,
  );
  await tester.ensureVisible(swatches.last);
  await tester.tap(swatches.last);
  await tester.pump();
}

Future<void> _tapDateTile(WidgetTester tester, int index) async {
  final tile = find.ancestor(
    of: find.byIcon(Icons.access_time_outlined).at(index),
    matching: find.byType(InkWell),
  );
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pump();
}

Future<void> _tapDatePickerDay(WidgetTester tester, String day) async {
  final dayText = find.descendant(
    of: find.byType(CalendarDatePicker),
    matching: find.text(day),
  );
  await tester.tap(dayText.last);
  await tester.pump();
}

Future<void> _tapDatePickerOk(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextButton),
        )
        .last,
  );
  await _pumpFrames(tester);
}

Future<void> _tapTimePickerOk(WidgetTester tester) async {
  await _tapTimePickerButton(tester, last: true);
}

Future<void> _tapTimePickerCancel(WidgetTester tester) async {
  await _tapTimePickerButton(tester, last: false);
}

Future<void> _tapTimePickerButton(
  WidgetTester tester, {
  required bool last,
}) async {
  final buttons = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextButton),
  );
  await tester.tap(last ? buttons.last : buttons.first);
  await _pumpFrames(tester);
}

Future<void> _pumpUntilDialog(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
  );
}

Future<void> _pumpUntilNoDialog(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isEmpty,
  );
}

Future<void> _pumpUntilTextField(WidgetTester tester, String text) async {
  await _pumpUntil(
    tester,
    () {
      final field = tester.widget<TextField>(
        find.byKey(AppKeys.eventSummaryField),
      );
      return field.controller?.text == text;
    },
  );
}

Future<void> _dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

void _setSelectedDate(WidgetTester tester, DateTime date) {
  final dynamic notifier =
      _container(tester).read(selectedDateProvider.notifier);
  notifier.setDate(date);
}

DateTime _selectedDate(WidgetTester tester) {
  return _container(tester).read(selectedDateProvider);
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MonthView)));
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 30,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    maxPumps: maxPumps,
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

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
