import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity_service.dart';
import '../data/activity_record_repository.dart';
import '../models/activity_log_entry.dart';
import '../services/window_sensor.dart';
import '../tracker_defaults.dart';
import 'activity_classifier.dart';
import 'activity_log_service.dart';
import 'android_usage_stats_service.dart';

class AndroidUsageImportResult {
  const AndroidUsageImportResult({
    required this.supported,
    required this.permissionGranted,
    required this.importedRecordCount,
    required this.importedLogCount,
    this.importedUntil,
    this.latestSnapshot,
    this.latestClassification,
    this.latestSessionStart,
  });

  const AndroidUsageImportResult.unsupported()
      : supported = false,
        permissionGranted = false,
        importedRecordCount = 0,
        importedLogCount = 0,
        importedUntil = null,
        latestSnapshot = null,
        latestClassification = null,
        latestSessionStart = null;

  final bool supported;
  final bool permissionGranted;
  final int importedRecordCount;
  final int importedLogCount;
  final DateTime? importedUntil;
  final WindowSnapshot? latestSnapshot;
  final ActivityClassification? latestClassification;
  final DateTime? latestSessionStart;
}

class AndroidUsageImportService {
  AndroidUsageImportService({
    required AppDatabase database,
    required ActivityRecordRepository activityRecordRepository,
    required ActivityLogService activityLogService,
    ActivityClassifier? classifier,
    AndroidUsageStatsService? usageStatsService,
    DeviceIdentityService? deviceIdentityService,
  })  : _database = database,
        _activityRecordRepository = activityRecordRepository,
        _activityLogService = activityLogService,
        _classifier = classifier ?? ActivityClassifier(),
        _usageStatsService = usageStatsService ?? const AndroidUsageStatsService(),
        _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService();

  static const _cursorSettingKey = 'tracker.android_usage_stats_cursor_millis';
  static const _androidSource = 'android_usage_stats';
  static const _minimumSessionDuration = Duration(seconds: 3);
  static const _mergeGapThreshold = Duration(seconds: 12);

  final AppDatabase _database;
  final ActivityRecordRepository _activityRecordRepository;
  final ActivityLogService _activityLogService;
  final ActivityClassifier _classifier;
  final AndroidUsageStatsService _usageStatsService;
  final DeviceIdentityService _deviceIdentityService;

  Future<AndroidUsageImportResult> importLatest() async {
    if (!Platform.isAndroid) {
      return const AndroidUsageImportResult.unsupported();
    }

    final permissionGranted = await _usageStatsService.hasUsageAccessPermission();
    if (!permissionGranted) {
      return const AndroidUsageImportResult(
        supported: true,
        permissionGranted: false,
        importedRecordCount: 0,
        importedLogCount: 0,
      );
    }

    final now = DateTime.now();
    final importStart = await _resolveImportStart(now);
    final events = await _usageStatsService.queryUsageEvents(
      start: importStart,
      end: now,
    );
    final nextCursor = _resolveNextCursor(now, events);
    if (events.isEmpty) {
      await _setCursor(nextCursor);
      return AndroidUsageImportResult(
        supported: true,
        permissionGranted: true,
        importedRecordCount: 0,
        importedLogCount: 0,
        importedUntil: nextCursor,
      );
    }

    final sessions = _buildSessions(
      events: events,
      rangeStart: importStart,
      rangeEnd: now,
    );
    final deviceId = await _deviceIdentityService.getOrCreateDeviceId(_database);

    var importedRecordCount = 0;
    var importedLogCount = 0;
    WindowSnapshot? latestSnapshot;
    ActivityClassification? latestClassification;
    DateTime? latestSessionStart;

    for (final session in sessions) {
      if (_shouldIgnorePackage(session.packageName)) {
        continue;
      }

      final displayLabel = _effectiveAppLabel(session);
      final classification = _classifier.classifyAndroidApp(
        packageName: session.packageName,
        appLabel: displayLabel,
        className: session.className,
        timestamp: session.start,
      );

      final recordId = await _activityRecordRepository.insertImportedRecord(
        startTime: session.start,
        endTime: session.end,
        processName: displayLabel,
        windowTitle: displayLabel,
        packageName: session.packageName,
        category: classification.category,
        deviceId: deviceId,
        platform: _deviceIdentityService.currentPlatform,
        isAuto: true,
        source: _androidSource,
      );

      importedRecordCount += 1;
      importedLogCount += await _appendImportedLogs(
        recordId: recordId,
        session: session,
        classification: classification,
        deviceId: deviceId,
        displayLabel: displayLabel,
      );

      latestSnapshot = WindowSnapshot(
        processName: displayLabel,
        className: session.className ?? '',
        windowTitle: displayLabel,
        isFullscreen: false,
        timestamp: session.end,
      );
      latestClassification = classification;
      latestSessionStart = session.start;
    }

    await _setCursor(nextCursor);

    return AndroidUsageImportResult(
      supported: true,
      permissionGranted: true,
      importedRecordCount: importedRecordCount,
      importedLogCount: importedLogCount,
      importedUntil: nextCursor,
      latestSnapshot: latestSnapshot,
      latestClassification: latestClassification,
      latestSessionStart: latestSessionStart,
    );
  }

