import 'dart:convert';

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
    this.remoteLastModifiedAt,
  });

  final int localTaskId;
  final int localTaskListId;
  final String remoteCalendarId;
  final String remoteCalendarName;
  final String remoteEventId;
  final DateTime syncedAt;
  final String? localSnapshotHash;
  final String? localSnapshotJson;
  final DateTime? remoteLastModifiedAt;

  Map<String, dynamic> toJson() => {
        'local_task_id': localTaskId,
        'local_task_list_id': localTaskListId,
        'remote_calendar_id': remoteCalendarId,
        'remote_calendar_name': remoteCalendarName,
        'remote_event_id': remoteEventId,
        'synced_at': syncedAt.toIso8601String(),
        'local_snapshot_hash': localSnapshotHash,
        'local_snapshot_json': localSnapshotJson,
        'remote_last_modified_at': remoteLastModifiedAt?.toIso8601String(),
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
      localSnapshotHash:
          (json['local_snapshot_hash'] as String?)?.trim(),
      localSnapshotJson:
          (json['local_snapshot_json'] as String?)?.trim(),
      remoteLastModifiedAt: DateTime.tryParse(
        json['remote_last_modified_at'] as String? ?? '',
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
    DateTime? remoteLastModifiedAt,
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
      remoteLastModifiedAt:
          remoteLastModifiedAt ?? this.remoteLastModifiedAt,
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
