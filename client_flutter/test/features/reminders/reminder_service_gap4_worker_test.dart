import 'dart:io';

import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReminderPayloadCodec gap4 coverage', () {
    test('decode returns empty maps for blank invalid and non-map payloads',
        () {
      expect(ReminderPayloadCodec.decode(null), isEmpty);
      expect(ReminderPayloadCodec.decode('   '), isEmpty);
      expect(ReminderPayloadCodec.decode('{broken json'), isEmpty);
      expect(ReminderPayloadCodec.decode('[1, 2, 3]'), isEmpty);
    });

    test('normalizes nested payload values before encoding', () {
      final encoded = ReminderPayloadCodec.encode(<String, Object?>{
        'at': DateTime.utc(2026, 6, 11, 9, 30),
        'nested': <Object?, Object?>{
          42: <Object?>[
            DateTime.utc(2026, 6, 11, 10),
            Uri.parse('https://flowplan.test/reminder'),
          ],
        },
      });

      final decoded = ReminderPayloadCodec.decode(encoded);

      expect(decoded['at'], '2026-06-11T09:30:00.000Z');
      expect(
        decoded['nested'],
        <String, Object?>{
          '42': <Object?>[
            '2026-06-11T10:00:00.000Z',
            'https://flowplan.test/reminder',
          ],
        },
      );
    });

    test('request stores an immutable normalized payload', () {
      final request = ReminderRequest(
        id: 7,
        triggerAt: DateTime.utc(2026, 6, 11, 12),
        title: 'Title',
        body: 'Body',
        payload: <String, Object?>{
          'when': DateTime.utc(2026, 6, 11, 11, 45),
        },
      );

      expect(request.payload['when'], '2026-06-11T11:45:00.000Z');
      expect(
        () => request.payload['extra'] = true,
        throwsUnsupportedError,
      );
      expect(
        ReminderPayloadCodec.decode(request.encodedPayload),
        containsPair('when', '2026-06-11T11:45:00.000Z'),
      );
    });
  });

  group('SystemReminderNotificationGateway gap4 coverage', () {
    const androidChannel =
        MethodChannel('com.flowplanv2.app/android_reminders');
    const desktopChannel = MethodChannel('com.flowplanv2/desktop_shell');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(desktopChannel, null);
    });

    test('initialize is idempotent for non-Android environments', () async {
      final gateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 11),
          isAndroid: false,
        ),
      );

      await gateway.initialize();
      await gateway.initialize();

      expect(await gateway.canScheduleExactAlarms(), isFalse);
      expect(await gateway.pendingSystemReminderCount(), 0);
    });

    test('Windows reminders are sent through the desktop shell channel',
        () async {
      if (!Platform.isWindows) {
        return;
      }
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(desktopChannel, (call) async {
        calls.add(call);
        return null;
      });
      final gateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 11),
          isWindows: true,
        ),
      );

      await gateway.showReminder(
        id: 9,
        title: 'Desktop title',
        body: 'Desktop body',
        payload: 'ignored on desktop',
      );

      expect(calls.map((call) => call.method), contains('showReminder'));
      final showCall = calls.singleWhere(
        (call) => call.method == 'showReminder',
      );
      expect(showCall.arguments, containsPair('title', 'Desktop title'));
      expect(showCall.arguments, containsPair('body', 'Desktop body'));
    });

    test('Android channel exceptions make show-free methods safe no-ops',
        () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'blocked');
      });
      final gateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 11),
          isAndroid: true,
        ),
      );

      expect(await gateway.canScheduleExactAlarms(), isFalse);
      expect(await gateway.pendingSystemReminderCount(), 0);
      expect(
        await gateway.scheduleSystemReminder(
          ReminderRequest(
            id: 11,
            triggerAt: DateTime.utc(2026, 6, 11, 13),
            title: 'Blocked',
            body: 'Body',
          ),
        ),
        isFalse,
      );
      await gateway.openAndroidExactAlarmSettings();
      await gateway.cancelAllSystemReminders();

      expect(
        calls.map((call) => call.method),
        <String>[
          'canScheduleExactAlarms',
          'pendingExactReminderCount',
          'scheduleExactReminder',
          'openExactAlarmSettings',
          'cancelAllExactReminders',
        ],
      );
    });
  });
}

class _FakeReminderEnvironment implements ReminderRuntimeEnvironment {
  _FakeReminderEnvironment({
    required DateTime now,
    this.isAndroid = false,
    this.isWindows = false,
  }) : _now = now;

  final DateTime _now;

  @override
  final bool isAndroid;

  @override
  final bool isWindows;

  @override
  DateTime now() => _now;
}