  Future<DateTime> _resolveImportStart(DateTime now) async {
    final rawValue = await _database.getSetting(_cursorSettingKey);
    final cursorMillis = int.tryParse(rawValue ?? '');
    if (cursorMillis == null || cursorMillis <= 0) {
      return DateTime(now.year, now.month, now.day);
    }

    final cursor = DateTime.fromMillisecondsSinceEpoch(cursorMillis);
    if (cursor.isAfter(now)) {
      return DateTime(now.year, now.month, now.day);
    }
    return cursor;
  }

  DateTime _resolveNextCursor(
    DateTime now,
    List<AndroidUsageEvent> events,
  ) {
    if (events.isEmpty) {
      return now;
    }

    final nextMillis = events.last.timestamp.millisecondsSinceEpoch + 1;
    final cappedMillis = nextMillis > now.millisecondsSinceEpoch
        ? now.millisecondsSinceEpoch
        : nextMillis;
    return DateTime.fromMillisecondsSinceEpoch(cappedMillis);
  }

  Future<void> _setCursor(DateTime cursor) {
    return _database.setSetting(
      _cursorSettingKey,
      cursor.millisecondsSinceEpoch.toString(),
    );
  }

  List<_AndroidUsageSession> _buildSessions({
    required List<AndroidUsageEvent> events,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final ordered = List<AndroidUsageEvent>.from(events)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final sessions = <_AndroidUsageSession>[];
    _OpenAndroidUsageSession? current;

    for (final event in ordered) {
      final packageName = event.packageName.trim();
      if (packageName.isEmpty) {
        continue;
      }

      if (event.eventType.opensForegroundSession) {
        final hasSameActivePackage = current != null &&
            current.packageName == packageName &&
            _sameText(current.className, event.className);
        if (hasSameActivePackage) {
          current = current.copyWith(
            className: event.className ?? current.className,
            appLabel: event.appLabel ?? current.appLabel,
          );
          continue;
        }

        if (current != null) {
          sessions.add(current.closeAt(event.timestamp));
        }

        current = _OpenAndroidUsageSession(
          start: event.timestamp.isBefore(rangeStart) ? rangeStart : event.timestamp,
          packageName: packageName,
          className: _cleanText(event.className),
          appLabel: _cleanText(event.appLabel),
        );
        continue;
      }

      if (event.eventType.closesForegroundSession &&
          current != null &&
          current.packageName == packageName) {
        sessions.add(current.closeAt(event.timestamp));
        current = null;
      }
    }

    if (current != null) {
      sessions.add(current.closeAt(rangeEnd));
    }

    final filtered = sessions
        .where((session) => session.end.isAfter(session.start))
        .where((session) => session.end.difference(session.start) >= _minimumSessionDuration)
        .where((session) => !_shouldIgnorePackage(session.packageName))
        .toList(growable: false);
    return _mergeAdjacentSessions(filtered);
  }

  List<_AndroidUsageSession> _mergeAdjacentSessions(
    List<_AndroidUsageSession> sessions,
  ) {
    if (sessions.isEmpty) {
      return const <_AndroidUsageSession>[];
    }

    final merged = <_AndroidUsageSession>[sessions.first];
    for (final session in sessions.skip(1)) {
      final previous = merged.last;
      final gap = session.start.difference(previous.end);
      final shouldMerge = previous.packageName == session.packageName &&
          gap <= _mergeGapThreshold;
      if (!shouldMerge) {
        merged.add(session);
        continue;
      }

      merged[merged.length - 1] = previous.copyWith(
        end: session.end,
        className: previous.className ?? session.className,
        appLabel: previous.appLabel ?? session.appLabel,
      );
    }
    return merged;
  }

  Future<int> _appendImportedLogs({
    required int recordId,
    required _AndroidUsageSession session,
    required ActivityClassification classification,
    required String deviceId,
    required String displayLabel,
  }) async {
    var count = 0;
    final openEntry = ActivityLogEntry(
      timestamp: session.start,
      type: ActivityLogEntryType.sessionOpen,
      recordId: recordId,
      isIgnored: false,
      isFullscreen: false,
      processName: displayLabel,
      packageName: session.packageName,
      className: session.className,
      windowTitle: displayLabel,
      appLabel: displayLabel,
      category: classification.category,
      label: classification.label,
      durationMinutes: 0,
      deviceId: deviceId,
      platform: _deviceIdentityService.currentPlatform,
      source: _androidSource,
      note: 'android_import_open',
    );
    await _activityLogService.append(openEntry);
    count += 1;

    final closeEntry = ActivityLogEntry(
      timestamp: session.end,
      type: ActivityLogEntryType.sessionClose,
      recordId: recordId,
      isIgnored: false,
      isFullscreen: false,
      processName: displayLabel,
      packageName: session.packageName,
      className: session.className,
      windowTitle: displayLabel,
      appLabel: displayLabel,
      category: classification.category,
      label: classification.label,
      durationMinutes:
          session.end.difference(session.start).inMinutes.clamp(0, 1 << 31).toInt(),
      deviceId: deviceId,
      platform: _deviceIdentityService.currentPlatform,
      source: _androidSource,
      note: 'android_import_close',
    );
    await _activityLogService.append(closeEntry);
    count += 1;

    return count;
  }

  String _effectiveAppLabel(_AndroidUsageSession session) {
    final appLabel = _cleanText(session.appLabel);
    if (appLabel != null) {
      return appLabel;
    }
    return session.packageName;
  }

  bool _shouldIgnorePackage(String? packageName) {
    final normalized = packageName?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return true;
    }
    return isAndroidTrackerIgnoredPackage(normalized);
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static bool _sameText(String? left, String? right) {
    final normalizedLeft = _cleanText(left);
    final normalizedRight = _cleanText(right);
    if (normalizedLeft == null || normalizedRight == null) {
      return normalizedLeft == normalizedRight;
    }
    return normalizedLeft == normalizedRight;
  }
}

class _OpenAndroidUsageSession {
  const _OpenAndroidUsageSession({
    required this.start,
    required this.packageName,
    this.className,
    this.appLabel,
  });

