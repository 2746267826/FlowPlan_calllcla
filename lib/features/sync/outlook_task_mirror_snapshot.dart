import 'dart:convert';

import '../../core/database/app_database.dart';

class OutlookTaskMirrorSnapshot {
  const OutlookTaskMirrorSnapshot({
    required this.taskId,
    required this.taskUid,
    required this.taskListId,
    required this.taskListName,
    required this.summary,
    required this.description,
    required this.status,
    required this.dtstart,
    required this.due,
    required this.completed,
    required this.durationMinutes,
    required this.priorityLocal,
    required this.percentComplete,
    required this.isAutoScheduled,
    required this.isSplittable,
    required this.isLocked,
    required this.reminderMinutesBefore,
  });

  final int taskId;
  final String taskUid;
  final int? taskListId;
  final String taskListName;
  final String summary;
  final String? description;
  final String status;
  final DateTime? dtstart;
  final DateTime? due;
  final DateTime? completed;
  final int durationMinutes;
  final int priorityLocal;
  final int percentComplete;
  final bool isAutoScheduled;
  final bool isSplittable;
  final bool isLocked;
  final int reminderMinutesBefore;

  factory OutlookTaskMirrorSnapshot.fromTask({
    required TaskItem task,
    required String taskListName,
  }) {
    return OutlookTaskMirrorSnapshot(
      taskId: task.id,
      taskUid: task.uid,
      taskListId: task.taskListId,
      taskListName: taskListName,
      summary: task.summary,
      description: task.description?.trim(),
      status: task.status,
      dtstart: task.dtstart,
      due: task.due,
      completed: task.completed,
      durationMinutes: task.durationMinutes,
      priorityLocal: task.priorityLocal,
      percentComplete: task.percentComplete,
      isAutoScheduled: task.isAutoScheduled,
      isSplittable: task.isSplittable,
      isLocked: task.isLocked,
      reminderMinutesBefore: task.reminderMinutesBefore,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': 2,
        'task_id': taskId,
        'task_uid': taskUid,
        'task_list_id': taskListId,
        'task_list_name': taskListName,
        'summary': summary,
        'description': description,
        'status': status,
        'dtstart': dtstart?.toIso8601String(),
        'due': due?.toIso8601String(),
        'completed': completed?.toIso8601String(),
        'duration_minutes': durationMinutes,
        'priority_local': priorityLocal,
        'percent_complete': percentComplete,
        'is_auto_scheduled': isAutoScheduled,
        'is_splittable': isSplittable,
        'is_locked': isLocked,
        'reminder_minutes_before': reminderMinutesBefore,
      };

  String get stableJson => jsonEncode(toJson());

  String get fingerprint => stableHash(stableJson);

  static String stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static List<String> changedFieldLabels({
    required String? previousSnapshotJson,
    required OutlookTaskMirrorSnapshot current,
  }) {
    if (previousSnapshotJson == null || previousSnapshotJson.trim().isEmpty) {
      return const <String>['缺少上一轮字段快照'];
    }

    try {
      final previous =
          jsonDecode(previousSnapshotJson) as Map<String, dynamic>;
      final currentJson = current.toJson();
      final changed = <String>[];
      for (final entry in _fieldLabels.entries) {
        if (previous[entry.key]?.toString() !=
            currentJson[entry.key]?.toString()) {
          changed.add(entry.value);
        }
      }
      return changed;
    } catch (_) {
      return const <String>['上一轮字段快照无法解析'];
    }
  }

  static const _fieldLabels = <String, String>{
    'summary': '标题',
    'description': '描述',
    'status': '状态',
    'dtstart': '计划开始',
    'due': '截止时间',
    'completed': '完成时间',
    'duration_minutes': '预计时长',
    'priority_local': '优先级',
    'percent_complete': '完成度',
    'is_auto_scheduled': '自动排程',
    'is_splittable': '允许拆分',
    'is_locked': '锁定排程',
    'reminder_minutes_before': '提前提醒',
  };
}
