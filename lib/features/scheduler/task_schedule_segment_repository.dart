import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../audit/data_operation_log_repository.dart';

class TaskScheduleSegment {
  const TaskScheduleSegment({
    required this.id,
    required this.taskId,
    required this.segmentIndex,
    required this.startAt,
    required this.endAt,
    required this.source,
    required this.planRunId,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int taskId;
  final int segmentIndex;
  final DateTime startAt;
  final DateTime endAt;
  final String source;
  final String? planRunId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get durationMinutes => endAt.difference(startAt).inMinutes;

  factory TaskScheduleSegment.fromRow(QueryRow row) {
    return TaskScheduleSegment(
      id: row.read<int>('id'),
      taskId: row.read<int>('task_id'),
      segmentIndex: row.read<int>('segment_index'),
      startAt: DateTime.parse(row.read<String>('start_at')),
      endAt: DateTime.parse(row.read<String>('end_at')),
      source: row.read<String>('source'),
      planRunId: row.data['plan_run_id'] as String?,
      note: row.data['note'] as String?,
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'segment_index': segmentIndex,
        'start_at': startAt.toIso8601String(),
        'end_at': endAt.toIso8601String(),
        'source': source,
        'plan_run_id': planRunId,
        'note': note,
      };
}

class TaskScheduleSegmentDraft {
  const TaskScheduleSegmentDraft({
    required this.taskId,
    required this.segmentIndex,
    required this.startAt,
    required this.endAt,
    required this.source,
    required this.planRunId,
    this.note,
  });

  final int taskId;
  final int segmentIndex;
  final DateTime startAt;
  final DateTime endAt;
  final String source;
  final String planRunId;
  final String? note;

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'segment_index': segmentIndex,
        'start_at': startAt.toIso8601String(),
        'end_at': endAt.toIso8601String(),
        'source': source,
        'plan_run_id': planRunId,
        'note': note,
      };
}

class TaskScheduleSegmentWithTask {
  const TaskScheduleSegmentWithTask({
    required this.segment,
    required this.task,
  });

  final TaskScheduleSegment segment;
  final TaskItem task;
}

class TaskScheduleSegmentRepository {
  TaskScheduleSegmentRepository(
    this._db,
    this._operationLogs,
  );

  final AppDatabase _db;
  final DataOperationLogRepository _operationLogs;

  Stream<List<TaskScheduleSegmentWithTask>> watchForDate(DateTime date) {
    return _watchForDatePolling(date);
  }

  Future<List<TaskScheduleSegmentWithTask>> getForDate(DateTime date) {
    return _loadForDate(date);
  }

  Stream<List<TaskScheduleSegmentWithTask>> _watchForDatePolling(
    DateTime date,
  ) async* {
    yield await _loadForDate(date);
    await for (final _ in Stream<void>.periodic(const Duration(seconds: 2))) {
      yield await _loadForDate(date);
    }
  }

  Future<List<TaskScheduleSegmentWithTask>> _loadForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.customSelect(
      '''
          SELECT
            s.*,
            t.id AS task_row_id,
            t.uid,
            t.dtstamp,
            t.summary,
            t.description,
            t.dtstart,
            t.due,
            t.completed,
            t.priority,
            t.status,
            t.percent_complete,
            t.categories,
            t.rrule,
            t.duration_minutes,
            t.is_splittable,
            t.priority_local,
            t.is_auto_scheduled,
            t.task_list_id,
            t.tag_id,
            t.is_locked,
            t.reminder_minutes_before
          FROM task_schedule_segments s
          INNER JOIN task_items t ON t.id = s.task_id
          INNER JOIN task_lists l ON l.id = t.task_list_id
          WHERE l.is_archived = 0
            AND t.status = 'NEEDS-ACTION'
            AND s.start_at < ?
            AND s.end_at > ?
          ORDER BY s.start_at ASC, s.segment_index ASC
          ''',
      variables: [
        Variable<String>(end.toIso8601String()),
        Variable<String>(start.toIso8601String()),
      ],
    ).get();
    return rows.map((row) {
      return TaskScheduleSegmentWithTask(
        segment: TaskScheduleSegment.fromRow(row),
        task: _taskFromRow(row),
      );
    }).toList();
  }

  Future<List<TaskScheduleSegment>> getByTaskId(int taskId) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM task_schedule_segments
      WHERE task_id = ?
      ORDER BY start_at ASC, segment_index ASC
      ''',
      variables: [Variable<int>(taskId)],
    ).get();
    return rows.map(TaskScheduleSegment.fromRow).toList();
  }

  Future<void> replaceForTasks({
    required Iterable<int> taskIds,
    required List<TaskScheduleSegmentDraft> segments,
    required String actor,
    required String summary,
    required Map<String, dynamic> metadata,
  }) async {
    final ids = taskIds.toSet();
    if (ids.isEmpty && segments.isEmpty) {
      return;
    }
    final before = <String, Object?>{};
    for (final id in ids) {
      before[id.toString()] =
          (await getByTaskId(id)).map((segment) => segment.toJson()).toList();
    }

    await _db.transaction(() async {
      for (final id in ids) {
        await _db.customStatement(
          'DELETE FROM task_schedule_segments WHERE task_id = ?',
          [id],
        );
      }
      for (final segment in segments) {
        final now = DateTime.now().toIso8601String();
        await _db.customStatement(
          '''
          INSERT INTO task_schedule_segments (
            task_id,
            segment_index,
            start_at,
            end_at,
            source,
            plan_run_id,
            note,
            created_at,
            updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            segment.taskId,
            segment.segmentIndex,
            segment.startAt.toIso8601String(),
            segment.endAt.toIso8601String(),
            segment.source,
            segment.planRunId,
            segment.note,
            now,
            now,
          ],
        );
      }
    });

    await _operationLogs.record(
      actor: actor,
      action: 'replace_task_schedule_segments',
      entityType: 'task_schedule_segments',
      entityId: ids.join(','),
      summary: summary,
      before: before,
      after: segments.map((segment) => segment.toJson()).toList(),
      metadata: metadata,
    );
  }

  Future<void> clearForTask({
    required int taskId,
    required String actor,
    required String summary,
  }) async {
    await replaceForTasks(
      taskIds: [taskId],
      segments: const <TaskScheduleSegmentDraft>[],
      actor: actor,
      summary: summary,
      metadata: const {'reason': 'clear_single_task_segments'},
    );
  }

  TaskItem _taskFromRow(QueryRow row) {
    return TaskItem(
      id: row.read<int>('task_row_id'),
      uid: row.read<String>('uid'),
      dtstamp: _readDateTime(row, 'dtstamp'),
      summary: row.read<String>('summary'),
      description: row.data['description'] as String?,
      dtstart: _readNullableDateTime(row, 'dtstart'),
      due: _readNullableDateTime(row, 'due'),
      completed: _readNullableDateTime(row, 'completed'),
      priority: row.read<int>('priority'),
      status: row.read<String>('status'),
      percentComplete: row.read<int>('percent_complete'),
      categories: row.read<String>('categories'),
      rrule: row.data['rrule'] as String?,
      durationMinutes: row.read<int>('duration_minutes'),
      isSplittable: _readBool(row, 'is_splittable'),
      priorityLocal: row.read<int>('priority_local'),
      isAutoScheduled: _readBool(row, 'is_auto_scheduled'),
      taskListId: row.data['task_list_id'] as int?,
      tagId: row.data['tag_id'] as String?,
      isLocked: _readBool(row, 'is_locked'),
      reminderMinutesBefore: row.read<int>('reminder_minutes_before'),
    );
  }

  DateTime _readDateTime(QueryRow row, String column) {
    final value = row.data[column];
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    return DateTime.now();
  }

  DateTime? _readNullableDateTime(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    return null;
  }

  bool _readBool(QueryRow row, String column) {
    final value = row.data[column];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
    return false;
  }
}
