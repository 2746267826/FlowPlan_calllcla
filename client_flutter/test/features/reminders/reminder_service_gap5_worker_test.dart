import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  group('ReminderService gap5 coverage', () {
    late AppDatabase db;
    late _FakeReminderGateway gateway;
    late _FakeReminderEnvironment environment;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      db = createTestDatabase();
      gateway = _FakeReminderGateway();
      environment = _FakeReminderEnvironment(
        now: DateTime.utc(2026, 6, 10, 8),
        isAndroid: true,
      );
    });

    tearDown(() async {
      await db.close();
      debugDefaultTargetPlatformOverride = null;
    });

    ReminderService service({int eventReminderMinutes = 15}) {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => eventReminderMinutes,
        gateway: gateway,
        environment: environment,
      );
    }

    test('provider-created service reads reminder minutes during scans',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reminder_minutes': 45,
      });
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      final reminders = container.read(reminderServiceProvider);

      await reminders.scanNow();

      expect(container.read(reminderMinutesProvider), 45);
    });

    testWidgets('start installs periodic scan and system schedule callbacks',
        (tester) async {
      final reminders = service(eventReminderMinutes: 0);

      await reminders.start();
      await tester.pump(const Duration(minutes: 16));
      await tester.pump();

      expect(gateway.initializeCalls, 1);
      expect(gateway.cancelAllCalls, greaterThanOrEqualTo(2));

      reminders.dispose();
      await tester.pump();
    });

    test('rebuild parses ISO UNTIL values that do not end in Z', () async {
      final reminders = service(eventReminderMinutes: 30);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'until-with-offset',
        summary: 'Offset until',
        dtstart: DateTime.utc(2026, 6, 1, 9),
        rrule: 'FREQ=DAILY;UNTIL=2026-06-12T09:00:00+00:00',
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, greaterThan(0));
      expect(
        gateway.scheduledRequests.first.payload,
        containsPair(
          'occurrenceAt',
          DateTime.utc(2026, 6, 10, 9).toIso8601String(),
        ),
      );
    });

    test(
        'Android notification gateway initializes and shows via plugin channel',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'initialize' ||
            call.method == 'requestNotificationsPermission') {
          return true;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final notificationGateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 10, 8),
          isAndroid: true,
        ),
      );

      await notificationGateway.initialize();
      await notificationGateway.showReminder(
        id: 99,
        title: 'Android title',
        body: 'Android body',
        payload: '{"entityType":"event"}',
      );

      expect(calls.map((call) => call.method), contains('initialize'));
      expect(
        calls.map((call) => call.method),
        contains('requestNotificationsPermission'),
      );
      final showCall = calls.singleWhere((call) => call.method == 'show');
      expect(showCall.arguments, containsPair('id', 99));
      expect(showCall.arguments, containsPair('title', 'Android title'));
      expect(showCall.arguments, containsPair('body', 'Android body'));
      expect(
        showCall.arguments,
        containsPair('payload', '{"entityType":"event"}'),
      );
    });
  });
}

Future<int> _insertCalendar(AppDatabase db) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: 'Gap5 calendar',
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

  final DateTime _now;

  @override
  bool isAndroid;

  @override
  bool isWindows = false;

  @override
  DateTime now() => _now;
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  var initializeCalls = 0;
  var canScheduleExactAlarmsValue = true;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  final scheduledRequests = <ReminderRequest>[];

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
  }) async {}
}
