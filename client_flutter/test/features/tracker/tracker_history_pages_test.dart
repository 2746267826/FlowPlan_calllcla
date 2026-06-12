import 'package:flowplanv2/features/tracker/presentation/tracker_input_history_page.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/provider_harness.dart';
import '../../test_support/test_database.dart';
import '../../test_support/tracking_store_test_double.dart';

void main() {
  Future<void> pumpTrackerPage(
    WidgetTester tester, {
    required Widget child,
    required TrackingStoreTestDouble store,
  }) async {
    final db = createTestDatabase();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, 4);
      await db.close();
    });

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(1200, 820),
      overrides: [
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
      child: MaterialApp(home: child),
    );
    await _pumpFrames(tester);
  }

  List<Map<String, Object?>> inputEventItems({int count = 80}) {
    final chromeAt = DateTime(2026, 6, 9, 10, 40);
    return <Map<String, Object?>>[
      <String, Object?>{
        'serverId': 'input-chrome',
        'objectType': 'tracked_input_event',
        'occurredAt': chromeAt.toIso8601String(),
        'metricCount': 4,
        'payload': <String, Object?>{
          'eventUid': 'input-chrome',
          'sequenceId': 200,
          'timestamp': chromeAt.toIso8601String(),
          'kind': 'mouse_wheel',
          'eventCount': 4,
          'processName': 'Chrome.exe',
          'windowTitle': 'Docs tab',
          'category': 'research',
          'activityLabel': 'Browser scroll',
          'mouseButton': 'wheel_down',
          'wheelDelta': -120,
        },
      },
      ...List<Map<String, Object?>>.generate(count - 1, (index) {
        final timestamp = DateTime(2026, 6, 9, 9, index % 60);
        return <String, Object?>{
          'serverId': 'input-code-$index',
          'objectType': 'tracked_input_event',
          'occurredAt': timestamp.toIso8601String(),
          'metricCount': 1,
          'payload': <String, Object?>{
            'eventUid': 'input-code-$index',
            'sequenceId': index + 1,
            'timestamp': timestamp.toIso8601String(),
            'kind': 'key_down',
            'eventCount': 1,
            'processName': 'Code.exe',
            'windowTitle': 'Tracker tests',
            'category': 'coding',
            'activityLabel': 'Typed Dart test $index',
            'keyCode': 65,
            'keyLabel': 'A',
            'tokenText': 'a',
          },
        };
      }),
    ];
  }

  testWidgets('input history paginates searches and filters event kind', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      inputEventsResponseBuilder: (call) => <String, dynamic>{
        'total': 160,
        'items': inputEventItems(),
      },
    );

    await pumpTrackerPage(
      tester,
      store: store,
      child: const TrackerInputHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('Browser scroll'));

    expect(store.inputEventsCalls.single.limit, 80);
    expect(store.inputEventsCalls.single.offset, 0);
    expect(find.text('Browser scroll'), findsOneWidget);

    final nextPageButton =
        find.byKey(AppKeys.trackerInputHistoryNextPageButton);
    expect(nextPageButton, findsOneWidget);
    await tester.tap(nextPageButton);
    await _pumpUntil(tester, () => store.inputEventsCalls.last.offset == 80);
    expect(store.inputEventsCalls.last.offset, 80);
    await _pumpFrames(tester);

    await tester.enterText(find.byType(TextField), 'chrome mouse_wheel');
    await tester.pump();

    expect(find.text('Browser scroll'), findsOneWidget);
    expect(find.text('Typed Dart test 0'), findsNothing);

    final wheelFilter = find.ancestor(
      of: find.text('滚轮'),
      matching: find.byType(ListTile),
    );
    expect(wheelFilter, findsOneWidget);
    await tester.tap(wheelFilter);
    await _pumpUntil(
        tester, () => store.inputEventsCalls.last.eventKind == 'mouse_wheel');
    expect(store.inputEventsCalls.last.eventKind, 'mouse_wheel');
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    maxPumps: maxPumps,
  );
  expect(finder, findsWidgets);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Expected condition to become true within bounded pumps.',
  );
}
