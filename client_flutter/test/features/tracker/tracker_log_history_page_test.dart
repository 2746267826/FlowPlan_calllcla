import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
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

  List<Map<String, Object?>> activityRecordItems({int count = 51}) {
    final chromeAt = DateTime(2026, 6, 9, 10, 30);
    return <Map<String, Object?>>[
      <String, Object?>{
        'serverId': 'record-chrome',
        'objectType': 'activity_record',
        'occurredAt': chromeAt.toIso8601String(),
        'metricMinutes': 25,
        'payload': <String, Object?>{
          'startTime': chromeAt.toIso8601String(),
          'durationMinutes': 25,
          'processName': 'Chrome.exe',
          'windowTitle': 'Research docs',
          'category': 'research',
          'manualLabel': 'Research docs',
          'keyCount': 12,
          'mouseClicks': 3,
          'scrollPx': 480,
          'isAuto': true,
        },
      },
      ...List<Map<String, Object?>>.generate(count - 1, (index) {
        final timestamp = DateTime(2026, 6, 9, 9, index % 60);
        return <String, Object?>{
          'serverId': 'record-code-$index',
          'objectType': 'activity_record',
          'occurredAt': timestamp.toIso8601String(),
          'metricMinutes': 10,
          'payload': <String, Object?>{
            'startTime': timestamp.toIso8601String(),
            'durationMinutes': 10,
            'processName': 'Code.exe',
            'windowTitle': 'Tracker tests',
            'category': 'coding',
            'manualLabel': 'Deep coding $index',
            'keyCount': 20,
            'mouseClicks': 1,
            'scrollPx': 0,
            'isAuto': false,
          },
        };
      }),
    ];
  }

  testWidgets('log history searches records and applies process filter', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe', 'Chrome.exe'],
      categoryOptions: const <String>['coding', 'research'],
      activityRecordsResponseBuilder: (call) {
        final items = activityRecordItems().where((item) {
          final payload = Map<String, Object?>.from(item['payload']! as Map);
          return call.processName == null ||
              payload['processName'] == call.processName;
        }).toList(growable: false);
        return <String, dynamic>{
          'total': 120,
          'items': items,
        };
      },
    );

    await pumpTrackerPage(
      tester,
      store: store,
      child: const TrackerLogHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('Research docs'));

    expect(store.activityRecordsCalls.single.limit, 50);
    expect(store.activityRecordsCalls.single.offset, 0);
    expect(store.activityRecordsCalls.single.processName, isNull);
    expect(find.text('Research docs'), findsOneWidget);
    expect(find.text('Deep coding 49'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'chrome research');
    await tester.pump();

    expect(find.text('Research docs'), findsOneWidget);
    expect(find.text('Deep coding 49'), findsNothing);

    final codeFilter = find.ancestor(
      of: find.text('Code.exe'),
      matching: find.byType(ListTile),
    );
    expect(codeFilter, findsOneWidget);
    await tester.tap(codeFilter);
    await _pumpUntil(
      tester,
      () => store.activityRecordsCalls.last.processName == 'Code.exe',
    );

    expect(store.activityRecordsCalls.last.processName, 'Code.exe');
    expect(store.activityRecordsCalls.last.offset, 0);
    await _pumpFrames(tester);

    final nextPageButton = find.byKey(AppKeys.trackerLogHistoryNextPageButton);
    expect(nextPageButton, findsOneWidget);
    await tester.tap(nextPageButton);
    await _pumpUntil(
        tester, () => store.activityRecordsCalls.last.offset == 50);
    expect(store.activityRecordsCalls.last.processName, 'Code.exe');
    expect(store.activityRecordsCalls.last.offset, 50);
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
