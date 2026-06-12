import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_input_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/tracking_store_test_double.dart';

void main() {
  testWidgets('log history changes date, searches, filters and paginates', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe', 'Chrome.exe'],
      categoryOptions: const <String>['coding', 'research'],
      activityRecordsResponseBuilder: (call) {
        final process = call.processName;
        final prefix = process == null ? 'All' : process.split('.').first;
        return <String, dynamic>{
          'total': 120,
          'items': _activityRecordItems(
            count: 50,
            prefix: prefix,
            offset: call.offset,
            onlyProcess: process,
          ),
        };
      },
    );

    await _pumpTrackerPage(
      tester,
      store: store,
      child: const TrackerLogHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('All record 49'));

    final initialStart = store.activityRecordsCalls.single.start!;
    expect(store.activityRecordsCalls.single.limit, 50);
    expect(store.activityRecordsCalls.single.offset, 0);
    expect(store.activityRecordsCalls.single.processName, isNull);

    await tester.tap(find.byKey(AppKeys.trackerLogHistoryNextPageButton));
    await _pumpUntil(
      tester,
      () => store.activityRecordsCalls.last.offset == 50,
    );
    expect(store.activityRecordsCalls.last.processName, isNull);
    final callsBeforePreviousDay = store.activityRecordsCalls.length;
    await tester.tap(find.byTooltip('前一天'));
    await _pumpUntil(
      tester,
      () => store.activityRecordsCalls.length > callsBeforePreviousDay,
    );
    expect(
      store.activityRecordsCalls.last.start,
      initialStart.subtract(const Duration(days: 1)),
    );
    expect(store.activityRecordsCalls.last.offset, 0);

    final callsBeforeSecondPreviousDay = store.activityRecordsCalls.length;
    await tester.tap(find.byTooltip('前一天'));
    await _pumpUntil(
      tester,
      () =>
          store.activityRecordsCalls.length > callsBeforeSecondPreviousDay &&
          store.activityRecordsCalls.last.start ==
              initialStart.subtract(const Duration(days: 2)),
    );

    final recordSearchField = _textFieldWithHint('搜索进程名、窗口标题、分类');
    await _pumpUntilFound(tester, recordSearchField);
    await tester.enterText(recordSearchField, 'all record 49');
    await tester.pump();
    expect(_textFieldValue(tester, recordSearchField), 'all record 49');
    expect(find.byTooltip('清空搜索'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(_textFieldValue(tester, recordSearchField), isEmpty);

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
    expect(store.activityRecordsCalls.last.start,
        initialStart.subtract(const Duration(days: 2)));
  });

  testWidgets(
      'input history changes date, filters kind, searches and paginates',
      (tester) async {
    final store = TrackingStoreTestDouble(
      inputEventsResponseBuilder: (call) {
        return <String, dynamic>{
          'total': 160,
          'items': _inputEventItems(
            count: 80,
            offset: call.offset,
            eventKind: call.eventKind,
          ),
        };
      },
    );

    await _pumpTrackerPage(
      tester,
      store: store,
      child: const TrackerInputHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('Key typing 79'));

    final initialStart = store.inputEventsCalls.single.start!;
    expect(store.inputEventsCalls.single.limit, 80);
    expect(store.inputEventsCalls.single.offset, 0);
    expect(store.inputEventsCalls.single.eventKind, isNull);

    await tester.tap(find.byKey(AppKeys.trackerInputHistoryNextPageButton));
    await _pumpUntil(
      tester,
      () => store.inputEventsCalls.last.offset == 80,
    );
    expect(store.inputEventsCalls.last.eventKind, isNull);
    final inputCallsBeforePreviousDay = store.inputEventsCalls.length;
    await tester.tap(find.byTooltip('前一天'));
    await _pumpUntil(
      tester,
      () => store.inputEventsCalls.length > inputCallsBeforePreviousDay,
    );
    expect(
      store.inputEventsCalls.last.start,
      initialStart.subtract(const Duration(days: 1)),
    );

    final wheelFilter = find.ancestor(
      of: find.text('滚轮'),
      matching: find.byType(ListTile),
    );
    expect(wheelFilter, findsOneWidget);
    await tester.tap(wheelFilter);
    await _pumpUntil(
      tester,
      () => store.inputEventsCalls.last.eventKind == 'mouse_wheel',
    );
    expect(store.inputEventsCalls.last.offset, 0);
    expect(store.inputEventsCalls.last.start,
        initialStart.subtract(const Duration(days: 1)));

    final inputSearchField = _textFieldWithHint('搜索进程名、窗口标题、按键标签');
    await _pumpUntilFound(tester, inputSearchField);
    await tester.enterText(inputSearchField, 'wheel review 0');
    await tester.pump();
    expect(_textFieldValue(tester, inputSearchField), 'wheel review 0');
    expect(find.byTooltip('清空搜索'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(_textFieldValue(tester, inputSearchField), isEmpty);
  });
}

Future<void> _pumpTrackerPage(
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
    size: const Size(1200, 860),
    overrides: [
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
    ],
    child: MaterialApp(home: child),
  );
  await _pumpFrames(tester);
}

List<Map<String, Object?>> _activityRecordItems({
  required int count,
  required String prefix,
  required int offset,
  required String? onlyProcess,
}) {
  final processName =
      onlyProcess ?? (prefix == 'All' ? 'Code.exe' : '$prefix.exe');
  final category = processName == 'Chrome.exe' ? 'research' : 'coding';
  return List<Map<String, Object?>>.generate(count, (index) {
    final absoluteIndex = offset + index;
    final timestamp = DateTime(2026, 6, 9, 9).add(
      Duration(minutes: absoluteIndex),
    );
    return <String, Object?>{
      'serverId': 'record-$prefix-$absoluteIndex',
      'objectType': 'activity_record',
      'occurredAt': timestamp.toIso8601String(),
      'metricMinutes': 10,
      'payload': <String, Object?>{
        'startTime': timestamp.toIso8601String(),
        'durationMinutes': 10,
        'processName': processName,
        'windowTitle': '$prefix tracker window $absoluteIndex',
        'category': category,
        'manualLabel': '$prefix record $absoluteIndex',
        'keyCount': 20 + index,
        'mouseClicks': 1,
        'scrollPx': 0,
        'isAuto': index.isEven,
      },
    };
  });
}

List<Map<String, Object?>> _inputEventItems({
  required int count,
  required int offset,
  required String? eventKind,
}) {
  final kind = eventKind ?? 'key_down';
  final prefix = kind == 'mouse_wheel' ? 'Wheel review' : 'Key typing';
  return List<Map<String, Object?>>.generate(count, (index) {
    final absoluteIndex = offset + index;
    final timestamp = DateTime(2026, 6, 9, 9).add(
      Duration(minutes: absoluteIndex),
    );
    return <String, Object?>{
      'serverId': 'input-$kind-$absoluteIndex',
      'objectType': 'tracked_input_event',
      'occurredAt': timestamp.toIso8601String(),
      'metricCount': kind == 'mouse_wheel' ? 3 : 1,
      'payload': <String, Object?>{
        'eventUid': 'input-$kind-$absoluteIndex',
        'sequenceId': absoluteIndex + 1,
        'timestamp': timestamp.toIso8601String(),
        'kind': kind,
        'eventCount': kind == 'mouse_wheel' ? 3 : 1,
        'processName': kind == 'mouse_wheel' ? 'Chrome.exe' : 'Code.exe',
        'windowTitle': '$prefix window $absoluteIndex',
        'category': kind == 'mouse_wheel' ? 'research' : 'coding',
        'activityLabel': '$prefix $absoluteIndex',
        if (kind == 'mouse_wheel') ...<String, Object?>{
          'mouseButton': 'wheel_down',
          'wheelDelta': -120,
        } else ...<String, Object?>{
          'keyCode': 65,
          'keyLabel': 'A',
          'tokenText': 'a',
        },
      },
    };
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

Finder _textFieldWithHint(String hintText) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hintText,
  );
}

String _textFieldValue(WidgetTester tester, Finder finder) {
  final field = tester.widget<TextField>(finder);
  return field.controller?.text ?? '';
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (predicate()) {
      return;
    }
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Expected condition to become true within bounded pumps.',
  );
}
