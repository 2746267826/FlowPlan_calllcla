import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('audit logs use before snapshots when containers disappear after update',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(
      db,
      DataOperationLogRepository(db),
    );
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'Vanishing calendar',
    );
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Vanishing tasks',
    );

    await db.customStatement('''
      CREATE TRIGGER delete_calendar_after_update
      AFTER UPDATE ON event_calendars
      BEGIN
        DELETE FROM event_calendars WHERE id = NEW.id;
      END
    ''');
    await db.customStatement('''
      CREATE TRIGGER delete_task_list_after_update
      AFTER UPDATE ON task_lists
      BEGIN
        DELETE FROM task_lists WHERE id = NEW.id;
      END
    ''');

    expect(
      await repository.updateEventCalendar(
        EventCalendarsCompanion(
          id: Value(calendarId),
          colorHex: const Value('#111111'),
        ),
      ),
      isTrue,
    );
    await repository.toggleTaskListVisible(taskListId, false);

    final logs = await _logs(db);
    expect(
      logs.map((row) => row['summary']),
      containsAll(<String>[
        '更新日历本「Vanishing calendar」',
        '隐藏任务本「Vanishing tasks」',
      ]),
    );
    expect(
      logs.singleWhere(
          (row) => row['entity_type'] == 'event_calendar')['after_json'],
      isNull,
    );
    expect(
      logs.singleWhere(
          (row) => row['action'] == 'toggle_visible')['after_json'],
      isNull,
    );
  });

  test('defaults for missing containers fall back to unnamed audit summaries',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(
      db,
      DataOperationLogRepository(db),
    );

    await repository.saveEventCalendarDefaults(
      id: 404,
      defaultIsBlock: true,
    );
    await repository.saveTaskListDefaults(
      id: 405,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 45,
    );

    final summaries = (await _logs(db))
        .map((row) => row['summary'] as String)
        .toList(growable: false);
    expect(summaries, contains('更新日历本「未命名日历本」默认规则'));
    expect(summaries, contains('更新任务本「未命名任务本」默认规则'));
  });

  test('archive and delete task list audit metadata preserves extra context',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(
      db,
      DataOperationLogRepository(db),
    );
    final archiveId = await insertFixtureTaskList(db, name: 'Archive me');
    final deleteId = await insertFixtureTaskList(db, name: 'Delete me');
    await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'archive-task',
            summary: 'Archive payload task',
            taskListId: archiveId,
          ),
        );
    await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'delete-task',
            summary: 'Delete payload task',
            taskListId: deleteId,
          ),
        );

    await repository.archiveTaskList(
      archiveId,
      metadata: const <String, Object?>{'reason': 'gap6 archive'},
    );
    await repository.deleteTaskList(
      deleteId,
      metadata: const <String, Object?>{'reason': 'gap6 delete'},
    );

    final logs = await _logs(db);
    final archiveMetadata = jsonDecode(
      logs.singleWhere((row) => row['action'] == 'archive')['metadata_json']
          as String,
    ) as Map<String, dynamic>;
    final deleteMetadata = jsonDecode(
      logs.singleWhere((row) => row['action'] == 'delete')['metadata_json']
          as String,
    ) as Map<String, dynamic>;

    expect(archiveMetadata['task_count'], 1);
    expect(archiveMetadata['extra'], {'reason': 'gap6 archive'});
    expect(deleteMetadata['task_count'], 2);
    expect(deleteMetadata['extra'], {'reason': 'gap6 delete'});
  });
}

Future<List<Map<String, Object?>>> _logs(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT * FROM data_operation_logs ORDER BY id ASC')
      .get();
  return rows.map((row) => row.data).toList(growable: false);
}
