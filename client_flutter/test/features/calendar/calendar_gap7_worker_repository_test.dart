import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('calendar and task defaults use fallback constructors and unnamed logs',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(
      db,
      DataOperationLogRepository(db),
    );

    final eventDefaults = await repository.getEventCalendarDefaults(9001);
    final taskDefaults = await repository.getTaskListDefaults(9002);

    expect(eventDefaults.defaultIsBlock, isFalse);
    expect(taskDefaults.defaultIsAutoScheduled, isTrue);
    expect(taskDefaults.defaultReminderMinutesBefore, 15);

    await repository.saveEventCalendarDefaults(
      id: 9001,
      defaultIsBlock: true,
    );
    await repository.saveTaskListDefaults(
      id: 9002,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 30,
    );
    await repository.toggleEventCalendarVisible(9003, false);

    final summaries = (await _logs(db))
        .map((row) => row['summary'] as String)
        .toList(growable: false);
    expect(
      summaries,
      containsAll(<String>[
        '更新日历本「未命名日历本」默认规则',
        '更新任务本「未命名任务本」默认规则',
        '隐藏日历本「未命名日历本」',
      ]),
    );
  });

  test('task list update audit falls back to before snapshot after deletion',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(
      db,
      DataOperationLogRepository(db),
    );
    final taskListId = await insertFixtureTaskList(db, name: 'Gap7 before');

    await db.customStatement('''
      CREATE TRIGGER gap7_delete_task_list_after_update
      AFTER UPDATE ON task_lists
      BEGIN
        DELETE FROM task_lists WHERE id = NEW.id;
      END
    ''');

    final updated = await repository.updateTaskList(
      TaskListsCompanion(
        id: Value(taskListId),
        name: const Value('Gap7 after'),
      ),
    );

    expect(updated, isTrue);
    final logs = await _logs(db);
    expect(logs.single['summary'], '更新任务本「Gap7 before」');
    expect(logs.single['after_json'], isNull);
  });

  test('event repository validates required calendars and extra filters',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId = await insertFixtureCalendar(db, name: 'Gap7 events');
    final hiddenCalendarId =
        await insertFixtureCalendar(db, name: 'Gap7 hidden events');
    await (db.update(db.eventCalendars)
          ..where((row) => row.id.equals(hiddenCalendarId)))
        .write(const EventCalendarsCompanion(isVisible: Value(false)));
    final repository = EventRepository(db);

    await expectLater(
      repository.create(
        CalendarEventsCompanion.insert(
          uid: 'gap7-missing-calendar',
          dtstamp: fixtureNow(),
          summary: 'Missing calendar event',
          dtstart: fixtureNow(),
        ),
        audit: false,
      ),
      throwsStateError,
    );

    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'gap7-visible-block',
            summary: 'Visible block',
            calendarId: calendarId,
          ).copyWith(isBlock: const Value(true)),
        );
    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'gap7-hidden-block',
            summary: 'Hidden block',
            calendarId: hiddenCalendarId,
          ).copyWith(isBlock: const Value(true)),
        );
    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'gap7-visible-free',
            summary: 'Visible free',
            calendarId: calendarId,
          ).copyWith(isBlock: const Value(false)),
        );

    final filtered = await repository
        .debugWatchForDateRangeWithExtraFilter(
          DateTime.utc(2026, 6, 8),
          DateTime.utc(2026, 6, 9),
          (event, calendar) =>
              event.isBlock.equals(true) & calendar.isVisible.equals(true),
        )
        .first;

    expect(filtered.map((event) => event.summary), ['Visible block']);
  });
}

Future<List<Map<String, Object?>>> _logs(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT * FROM data_operation_logs ORDER BY id ASC')
      .get();
  return rows.map((row) => row.data).toList(growable: false);
}
