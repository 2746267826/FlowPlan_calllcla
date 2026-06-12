import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/theme/app_theme.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/week_view.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/widgets/task_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets(
    'week view renders scheduled events and tasks with color and duration branches',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final selectedDay = DateTime(2026, 6, 25);
      final calendarId = await insertFixtureCalendar(db);
      final taskListId = await insertFixtureTaskList(db);
      final eventId = await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'week-event-valid-color',
        summary: 'Week design review',
        start: _at(selectedDay, 9, 15),
        end: _at(selectedDay, 10, 45),
        colorHex: '#123456',
        location: 'Room A',
        description: 'Review notes',
      );
      final fallbackEventId = await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'week-event-fallback-color',
        summary: 'Fallback color sync',
        start: _at(selectedDay, 11),
        colorHex: 'not-a-color',
      );
      final highTaskId = await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'week-task-high',
        summary: 'High priority sprint',
        start: _at(selectedDay, 13),
        durationMinutes: 30,
        priorityLocal: 1,
        location: 'Desk',
        description: 'Short task notes',
      );
      final lowTaskId = await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'week-task-low',
        summary: 'Low priority research',
        start: _at(selectedDay, 15, 30),
        durationMinutes: 90,
        priorityLocal: 3,
      );

      await _pumpWeek(
        tester,
        db: db,
        selectedDay: selectedDay,
        events: await db.select(db.calendarEvents).get(),
        tasks: await db.select(db.taskItems).get(),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ValueKey<String>('week_event_$eventId')),
      );

      expect(find.text('Week design review'), findsOneWidget);
      expect(find.text('Fallback color sync'), findsOneWidget);
      expect(find.text('High priority sprint'), findsOneWidget);
      expect(find.text('Low priority research'), findsOneWidget);
      expect(find.byType(TaskBlock), findsNWidgets(4));

      final eventBlock = _taskBlock(tester, 'week_event_$eventId');
      expect(eventBlock.color, const Color(0xFF123456));
      expect(eventBlock.durationText, allOf(contains('1'), contains('30')));
      expect(eventBlock.location, 'Room A');
      expect(eventBlock.note, 'Review notes');

      final fallbackEventBlock =
          _taskBlock(tester, 'week_event_$fallbackEventId');
      expect(fallbackEventBlock.color, AppColors.primary);
      expect(fallbackEventBlock.durationText, contains('1'));

      final highTaskBlock = _taskBlock(tester, 'week_task_$highTaskId');
      expect(highTaskBlock.color, const Color(0xFFE53935));
      expect(highTaskBlock.durationText, contains('30'));
      expect(highTaskBlock.location, 'Desk');

      final lowTaskBlock = _taskBlock(tester, 'week_task_$lowTaskId');
      expect(lowTaskBlock.color, const Color(0xFF43A047));
      expect(lowTaskBlock.durationText, allOf(contains('1'), contains('30')));

      await tester.tap(find.text('26'));
      await tester.pump();
      expect(_selectedDate(tester).day, 26);
    },
  );

  testWidgets('week view opens detail dialogs from event and task blocks',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final selectedDay = DateTime(2026, 6, 25);
    final calendarId = await insertFixtureCalendar(db);
    final taskListId = await insertFixtureTaskList(db);
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'week-event-detail',
      summary: 'Open event detail',
      start: _at(selectedDay, 9),
      end: _at(selectedDay, 10),
    );
    await _insertTask(
      db,
      taskListId: taskListId,
      uid: 'week-task-detail',
      summary: 'Open task detail',
      start: _at(selectedDay, 12),
      durationMinutes: 45,
    );

    await _pumpWeek(
      tester,
      db: db,
      selectedDay: selectedDay,
      events: await db.select(db.calendarEvents).get(),
      tasks: await db.select(db.taskItems).get(),
      calendars: await db.select(db.eventCalendars).get(),
      taskLists: await db.select(db.taskLists).get(),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(ValueKey<String>('week_event_$eventId')),
    );

    await tester.tap(find.text('Open event detail'));
    await _pumpUntilFound(tester, find.byKey(AppKeys.eventSummaryField));
    final eventSummary =
        tester.widget<TextField>(find.byKey(AppKeys.eventSummaryField));
    expect(eventSummary.controller?.text, 'Open event detail');

    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open task detail'));
    await _pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    final taskSummary =
        tester.widget<TextField>(find.byKey(AppKeys.taskSummaryField));
    expect(taskSummary.controller?.text, 'Open task detail');

    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('week view shows an empty schedule grid without blocks',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await _pumpWeek(
      tester,
      db: db,
      selectedDay: DateTime(2026, 6, 25),
    );

    expect(find.text('6/22 - 6/28'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.byType(TaskBlock), findsNothing);
    expect(find.text('09'), findsOneWidget);
  });
}

