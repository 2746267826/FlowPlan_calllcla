import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/platform/desktop_shell_service.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/settings_provider.dart';

final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService(
    database: ref.read(databaseProvider),
    defaultEventReminderMinutes: () => ref.read(reminderMinutesProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final reminderScheduleRefreshTickProvider = StateProvider<int>((ref) => 0);

final reminderSystemStatusProvider =
    FutureProvider<ReminderSystemStatus>((ref) {
  ref.watch(reminderScheduleRefreshTickProvider);
  final service = ref.watch(reminderServiceProvider);
  return service.getSystemStatus();
});

class ReminderSystemStatus {
  const ReminderSystemStatus({
    required this.platformLabel,
    required this.runtimeScannerEnabled,
    required this.supportsSystemSchedule,
    required this.canScheduleExactAlarms,
    required this.pendingSystemReminderCount,
    required this.lastRebuiltAt,
  });

  final String platformLabel;
  final bool runtimeScannerEnabled;
  final bool supportsSystemSchedule;
  final bool canScheduleExactAlarms;
  final int pendingSystemReminderCount;
  final DateTime? lastRebuiltAt;

  bool get needsAndroidExactAlarmPermission =>
      supportsSystemSchedule && !canScheduleExactAlarms;
}

class ReminderRebuildResult {
  const ReminderRebuildResult({
    required this.scheduledCount,
    required this.canScheduleExactAlarms,
  });

  final int scheduledCount;
  final bool canScheduleExactAlarms;
}

abstract class ReminderRuntimeEnvironment {
  bool get isAndroid;
  bool get isWindows;
  DateTime now();
}

class SystemReminderRuntimeEnvironment implements ReminderRuntimeEnvironment {
  const SystemReminderRuntimeEnvironment();

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  DateTime now() => DateTime.now();
}

abstract class ReminderNotificationGateway {
  Future<void> initialize();
  Future<bool> canScheduleExactAlarms();
  Future<void> openAndroidExactAlarmSettings();
  Future<int> pendingSystemReminderCount();
  Future<bool> scheduleSystemReminder(ReminderRequest request);
  Future<void> cancelAllSystemReminders();
  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
}

abstract final class ReminderPayloadCodec {
  static String encode(Map<String, Object?> payload) {
    return jsonEncode(normalize(payload));
  }

  static Map<String, Object?> decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return _normalizeMap(decoded);
      }
    } catch (_) {
      return <String, Object?>{};
    }
    return <String, Object?>{};
  }

  static Map<String, Object?> normalize(Map<String, Object?> payload) {
    return _normalizeMap(payload);
  }

  static Map<String, Object?> _normalizeMap(Map<dynamic, dynamic> source) {
    final normalized = <String, Object?>{};
    for (final entry in source.entries) {
      normalized['${entry.key}'] = _normalizeValue(entry.value);
    }
    return normalized;
  }

  static Object? _normalizeValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Map) {
      return _normalizeMap(value);
    }
    if (value is Iterable) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value.toString();
  }
}

class ReminderRequest {
  ReminderRequest({
    required this.id,
    required this.triggerAt,
    required this.title,
    required this.body,
    Map<String, Object?> payload = const <String, Object?>{},
  }) : payload = Map.unmodifiable(ReminderPayloadCodec.normalize(payload));

  final int id;
  final DateTime triggerAt;
  final String title;
  final String body;
  final Map<String, Object?> payload;

  String get encodedPayload => ReminderPayloadCodec.encode(payload);
}

class ReminderService {
  ReminderService({
    required AppDatabase database,
    required int Function() defaultEventReminderMinutes,
    ReminderNotificationGateway? gateway,
    ReminderRuntimeEnvironment? environment,
  })  : _db = database,
        _defaultEventReminderMinutes = defaultEventReminderMinutes,
        _environment = environment ?? const SystemReminderRuntimeEnvironment(),
        _gateway = gateway ??
            SystemReminderNotificationGateway(
              environment ?? const SystemReminderRuntimeEnvironment(),
            );

