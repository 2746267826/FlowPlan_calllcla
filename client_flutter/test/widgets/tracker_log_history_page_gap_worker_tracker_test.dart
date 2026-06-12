import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/tracking_store_test_double.dart';

void main() {
  testWidgets('shows loading, empty and error states with retry refresh', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble();
    final db = createTestDatabase();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, 4);
      await db.close();
    });

    store.activityRecordsError = StateError('server unavailable');

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(390, 820),
      overrides: [
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
      child: const MaterialApp(home: TrackerLogHistoryPage()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _pumpUntilFound(tester, find.textContaining('server unavailable'));

    expect(store.activityRecordsCalls, hasLength(1));
    store.activityRecordsError = null;
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.refresh));
    await _pumpUntil(tester, () => store.activityRecordsCalls.length == 2);
    await _pumpUntilFound(tester, find.byType(TextField));

    expect(find.textContaining('0'), findsWidgets);
    expect(find.text('Fallback window'), findsNothing);
    expect(store.activityRecordsCalls.last.limit, 50);
    expect(store.activityRecordsCalls.last.offset, 0);
  });

  testWidgets('date controls, filters, search and pagination call store',
      (tester) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe', 'Chrome.exe'],
      categoryOptions: const <String>['coding', 'research'],
      activityRecordsResponseBuilder: (call) {
        final process = call.processName;
        return <String, dynamic>{
          'total': 125,
          'items': _records(
            count: call.offset == 100 ? 25 : 50,
            offset: call.offset,
            processName: process ?? 'Code.exe',
            labelPrefix: process == null ? 'All log' : 'Filtered log',
          ),
        };
      },
    );

    await _pumpTrackerPage(
      tester,
      store: store,
    );
    await _pumpUntilFound(tester, find.text('All log 49'));

    final initialStart = store.activityRecordsCalls.single.start!;
    expect(store.activityRecordsCalls.single.limit, 50);
    expect(store.activityRecordsCalls.single.offset, 0);
    expect(store.activityRecordsCalls.single.processName, isNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await _pumpUntil(
      tester,
      () =>
          store.activityRecordsCalls.last.start ==
          initialStart.add(const Duration(days: 1)),
    );
    expect(store.activityRecordsCalls.last.offset, 0);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.today_outlined));
    await tester.pumpAndSettle();
    expect(find.text(_formatDate(initialStart)), findsWidgets);

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
    expect(store.activityRecordsCalls.last.offset, 0);

    await tester.tap(codeFilter);
    await _pumpUntilFound(tester, find.text('All log 49'));

    await tester.enterText(find.byType(TextField), 'all log 49 code');
    await tester.pump();
    expect(find.text('All log 49'), findsOneWidget);
    expect(find.text('All log 48'), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pump();
    expect(_textFieldValue(tester, find.byType(TextField)), isEmpty);
    await _pumpUntilFound(
      tester,
      find.byKey(AppKeys.trackerLogHistoryNextPageButton),
    );

    await tester.tap(find.byKey(AppKeys.trackerLogHistoryNextPageButton));
    await _pumpUntil(
        tester, () => store.activityRecordsCalls.last.offset == 50);
    await _pumpUntilFound(
      tester,
      find.byKey(AppKeys.trackerLogHistoryNextPageButton),
    );
    await tester.tap(find.byKey(AppKeys.trackerLogHistoryNextPageButton));
    await _pumpUntil(
      tester,
      () => store.activityRecordsCalls.last.offset == 100,
    );
    await _pumpUntilFound(
      tester,
      find.byKey(AppKeys.trackerLogHistoryPreviousPageButton),
    );
    await tester.tap(find.byKey(AppKeys.trackerLogHistoryPreviousPageButton));
    await _pumpUntilFound(tester, find.text('All log 99'));
  });

  testWidgets('renders fallback titles, details and server payload variants',
      (tester) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Package.exe'],
      activityRecordsResponseBuilder: (_) => <String, dynamic>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'variant-map',
            'objectType': 'legacy_activity',
            'occurredAt': DateTime(2026, 6, 9, 8).toIso8601String(),
            'metricMinutes': '9',
            'payload': <Object?, Object?>{
              'start_time': DateTime(2026, 6, 9, 9, 15).toIso8601String(),
              'duration_minutes': '12.4',
              'process_name': 'Snake.exe',
              'window_title': 'Fallback window',
              'category': 'legacy',
              'key_count': '7',
              'mouse_clicks': 2.2,
              'mouse_move_px': '33',
              'scroll_px': '44.6',
              'linked_task_id': '42',
              'isAuto': false,
            },
          },
          <String, Object?>{
            'serverId': 'package-name',
            'objectType': 'package_activity',
            'occurredAt': DateTime(2026, 6, 9, 10).toIso8601String(),
            'payload': <String, Object?>{
              'startedAt': DateTime(2026, 6, 9, 10, 30).toIso8601String(),
              'packageName': 'Fallback.exe',
              'title': '   ',
              'label': '   ',
              'durationMinutes': 0,
            },
          },
          <String, Object?>{
            'serverId': 'manual-label',
            'objectType': 'activity_record',
            'occurredAt': DateTime(2026, 6, 9, 11).toIso8601String(),
            'metricMinutes': 5,
            'payload': <String, Object?>{
              'startTime': DateTime(2026, 6, 9, 11, 45).toIso8601String(),
              'processName': 'Code.exe',
              'windowTitle': 'Manual window',
              'manualLabel': 'Manual title',
              'category': 'coding',
              'keyCount': 1,
            },
          },
        ],
      },
    );

    await _pumpTrackerPage(tester, store: store);
    await _pumpUntilFound(tester, find.text('Manual title'));

    expect(find.text('Manual title'), findsOneWidget);
    expect(find.text('Fallback.exe'), findsWidgets);
    expect(find.text('Fallback window'), findsOneWidget);
    expect(find.textContaining('legacy'), findsWidgets);
    expect(find.textContaining('7'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('33px'), findsWidgets);
    expect(find.textContaining('45px'), findsWidgets);
    expect(find.textContaining('12'), findsWidgets);

    await tester.tap(find.byType(ExpansionTile).last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Snake.exe'), findsWidgets);
    expect(find.textContaining('42'), findsOneWidget);
    expect(find.textContaining('legacy_activity'), findsOneWidget);
  });
}

