import 'dart:convert';

class OutlookTaskListBinding {
  const OutlookTaskListBinding({
    required this.localTaskListId,
    required this.remoteCalendarId,
    required this.remoteCalendarName,
    required this.linkedAt,
  });

  final int localTaskListId;
  final String remoteCalendarId;
  final String remoteCalendarName;
  final DateTime linkedAt;

  Map<String, dynamic> toJson() => {
        'local_task_list_id': localTaskListId,
        'remote_calendar_id': remoteCalendarId,
        'remote_calendar_name': remoteCalendarName,
        'linked_at': linkedAt.toIso8601String(),
      };

  factory OutlookTaskListBinding.fromJson(Map<String, dynamic> json) {
    return OutlookTaskListBinding(
      localTaskListId: json['local_task_list_id'] as int? ?? 0,
      remoteCalendarId: (json['remote_calendar_id'] as String? ?? '').trim(),
      remoteCalendarName:
          (json['remote_calendar_name'] as String? ?? '').trim(),
      linkedAt: DateTime.tryParse(json['linked_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  OutlookTaskListBinding copyWith({
    int? localTaskListId,
    String? remoteCalendarId,
    String? remoteCalendarName,
    DateTime? linkedAt,
  }) {
    return OutlookTaskListBinding(
      localTaskListId: localTaskListId ?? this.localTaskListId,
      remoteCalendarId: remoteCalendarId ?? this.remoteCalendarId,
      remoteCalendarName: remoteCalendarName ?? this.remoteCalendarName,
      linkedAt: linkedAt ?? this.linkedAt,
    );
  }

  static Map<int, OutlookTaskListBinding> decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <int, OutlookTaskListBinding>{};
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final result = <int, OutlookTaskListBinding>{};
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final binding =
            OutlookTaskListBinding.fromJson(Map<String, dynamic>.from(item));
        if (binding.localTaskListId <= 0 ||
            binding.remoteCalendarId.isEmpty ||
            binding.remoteCalendarName.isEmpty) {
          continue;
        }
        result[binding.localTaskListId] = binding;
      }
      return result;
    } catch (_) {
      return <int, OutlookTaskListBinding>{};
    }
  }

  static String encodeMap(Map<int, OutlookTaskListBinding> bindings) {
    final items = bindings.values
        .map((binding) => binding.toJson())
        .toList(growable: false);
    return jsonEncode(items);
  }
}