  static const _scanInterval = Duration(minutes: 1);
  static const _systemScheduleRefreshInterval = Duration(minutes: 15);
  static const _triggerGrace = Duration(seconds: 90);
  static const _lookAhead = Duration(hours: 24);
  static const _systemScheduleLookAhead = Duration(days: 7);
  static const _planDeviationGrace = Duration(minutes: 15);
  static const _lastSystemRebuiltAtSettingKey =
      'reminder.system_schedule.last_rebuilt_at';
  static const _lastSystemScheduledCountSettingKey =
      'reminder.system_schedule.last_count';

  final AppDatabase _db;
  final int Function() _defaultEventReminderMinutes;
  final ReminderRuntimeEnvironment _environment;
  final ReminderNotificationGateway _gateway;
  final Set<String> _deliveredKeys = <String>{};

  Timer? _timer;
  Timer? _systemScheduleTimer;
  bool _started = false;
  bool _isScanning = false;
  bool _isRebuildingSystemSchedule = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await _gateway.initialize();
    await rebuildSystemSchedule();
    await scanNow();
    _timer = Timer.periodic(_scanInterval, (_) {
      unawaited(scanNow());
    });
    _systemScheduleTimer = Timer.periodic(
      _systemScheduleRefreshInterval,
      (_) {
        unawaited(rebuildSystemSchedule());
      },
    );
  }

  Future<void> scanNow() async {
    if (_isScanning) {
      return;
    }
    _isScanning = true;
    try {
      final now = _environment.now();
      await _scanEvents(now);
      await _scanTasks(now);
      await _scanPlanDeviation(now);
      _trimDeliveredKeys();
    } finally {
      _isScanning = false;
    }
  }

  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    if (_isRebuildingSystemSchedule) {
      return ReminderRebuildResult(
        scheduledCount: await _gateway.pendingSystemReminderCount(),
        canScheduleExactAlarms: await _gateway.canScheduleExactAlarms(),
      );
    }

    _isRebuildingSystemSchedule = true;
    try {
      if (!_environment.isAndroid) {
        await _db.setIntSetting(_lastSystemScheduledCountSettingKey, 0);
        await _db.setSetting(
          _lastSystemRebuiltAtSettingKey,
          _environment.now().toIso8601String(),
        );
        return const ReminderRebuildResult(
          scheduledCount: 0,
          canScheduleExactAlarms: false,
        );
      }

      final canSchedule = await _gateway.canScheduleExactAlarms();
      if (!canSchedule) {
        await _gateway.cancelAllSystemReminders();
        await _db.setIntSetting(_lastSystemScheduledCountSettingKey, 0);
        await _db.setSetting(
          _lastSystemRebuiltAtSettingKey,
          _environment.now().toIso8601String(),
        );
        return const ReminderRebuildResult(
          scheduledCount: 0,
          canScheduleExactAlarms: false,
        );
      }

      final now = _environment.now();
      final requests = await _collectSystemReminderRequests(now);
      await _gateway.cancelAllSystemReminders();

      var scheduledCount = 0;
      for (final request in requests.take(128)) {
        final scheduled = await _tryScheduleSystemReminder(request);
        if (scheduled) {
          scheduledCount++;
        }
      }

      await _db.setIntSetting(
        _lastSystemScheduledCountSettingKey,
        scheduledCount,
      );
      await _db.setSetting(
        _lastSystemRebuiltAtSettingKey,
        _environment.now().toIso8601String(),
      );
      return ReminderRebuildResult(
        scheduledCount: scheduledCount,
        canScheduleExactAlarms: true,
      );
    } finally {
      _isRebuildingSystemSchedule = false;
    }
  }

  Future<bool> _tryScheduleSystemReminder(ReminderRequest request) async {
    try {
      return await _gateway.scheduleSystemReminder(request);
    } catch (_) {
      return false;
    }
  }

  Future<ReminderSystemStatus> getSystemStatus() async {
    final lastRaw = await _db.getSetting(_lastSystemRebuiltAtSettingKey);
    final lastRebuiltAt =
        lastRaw == null ? null : DateTime.tryParse(lastRaw.trim());
    final fallbackCount = await _db.getIntSetting(
      _lastSystemScheduledCountSettingKey,
      defaultValue: 0,
    );
    final pendingCount = _environment.isAndroid
        ? await _gateway.pendingSystemReminderCount()
        : fallbackCount;
    final canSchedule = await _gateway.canScheduleExactAlarms();

    return ReminderSystemStatus(
      platformLabel: _environment.isAndroid
          ? 'Android 绮惧噯闂归挓'
          : _environment.isWindows
              ? 'Windows 杩愯鏃跺己鎻愰啋'
              : 'System reminders are not available on this platform',
      runtimeScannerEnabled: _started,
      supportsSystemSchedule: _environment.isAndroid,
      canScheduleExactAlarms: canSchedule,
      pendingSystemReminderCount: pendingCount,
      lastRebuiltAt: lastRebuiltAt,
    );
  }

  Future<void> openAndroidExactAlarmSettings() {
    return _gateway.openAndroidExactAlarmSettings();
  }

  void dispose() {
    _timer?.cancel();
    _systemScheduleTimer?.cancel();
    _timer = null;
    _systemScheduleTimer = null;
    _started = false;
  }

  Future<void> _scanEvents(DateTime now) async {
    final reminderMinutes = _defaultEventReminderMinutes();
    if (reminderMinutes <= 0) {
      return;
    }

    final lower = now.subtract(Duration(minutes: reminderMinutes + 5));
    final upper = now.add(_lookAhead);
    final query = _db.select(_db.calendarEvents).join([
      innerJoin(
        _db.eventCalendars,
        _db.eventCalendars.id.equalsExp(_db.calendarEvents.eventCalendarId),
      ),
    ]);
    query.where(
      _db.eventCalendars.isVisible.equals(true) &
          _db.calendarEvents.status.isNotIn(['CANCELLED']) &
          ((_db.calendarEvents.dtstart.isBiggerOrEqualValue(lower) &
                  _db.calendarEvents.dtstart.isSmallerOrEqualValue(upper)) |
              (_db.calendarEvents.rrule.isNotNull() &
                  _db.calendarEvents.dtstart.isSmallerOrEqualValue(upper))),
    );
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);

    final rows = await query.get();
    await _scanEventRows(now, reminderMinutes, lower, upper, rows);
  }

  Future<void> _scanEventRows(
    DateTime now,
    int reminderMinutes,
    DateTime lower,
    DateTime upper,
    List<TypedResult> rows,
  ) async {
    for (final row in rows) {
      final event = row.readTable(_db.calendarEvents);
      for (final occurrenceAt
          in _eventOccurrencesInRange(event, lower, upper)) {
        final triggerAt = occurrenceAt.subtract(
          Duration(minutes: reminderMinutes),
        );
        if (!_shouldTrigger(now, triggerAt)) {
          continue;
        }

        final key = 'event:${event.id}:${triggerAt.toIso8601String()}';
        if (!_deliveredKeys.add(key)) {
          continue;
        }

        await _gateway.showReminder(
          id: _stableNotificationId(key),
          title: 'Event reminder',
          body: '${event.summary} starts at ${_formatTime(occurrenceAt)}',
          payload: ReminderPayloadCodec.encode(
            _eventPayload(
              event,
              occurrenceAt: occurrenceAt,
              triggerAt: triggerAt,
            ),
          ),
        );
      }
    }
  }

  Future<void> _scanTasks(DateTime now) async {
    final lower = now.subtract(const Duration(hours: 2));
    final upper = now.add(_lookAhead);
    final query = _db.select(_db.taskItems).join([
      innerJoin(
        _db.taskLists,
        _db.taskLists.id.equalsExp(_db.taskItems.taskListId),
      ),
    ]);
    query.where(
      _db.taskLists.isArchived.equals(false) &
          _db.taskLists.isVisible.equals(true) &
          _db.taskItems.status.isNotIn(['COMPLETED', 'CANCELLED']) &
          ((_db.taskItems.dtstart.isBiggerOrEqualValue(lower) &
                  _db.taskItems.dtstart.isSmallerOrEqualValue(upper)) |
              (_db.taskItems.due.isBiggerOrEqualValue(lower) &
                  _db.taskItems.due.isSmallerOrEqualValue(upper))),
    );
    query.orderBy([
      OrderingTerm(expression: _db.taskItems.due, mode: OrderingMode.asc),
      OrderingTerm(expression: _db.taskItems.dtstart, mode: OrderingMode.asc),
    ]);

    final rows = await query.get();
    for (final row in rows) {
      final task = row.readTable(_db.taskItems);
      final reminderMinutes = task.reminderMinutesBefore;
      if (reminderMinutes <= 0) {
        continue;
      }

      final startAt = task.dtstart;
      if (startAt != null &&
          startAt.isAfter(lower) &&
          startAt.isBefore(upper)) {
        final triggerAt = startAt.subtract(Duration(minutes: reminderMinutes));
        if (_shouldTrigger(now, triggerAt)) {
          final key = 'task-start:${task.id}:${triggerAt.toIso8601String()}';
          if (_deliveredKeys.add(key)) {
            await _gateway.showReminder(
              id: _stableNotificationId(key),
              title: 'Task start reminder',
              body: '${task.summary} starts at ${_formatTime(startAt)}',
            );
          }
        }
      }

      final dueAt = task.due;
      if (dueAt == null || dueAt.isBefore(lower) || dueAt.isAfter(upper)) {
        continue;
      }

      final dueTriggerAt = dueAt.subtract(Duration(minutes: reminderMinutes));
      if (_shouldTrigger(now, dueTriggerAt)) {
        final key = 'task-due:${task.id}:${dueTriggerAt.toIso8601String()}';
        if (_deliveredKeys.add(key)) {
          await _gateway.showReminder(
            id: _stableNotificationId(key),
            title: '浠诲姟鎴鎻愰啋',
            body: '${task.summary} 灏嗗湪 ${_formatTime(dueAt)} 鎴',
          );
        }
      }

      if (_shouldTriggerDeadlineRisk(now, dueAt, startAt)) {
        final key = 'task-risk:${task.id}:${_dayKey(now)}';
        if (_deliveredKeys.add(key)) {
          await _gateway.showReminder(
            id: _stableNotificationId(key),
            title: '浠诲姟椋庨櫓鎻愰啋',
            body: '${task.summary} has less than 2 hours before the deadline.',
          );
        }
      }
    }
  }

  Future<void> _scanPlanDeviation(DateTime now) async {
    final candidateStart = now.subtract(const Duration(hours: 8));
    final missedUntil = now.subtract(_planDeviationGrace);
    final query = _db.select(_db.taskItems).join([
      innerJoin(
        _db.taskLists,
        _db.taskLists.id.equalsExp(_db.taskItems.taskListId),
      ),
    ]);
    query.where(
      _db.taskLists.isArchived.equals(false) &
          _db.taskLists.isVisible.equals(true) &
          _db.taskItems.isAutoScheduled.equals(true) &
          _db.taskItems.status.isNotIn(['COMPLETED', 'CANCELLED']) &
          _db.taskItems.dtstart.isBiggerOrEqualValue(candidateStart) &
          _db.taskItems.dtstart.isSmallerOrEqualValue(missedUntil),
    );
    query.orderBy([OrderingTerm.asc(_db.taskItems.dtstart)]);

    final rows = await query.get();
    for (final row in rows) {
      final task = row.readTable(_db.taskItems);
      final startAt = task.dtstart;
      if (startAt == null) {
        continue;
      }

      final scheduledEnd = startAt.add(
        Duration(
            minutes: task.durationMinutes <= 0 ? 30 : task.durationMinutes),
      );
      if (now.isAfter(scheduledEnd)) {
        continue;
      }

      final key =
          'task-deviation:${task.id}:${startAt.toIso8601String()}:${_dayKey(now)}';
      if (_deliveredKeys.contains(key)) {
        continue;
      }

      final hasEvidence = await _hasLinkedActivityEvidence(
        taskId: task.id,
        start: startAt,
        end: now,
      );
      if (hasEvidence) {
        continue;
      }

      _deliveredKeys.add(key);
      await _gateway.showReminder(
        id: _stableNotificationId(key),
        title: '璁″垝鍋忕鎻愰啋',
        body:
            '${task.summary} was planned to start at ${_formatTime(startAt)}, but no linked activity has been recorded yet.',
      );
    }
  }

  Future<bool> _hasLinkedActivityEvidence({
    required int taskId,
    required DateTime start,
    required DateTime end,
  }) async {
    final countExpression = _db.activityRecords.id.count();
    final query = _db.selectOnly(_db.activityRecords)
      ..addColumns([countExpression])
      ..where(
        _db.activityRecords.linkedTaskId.equals(taskId) &
            _db.activityRecords.startTime.isSmallerOrEqualValue(end) &
            (_db.activityRecords.endTime.isNull() |
                _db.activityRecords.endTime.isBiggerOrEqualValue(start)),
      );
    final row = await query.getSingle();
    return (row.read(countExpression) ?? 0) > 0;
  }

  Future<List<ReminderRequest>> _collectSystemReminderRequests(
    DateTime now,
  ) async {
    final requests = <ReminderRequest>[];
    await _collectSystemEventReminderRequests(now, requests);
    await _collectSystemTaskReminderRequests(now, requests);
    requests.sort((left, right) => left.triggerAt.compareTo(right.triggerAt));
    return requests;
  }

  Future<void> _collectSystemEventReminderRequests(
    DateTime now,
    List<ReminderRequest> requests,
  ) async {
    final reminderMinutes = _defaultEventReminderMinutes();
    if (reminderMinutes <= 0) {
      return;
    }

    final upper = now.add(_systemScheduleLookAhead).add(
          Duration(minutes: reminderMinutes),
        );
    final query = _db.select(_db.calendarEvents).join([
      innerJoin(
        _db.eventCalendars,
        _db.eventCalendars.id.equalsExp(_db.calendarEvents.eventCalendarId),
      ),
    ]);
    query.where(
      _db.eventCalendars.isVisible.equals(true) &
          _db.calendarEvents.status.isNotIn(['CANCELLED']) &
          ((_db.calendarEvents.dtstart.isBiggerOrEqualValue(now) &
                  _db.calendarEvents.dtstart.isSmallerOrEqualValue(upper)) |
              (_db.calendarEvents.rrule.isNotNull() &
                  _db.calendarEvents.dtstart.isSmallerOrEqualValue(upper))),
    );
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);

    final rows = await query.get();
    _collectSystemEventRows(now, reminderMinutes, rows, requests);
  }

  Future<void> _collectSystemTaskReminderRequests(
    DateTime now,
    List<ReminderRequest> requests,
  ) async {
    final upper = now.add(_systemScheduleLookAhead);
    final query = _db.select(_db.taskItems).join([
      innerJoin(
        _db.taskLists,
        _db.taskLists.id.equalsExp(_db.taskItems.taskListId),
      ),
    ]);
    query.where(
      _db.taskLists.isArchived.equals(false) &
          _db.taskLists.isVisible.equals(true) &
          _db.taskItems.status.isNotIn(['COMPLETED', 'CANCELLED']) &
          ((_db.taskItems.dtstart.isBiggerOrEqualValue(now) &
                  _db.taskItems.dtstart.isSmallerOrEqualValue(upper)) |
              (_db.taskItems.due.isBiggerOrEqualValue(now) &
                  _db.taskItems.due.isSmallerOrEqualValue(upper))),
    );
    query.orderBy([
      OrderingTerm(expression: _db.taskItems.due, mode: OrderingMode.asc),
      OrderingTerm(expression: _db.taskItems.dtstart, mode: OrderingMode.asc),
    ]);

    final rows = await query.get();
    for (final row in rows) {
      final task = row.readTable(_db.taskItems);
      final reminderMinutes = task.reminderMinutesBefore;
      if (reminderMinutes <= 0) {
        continue;
      }

      final startAt = task.dtstart;
      if (startAt != null) {
        final triggerAt = startAt.subtract(Duration(minutes: reminderMinutes));
        if (_isFutureSystemTrigger(now, triggerAt)) {
          final key = 'task-start:${task.id}:${triggerAt.toIso8601String()}';
          requests.add(
            ReminderRequest(
              id: _stableNotificationId(key),
              triggerAt: triggerAt,
              title: 'Task start reminder',
              body: '${task.summary} starts at ${_formatTime(startAt)}',
            ),
          );
        }
      }

      final dueAt = task.due;
      if (dueAt == null) {
        continue;
      }

      final dueTriggerAt = dueAt.subtract(Duration(minutes: reminderMinutes));
      if (_isFutureSystemTrigger(now, dueTriggerAt)) {
        final key = 'task-due:${task.id}:${dueTriggerAt.toIso8601String()}';
        requests.add(
          ReminderRequest(
            id: _stableNotificationId(key),
            triggerAt: dueTriggerAt,
            title: '浠诲姟鎴鎻愰啋',
            body: '${task.summary} 灏嗗湪 ${_formatTime(dueAt)} 鎴',
          ),
        );
      }

      final riskTriggerAt = dueAt.subtract(const Duration(hours: 2));
      if (_isFutureSystemTrigger(now, riskTriggerAt) &&
          (startAt == null || startAt.isAfter(riskTriggerAt))) {
        final key = 'task-risk:${task.id}:${_dayKey(riskTriggerAt)}';
        requests.add(
          ReminderRequest(
            id: _stableNotificationId(key),
            triggerAt: riskTriggerAt,
            title: '浠诲姟椋庨櫓鎻愰啋',
            body: '${task.summary} has less than 2 hours before the deadline.',
          ),
        );
      }
    }
  }

  void _collectSystemEventRows(
    DateTime now,
    int reminderMinutes,
    List<TypedResult> rows,
    List<ReminderRequest> requests,
  ) {
    final upper = now.add(_systemScheduleLookAhead);
    for (final row in rows) {
      final event = row.readTable(_db.calendarEvents);
      for (final occurrenceAt in _eventOccurrencesInRange(event, now, upper)) {
        final triggerAt =
            occurrenceAt.subtract(Duration(minutes: reminderMinutes));
        if (!_isFutureSystemTrigger(now, triggerAt)) {
          continue;
        }

        final key = 'event:${event.id}:${triggerAt.toIso8601String()}';
        requests.add(
          ReminderRequest(
            id: _stableNotificationId(key),
            triggerAt: triggerAt,
            title: 'Event reminder',
            body: '${event.summary} starts at ${_formatTime(occurrenceAt)}',
            payload: _eventPayload(
              event,
              occurrenceAt: occurrenceAt,
              triggerAt: triggerAt,
            ),
          ),
        );
      }
    }
  }

  Iterable<DateTime> _eventOccurrencesInRange(
    CalendarEvent event,
    DateTime lower,
    DateTime upper,
  ) sync* {
    final rule = _ParsedReminderRrule.parse(event.rrule);
    if (rule == null) {
      if (!event.dtstart.isBefore(lower) && !event.dtstart.isAfter(upper)) {
        yield event.dtstart;
      }
      return;
    }

    var occurrence = event.dtstart;
    var occurrenceIndex = 0;
    final fastForward = rule.fastForwardSteps(event.dtstart, lower);
    if (fastForward > 0) {
      occurrenceIndex = fastForward;
      occurrence = rule.addSteps(event.dtstart, fastForward);
      while (occurrence.isBefore(lower)) {
        occurrenceIndex++;
        occurrence = rule.next(occurrence);
      }
    }

    var guard = 0;
    while (!occurrence.isAfter(upper) && guard < 8192) {
      if (rule.count != null && occurrenceIndex >= rule.count!) {
        break;
      }
      if (rule.until != null && occurrence.isAfter(rule.until!)) {
        break;
      }
      if (!occurrence.isBefore(lower)) {
        yield occurrence;
      }
      occurrenceIndex++;
      occurrence = rule.next(occurrence);
      guard++;
    }
  }

  Map<String, Object?> _eventPayload(
    CalendarEvent event, {
    required DateTime occurrenceAt,
    required DateTime triggerAt,
  }) {
    return <String, Object?>{
      'entityType': 'event',
      'entityId': event.id,
      'uid': event.uid,
      'summary': event.summary,
      'occurrenceAt': occurrenceAt,
      'triggerAt': triggerAt,
      'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
      'timezoneOffsetMinutes': triggerAt.timeZoneOffset.inMinutes,
      if (event.rrule != null && event.rrule!.trim().isNotEmpty)
        'rrule': event.rrule,
    };
  }

  bool _isFutureSystemTrigger(DateTime now, DateTime triggerAt) {
    return triggerAt.isAfter(now.add(const Duration(seconds: 30))) &&
        triggerAt.isBefore(now.add(_systemScheduleLookAhead));
  }

  bool _shouldTrigger(DateTime now, DateTime triggerAt) {
    return !now.isBefore(triggerAt) &&
        now.difference(triggerAt) <= _triggerGrace;
  }

  bool _shouldTriggerDeadlineRisk(
    DateTime now,
    DateTime dueAt,
    DateTime? startAt,
  ) {
    if (now.isAfter(dueAt)) {
      return false;
    }
    if (dueAt.difference(now) > const Duration(hours: 2)) {
      return false;
    }
    return startAt == null || startAt.isAfter(now);
  }

  void _trimDeliveredKeys() {
    if (_deliveredKeys.length <= 400) {
      return;
    }
    final overflow = _deliveredKeys.length - 300;
    _deliveredKeys.removeAll(_deliveredKeys.take(overflow).toList());
  }

  static int _stableNotificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  static String _formatTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  static String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _ParsedReminderRrule {
  const _ParsedReminderRrule({
    required this.frequency,
    required this.interval,
    this.count,
    this.until,
  });

  final String frequency;
  final int interval;
  final int? count;
  final DateTime? until;

  static _ParsedReminderRrule? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final parts = <String, String>{};
    for (final segment in raw.split(';')) {
      final index = segment.indexOf('=');
      if (index <= 0) {
        continue;
      }
      parts[segment.substring(0, index).trim().toUpperCase()] =
          segment.substring(index + 1).trim();
    }

    final frequency = parts['FREQ']?.toUpperCase();
    if (frequency == null ||
        !const <String>{'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}
            .contains(frequency)) {
      return null;
    }

    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    return _ParsedReminderRrule(
      frequency: frequency,
      interval: interval <= 0 ? 1 : interval,
      count: int.tryParse(parts['COUNT'] ?? ''),
      until: _parseUntil(parts['UNTIL']),
    );
  }

  DateTime next(DateTime value) => addSteps(value, 1);

  DateTime addSteps(DateTime value, int steps) {
    final amount = interval * steps;
    switch (frequency) {
      case 'DAILY':
        return value.add(Duration(days: amount));
      case 'WEEKLY':
        return value.add(Duration(days: amount * 7));
      case 'MONTHLY':
        return _addMonths(value, amount);
      case 'YEARLY':
        return _addMonths(value, amount * 12);
      default:
        return value;
    }
  }

  int fastForwardSteps(DateTime start, DateTime lower) {
    if (!start.isBefore(lower)) {
      return 0;
    }
    switch (frequency) {
      case 'DAILY':
        return lower.difference(start).inDays ~/ interval;
      case 'WEEKLY':
        return lower.difference(start).inDays ~/ (interval * 7);
      case 'MONTHLY':
        return _wholeMonthsBetween(start, lower) ~/ interval;
      case 'YEARLY':
        return _wholeMonthsBetween(start, lower) ~/ (interval * 12);
      default:
        return 0;
    }
  }

  static DateTime? _parseUntil(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final value = raw.trim();
    if (value.length == 8) {
      final year = int.tryParse(value.substring(0, 4));
      final month = int.tryParse(value.substring(4, 6));
      final day = int.tryParse(value.substring(6, 8));
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day, 23, 59, 59);
      }
    }
    if (value.endsWith('Z') && value.length >= 16) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return DateTime.tryParse(value);
  }

  static DateTime _addMonths(DateTime value, int months) {
    final targetMonthIndex = value.month - 1 + months;
    final year = value.year + targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final day = value.day.clamp(1, _daysInMonth(year, month));
    return DateTime(
      year,
      month,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  static int _wholeMonthsBetween(DateTime start, DateTime lower) {
    var months = (lower.year - start.year) * 12 + lower.month - start.month;
    final candidate = _addMonths(start, months);
    if (candidate.isAfter(lower)) {
      months--;
    }
    return months < 0 ? 0 : months;
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}

class SystemReminderNotificationGateway implements ReminderNotificationGateway {
  SystemReminderNotificationGateway(this._environment);

  final ReminderRuntimeEnvironment _environment;
  final _notifications = FlutterLocalNotificationsPlugin();
  final _desktopShell = const DesktopShellService();

  static const _androidReminderChannel =
      MethodChannel('com.flowplanv2.app/android_reminders');

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (!_environment.isAndroid) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('ic_stat_flowplanv2');
    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    if (!_environment.isAndroid) {
      return false;
    }
    try {
      final value = await _androidReminderChannel.invokeMethod<bool>(
        'canScheduleExactAlarms',
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openAndroidExactAlarmSettings() async {
    if (!_environment.isAndroid) {
      return;
    }
    try {
      await _androidReminderChannel.invokeMethod<void>(
        'openExactAlarmSettings',
      );
    } catch (_) {
      // Opening the permission page should not block settings flows.
    }
  }

  @override
  Future<int> pendingSystemReminderCount() async {
    if (!_environment.isAndroid) {
      return 0;
    }
    try {
      final value = await _androidReminderChannel.invokeMethod<int>(
        'pendingExactReminderCount',
      );
      return value ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async {
    if (!_environment.isAndroid) {
      return false;
    }
    try {
      final scheduled = await _androidReminderChannel.invokeMethod<bool>(
        'scheduleExactReminder',
        <String, Object?>{
          'id': request.id,
          'triggerAtMillis': request.triggerAt.millisecondsSinceEpoch,
          'title': request.title,
          'body': request.body,
          'payload': request.encodedPayload,
        },
      );
      return scheduled ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancelAllSystemReminders() async {
    if (!_environment.isAndroid) {
      return;
    }
    try {
      await _androidReminderChannel.invokeMethod<void>(
        'cancelAllExactReminders',
      );
    } catch (_) {
      // System scheduling is best-effort; runtime scanning remains available.
    }
  }

  @override
  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_environment.isWindows) {
      await _desktopShell.showReminder(title: title, body: body);
      return;
    }

    if (!_environment.isAndroid) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'flowplanv2_reminders',
      'FlowPlanV2 鎻愰啋',
      channelDescription: 'Calendar and task reminders',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      ticker: 'FlowPlanV2 鎻愰啋',
    );
    await _notifications.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }
}