Future<void> _pumpTrackerPage(
  WidgetTester tester, {
  required TrackingStoreTestDouble store,
  Size size = const Size(1200, 820),
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
    size: size,
    overrides: [
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
    ],
    child: const MaterialApp(home: TrackerLogHistoryPage()),
  );
  await _pumpFrames(tester);
}

List<Map<String, Object?>> _records({
  required int count,
  required int offset,
  required String processName,
  required String labelPrefix,
}) {
  return List<Map<String, Object?>>.generate(count, (index) {
    final absoluteIndex = offset + index;
    final timestamp = DateTime(2026, 6, 9, 9).add(
      Duration(minutes: absoluteIndex),
    );
    return <String, Object?>{
      'serverId': 'record-$absoluteIndex',
      'objectType': 'activity_record',
      'occurredAt': timestamp.toIso8601String(),
      'metricMinutes': 10,
      'payload': <String, Object?>{
        'startTime': timestamp.toIso8601String(),
        'durationMinutes': 10,
        'processName': processName,
        'windowTitle': '$processName window $absoluteIndex',
        'category': processName == 'Chrome.exe' ? 'research' : 'coding',
        'manualLabel': '$labelPrefix $absoluteIndex',
        'keyCount': index + 1,
        'mouseClicks': index.isEven ? 1 : 0,
        'scrollPx': index.isOdd ? 80 : 0,
        'isAuto': index.isEven,
      },
    };
  });
}

String _textFieldValue(WidgetTester tester, Finder finder) {
  final field = tester.widget<TextField>(finder);
  return field.controller?.text ?? '';
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 30,
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
  int maxPumps = 30,
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
