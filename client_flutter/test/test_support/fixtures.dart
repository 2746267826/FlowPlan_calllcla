import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';

DateTime fixtureNow() => DateTime.utc(2026, 6, 8, 9);

Future<int> insertFixtureTaskList(
  AppDatabase db, {
  String name = 'Test inbox',
}) {
  return db.into(db.taskLists).insert(
        TaskListsCompanion.insert(
          name: name,
          createdAt: fixtureNow(),
          isDefault: const Value(true),
        ),
      );
}

Future<int> insertFixtureCalendar(
  AppDatabase db, {
  String name = 'Test calendar',
}) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: name,
          createdAt: fixtureNow(),
          isDefault: const Value(true),
        ),
      );
}

TaskItemsCompanion fixtureTask({
  required String uid,
  required String summary,
  required int taskListId,
}) {
  return TaskItemsCompanion.insert(
    uid: uid,
    dtstamp: fixtureNow(),
    summary: summary,
    taskListId: Value(taskListId),
  );
}

CalendarEventsCompanion fixtureEvent({
  required String uid,
  required String summary,
  required int calendarId,
}) {
  return CalendarEventsCompanion.insert(
    uid: uid,
    dtstamp: fixtureNow(),
    summary: summary,
    dtstart: fixtureNow(),
    eventCalendarId: Value(calendarId),
  );
}
