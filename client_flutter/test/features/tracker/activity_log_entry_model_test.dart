import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActivityLogEntryTypeValue', () {
    test('round trips known storage values and defaults unknown values', () {
      expect(ActivityLogEntryType.sample.value, 'sample');
      expect(ActivityLogEntryType.sessionOpen.value, 'session_open');
      expect(ActivityLogEntryType.sessionUpdate.value, 'session_update');
      expect(ActivityLogEntryType.sessionClose.value, 'session_close');
      expect(ActivityLogEntryType.snapshot.value, 'snapshot');

      expect(
        ActivityLogEntryTypeValue.fromValue('session_open'),
        ActivityLogEntryType.sessionOpen,
      );
      expect(
        ActivityLogEntryTypeValue.fromValue('session_update'),
        ActivityLogEntryType.sessionUpdate,
      );
      expect(
        ActivityLogEntryTypeValue.fromValue('session_close'),
        ActivityLogEntryType.sessionClose,
      );
      expect(
        ActivityLogEntryTypeValue.fromValue('snapshot'),
        ActivityLogEntryType.snapshot,
      );
      expect(
        ActivityLogEntryTypeValue.fromValue('future_type'),
        ActivityLogEntryType.sample,
      );
    });
  });

  group('ActivityLogEntry', () {
    test('serializes optional fields only when meaningful', () {
      final entry = ActivityLogEntry(
        timestamp: DateTime.utc(2026, 6, 10, 8, 30),
        type: ActivityLogEntryType.sessionUpdate,
        recordId: 42,
        isIgnored: true,
        isFullscreen: true,
        processName: 'Code.exe',
        packageName: 'com.example.code',
        className: 'EditorWindow',
        windowTitle: 'main.dart',
        appLabel: 'Code',
        category: 'coding',
        label: 'VS Code',
        durationMinutes: 25,
        keyCount: 12,
        mouseClicks: 3,
        mouseMovePx: 400,
        scrollPx: 20,
        keyDistribution: const <int, int>{65: 2, 66: 1},
        keySequence: 'AB',
        deviceId: 'device-1',
        platform: 'windows',
        source: 'tracker',
        note: 'sampled',
      );

      final json = entry.toJson();

      expect(json['timestamp'], '2026-06-10T08:30:00.000Z');
      expect(json['type'], 'session_update');
      expect(json['recordId'], 42);
      expect(json['isIgnored'], isTrue);
      expect(json['isFullscreen'], isTrue);
      expect(json['keyDistribution'], <String, int>{'65': 2, '66': 1});
      expect(json['keySequence'], 'AB');
      expect(json['deviceId'], 'device-1');
      expect(json['platform'], 'windows');
      expect(json['source'], 'tracker');
      expect(json['note'], 'sampled');

      final minimal = ActivityLogEntry(
        timestamp: DateTime.utc(2026),
        type: ActivityLogEntryType.sample,
        keySequence: '',
        deviceId: '',
        platform: '',
        source: '',
        note: '',
      ).toJson();
      expect(minimal, isNot(contains('keySequence')));
      expect(minimal, isNot(contains('deviceId')));
      expect(minimal, isNot(contains('platform')));
      expect(minimal, isNot(contains('source')));
      expect(minimal, isNot(contains('note')));
    });

    test('parses robust JSON fallbacks and key distribution coercions', () {
      final parsed = ActivityLogEntry.fromJson(<String, dynamic>{
        'timestamp': 'not-a-date',
        'type': 'session_close',
        'recordId': 7.9,
        'isIgnored': true,
        'isFullscreen': true,
        'durationMinutes': 12.8,
        'keyCount': 6.2,
        'mouseClicks': 2.9,
        'mouseMovePx': 123.8,
        'scrollPx': 4.1,
        'keyDistribution': <dynamic, dynamic>{
          '65': 3.7,
          66: 2,
          'bad': 99,
          '67': 'not numeric',
        },
      });

      expect(parsed.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
      expect(parsed.type, ActivityLogEntryType.sessionClose);
      expect(parsed.recordId, 7);
      expect(parsed.durationMinutes, 12);
      expect(parsed.keyCount, 6);
      expect(parsed.mouseClicks, 2);
      expect(parsed.mouseMovePx, 123);
      expect(parsed.scrollPx, 4);
      expect(parsed.keyDistribution, <int, int>{65: 3, 66: 2, 67: 0});
    });

    test('tryParseLine rejects blank malformed and non-object lines', () {
      expect(ActivityLogEntry.tryParseLine('   '), isNull);
      expect(ActivityLogEntry.tryParseLine('not json'), isNull);
      expect(ActivityLogEntry.tryParseLine('[1,2,3]'), isNull);

      final parsed = ActivityLogEntry.tryParseLine(
        ActivityLogEntry(
          timestamp: DateTime.utc(2026, 6, 10, 9),
          type: ActivityLogEntryType.snapshot,
          processName: 'Code.exe',
        ).toJsonLine(),
      );
      expect(parsed, isNotNull);
      expect(parsed!.type, ActivityLogEntryType.snapshot);
      expect(parsed.processName, 'Code.exe');
    });

    test('fromTelemetry copies input telemetry and handles null telemetry', () {
      final timestamp = DateTime.utc(2026, 6, 10, 11);
      final telemetry = InputTelemetry(
        keyCount: 9,
        keyDistribution: const <int, int>{13: 1, 65: 8},
        keySequence: 'Enter A',
        clicks: const MouseClicks(left: 2, right: 1, middle: 1),
        scrollPx: 30,
        mouseMovePx: 250,
        timestamp: timestamp,
        inputEvents: const <RawInputEvent>[],
      );

      final entry = ActivityLogEntry.fromTelemetry(
        timestamp: timestamp,
        type: ActivityLogEntryType.sample,
        isIgnored: false,
        isFullscreen: false,
        processName: 'Code.exe',
        className: 'Editor',
        windowTitle: 'main.dart',
        category: 'coding',
        label: 'VS Code',
        recordId: 5,
        durationMinutes: 15,
        telemetry: telemetry,
        deviceId: 'device',
        platform: 'windows',
        source: 'raw-input',
        note: 'context_changed',
      );

      expect(entry.keyCount, 9);
      expect(entry.mouseClicks, 4);
      expect(entry.mouseMovePx, 250);
      expect(entry.scrollPx, 30);
      expect(entry.keyDistribution, <int, int>{13: 1, 65: 8});
      expect(entry.keySequence, 'Enter A');
      expect(entry.note, 'context_changed');

      final empty = ActivityLogEntry.fromTelemetry(
        timestamp: timestamp,
        type: ActivityLogEntryType.sample,
        isIgnored: true,
        isFullscreen: true,
        processName: null,
        packageName: 'com.example',
        className: null,
        windowTitle: null,
        appLabel: 'Example',
        category: null,
        label: null,
        recordId: null,
        durationMinutes: null,
        telemetry: null,
      );
      expect(empty.keyCount, 0);
      expect(empty.mouseClicks, 0);
      expect(empty.packageName, 'com.example');
      expect(empty.appLabel, 'Example');
      expect(empty.isIgnored, isTrue);
      expect(empty.isFullscreen, isTrue);
    });
  });
}
