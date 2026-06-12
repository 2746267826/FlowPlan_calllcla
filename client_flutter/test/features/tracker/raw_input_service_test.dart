import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.flowplanv2/raw_input');

  late List<MethodCall> calls;
  RawInputService? serviceUnderTest;

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() async {
    final service = serviceUnderTest;
    if (service != null && service.isRunning) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await service.stop();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start and stop are no-ops on non-Windows hosts', () async {
    final service = RawInputService(
      isWindows: () => false,
      channel: channel,
    );
    serviceUnderTest = service;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    await service.start();
    await service.stop();
    await service.setSequenceRecording(true);
    final stats = await service.getStats();
    final events = await service.getPendingInputEvents();
    await service.ackInputEvents(7);
    await service.resetStats();

    expect(service.isRunning, isFalse);
    expect(stats, isNull);
    expect(events, isEmpty);
    expect(calls, isEmpty);
  });

  test('start records channel errors and leaves service stopped on Windows',
      () async {
    final service = RawInputService(
      isWindows: () => true,
      channel: channel,
    );
    serviceUnderTest = service;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'start') {
        throw PlatformException(code: 'boom', message: 'native start failed');
      }
      return null;
    });

    await expectLater(service.start(), throwsA(isA<PlatformException>()));

    expect(service.isRunning, isFalse);
    expect(service.lastError, contains('native start failed'));
    expect(calls.map((call) => call.method), <String>['start']);
  });

  test('mouse click and telemetry value objects merge, subtract, and clamp',
      () {
    final baseClicks = MouseClicks.fromMap(<String, Object?>{
      'leftClick': 5,
      'rightClick': 4,
      'middleClick': 3,
      'backward': 2,
      'forward': 1,
    });
    final currentClicks = MouseClicks.fromMap(<String, Object?>{
      'left': 8,
      'right': 6,
      'middle': 5,
      'xButton1': 4,
      'xButton2': 3,
    });

    expect(MouseClicks.fromMap(null).total, 0);
    expect(baseClicks.copyWith(left: 7).left, 7);
    expect(baseClicks.add(currentClicks).toMap(), <String, int>{
      'left': 13,
      'right': 10,
      'middle': 8,
      'xButton1': 6,
      'xButton2': 4,
    });
    expect(currentClicks.subtract(baseClicks).toMap(), <String, int>{
      'left': 3,
      'right': 2,
      'middle': 2,
      'xButton1': 2,
      'xButton2': 2,
    });
    expect(baseClicks.subtract(currentClicks).total, 0);

    final firstAt = DateTime(2026, 6, 10, 9);
    final laterAt = firstAt.add(const Duration(seconds: 3));
    final firstEvent = RawInputEvent(
      sequenceId: 12,
      timestampMicros: laterAt.microsecondsSinceEpoch,
      kind: RawInputEventKind.keyDown,
    );
    final secondEvent = RawInputEvent(
      sequenceId: 4,
      timestampMicros: firstAt.microsecondsSinceEpoch,
      kind: RawInputEventKind.mouseMove,
    );
    final base = InputTelemetry(
      keyCount: 10,
      keyDistribution: const <int, int>{65: 4, 66: 3},
      keySequence: 'AB',
      clicks: baseClicks,
      scrollPx: 100,
      mouseMovePx: 500,
      timestamp: firstAt,
      inputEvents: <RawInputEvent>[firstEvent],
    );
    final current = InputTelemetry(
      keyCount: 15,
      keyDistribution: const <int, int>{65: 6, 67: 2},
      keySequence: 'CD',
      clicks: currentClicks,
      scrollPx: 130,
      mouseMovePx: 650,
      timestamp: laterAt,
      inputEvents: <RawInputEvent>[secondEvent],
    );

    final merged = base.add(current);
    expect(merged.keyCount, 25);
    expect(merged.keyDistribution, <int, int>{65: 10, 66: 3, 67: 2});
    expect(merged.keySequence, 'ABCD');
    expect(merged.clicks.total, 41);
    expect(merged.scrollPx, 230);
    expect(merged.mouseMovePx, 1150);
    expect(
      merged.inputEvents.map((event) => event.sequenceId),
      <int>[4, 12],
    );
    expect(merged.timestamp, laterAt);

    final delta = current.subtract(base);
    expect(delta.keyCount, 5);
    expect(delta.keyDistribution, <int, int>{65: 2, 67: 2});
    expect(delta.keySequence, 'CD');
    expect(delta.clicks.total, 11);
    expect(delta.scrollPx, 30);
    expect(delta.mouseMovePx, 150);
    expect(delta.timestamp, laterAt);

    final clamped = base.subtract(current);
    expect(clamped.keyCount, 0);
    expect(clamped.keyDistribution, <int, int>{66: 3});
    expect(clamped.clicks.total, 0);
    expect(clamped.scrollPx, 0);
    expect(clamped.mouseMovePx, 0);

    final empty = InputTelemetry.empty(firstAt).copyWith(
      keyCount: 2,
      keySequence: 'Z',
    );
    expect(empty.keyCount, 2);
    expect(empty.keySequence, 'Z');
    expect(empty.timestamp, firstAt);
    expect(empty.toString(), contains('keys=2'));
  });

  test('raw input events parse every kind and serialize non-empty fields', () {
    final eventAt = DateTime(2026, 6, 10, 9, 30);
    final kindValues = <RawInputEventKind, String>{
      RawInputEventKind.keyDown: 'key_down',
      RawInputEventKind.keyUp: 'key_up',
      RawInputEventKind.mouseButtonDown: 'mouse_button_down',
      RawInputEventKind.mouseButtonUp: 'mouse_button_up',
      RawInputEventKind.mouseButton: 'mouse_button',
      RawInputEventKind.mouseWheel: 'mouse_wheel',
      RawInputEventKind.mouseMove: 'mouse_move',
    };

    for (final entry in kindValues.entries) {
      expect(entry.key.value, entry.value);
      expect(RawInputEventKindValue.fromValue(entry.value), entry.key);
    }
    expect(
      RawInputEventKindValue.fromValue('not-a-real-kind'),
      RawInputEventKind.keyDown,
    );

    final event = RawInputEvent.fromMap(<String, Object?>{
      'sequenceId': 42.0,
      'timestampMicros': eventAt.microsecondsSinceEpoch,
      'kind': 'mouse_wheel',
      'eventCount': 3.0,
      'keyCode': 65.0,
      'processName': 'Code.exe',
      'className': '',
      'windowTitle': 'main.dart',
      'mouseButton': 'wheel_up',
      'wheelDelta': 120.0,
      'deltaX': -2.0,
      'deltaY': 5.0,
      'moveDistance': 11.0,
      'tokenText': '',
    });

    expect(event.sequenceId, 42);
    expect(event.timestamp, eventAt);
    expect(event.kind, RawInputEventKind.mouseWheel);
    expect(event.eventCount, 3);
    expect(event.keyCode, 65);
    expect(event.deltaX, -2);

    expect(event.toJson(), <String, Object?>{
      'sequenceId': 42,
      'timestamp': eventAt.toIso8601String(),
      'kind': 'mouse_wheel',
      'eventCount': 3,
      'keyCode': 65,
      'processName': 'Code.exe',
      'windowTitle': 'main.dart',
      'mouseButton': 'wheel_up',
      'wheelDelta': 120,
      'deltaX': -2,
      'deltaY': 5,
      'moveDistance': 11,
    });
  });

  test(
      'parses stats, pending events, ack, and reset through channel on Windows',
      () async {
    final service = RawInputService(
      isWindows: () => true,
      channel: channel,
    );
    serviceUnderTest = service;
    final eventAt = DateTime(2026, 6, 10, 9);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'start' => null,
        'setSequenceRecording' => null,
        'getStats' => <String, Object?>{
            'keyCount': 4,
            'keyDistribution': <String, Object?>{'65': 3, 'bad': 9, '66': 1},
            'keySequence': 'ABBA',
            'mouseClicks': <String, Object?>{
              'leftClick': 2,
              'right': 1,
              'x1': 1,
            },
            'scrollPx': 120,
            'mouseMovePx': 640,
            'lastError': ' ',
            'inputEvents': <Object?>[
              <String, Object?>{
                'sequenceId': 5,
                'timestampMicros': eventAt.microsecondsSinceEpoch,
                'kind': 'mouse_button_down',
                'eventCount': 2,
                'mouseButton': 'left',
                'processName': 'Code.exe',
              },
              'malformed',
            ],
          },
        'getPendingInputEvents' => <Object?>[
            <String, Object?>{
              'sequenceId': 6,
              'timestampMicros': eventAt
                  .add(const Duration(seconds: 1))
                  .microsecondsSinceEpoch,
              'kind': 'key_up',
              'keyCode': 65,
            },
          ],
        'ackInputEvents' => null,
        'resetStats' => null,
        'stop' => null,
        _ => null,
      };
    });

    await service.start();
    await service.setSequenceRecording(false);
    final stats = await service.getStats();
    final pending = await service.getPendingInputEvents(maxEvents: 25);
    await service.ackInputEvents(6);
    await service.ackInputEvents(0);
    await service.resetStats();
    await service.stop();

    expect(service.isRunning, isFalse);
    expect(service.lastError, isNull);
    expect(stats, isNotNull);
    expect(stats!.keyCount, 4);
    expect(stats.keyDistribution, <int, int>{65: 3, 66: 1});
    expect(stats.clicks.total, 4);
    expect(stats.inputEvents.single.sequenceId, 5);
    expect(stats.inputEvents.single.kind, RawInputEventKind.mouseButtonDown);
    expect(pending.single.sequenceId, 6);
    expect(pending.single.kind, RawInputEventKind.keyUp);
    expect(
      calls.map((call) => call.method),
      <String>[
        'start',
        'setSequenceRecording',
        'getStats',
        'getPendingInputEvents',
        'ackInputEvents',
        'resetStats',
        'stop',
      ],
    );
    expect(calls[1].arguments, <String, Object?>{'enabled': true});
    expect(calls[3].arguments, <String, Object?>{'maxEvents': 25});
    expect(calls[4].arguments, <String, Object?>{'throughSequenceId': 6});
  });

  test('getStats returns null and pending events rethrows channel errors',
      () async {
    final service = RawInputService(
      isWindows: () => true,
      channel: channel,
    );
    serviceUnderTest = service;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getStats':
          throw PlatformException(code: 'stats_failed', message: 'bad stats');
        case 'getPendingInputEvents':
          throw PlatformException(code: 'events_failed', message: 'bad events');
      }
      return null;
    });

    final stats = await service.getStats();
    expect(stats, isNull);
    expect(service.lastError, contains('bad stats'));

    await expectLater(
      service.getPendingInputEvents(),
      throwsA(isA<PlatformException>()),
    );
    expect(service.lastError, contains('bad events'));
  });

  test('Windows channel no-ops and swallowed errors update service state',
      () async {
    final service = RawInputService(
      isWindows: () => true,
      channel: channel,
    );
    serviceUnderTest = service;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'start':
          return null;
        case 'stop':
          throw PlatformException(code: 'stop_failed', message: 'bad stop');
        case 'setSequenceRecording':
          throw PlatformException(
            code: 'sequence_failed',
            message: 'bad sequence',
          );
        case 'resetStats':
          throw PlatformException(code: 'reset_failed', message: 'bad reset');
        case 'getStats':
          return null;
      }
      return null;
    });

    await service.start();
    await service.start();
    expect(service.isRunning, isTrue);
    expect(calls.map((call) => call.method), <String>['start']);

    await service.stop();
    expect(service.isRunning, isTrue);
    expect(service.lastError, contains('bad stop'));

    await service.setSequenceRecording(false);
    expect(service.lastError, contains('bad sequence'));

    await service.resetStats();
    expect(service.lastError, contains('bad reset'));

    final stats = await service.getStats();
    expect(stats, isNull);
    expect(service.lastError, contains('bad reset'));

    expect(
      calls.map((call) => call.method),
      <String>[
        'start',
        'stop',
        'setSequenceRecording',
        'resetStats',
        'getStats',
      ],
    );
  });

  test('ack errors are recorded and rethrown after validating sequence id',
      () async {
    final service = RawInputService(
      isWindows: () => true,
      channel: channel,
    );
    serviceUnderTest = service;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ackInputEvents') {
        throw PlatformException(code: 'ack_failed', message: 'bad ack');
      }
      return null;
    });

    await service.ackInputEvents(0);
    await service.ackInputEvents(-1);
    expect(calls, isEmpty);

    await expectLater(
      service.ackInputEvents(9),
      throwsA(isA<PlatformException>()),
    );
    expect(service.lastError, contains('bad ack'));
    expect(calls.single.method, 'ackInputEvents');
    expect(calls.single.arguments, <String, Object?>{'throughSequenceId': 9});
  });
}
