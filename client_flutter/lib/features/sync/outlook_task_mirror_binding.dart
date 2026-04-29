import 'dart:convert';

enum OutlookTaskMirrorConflictState {
  none,
  pendingLocalPush,
  remoteDeleted,
  remoteChanged,
  divergent,
  writeFailed,
}

extension OutlookTaskMirrorConflictStateX
    on OutlookTaskMirrorConflictState {
  String get storageValue {
    switch (this) {
      case OutlookTaskMirrorConflictState.none:
        return 'none';
      case OutlookTaskMirrorConflictState.pendingLocalPush:
        return 'pending_local_push';
      case OutlookTaskMirrorConflictState.remoteDeleted:
        return 'remote_deleted';
      case OutlookTaskMirrorConflictState.remoteChanged:
        return 'remote_changed';
      case OutlookTaskMirrorConflictState.divergent:
        return 'divergent';
      case OutlookTaskMirrorConflictState.writeFailed:
        return 'write_failed';
    }
  }

  String get label {
    switch (this) {
      case OutlookTaskMirrorConflictState.none:
        return '\u6b63\u5e38';
      case OutlookTaskMirrorConflictState.pendingLocalPush:
        return '\u672c\u5730\u5f85\u5199\u56de';
      case OutlookTaskMirrorConflictState.remoteDeleted:
        return '\u8fdc\u7aef\u955c\u50cf\u5df2\u5220\u9664';
      case OutlookTaskMirrorConflictState.remoteChanged:
        return '\u8fdc\u7aef\u955c\u50cf\u5df2\u4fee\u6539';
      case OutlookTaskMirrorConflictState.divergent:
        return '\u4e24\u4fa7\u90fd\u5df2\u4fee\u6539';
      case OutlookTaskMirrorConflictState.writeFailed:
        return '\u5199\u56de\u5931\u8d25';
    }
  }
}

OutlookTaskMirrorConflictState outlookTaskMirrorConflictStateFromStorage(
  String? raw,
) {
  switch ((raw ?? '').trim()) {
    case 'pending_local_push':
      return OutlookTaskMirrorConflictState.pendingLocalPush;
    case 'remote_deleted':
      return OutlookTaskMirrorConflictState.remoteDeleted;
    case 'remote_changed':
      return OutlookTaskMirrorConflictState.remoteChanged;
    case 'divergent':
      return OutlookTaskMirrorConflictState.divergent;
    case 'write_failed':
      return OutlookTaskMirrorConflictState.writeFailed;
    case 'none':
    default:
      return OutlookTaskMirrorConflictState.none;
  }
}

class OutlookTaskMirrorBinding {
  const OutlookTaskMirrorBinding({
    required this.localTaskId,
    required this.localTaskListId,
    required this.remoteCalendarId,
    required this.remoteCalendarName,
    required this.remoteEventId,
    required this.syncedAt,
    this.localSnapshotHash,
    this.localSnapshotJson,
    this.remoteSnapshotHash,
    this.remoteSnapshotJson,
    this.remoteLastModifiedAt,
    this.conflictState = OutlookTaskMirrorConflictState.none,
    this.conflictMessage,
    this.conflictDetectedAt,
  });

  final int localTaskId;
  final int localTaskListId;
  final String remoteCalendarId;
  final String remoteCalendarName;
  final String remoteEventId;
  final DateTime syncedAt;
  final String? localSnapshotHash;
  final String? localSnapshotJson;
  final String? remoteSnapshotHash;
  final String? remoteSnapshotJson;
  final DateTime? remoteLastModifiedAt;
  final OutlookTaskMirrorConflictState conflictState;
  final String? conflictMessage;
  final DateTime? conflictDetectedAt;

  Map<String, dynamic> toJson() => {
        'local_task_id': localTaskId,
        'local_task_list_id': localTaskListId,
        'remote_calendar_id': remoteCalendarId,
        'remote_calendar_name': remoteCalendarName,
        'remote_event_id': remoteEventId,
        'synced_at': syncedAt.toIso8601String(),
        'local_snapshot_hash': localSnapshotHash,
        'local_snapshot_json': localSnapshotJson,
        'remote_snapshot_hash': remoteSnapshotHash,
        'remote_snapshot_json': remoteSnapshotJson,
        'remote_last_modified_at': remoteLastModifiedAt?.toIso8601String(),
        'conflict_state': conflictState.storageValue,
        'conflict_message': conflictMessage,
        'conflict_detected_at': conflictDetectedAt?.toIso8601String(),
      };

  factory OutlookTaskMirrorBinding.fromJson(Map<String, dynamic> json) {
    return OutlookTaskMirrorBinding(
      localTaskId: json['local_task_id'] as int? ?? 0,
      localTaskListId: json['local_task_list_id'] as int? ?? 0,
      remoteCalendarId: (json['remote_calendar_id'] as String? ?? '').trim(),
      remoteCalendarName:
          (json['remote_calendar_name'] as String? ?? '').trim(),
      remoteEventId: (json['remote_event_id'] as String? ?? '').trim(),
      syncedAt:
          DateTime.tryParse(json['synced_at'] as String? ?? '') ?? DateTime.now(),
      localSnapshotHash: (json['local_snapshot_hash'] as String?)?.trim(),
      localSnapshotJson: (json['local_snapshot_json'] as String?)?.trim(),
      remoteSnapshotHash: (json['remote_snapshot_hash'] as String?)?.trim(),
      remoteSnapshotJson: (json['remote_snapshot_json'] as String?)?.trim(),
      remoteLastModifiedAt: DateTime.tryParse(
        json['remote_last_modified_at'] as String? ?? '',
      ),
      conflictState: outlookTaskMirrorConflictStateFromStorage(
        json['conflict_state'] as String?,
      ),
      conflictMessage: (json['conflict_message'] as String?)?.trim(),
      conflictDetectedAt: DateTime.tryParse(
        json['conflict_detected_at'] as String? ?? '',
      ),
    );
  }

