import 'dart:io';

import 'package:flutter/services.dart';

enum AndroidUsageEventType {
  activityResumed,
  activityPaused,
  activityStopped,
  moveToForeground,
  moveToBackground,
}

extension AndroidUsageEventTypeValue on AndroidUsageEventType {
  static AndroidUsageEventType? fromValue(String rawValue) {
    return switch (rawValue) {
      'activity_resumed' => AndroidUsageEventType.activityResumed,
      'activity_paused' => AndroidUsageEventType.activityPaused,
      'activity_stopped' => AndroidUsageEventType.activityStopped,
      'move_to_foreground' => AndroidUsageEventType.moveToForeground,
      'move_to_background' => AndroidUsageEventType.moveToBackground,
      _ => null,
    };
  }

  bool get opensForegroundSession {
    return this == AndroidUsageEventType.activityResumed ||
        this == AndroidUsageEventType.moveToForeground;
  }

  bool get closesForegroundSession {
    return this == AndroidUsageEventType.activityPaused ||
        this == AndroidUsageEventType.activityStopped ||
        this == AndroidUsageEventType.moveToBackground;
  }
}

class AndroidUsageEvent {
  const AndroidUsageEvent({
    required this.timestamp,
    required this.packageName,
    required this.eventType,
    this.className,
    this.appLabel,
  });

  final DateTime timestamp;
  final String packageName;
  final AndroidUsageEventType eventType;
  final String? className;
  final String? appLabel;

  factory AndroidUsageEvent.fromMap(Map<String, Object?> map) {
    final rawEventType = map['eventType'] as String? ?? '';
    final eventType = AndroidUsageEventTypeValue.fromValue(rawEventType);
    if (eventType == null) {
      throw ArgumentError('Unsupported Android usage event type: $rawEventType');
    }

    final timestampMillis = (map['timestampMillis'] as num?)?.toInt() ?? 0;
    return AndroidUsageEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMillis),
      packageName: (map['packageName'] as String? ?? '').trim(),
      eventType: eventType,
      className: (map['className'] as String?)?.trim(),
      appLabel: (map['appLabel'] as String?)?.trim(),
    );
  }
}

class AndroidUsageStatsService {
  const AndroidUsageStatsService();

  static const MethodChannel _channel =
      MethodChannel('com.flowplan.flawplanv2/android_usage_stats');

  Future<bool> hasUsageAccessPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final granted =
        await _channel.invokeMethod<bool>('getUsageAccessPermissionStatus');
    return granted ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<List<AndroidUsageEvent>> queryUsageEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!Platform.isAndroid) {
      return const <AndroidUsageEvent>[];
    }

    final rawList = await _channel.invokeMethod<List<Object?>>(
          'queryUsageEvents',
          <String, Object?>{
            'sinceMillis': start.millisecondsSinceEpoch,
            'untilMillis': end.millisecondsSinceEpoch,
          },
        ) ??
        const <Object?>[];

    final events = <AndroidUsageEvent>[];
    for (final item in rawList) {
      if (item is! Map) {
        continue;
      }
      try {
        events.add(
          AndroidUsageEvent.fromMap(
            Map<String, Object?>.from(item),
          ),
        );
      } catch (_) {
        // Skip malformed native payloads so one bad event won't block import.
      }
    }

    events.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return events;
  }
}
