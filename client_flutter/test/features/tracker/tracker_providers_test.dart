import 'dart:async';

import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/tracking_store_test_double.dart';

void main() {
  ProviderContainer createContainer(TrackingStoreTestDouble store) {
    final container = ProviderContainer(
      overrides: [
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('inputHeatmapSummaryProvider forwards query and parses server response',
      () async {
    final start = DateTime(2026, 6, 9, 9);
    final end = DateTime(2026, 6, 9, 12);
    final store = TrackingStoreTestDouble(
      inputHeatmapResponseBuilder: (_) => <String, dynamic>{
        'buckets': <Map<String, Object?>>[
          <String, Object?>{
            'bucketStart': start.toIso8601String(),
            'eventCount': 12,
            'keyboardEventCount': 7,
            'mouseButtonEventCount': 2,
            'wheelEventCount': 1,
            'mouseMoveEventCount': 2,
            'mouseMoveDistance': 300,
          },
          <String, Object?>{
            'bucketStart':
                start.add(const Duration(hours: 1)).toIso8601String(),
            'eventCount': '3',
            'keyboardEventCount': '1',
            'mouseButtonEventCount': 1,
            'wheelEventCount': 0,
            'mouseMoveEventCount': 1,
            'mouseMoveDistance': '120',
          },
          <String, Object?>{
            'eventCount': 99,
            'keyboardEventCount': 99,
          },
        ],
        'keyCounts': <String, Object?>{
          '65': 5,
          '66': '3',
          'bad': 9,
          '67': 0,
        },
        'mouseCounts': <String, Object?>{
          'left': 4,
          'right': '2',
          'middle': 0,
          ' ': 1,
        },
        'topKeys': <Map<String, Object?>>[
          <String, Object?>{
            'keyCode': 65,
            'label': 'A',
            'count': 5,
            'share': 0.625,
          },
          <String, Object?>{
            'key_code': 66,
            'eventCount': '3',
          },
          <String, Object?>{
            'keyCode': 67,
            'count': 0,
          },
        ],
        'processIntensities': <Map<String, Object?>>[
          <String, Object?>{
            'process_name': 'Code.exe',
            'eventCount': 15,
            'keyboardEventCount': 8,
            'mouseButtonEventCount': 3,
            'wheelEventCount': 1,
            'mouseMoveEventCount': 3,
            'mouseMoveDistance': 420,
            'activeMinutes': 30,
            'intensityScore': 23,
          },
          <String, Object?>{
            'processName': ' ',
            'eventCount': 99,
          },
        ],
      },
    );
    final container = createContainer(store);
    final query = InputEventQuery(
      start: start,
      end: end,
      processName: 'Code.exe',
    );

    final summary = await container.read(
      inputHeatmapSummaryProvider(query).future,
    );

    expect(store.inputHeatmapCalls, hasLength(1));
    final call = store.inputHeatmapCalls.single;
    expect(call.start, start);
    expect(call.end, end);
    expect(call.bucket, 'hour');
    expect(call.processName, 'Code.exe');
    expect(call.category, isNull);
    expect(call.eventKind, isNull);

    expect(summary.query, query);
    expect(summary.totalEventCount, 15);
    expect(summary.activeMinuteCount, 120);
    expect(summary.keyboardEventCount, 8);
    expect(summary.mouseButtonEventCount, 3);
    expect(summary.wheelEventCount, 1);
    expect(summary.mouseMoveEventCount, 3);
    expect(summary.mouseMoveDistance, 420);
    expect(summary.keyCounts, <int, int>{65: 5, 66: 3});
    expect(summary.mouseCounts, <String, int>{'left': 4, 'right': 2});
    expect(summary.topKeys, hasLength(2));
    expect(summary.topKeys.first.keyCode, 65);
    expect(summary.topKeys.first.label, 'A');
    expect(summary.topKeys.first.count, 5);
    expect(summary.topKeys.first.share, 0.625);
    expect(summary.processIntensities, hasLength(1));
    expect(summary.processIntensities.single.processName, 'Code.exe');
    expect(summary.processIntensities.single.totalEvents, 15);
    expect(summary.processIntensities.single.intensityScore, 23);
    expect(summary.hourlyDistribution, hasLength(24));
    expect(summary.hourlyDistribution[9].totalEvents, 12);
    expect(summary.hourlyDistribution[10].totalEvents, 3);
    expect(summary.hourlyDistribution[10].moveDistance, 120);
  });

  test('serverInputEventsPageProvider forwards page query parameters',
      () async {
    final start = DateTime(2026, 6, 9, 8);
    final end = DateTime(2026, 6, 9, 18);
    final store = TrackingStoreTestDouble(
      inputEventsResponseBuilder: (call) => <String, dynamic>{
        'total': 42,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'event-${call.offset}',
            'objectType': 'tracked_input_event',
          },
        ],
      },
    );
    final container = createContainer(store);
    final query = ServerInputEventQuery(
      start: start,
      end: end,
      processName: 'Code.exe',
      category: 'coding',
      eventKind: 'key_down',
      limit: 25,
      offset: 50,
    );

    final response = await container.read(
      serverInputEventsPageProvider(query).future,
    );

    expect(response['total'], 42);
    expect(store.inputEventsCalls, hasLength(1));
    final call = store.inputEventsCalls.single;
    expect(call.start, start);
    expect(call.end, end);
    expect(call.processName, 'Code.exe');
    expect(call.category, 'coding');
    expect(call.eventKind, 'key_down');
    expect(call.limit, 25);
    expect(call.offset, 50);
  });

  test('serverInputEventsPageProvider propagates store errors', () async {
    final error = StateError('input events unavailable');
    final store = TrackingStoreTestDouble()..inputEventsError = error;
    final container = createContainer(store);

    await expectLater(
      container.read(
        serverInputEventsPageProvider(
          ServerInputEventQuery(
            start: DateTime(2026, 6, 9),
            end: DateTime(2026, 6, 10),
            eventKind: 'mouse_wheel',
            limit: 80,
            offset: 80,
          ),
        ).future,
      ),
      throwsA(same(error)),
    );

    expect(store.inputEventsCalls.single.eventKind, 'mouse_wheel');
    expect(store.inputEventsCalls.single.limit, 80);
    expect(store.inputEventsCalls.single.offset, 80);
  });

  test('serverActivityRecordsPageProvider forwards page query parameters',
      () async {
    final start = DateTime(2026, 6, 9, 8);
    final end = DateTime(2026, 6, 9, 18);
    final store = TrackingStoreTestDouble(
      activityRecordsResponseBuilder: (call) => <String, dynamic>{
        'total': 7,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'record-${call.offset}',
            'objectType': 'activity_record',
          },
        ],
      },
    );
    final container = createContainer(store);
    final query = ServerRecordQuery(
      start: start,
      end: end,
      processName: 'Code.exe',
      category: 'coding',
      taskId: 123,
      limit: 30,
      offset: 60,
    );

    final response = await container.read(
      serverActivityRecordsPageProvider(query).future,
    );

    expect(response['total'], 7);
    expect(store.activityRecordsCalls, hasLength(1));
    final call = store.activityRecordsCalls.single;
    expect(call.start, start);
    expect(call.end, end);
    expect(call.processName, 'Code.exe');
    expect(call.category, 'coding');
    expect(call.taskId, 123);
    expect(call.limit, 30);
    expect(call.offset, 60);
  });

  test('trackerServerFilterOptionsProvider exposes loading and errors',
      () async {
    final completer = Completer<TrackingServerFirstStore>();
    final loadingStore = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe'],
      categoryOptions: const <String>['coding'],
    );
    final loadingContainer = ProviderContainer(
      overrides: [
        trackingServerFirstStoreProvider
            .overrideWith((ref) => completer.future),
      ],
    );
    addTearDown(loadingContainer.dispose);

    expect(loadingContainer.read(trackerServerFilterOptionsProvider).isLoading,
        isTrue);

    completer.complete(loadingStore);
    expect(
      (await loadingContainer
          .read(trackerServerFilterOptionsProvider.future))['processOptions'],
      <String>['Code.exe'],
    );
    expect(loadingStore.inputEventsCalls, isEmpty);

    final error = StateError('filter options unavailable');
    final errorStore = TrackingStoreTestDouble()..filterOptionsError = error;
    final errorContainer = createContainer(errorStore);

    await expectLater(
      errorContainer.read(trackerServerFilterOptionsProvider.future),
      throwsA(same(error)),
    );
    expect(errorContainer.read(trackerServerFilterOptionsProvider).hasError,
        isTrue);
    expect(
      errorContainer.read(trackerHistoryFilterOptionsProvider).processOptions,
      isEmpty,
    );
  });

  test('trackerHistoryFilterOptionsProvider sorts dedupes and drops blanks',
      () async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>[
        'beta.exe',
        '',
        ' Alpha.exe ',
        'beta.exe',
        '  ',
      ],
      categoryOptions: const <String>[
        'research',
        ' coding ',
        '',
        'research',
      ],
    );
    final container = createContainer(store);

    await container.read(trackerServerFilterOptionsProvider.future);
    final options = container.read(trackerHistoryFilterOptionsProvider);

    expect(options.processOptions, <String>['Alpha.exe', 'beta.exe']);
    expect(options.categoryOptions, <String>['coding', 'research']);
  });

  test('selectedDateInputBehaviorSummaryProvider uses the selected day range',
      () async {
    final selected = DateTime(2026, 6, 9, 15, 45);
    final expectedStart = DateTime(2026, 6, 9);
    final expectedEnd = DateTime(2026, 6, 10);
    final store = TrackingStoreTestDouble(
      inputHeatmapResponseBuilder: (_) => <String, dynamic>{
        'buckets': <Map<String, Object?>>[
          <String, Object?>{
            'bucketStart': DateTime(2026, 6, 9, 23).toIso8601String(),
            'eventCount': 4,
            'keyboardEventCount': 2,
            'mouseButtonEventCount': 1,
            'wheelEventCount': 0,
            'mouseMoveEventCount': 1,
            'mouseMoveDistance': 80,
          },
        ],
      },
    );
    final container = createContainer(store);
    final dynamic selectedDateNotifier = container.read(
      selectedDateProvider.notifier,
    );
    selectedDateNotifier.setDate(selected);

    final summary = await container.read(
      selectedDateInputBehaviorSummaryProvider.future,
    );

    expect(store.inputHeatmapCalls, hasLength(1));
    final call = store.inputHeatmapCalls.single;
    expect(call.start, expectedStart);
    expect(call.end, expectedEnd);
    expect(call.bucket, 'hour');
    expect(call.processName, isNull);
    expect(call.category, isNull);
    expect(call.eventKind, isNull);
    expect(summary.query.start, expectedStart);
    expect(summary.query.end, expectedEnd);
    expect(summary.query.processName, isNull);
    expect(summary.totalEventCount, 4);
    expect(summary.hourlyDistribution[23].totalEvents, 4);
  });
}
