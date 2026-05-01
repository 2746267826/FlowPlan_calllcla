import 'dart:async';
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

final reminderSystemStatusProvider = FutureProvider<ReminderSystemStatus>((ref) {
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
      Platform.isAndroid && supportsSystemSchedule && !canScheduleExactAlarms;
}

class ReminderRebuildResult {
  const ReminderRebuildResult({
    required this.scheduledCount,
    required this.canScheduleExactAlarms,
  });

  final int scheduledCount;
  final bool canScheduleExactAlarms;
}

class ReminderService {
  ReminderService({
    required AppDatabase database,
    required int Function() defaultEventReminderMinutes,
  })  : _db = database,
        _defaultEventReminderMinutes = defaultEventReminderMinutes;

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
  final _gateway = _ReminderNotificationGateway();
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
      final now = DateTime.now();
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
      if (!Platform.isAndroid) {
        await _db.setIntSetting(_lastSystemScheduledCountSettingKey, 0);
        await _db.setSetting(
          _lastSystemRebuiltAtSettingKey,
          DateTime.now().toIso8601String(),
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
          DateTime.now().toIso8601String(),
        );
        return const ReminderRebuildResult(
          scheduledCount: 0,
          canScheduleExactAlarms: false,
        );
      }

      final now = DateTime.now();
      final requests = await _collectSystemReminderRequests(now);
      await _gateway.cancelAllSystemReminders();

      var scheduledCount = 0;
      for (final request in requests.take(128)) {
        final scheduled = await _gateway.scheduleSystemReminder(request);
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
        DateTime.now().toIso8601String(),
      );
      return ReminderRebuildResult(
        scheduledCount: scheduledCount,
        canScheduleExactAlarms: true,
      );
    } finally {
      _isRebuildingSystemSchedule = false;
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
    final pendingCount = Platform.isAndroid
        ? await _gateway.pendingSystemReminderCount()
        : fallbackCount;
    final canSchedule = await _gateway.canScheduleExactAlarms();

    return ReminderSystemStatus(
      platformLabel: Platform.isAndroid
          ? 'Android 精准闹钟'
          : Platform.isWindows
              ? 'Windows 运行时强提醒'
              : '当前平台暂未接入系统级提醒',
      runtimeScannerEnabled: _started,
      supportsSystemSchedule: Platform.isAndroid,
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
          _db.calendarEvents.dtstart.isBiggerOrEqualValue(lower) &
          _db.calendarEvents.dtstart.isSmallerOrEqualValue(upper) &
          _db.calendarEvents.status.isNotIn(['CANCELLED']),
    );
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);

    final rows = await query.get();
    for (final row in rows) {
      final event = row.readTable(_db.calendarEvents);
      final triggerAt =
          event.dtstart.subtract(Duration(minutes: reminderMinutes));
      if (!_shouldTrigger(now, triggerAt)) {
        continue;
      }

      final key = 'event:${event.id}:${triggerAt.toIso8601String()}';
      if (!_deliveredKeys.add(key)) {
        continue;
      }

      await _gateway.showReminder(
        id: _stableNotificationId(key),
        title: '日程提醒',
        body: '${event.summary} 将在 ${_formatTime(event.dtstart)} 开始',
      );
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
        final triggerAt =
            startAt.subtract(Duration(minutes: reminderMinutes));
        if (_shouldTrigger(now, triggerAt)) {
          final key = 'task-start:${task.id}:${triggerAt.toIso8601String()}';
          if (_deliveredKeys.add(key)) {
            await _gateway.showReminder(
              id: _stableNotificationId(key),
              title: '任务开始提醒',
              body: '${task.summary} 计划在 ${_formatTime(startAt)} 开始',
            );
          }
        }
      }

      final dueAt = task.due;
      if (dueAt == null || dueAt.isBefore(lower) || dueAt.isAfter(upper)) {
        continue;
      }

      final dueTriggerAt =
          dueAt.subtract(Duration(minutes: reminderMinutes));
      if (_shouldTrigger(now, dueTriggerAt)) {
        final key = 'task-due:${task.id}:${dueTriggerAt.toIso8601String()}';
        if (_deliveredKeys.add(key)) {
          await _gateway.showReminder(
            id: _stableNotificationId(key),
            title: '任务截止提醒',
            body: '${task.summary} 将在 ${_formatTime(dueAt)} 截止',
          );
        }
      }

      if (_shouldTriggerDeadlineRisk(now, dueAt, startAt)) {
        final key = 'task-risk:${task.id}:${_dayKey(now)}';
        if (_deliveredKeys.add(key)) {
          await _gateway.showReminder(
            id: _stableNotificationId(key),
            title: '任务风险提醒',
            body: '${task.summary} 距离截止时间不足 2 小时，建议尽快安排处理',
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
        Duration(minutes: task.durationMinutes <= 0 ? 30 : task.durationMinutes),
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
        title: '计划偏离提醒',
        body:
            '${task.summary} 已计划在 ${_formatTime(startAt)} 开始，但当前还没有看到与该任务绑定的追踪记录。',
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

  Future<List<_ReminderRequest>> _collectSystemReminderRequests(
    DateTime now,
  ) async {
    final requests = <_ReminderRequest>[];
    await _collectSystemEventReminderRequests(now, requests);
    await _collectSystemTaskReminderRequests(now, requests);
    requests.sort((left, right) => left.triggerAt.compareTo(right.triggerAt));
    return requests;
  }

  Future<void> _collectSystemEventReminderRequests(
    DateTime now,
    List<_ReminderRequest> requests,
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
          _db.calendarEvents.dtstart.isBiggerOrEqualValue(now) &
          _db.calendarEvents.dtstart.isSmallerOrEqualValue(upper) &
          _db.calendarEvents.status.isNotIn(['CANCELLED']),
    );
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);

    final rows = await query.get();
    for (final row in rows) {
      final event = row.readTable(_db.calendarEvents);
      final triggerAt =
          event.dtstart.subtract(Duration(minutes: reminderMinutes));
      if (!_isFutureSystemTrigger(now, triggerAt)) {
        continue;
      }

      final key = 'event:${event.id}:${triggerAt.toIso8601String()}';
      requests.add(
        _ReminderRequest(
          id: _stableNotificationId(key),
          triggerAt: triggerAt,
          title: '日程提醒',
          body: '${event.summary} 将在 ${_formatTime(event.dtstart)} 开始',
        ),
      );
    }
  }

  Future<void> _collectSystemTaskReminderRequests(
    DateTime now,
    List<_ReminderRequest> requests,
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
        final triggerAt =
            startAt.subtract(Duration(minutes: reminderMinutes));
        if (_isFutureSystemTrigger(now, triggerAt)) {
          final key = 'task-start:${task.id}:${triggerAt.toIso8601String()}';
          requests.add(
            _ReminderRequest(
              id: _stableNotificationId(key),
              triggerAt: triggerAt,
              title: '任务开始提醒',
              body: '${task.summary} 计划在 ${_formatTime(startAt)} 开始',
            ),
          );
        }
      }

      final dueAt = task.due;
      if (dueAt == null) {
        continue;
      }

      final dueTriggerAt =
          dueAt.subtract(Duration(minutes: reminderMinutes));
      if (_isFutureSystemTrigger(now, dueTriggerAt)) {
        final key = 'task-due:${task.id}:${dueTriggerAt.toIso8601String()}';
        requests.add(
          _ReminderRequest(
            id: _stableNotificationId(key),
            triggerAt: dueTriggerAt,
            title: '任务截止提醒',
            body: '${task.summary} 将在 ${_formatTime(dueAt)} 截止',
          ),
        );
      }

      final riskTriggerAt = dueAt.subtract(const Duration(hours: 2));
      if (_isFutureSystemTrigger(now, riskTriggerAt) &&
          (startAt == null || startAt.isAfter(riskTriggerAt))) {
        final key = 'task-risk:${task.id}:${_dayKey(riskTriggerAt)}';
        requests.add(
          _ReminderRequest(
            id: _stableNotificationId(key),
            triggerAt: riskTriggerAt,
            title: '任务风险提醒',
            body: '${task.summary} 距离截止时间不足 2 小时，建议尽快安排处理',
          ),
        );
      }
    }
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

class _ReminderRequest {
  const _ReminderRequest({
    required this.id,
    required this.triggerAt,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime triggerAt;
  final String title;
  final String body;
}

class _ReminderNotificationGateway {
  final _notifications = FlutterLocalNotificationsPlugin();
  final _desktopShell = const DesktopShellService();

  static const _androidReminderChannel =
      MethodChannel('com.flowplan.flawplanv2/android_reminders');

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (!Platform.isAndroid) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('ic_stat_flowplan');
    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) {
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

  Future<void> openAndroidExactAlarmSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidReminderChannel.invokeMethod<void>(
        'openExactAlarmSettings',
      );
    } catch (_) {
      // 权限页打开失败不应阻塞设置页。
    }
  }

  Future<int> pendingSystemReminderCount() async {
    if (!Platform.isAndroid) {
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

  Future<bool> scheduleSystemReminder(_ReminderRequest request) async {
    if (!Platform.isAndroid) {
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
        },
      );
      return scheduled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelAllSystemReminders() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidReminderChannel.invokeMethod<void>(
        'cancelAllExactReminders',
      );
    } catch (_) {
      // 系统级调度是增强能力，失败时仍保留运行时扫描提醒。
    }
  }

  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
  }) async {
    if (Platform.isWindows) {
      await _desktopShell.showReminder(title: title, body: body);
      return;
    }

    if (!Platform.isAndroid) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'flowplan_reminders',
      'FlowPlan 提醒',
      channelDescription: '日程和任务提醒',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      ticker: 'FlowPlan 提醒',
    );
    await _notifications.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }
}