Future<void> _pumpWeek(
  WidgetTester tester, {
  required AppDatabase db,
  required DateTime selectedDay,
  List<CalendarEvent> events = const <CalendarEvent>[],
  List<TaskItem> tasks = const <TaskItem>[],
  List<EventCalendar> calendars = const <EventCalendar>[],
  List<TaskList> taskLists = const <TaskList>[],
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, count: 4);
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(1000, 900),
    overrides: [
      weekEventsProvider.overrideWith(
        (ref, range) => Stream<List<CalendarEvent>>.value(events),
      ),
      weekTasksProvider.overrideWith(
        (ref, range) => Stream<List<TaskItem>>.value(tasks),
      ),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream<List<EventCalendar>>.value(calendars),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream<List<TaskList>>.value(taskLists),
      ),
      activityRecordRepositoryProvider.overrideWith(
        (ref) => _EmptyActivityRecordRepository(db),
      ),
      inputActivityEventServiceProvider.overrideWith(
        (ref) => _EmptyInputActivityEventService(db),
      ),
      activityFusionRepositoryProvider.overrideWith(
        (ref) => _EmptyActivityFusionRepository(db),
      ),
    ],
    child: const MaterialApp(home: WeekView()),
  );
  _setSelectedDate(tester, selectedDay);
  await _pumpFrames(tester);
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
  return ProviderScope.containerOf(tester.element(find.byType(WeekView)));
}

TaskBlock _taskBlock(WidgetTester tester, String key) {
  return tester.widget<TaskBlock>(find.byKey(ValueKey<String>(key)));
}

Future<int> _insertEvent(
  AppDatabase db, {
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime start,
  DateTime? end,
  String colorHex = '#6B5EE4',
  String? location,
  String? description,
}) {
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: fixtureNow(),
          summary: summary,
          description: Value(description),
          location: Value(location),
          dtstart: start,
          dtend: Value(end),
          eventCalendarId: Value(calendarId),
          colorHex: Value(colorHex),
        ),
      );
}

Future<int> _insertTask(
  AppDatabase db, {
  required int taskListId,
  required String uid,
  required String summary,
  required DateTime start,
  int durationMinutes = 60,
  int priorityLocal = 2,
  String? location,
  String? description,
}) {
  return db.into(db.taskItems).insert(
        TaskItemsCompanion.insert(
          uid: uid,
          dtstamp: fixtureNow(),
          summary: summary,
          description: Value(description),
          location: Value(location),
          dtstart: Value(start),
          durationMinutes: Value(durationMinutes),
          priorityLocal: Value(priorityLocal),
          taskListId: Value(taskListId),
        ),
      );
}

DateTime _at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
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

Future<void> _pumpFrames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _EmptyActivityRecordRepository extends ActivityRecordRepository {
  _EmptyActivityRecordRepository(super.db);

  @override
  Stream<List<ActivityRecord>> watchByTaskId(int taskId) {
    return Stream<List<ActivityRecord>>.value(const <ActivityRecord>[]);
  }

  @override
  Future<void> linkTask(int recordId, int? taskId) async {}
}

class _EmptyInputActivityEventService extends InputActivityEventService {
  _EmptyInputActivityEventService(super.db);

  @override
  Future<InputHeatmapSummary> buildHeatmapSummaryForTask(int taskId) async {
    final now = DateTime(2026, 6, 25);
    return InputHeatmapSummary.empty(
      InputEventQuery(start: now, end: now.add(const Duration(days: 1))),
    );
  }

  @override
  Future<List<TrackedInputEvent>> listRecentEventsForTask(
    int taskId, {
    int limit = 10,
  }) async {
    return const <TrackedInputEvent>[];
  }
}

class _EmptyActivityFusionRepository extends ActivityFusionRepository {
  _EmptyActivityFusionRepository(super.db);

  @override
  Future<List<TaskWorkLog>> listTaskWorkLogsForTask(
    int taskId, {
    int limit = 200,
    int offset = 0,
  }) async {
    return const <TaskWorkLog>[];
  }
}