  OutlookTaskMirrorBinding copyWith({
    int? localTaskId,
    int? localTaskListId,
    String? remoteCalendarId,
    String? remoteCalendarName,
    String? remoteEventId,
    DateTime? syncedAt,
    String? localSnapshotHash,
    String? localSnapshotJson,
    String? remoteSnapshotHash,
    String? remoteSnapshotJson,
    DateTime? remoteLastModifiedAt,
    OutlookTaskMirrorConflictState? conflictState,
    String? conflictMessage,
    DateTime? conflictDetectedAt,
  }) {
    return OutlookTaskMirrorBinding(
      localTaskId: localTaskId ?? this.localTaskId,
      localTaskListId: localTaskListId ?? this.localTaskListId,
      remoteCalendarId: remoteCalendarId ?? this.remoteCalendarId,
      remoteCalendarName: remoteCalendarName ?? this.remoteCalendarName,
      remoteEventId: remoteEventId ?? this.remoteEventId,
      syncedAt: syncedAt ?? this.syncedAt,
      localSnapshotHash: localSnapshotHash ?? this.localSnapshotHash,
      localSnapshotJson: localSnapshotJson ?? this.localSnapshotJson,
      remoteSnapshotHash: remoteSnapshotHash ?? this.remoteSnapshotHash,
      remoteSnapshotJson: remoteSnapshotJson ?? this.remoteSnapshotJson,
      remoteLastModifiedAt: remoteLastModifiedAt ?? this.remoteLastModifiedAt,
      conflictState: conflictState ?? this.conflictState,
      conflictMessage: conflictMessage ?? this.conflictMessage,
      conflictDetectedAt: conflictDetectedAt ?? this.conflictDetectedAt,
    );
  }

  OutlookTaskMirrorBinding markResolved({
    required DateTime syncedAt,
    required String? localSnapshotHash,
    required String? localSnapshotJson,
    required String? remoteSnapshotHash,
    required String? remoteSnapshotJson,
    required DateTime? remoteLastModifiedAt,
    int? localTaskListId,
    String? remoteCalendarId,
    String? remoteCalendarName,
    String? remoteEventId,
  }) {
    return OutlookTaskMirrorBinding(
      localTaskId: localTaskId,
      localTaskListId: localTaskListId ?? this.localTaskListId,
      remoteCalendarId: remoteCalendarId ?? this.remoteCalendarId,
      remoteCalendarName: remoteCalendarName ?? this.remoteCalendarName,
      remoteEventId: remoteEventId ?? this.remoteEventId,
      syncedAt: syncedAt,
      localSnapshotHash: localSnapshotHash,
      localSnapshotJson: localSnapshotJson,
      remoteSnapshotHash: remoteSnapshotHash,
      remoteSnapshotJson: remoteSnapshotJson,
      remoteLastModifiedAt: remoteLastModifiedAt,
      conflictState: OutlookTaskMirrorConflictState.none,
      conflictMessage: null,
      conflictDetectedAt: null,
    );
  }

  OutlookTaskMirrorBinding markConflict({
    required OutlookTaskMirrorConflictState state,
    required String message,
    required DateTime detectedAt,
    String? localSnapshotHash,
    String? localSnapshotJson,
    String? remoteSnapshotHash,
    String? remoteSnapshotJson,
    DateTime? remoteLastModifiedAt,
  }) {
    return OutlookTaskMirrorBinding(
      localTaskId: localTaskId,
      localTaskListId: localTaskListId,
      remoteCalendarId: remoteCalendarId,
      remoteCalendarName: remoteCalendarName,
      remoteEventId: remoteEventId,
      syncedAt: syncedAt,
      localSnapshotHash: localSnapshotHash ?? this.localSnapshotHash,
      localSnapshotJson: localSnapshotJson ?? this.localSnapshotJson,
      remoteSnapshotHash: remoteSnapshotHash ?? this.remoteSnapshotHash,
      remoteSnapshotJson: remoteSnapshotJson ?? this.remoteSnapshotJson,
      remoteLastModifiedAt: remoteLastModifiedAt ?? this.remoteLastModifiedAt,
      conflictState: state,
      conflictMessage: message.trim(),
      conflictDetectedAt: detectedAt,
    );
  }

  static Map<int, OutlookTaskMirrorBinding> decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <int, OutlookTaskMirrorBinding>{};
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final result = <int, OutlookTaskMirrorBinding>{};
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final binding = OutlookTaskMirrorBinding.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (binding.localTaskId <= 0 ||
            binding.localTaskListId <= 0 ||
            binding.remoteCalendarId.isEmpty ||
            binding.remoteCalendarName.isEmpty ||
            binding.remoteEventId.isEmpty) {
          continue;
        }
        result[binding.localTaskId] = binding;
      }
      return result;
    } catch (_) {
      return <int, OutlookTaskMirrorBinding>{};
    }
  }

  static String encodeMap(Map<int, OutlookTaskMirrorBinding> bindings) {
    final items = bindings.values
        .map((binding) => binding.toJson())
        .toList(growable: false);
    return jsonEncode(items);
  }
}
