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
    required this.location,
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

  static const metadataStartMarker = 'FLOWPLANV2_TASK_META_START';
  static const metadataEndMarker = 'FLOWPLANV2_TASK_META_END';

  final int taskId;
  final String taskUid;
  final int? taskListId;
  final String taskListName;
  final String summary;
  final String? description;
  final String? location;
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
      summary: task.summary.trim(),
      description: task.description?.trim(),
      location: task.location?.trim(),
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

  factory OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent({
    required TaskItem task,
    required String taskListName,
    required Map<String, dynamic> event,
  }) {
    final bodyMap = event['body'] as Map<String, dynamic>?;
    final bodyContent = (bodyMap?['content'] as String?)?.trim();
    final metadata = tryExtractMetadata(bodyContent);
    final base = metadata == null
        ? OutlookTaskMirrorSnapshot.fromTask(
            task: task,
            taskListName: taskListName,
          )
        : OutlookTaskMirrorSnapshot.fromJson(metadata);

    final start =
        DateTime.tryParse(_nestedString(event, 'start', 'dateTime'))?.toLocal();
    final end =
        DateTime.tryParse(_nestedString(event, 'end', 'dateTime'))?.toLocal();
    final subject = (event['subject'] as String?)?.trim();
    final extractedDescription = extractDescriptionFromBody(bodyContent);
    final extractedLocation = _nestedString(event, 'location', 'displayName');

    return base.copyWith(
      taskId: task.id,
      taskUid: base.taskUid.trim().isEmpty ? task.uid : base.taskUid,
      taskListId: task.taskListId ?? base.taskListId,
      taskListName: taskListName,
      summary: subject == null || subject.isEmpty ? base.summary : subject,
      description: extractedDescription ?? base.description,
      location: extractedLocation.isEmpty ? base.location : extractedLocation,
      status: _taskStatusFromGraph(event['showAs'] as String?) ?? base.status,
      dtstart: start ?? base.dtstart,
      due: end ?? base.due,
      durationMinutes: _resolveDurationMinutes(
        start: start ?? base.dtstart,
        end: end ?? base.due,
        fallback: base.durationMinutes,
      ),
    );
  }

  factory OutlookTaskMirrorSnapshot.fromJson(Map<String, dynamic> json) {
    return OutlookTaskMirrorSnapshot(
      taskId: json['task_id'] as int? ?? 0,
      taskUid: (json['task_uid'] as String? ?? '').trim(),
      taskListId: json['task_list_id'] as int?,
      taskListName: (json['task_list_name'] as String? ?? '').trim(),
      summary: (json['summary'] as String? ?? '').trim(),
      description: (json['description'] as String?)?.trim(),
      location: (json['location'] as String?)?.trim(),
      status: (json['status'] as String? ?? 'NEEDS-ACTION').trim(),
      dtstart: _parseDateTime(json['dtstart']),
      due: _parseDateTime(json['due']),
      completed: _parseDateTime(json['completed']),
      durationMinutes: json['duration_minutes'] as int? ?? 60,
      priorityLocal: json['priority_local'] as int? ?? 2,
      percentComplete: json['percent_complete'] as int? ?? 0,
      isAutoScheduled: json['is_auto_scheduled'] as bool? ?? true,
      isSplittable: json['is_splittable'] as bool? ?? false,
      isLocked: json['is_locked'] as bool? ?? false,
      reminderMinutesBefore: json['reminder_minutes_before'] as int? ?? 15,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': 3,
        'task_id': taskId,
        'task_uid': taskUid,
        'task_list_id': taskListId,
        'task_list_name': taskListName,
        'summary': summary,
        'description': description,
        'location': location,
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

  OutlookTaskMirrorSnapshot copyWith({
    int? taskId,
    String? taskUid,
    int? taskListId,
    String? taskListName,
    String? summary,
    String? description,
    String? location,
    String? status,
    DateTime? dtstart,
    DateTime? due,
    DateTime? completed,
    int? durationMinutes,
    int? priorityLocal,
    int? percentComplete,
    bool? isAutoScheduled,
    bool? isSplittable,
    bool? isLocked,
    int? reminderMinutesBefore,
  }) {
    return OutlookTaskMirrorSnapshot(
      taskId: taskId ?? this.taskId,
      taskUid: taskUid ?? this.taskUid,
      taskListId: taskListId ?? this.taskListId,
      taskListName: taskListName ?? this.taskListName,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      status: status ?? this.status,
      dtstart: dtstart ?? this.dtstart,
      due: due ?? this.due,
      completed: completed ?? this.completed,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      priorityLocal: priorityLocal ?? this.priorityLocal,
      percentComplete: percentComplete ?? this.percentComplete,
      isAutoScheduled: isAutoScheduled ?? this.isAutoScheduled,
      isSplittable: isSplittable ?? this.isSplittable,
      isLocked: isLocked ?? this.isLocked,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
    );
  }

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

  static Map<String, dynamic>? tryExtractMetadata(String? bodyContent) {
    if (bodyContent == null || bodyContent.trim().isEmpty) {
      return null;
    }

    final startIndex = bodyContent.indexOf(metadataStartMarker);
    final endIndex = bodyContent.indexOf(metadataEndMarker);
    if (startIndex < 0 || endIndex <= startIndex) {
      return null;
    }

    final rawJson = bodyContent
        .substring(startIndex + metadataStartMarker.length, endIndex)
        .trim();
    if (rawJson.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? extractDescriptionFromBody(String? bodyContent) {
    if (bodyContent == null || bodyContent.trim().isEmpty) {
      return null;
    }

    const startMarker = '\u4e8c\u3001\u4efb\u52a1\u63cf\u8ff0';
    const endMarker = '---';
    final startIndex = bodyContent.indexOf(startMarker);
    if (startIndex < 0) {
      return null;
    }

    final sliceStart = startIndex + startMarker.length;
    final endIndex = bodyContent.indexOf(endMarker, sliceStart);
    final raw = (endIndex < 0
            ? bodyContent.substring(sliceStart)
            : bodyContent.substring(sliceStart, endIndex))
        .trim();
    if (raw.isEmpty || raw == '\u65e0') {
      return null;
    }
    return raw;
  }

  static List<String> changedFieldLabels({
    required String? previousSnapshotJson,
    required OutlookTaskMirrorSnapshot current,
  }) {
    if (previousSnapshotJson == null || previousSnapshotJson.trim().isEmpty) {
      return const <String>['\u7f3a\u5c11\u4e0a\u4e00\u8f6e\u5b57\u6bb5\u5feb\u7167'];
    }

    try {
      final previous = jsonDecode(previousSnapshotJson) as Map<String, dynamic>;
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
      return const <String>['\u4e0a\u4e00\u8f6e\u5b57\u6bb5\u5feb\u7167\u65e0\u6cd5\u89e3\u6790'];
    }
  }

  static List<String> changedFieldLabelsBetween({
    required String? leftSnapshotJson,
    required String? rightSnapshotJson,
  }) {
    if (leftSnapshotJson == null || leftSnapshotJson.trim().isEmpty) {
      return const <String>['\u7f3a\u5c11\u5de6\u4fa7\u5b57\u6bb5\u5feb\u7167'];
    }
    if (rightSnapshotJson == null || rightSnapshotJson.trim().isEmpty) {
      return const <String>['\u7f3a\u5c11\u53f3\u4fa7\u5b57\u6bb5\u5feb\u7167'];
    }

    try {
      final left = jsonDecode(leftSnapshotJson) as Map<String, dynamic>;
      final right = jsonDecode(rightSnapshotJson) as Map<String, dynamic>;
      final changed = <String>[];
      for (final entry in _fieldLabels.entries) {
        if (left[entry.key]?.toString() != right[entry.key]?.toString()) {
          changed.add(entry.value);
        }
      }
      return changed;
    } catch (_) {
      return const <String>['\u5b57\u6bb5\u5feb\u7167\u65e0\u6cd5\u89e3\u6790'];
    }
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  static String _nestedString(
    Map<String, dynamic> source,
    String objectKey,
    String valueKey,
  ) {
    final nested = source[objectKey] as Map<String, dynamic>?;
    return (nested?[valueKey] as String? ?? '').trim();
  }

  static int _resolveDurationMinutes({
    required DateTime? start,
    required DateTime? end,
    required int fallback,
  }) {
    if (start == null || end == null) {
      return fallback <= 0 ? 60 : fallback;
    }
    final minutes = end.difference(start).inMinutes;
    return minutes <= 0 ? (fallback <= 0 ? 60 : fallback) : minutes;
  }

  static String? _taskStatusFromGraph(String? showAsRaw) {
    switch ((showAsRaw ?? '').trim().toLowerCase()) {
      case 'free':
        return 'COMPLETED';
      case 'tentative':
        return 'IN-PROCESS';
      case 'busy':
      case 'oof':
        return 'NEEDS-ACTION';
      default:
        return null;
    }
  }

  static const _fieldLabels = <String, String>{
    'summary': '\u6807\u9898',
    'description': '\u63cf\u8ff0',
    'location': '地点',
    'status': '\u72b6\u6001',
    'dtstart': '\u8ba1\u5212\u5f00\u59cb',
    'due': '\u622a\u6b62\u65f6\u95f4',
    'completed': '\u5b8c\u6210\u65f6\u95f4',
    'duration_minutes': '\u9884\u8ba1\u65f6\u957f',
    'priority_local': '\u4f18\u5148\u7ea7',
    'percent_complete': '\u5b8c\u6210\u5ea6',
    'is_auto_scheduled': '\u81ea\u52a8\u6392\u7a0b',
    'is_splittable': '\u5141\u8bb8\u62c6\u5206',
    'is_locked': '\u9501\u5b9a\u6392\u7a0b',
    'reminder_minutes_before': '\u63d0\u524d\u63d0\u9192',
  };
}
