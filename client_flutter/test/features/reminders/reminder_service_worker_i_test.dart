import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReminderService worker I coverage', () {
    late AppDatabase db;
    late _FakeReminderGateway gateway;
    late _FakeReminderEnvironment environment;

    setUp(() {
      db = createTestDatabase();
      gateway = _FakeReminderGateway();
      environment = _FakeReminderEnvironment(
        now: DateTime.utc(2026, 6, 10, 8),
        isAndroid: true,
      );
    });

    tearDown(() async {
      await db.close();
    });

    ReminderService service({int eventReminderMinutes = 15}) {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => eventReminderMinutes,
        gateway: gateway,
        environment: environment,
      );
    }

    test('scanNow emits a recurring event occurrence from a past base event',
        () async {
      final reminders = service(eventReminderMinutes: 15);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'daily-runtime-occurrence',
        summary: 'Daily planning',
        dtstart: DateTime.utc(2026, 6, 1, 8, 15),
        rrule: 'FREQ=DAILY;COUNT=20',
      );

      await reminders.scanNow();
      await reminders.scanNow();

      expect(gateway.shownReminders, hasLength(1));
      expect(gateway.shownReminders.single.body, contains('Daily planning'));
      expect(
        ReminderPayloadCodec.decode(gateway.shownReminders.single.payload),
        containsPair(
          'occurrenceAt',
          DateTime.utc(2026, 6, 10, 8, 15).toIso8601String(),
        ),
      );
    });

    test('rebuild schedules task start due and deadline-risk requests in order',
        () async {
      final reminders = service(eventReminderMinutes: 0);
      final listId = await _insertTaskList(db);
      final now = environment.now();
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-system-start',
        summary: 'Start focus',
        dtstart: now.add(const Duration(hours: 1)),
        reminderMinutesBefore: 15,
      );
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-system-due',
        summary: 'Due budget',
        due: now.add(const Duration(hours: 2)),
        reminderMinutesBefore: 20,
      );
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-system-risk',
        summary: 'Risky deadline',
        due: now.add(const Duration(hours: 3)),
        reminderMinutesBefore: 15,
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 4);
      expect(
        gateway.scheduledRequests
            .map((request) => request.triggerAt.millisecondsSinceEpoch),
        <int>[
          DateTime.utc(2026, 6, 10, 8, 45).millisecondsSinceEpoch,
          DateTime.utc(2026, 6, 10, 9).millisecondsSinceEpoch,
          DateTime.utc(2026, 6, 10, 9, 40).millisecondsSinceEpoch,
          DateTime.utc(2026, 6, 10, 10, 45).millisecondsSinceEpoch,
        ],
      );
      final bodies = gateway.scheduledRequests.map((request) => request.body);
      expect(bodies, contains(contains('Start focus')));
      expect(bodies, contains(contains('Due budget')));
      expect(
        bodies.where((body) => body.contains('Risky deadline')),
        hasLength(2),
      );
    });

    test('rebuild expands monthly recurrence with clamped month days',
        () async {
      environment.nowValue = DateTime.utc(2026, 2, 27, 8);
      final reminders = service(eventReminderMinutes: 30);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'monthly-clamped-event',
        summary: 'Month end review',
        dtstart: DateTime.utc(2026, 1, 31, 9),
        rrule: 'FREQ=MONTHLY;COUNT=5',
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 1);
      final request = gateway.scheduledRequests.single;
      expect(
        request.triggerAt.millisecondsSinceEpoch,
        DateTime.utc(2026, 2, 28, 8, 30).millisecondsSinceEpoch,
      );
      expect(
        request.payload,
        containsPair(
          'occurrenceAt',
          DateTime.utc(2026, 2, 28, 9).toIso8601String(),
        ),
      );
    });

    test('non-Android rebuild records fallback status without platform calls',
        () async {
      environment
        ..isAndroid = false
        ..isWindows = false;
      gateway.pendingSystemReminderCountValue = 99;
      final reminders = service();

      final result = await reminders.rebuildSystemSchedule();

      expect(result.canScheduleExactAlarms, isFalse);
      expect(result.scheduledCount, 0);
      expect(gateway.cancelAllCalls, 0);
      expect(gateway.scheduleAttempts, 0);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );
      expect(
        DateTime.parse(
          (await db.getSetting('reminder.system_schedule.last_rebuilt_at'))!,
        ),
        environment.now(),
      );
    });

    test('Android status uses pending system count and handles bad timestamps',
        () async {
      gateway
        ..canScheduleExactAlarmsValue = true
        ..pendingSystemReminderCountValue = 12;
      await db.setIntSetting('reminder.system_schedule.last_count', 4);
      await db.setSetting('reminder.system_schedule.last_rebuilt_at', 'bad');
      final reminders = service();

      final status = await reminders.getSystemStatus();

      expect(status.supportsSystemSchedule, isTrue);
      expect(status.canScheduleExactAlarms, isTrue);
      expect(status.needsAndroidExactAlarmPermission, isFalse);
      expect(status.pendingSystemReminderCount, 12);
      expect(status.lastRebuiltAt, null);
    });

    test('openAndroidExactAlarmSettings delegates to the gateway', () async {
      final reminders = service();

      await reminders.openAndroidExactAlarmSettings();

      expect(gateway.openSettingsCalls, 1);
    });
  });
}

Future<int> _insertCalendar(AppDatabase db) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: 'Worker I calendar',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
}

Future<int> _insertEvent(
  AppDatabase db, {
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime dtstart,
  String? rrule,
}) {
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 1, 1),
          summary: summary,
          dtstart: dtstart,
          eventCalendarId: Value(calendarId),
          rrule: Value(rrule),
        ),
      );
}

Future<int> _insertTaskList(AppDatabase db) {
  return db.into(db.taskLists).insert(
        TaskListsCompanion.insert(
          name: 'Worker I tasks',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
}

Future<int> _insertTask(
  AppDatabase db, {
  required int taskListId,
  required String uid,
  required String summary,
  DateTime? dtstart,
  DateTime? due,
  int reminderMinutesBefore = 15,
}) {
  return db.into(db.taskItems).insert(
        TaskItemsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 1, 1),
          summary: summary,
          dtstart: Value(dtstart),
          due: Value(due),
          taskListId: Value(taskListId),
          reminderMinutesBefore: Value(reminderMinutesBefore),
        ),
      );
}

class _FakeReminderEnvironment implements ReminderRuntimeEnvironment {
  _FakeReminderEnvironment({
    required DateTime now,
    this.isAndroid = false,
  }) : _now = now;

  DateTime _now;

  @override
  bool isAndroid;

  @override
  bool isWindows = false;

  @override
  DateTime now() => _now;

  set nowValue(DateTime value) {
    _now = value;
  }
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  var canScheduleExactAlarmsValue = true;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  var scheduleAttempts = 0;
  var openSettingsCalls = 0;
  final scheduledRequests = <ReminderRequest>[];
  final shownReminders = <_ShownReminder>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> canScheduleExactAlarms() async => canScheduleExactAlarmsValue;

  @override
  Future<void> openAndroidExactAlarmSettings() async {
    openSettingsCalls++;
  }

  @override
  Future<int> pendingSystemReminderCount() async {
    return pendingSystemReminderCountValue;
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async {
    scheduleAttempts++;
    scheduledRequests.add(request);
    return true;
  }

  @override
  Future<void> cancelAllSystemReminders() async {
    cancelAllCalls++;
    scheduledRequests.clear();
  }

  @override
  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shownReminders.add(
      _ShownReminder(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }
}

class _ShownReminder {
  const _ShownReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String? payload;
}
