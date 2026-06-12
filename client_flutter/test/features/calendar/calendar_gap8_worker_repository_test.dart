import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('fallback defaults and missing calendar binding branches stay explicit',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final events = EventRepository(db);

    const eventDefaults = EventCalendarDefaults.fallback();
    expect(eventDefaults.defaultIsBlock, isFalse);

    await expectLater(
      events.create(
        CalendarEventsCompanion.insert(
          uid: 'gap8-no-calendar',
          dtstamp: fixtureNow(),
          summary: 'No calendar binding',
          dtstart: fixtureNow(),
        ),
        audit: false,
      ),
      throwsStateError,
    );
  });

  test('event watches combine visible calendars with an extra filter',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final visibleCalendarId =
        await insertFixtureCalendar(db, name: 'Gap8 visible');
    final hiddenCalendarId =
        await insertFixtureCalendar(db, name: 'Gap8 hidden');
    await (db.update(db.eventCalendars)
          ..where((row) => row.id.equals(hiddenCalendarId)))
        .write(const EventCalendarsCompanion(isVisible: Value(false)));
    final repository = EventRepository(db);

    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'gap8-visible-block',
            summary: 'Visible blocked focus',
            calendarId: visibleCalendarId,
          ).copyWith(isBlock: const Value(true)),
        );
    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'gap8-hidden-block',
            summary: 'Hidden blocked focus',
            calendarId: hiddenCalendarId,
          ).copyWith(isBlock: const Value(true)),
        );
    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'gap8-visible-free',
            summary: 'Visible free focus',
            calendarId: visibleCalendarId,
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

    expect(filtered.map((event) => event.summary), ['Visible blocked focus']);
  });

  test('container audit summaries fall back through after before and unnamed',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(
      db,
      DataOperationLogRepository(db),
    );
    final calendarId =
        await insertFixtureCalendar(db, name: 'Gap8 before calendar');
    final taskListId =
        await insertFixtureTaskList(db, name: 'Gap8 before tasks');

    await repository.saveEventCalendarDefaults(
      id: calendarId,
      defaultIsBlock: true,
    );
    await repository.toggleEventCalendarVisible(808080, false);
    await repository.saveTaskListDefaults(
      id: 909090,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 35,
    );

    await db.customStatement('''
      CREATE TRIGGER gap8_delete_task_list_after_update
      AFTER UPDATE ON task_lists
      BEGIN
        DELETE FROM task_lists WHERE id = NEW.id;
      END
    ''');
    expect(
      await repository.updateTaskList(
        TaskListsCompanion(
          id: Value(taskListId),
          name: const Value('Gap8 after tasks'),
        ),
      ),
      isTrue,
    );

    final logs = await _logs(db);
    expect(
      logs.map((row) => row['summary'] as String),
      containsAll(<String>[
        '更新日历本「Gap8 before calendar」默认规则',
        '隐藏日历本「未命名日历本」',
        '更新任务本「未命名任务本」默认规则',
        '更新任务本「Gap8 before tasks」',
      ]),
    );
    expect(
      logs.singleWhere(
          (row) => row['entity_id'] == '$taskListId')['after_json'],
      isNull,
    );
  });
}

Future<List<Map<String, Object?>>> _logs(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT * FROM data_operation_logs ORDER BY id ASC')
      .get();
  return rows.map((row) => row.data).toList(growable: false);
}