  final DateTime start;
  final String packageName;
  final String? className;
  final String? appLabel;

  _OpenAndroidUsageSession copyWith({
    String? className,
    String? appLabel,
  }) {
    return _OpenAndroidUsageSession(
      start: start,
      packageName: packageName,
      className: className ?? this.className,
      appLabel: appLabel ?? this.appLabel,
    );
  }

  _AndroidUsageSession closeAt(DateTime end) {
    final normalizedEnd = end.isAfter(start)
        ? end
        : start.add(const Duration(seconds: 1));
    return _AndroidUsageSession(
      start: start,
      end: normalizedEnd,
      packageName: packageName,
      className: className,
      appLabel: appLabel,
    );
  }
}

class _AndroidUsageSession {
  const _AndroidUsageSession({
    required this.start,
    required this.end,
    required this.packageName,
    this.className,
    this.appLabel,
  });

  final DateTime start;
  final DateTime end;
  final String packageName;
  final String? className;
  final String? appLabel;

  _AndroidUsageSession copyWith({
    DateTime? end,
    String? className,
    String? appLabel,
  }) {
    return _AndroidUsageSession(
      start: start,
      end: end ?? this.end,
      packageName: packageName,
      className: className ?? this.className,
      appLabel: appLabel ?? this.appLabel,
    );
  }
}
