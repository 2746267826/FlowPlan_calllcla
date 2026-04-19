import 'dart:convert';

import '../services/raw_input_service.dart';

enum ActivityLogEntryType {
  sample,
  sessionOpen,
  sessionUpdate,
  sessionClose,
  snapshot,
}

extension ActivityLogEntryTypeValue on ActivityLogEntryType {
  String get value => switch (this) {
        ActivityLogEntryType.sample => 'sample',
        ActivityLogEntryType.sessionOpen => 'session_open',
        ActivityLogEntryType.sessionUpdate => 'session_update',
        ActivityLogEntryType.sessionClose => 'session_close',
        ActivityLogEntryType.snapshot => 'snapshot',
      };

  static ActivityLogEntryType fromValue(String value) {
    return switch (value) {
      'session_open' => ActivityLogEntryType.sessionOpen,
      'session_update' => ActivityLogEntryType.sessionUpdate,
      'session_close' => ActivityLogEntryType.sessionClose,
      'snapshot' => ActivityLogEntryType.snapshot,
      _ => ActivityLogEntryType.sample,
    };
  }
}

class ActivityLogEntry {
  final DateTime timestamp;
  final ActivityLogEntryType type;
  final int? recordId;
  final bool isIgnored;
  final bool isFullscreen;
  final String? processName;
  final String? packageName;
  final String? className;
  final String? windowTitle;
  final String? appLabel;
  final String? category;
  final String? label;
  final int? durationMinutes;
  final int keyCount;
  final int mouseClicks;
  final int mouseMovePx;
  final int scrollPx;
  final Map<int, int> keyDistribution;
  final String? keySequence;
  final String? deviceId;
  final String? platform;
  final String? source;
  final String? note;

  const ActivityLogEntry({
    required this.timestamp,
    required this.type,
    this.recordId,
    this.isIgnored = false,
    this.isFullscreen = false,
    this.processName,
    this.packageName,
    this.className,
    this.windowTitle,
    this.appLabel,
    this.category,
    this.label,
    this.durationMinutes,
    this.keyCount = 0,
    this.mouseClicks = 0,
    this.mouseMovePx = 0,
    this.scrollPx = 0,
    this.keyDistribution = const <int, int>{},
    this.keySequence,
    this.deviceId,
    this.platform,
    this.source,
    this.note,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    final rawKeyDistribution =
        (json['keyDistribution'] as Map<dynamic, dynamic>?) ??
            const <dynamic, dynamic>{};

    final keyDistribution = <int, int>{};
    for (final entry in rawKeyDistribution.entries) {
      final key = entry.key is int
          ? entry.key as int
          : int.tryParse(entry.key.toString());
      if (key == null) {
        continue;
      }
      keyDistribution[key] = (entry.value as num?)?.toInt() ?? 0;
    }

    return ActivityLogEntry(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      type: ActivityLogEntryTypeValue.fromValue(
        json['type'] as String? ?? 'sample',
      ),
      recordId: (json['recordId'] as num?)?.toInt(),
      isIgnored: json['isIgnored'] as bool? ?? false,
      isFullscreen: json['isFullscreen'] as bool? ?? false,
      processName: json['processName'] as String?,
      packageName: json['packageName'] as String?,
      className: json['className'] as String?,
      windowTitle: json['windowTitle'] as String?,
      appLabel: json['appLabel'] as String?,
      category: json['category'] as String?,
      label: json['label'] as String?,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      keyCount: (json['keyCount'] as num?)?.toInt() ?? 0,
      mouseClicks: (json['mouseClicks'] as num?)?.toInt() ?? 0,
      mouseMovePx: (json['mouseMovePx'] as num?)?.toInt() ?? 0,
      scrollPx: (json['scrollPx'] as num?)?.toInt() ?? 0,
      keyDistribution: keyDistribution,
      keySequence: json['keySequence'] as String?,
      deviceId: json['deviceId'] as String?,
      platform: json['platform'] as String?,
      source: json['source'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'type': type.value,
        if (recordId != null) 'recordId': recordId,
        'isIgnored': isIgnored,
        'isFullscreen': isFullscreen,
        if (processName != null) 'processName': processName,
        if (packageName != null) 'packageName': packageName,
        if (className != null) 'className': className,
        if (windowTitle != null) 'windowTitle': windowTitle,
        if (appLabel != null) 'appLabel': appLabel,
        if (category != null) 'category': category,
        if (label != null) 'label': label,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'keyCount': keyCount,
        'mouseClicks': mouseClicks,
        'mouseMovePx': mouseMovePx,
        'scrollPx': scrollPx,
        if (keyDistribution.isNotEmpty)
          'keyDistribution': keyDistribution.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        if (keySequence != null && keySequence!.isNotEmpty)
          'keySequence': keySequence,
        if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
        if (platform != null && platform!.isNotEmpty) 'platform': platform,
        if (source != null && source!.isNotEmpty) 'source': source,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  String toJsonLine() => jsonEncode(toJson());

  static ActivityLogEntry? tryParseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return ActivityLogEntry.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  factory ActivityLogEntry.fromTelemetry({
    required DateTime timestamp,
    required ActivityLogEntryType type,
    required bool isIgnored,
    required bool isFullscreen,
    required String? processName,
    String? packageName,
    required String? className,
    required String? windowTitle,
    String? appLabel,
    required String? category,
    required String? label,
    required int? recordId,
    required int? durationMinutes,
    required InputTelemetry? telemetry,
    String? deviceId,
    String? platform,
    String? source,
    String? note,
  }) {
    final snapshot = telemetry ?? InputTelemetry.empty(timestamp);
    return ActivityLogEntry(
      timestamp: timestamp,
      type: type,
      recordId: recordId,
      isIgnored: isIgnored,
      isFullscreen: isFullscreen,
      processName: processName,
      packageName: packageName,
      className: className,
      windowTitle: windowTitle,
      appLabel: appLabel,
      category: category,
      label: label,
      durationMinutes: durationMinutes,
      keyCount: snapshot.keyCount,
      mouseClicks: snapshot.clicks.total,
      mouseMovePx: snapshot.mouseMovePx,
      scrollPx: snapshot.scrollPx,
      keyDistribution: snapshot.keyDistribution,
      keySequence: snapshot.keySequence,
      deviceId: deviceId,
      platform: platform,
      source: source,
      note: note,
    );
  }
}
