import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/theme/app_theme.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/month_view.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets(
    'month view previews selected day events and tasks with color and duration branches',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final selectedDay = DateTime(2026, 6, 25);
      final calendarId = await insertFixtureCalendar(db);
      final taskListId = await insertFixtureTaskList(db);
      final eventId = await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'month-event-valid-color',
        summary: 'Month planning review',
        start: _at(selectedDay, 9, 15),
        end: _at(selectedDay, 10, 45),
        colorHex: '#123456',
        location: 'Room B',
        description: 'Preview notes',
      );
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'month-event-fallback-color',
        summary: 'Month fallback color',
        start: _at(selectedDay, 11),
        colorHex: 'not-a-color',
      );
      final highTaskId = await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'month-task-high',
        summary: 'Month high priority',
        start: _at(selectedDay, 13),
        durationMinutes: 45,
        priorityLocal: 1,
        location: 'Desk',
        description: 'Short task',
      );
      await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'month-task-low',
        summary: 'Month low priority',
        start: _at(selectedDay, 15, 30),
        durationMinutes: 90,
        priorityLocal: 3,
      );

      await _pumpMonth(
        tester,
        db: db,
        selectedDay: selectedDay,
        events: await db.select(db.calendarEvents).get(),
        tasks: await db.select(db.taskItems).get(),
        calendars: await db.select(db.eventCalendars).get(),
        taskLists: await db.select(db.taskLists).get(),
      );
      await _pumpUntilFound(tester, find.text('Month planning review'));

      expect(find.text('\u65e5\u7a0b'), findsOneWidget);
      expect(find.text('\u4efb\u52a1'), findsOneWidget);
      expect(find.text('Month planning review'), findsOneWidget);
      expect(find.text('Month fallback color'), findsOneWidget);
      expect(find.text('Month high priority'), findsOneWidget);
      expect(find.text('Month low priority'), findsOneWidget);
      expect(find.textContaining('09:15'), findsOneWidget);
      expect(find.textContaining('Room B'), findsOneWidget);
      expect(find.textContaining('Preview notes'), findsOneWidget);
      expect(find.textContaining('45'), findsOneWidget);
      expect(find.textContaining('Desk'), findsOneWidget);
      expect(find.textContaining('Short task'), findsOneWidget);

      final eventStripe = _leadingStripe(tester, 'Month planning review');
      expect(_boxColor(eventStripe), const Color(0xFF123456));
      final fallbackEventStripe =
          _leadingStripe(tester, 'Month fallback color');
      expect(_boxColor(fallbackEventStripe), AppColors.primary);
      final highTaskStripe = _leadingStripe(tester, 'Month high priority');
      expect(_boxColor(highTaskStripe), const Color(0xFFE53935));
      final lowTaskStripe = _leadingStripe(tester, 'Month low priority');
      expect(_boxColor(lowTaskStripe), const Color(0xFF43A047));

      await tester.tap(find.text('Month planning review'));
      await _pumpUntilFound(tester, find.byKey(AppKeys.eventSummaryField));
      final eventSummary =
          tester.widget<TextField>(find.byKey(AppKeys.eventSummaryField));
      expect(eventSummary.controller?.text, 'Month planning review');
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Month high priority'));
      await _pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
      final taskSummary =
          tester.widget<TextField>(find.byKey(AppKeys.taskSummaryField));
      expect(taskSummary.controller?.text, 'Month high priority');

      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();

      expect(eventId, isPositive);
      expect(highTaskId, isPositive);
    },
  );

  testWidgets('month view changes selected date and shows empty day state',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final selectedDay = DateTime(2026, 6, 25);
    final calendarId = await insertFixtureCalendar(db);
    await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'month-event-before-selection',
      summary: 'Before day event',
      start: _at(selectedDay, 9),
      end: _at(selectedDay, 10),
    );

    await _pumpMonth(
      tester,
      db: db,
      selectedDay: selectedDay,
      events: await db.select(db.calendarEvents).get(),
    );
    await _pumpUntilFound(tester, find.text('Before day event'));

    await tester.tap(_calendarDay('26'));
    await _pumpFrames(tester);

    expect(_selectedDate(tester), DateTime(2026, 6, 26));
    expect(find.text('Before day event'), findsNothing);
    expect(find.text('6/26'), findsOneWidget);
    expect(find.text('\u6682\u65e0\u5b89\u6392'), findsOneWidget);
    expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
  });
}

Future<void> _pumpMonth(
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
    size: const Size(900, 1100),
    overrides: [
      monthEventsProvider.overrideWith(
        (ref, range) {
          final filtered = events
              .where((event) =>
                  !event.dtstart.isBefore(range.start) &&
                  event.dtstart.isBefore(range.end))
              .toList(growable: false);
          return Stream<List<CalendarEvent>>.value(filtered);
        },
      ),
      monthTasksProvider.overrideWith(
        (ref, range) {
          final filtered = tasks
              .where((task) =>
                  task.dtstart != null &&
                  !task.dtstart!.isBefore(range.start) &&
                  task.dtstart!.isBefore(range.end))
              .toList(growable: false);
          return Stream<List<TaskItem>>.value(filtered);
        },
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
    child: const MaterialApp(home: MonthView()),
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
  return ProviderScope.containerOf(tester.element(find.byType(MonthView)));
}

Finder _calendarDay(String day) {
  return find
      .descendant(
        of: find.byWidgetPredicate((widget) => widget is TableCalendar),
        matching: find.text(day),
      )
      .first;
}

Container _leadingStripe(WidgetTester tester, String title) {
  final tile = find.ancestor(
    of: find.text(title),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is InkWell &&
          widget.onTap != null &&
          widget.borderRadius == BorderRadius.circular(8),
    ),
  );
  expect(tile, findsOneWidget);
  final stripe = find.descendant(
    of: tile,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints?.minWidth == 4 &&
          widget.constraints?.maxWidth == 4 &&
          widget.constraints?.minHeight == 36 &&
          widget.constraints?.maxHeight == 36 &&
          widget.child == null &&
          widget.decoration is BoxDecoration,
    ),
  );
  return tester.widget<Container>(stripe.first);
}

Color? _boxColor(Container container) {
  return (container.decoration as BoxDecoration?)?.color;
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
