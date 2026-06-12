import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReminderService deep behavior', () {
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

    test('start initializes once and falls back without exact alarm permission',
        () async {
      gateway.canScheduleExactAlarmsValue = false;
      final reminders = service();

      await reminders.start();
      await reminders.start();

      expect(gateway.initializeCalls, 1);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduledRequests, isEmpty);

      final status = await reminders.getSystemStatus();
      expect(status.runtimeScannerEnabled, isTrue);
      expect(status.supportsSystemSchedule, isTrue);
      expect(status.canScheduleExactAlarms, isFalse);
      expect(status.needsAndroidExactAlarmPermission, isTrue);

      reminders.dispose();
    });

    test('rebuild creates updates and cancels exact system reminders',
        () async {
      final reminders = service(eventReminderMinutes: 10);
      final calendarId = await _insertCalendar(db);
      final eventId = await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'create-update-cancel',
        summary: 'Roadmap review',
        dtstart: environment.now().add(const Duration(hours: 1)),
      );

      var result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 1);
      expect(gateway.cancelAllCalls, 1);
      expect(
        gateway.scheduledRequests.single.triggerAt.millisecondsSinceEpoch,
        DateTime.utc(2026, 6, 10, 8, 50).millisecondsSinceEpoch,
      );
      expect(
        gateway.scheduledRequests.single.payload,
        containsPair('entityType', 'event'),
      );

      gateway.clearScheduleCalls();
      await (db.update(db.calendarEvents)
            ..where((event) => event.id.equals(eventId)))
          .write(
        CalendarEventsCompanion(
          dtstart: Value(environment.now().add(const Duration(hours: 2))),
        ),
      );

      result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 1);
      expect(gateway.cancelAllCalls, 1);
      expect(
        gateway.scheduledRequests.single.triggerAt.millisecondsSinceEpoch,
        DateTime.utc(2026, 6, 10, 9, 50).millisecondsSinceEpoch,
      );

      gateway.clearScheduleCalls();
      await (db.update(db.calendarEvents)
            ..where((event) => event.id.equals(eventId)))
          .write(const CalendarEventsCompanion(status: Value('CANCELLED')));

      result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 0);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduledRequests, isEmpty);
    });

    test('rebuild expands daily recurring events from a past base event',
        () async {
      final reminders = service(eventReminderMinutes: 30);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'daily-past-event',
        summary: 'Daily standup',
        dtstart: DateTime.utc(2026, 6, 1, 9),
        rrule: 'FREQ=DAILY;COUNT=20',
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 7);
      expect(
        gateway.scheduledRequests.first.triggerAt.millisecondsSinceEpoch,
        DateTime.utc(2026, 6, 10, 8, 30).millisecondsSinceEpoch,
      );
      expect(
        gateway.scheduledRequests.first.payload,
        containsPair('rrule', 'FREQ=DAILY;COUNT=20'),
      );
      expect(
        gateway.scheduledRequests.first.payload,
        containsPair(
            'occurrenceAt', DateTime.utc(2026, 6, 10, 9).toIso8601String()),
      );
    });

    test('scan ignores stale past triggers and de-duplicates fresh reminders',
        () async {
      final reminders = service(eventReminderMinutes: 15);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'stale-event',
        summary: 'Already missed',
        dtstart: environment.now().subtract(const Duration(hours: 1)),
      );
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'fresh-event',
        summary: 'Fresh reminder',
        dtstart: environment.now().add(const Duration(minutes: 15)),
      );

      await reminders.scanNow();
      await reminders.scanNow();

      expect(gateway.shownReminders, hasLength(1));
      expect(gateway.shownReminders.single.body, contains('Fresh reminder'));
      expect(
        ReminderPayloadCodec.decode(gateway.shownReminders.single.payload),
        containsPair('entityType', 'event'),
      );
    });

    test('system request stores epoch and timezone metadata in payload',
        () async {
      final reminders = service(eventReminderMinutes: 20);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'utc-event',
        summary: 'UTC event',
        dtstart: DateTime.utc(2026, 6, 10, 10),
      );

      await reminders.rebuildSystemSchedule();

      final request = gateway.scheduledRequests.single;
      expect(
        request.triggerAt.millisecondsSinceEpoch,
        DateTime.utc(2026, 6, 10, 9, 40).millisecondsSinceEpoch,
      );
      final payload = ReminderPayloadCodec.decode(request.encodedPayload);
      expect(
          payload['triggerAtMillis'], request.triggerAt.millisecondsSinceEpoch);
      expect(
        payload['timezoneOffsetMinutes'],
        request.triggerAt.timeZoneOffset.inMinutes,
      );
    });

    test('platform schedule exceptions are treated as fallback misses',
        () async {
      final reminders = service(eventReminderMinutes: 10);
      gateway.scheduleException = PlatformException(
        code: 'alarm_error',
        message: 'Alarm manager rejected the request',
      );
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'throws-on-schedule',
        summary: 'Schedule throws',
        dtstart: environment.now().add(const Duration(hours: 1)),
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 0);
      expect(gateway.scheduleAttempts, 1);
      expect(gateway.scheduledRequests, isEmpty);
    });

    test(
        'payload codec round-trips nested metadata and tolerates malformed input',
        () {
      final payload = <String, Object?>{
        'entityType': 'task',
        'entityId': 42,
        'triggerAt': DateTime.utc(2026, 6, 10, 8, 30),
        'nested': <String, Object?>{
          'labels': <Object?>['focus', 3],
        },
      };

      final encoded = ReminderPayloadCodec.encode(payload);
      final decoded = ReminderPayloadCodec.decode(encoded);

      expect(decoded['entityType'], 'task');
      expect(decoded['entityId'], 42);
      expect(
        decoded['triggerAt'],
        DateTime.utc(2026, 6, 10, 8, 30).toIso8601String(),
      );
      expect(ReminderPayloadCodec.decode('{not-json'), isEmpty);
      expect(ReminderPayloadCodec.decode(null), isEmpty);
    });
  });
}

Future<int> _insertCalendar(AppDatabase db) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: 'Reminder calendar',
          createdAt: DateTime.utc(2026, 6, 1),
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
          dtstamp: DateTime.utc(2026, 6, 1),
          summary: summary,
          dtstart: dtstart,
          eventCalendarId: Value(calendarId),
          rrule: Value(rrule),
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
  var initializeCalls = 0;
  var canScheduleExactAlarmsValue = true;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  var scheduleAttempts = 0;
  Object? scheduleException;
  final scheduledRequests = <ReminderRequest>[];
  final shownReminders = <_ShownReminder>[];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    return canScheduleExactAlarmsValue;
  }

  @override
  Future<void> openAndroidExactAlarmSettings() async {}

  @override
  Future<int> pendingSystemReminderCount() async {
    return pendingSystemReminderCountValue;
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async {
    scheduleAttempts++;
    final exception = scheduleException;
    if (exception != null) {
      throw exception;
    }
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

  void clearScheduleCalls() {
    cancelAllCalls = 0;
    scheduleAttempts = 0;
    scheduledRequests.clear();
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
