import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('log history process filter toggles, clears, and resets paging',
      (tester) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe', 'Browser.exe'],
      categoryOptions: const <String>['coding'],
      activityRecordsResponseBuilder: (call) {
        final start = call.start ?? DateTime(2026, 6, 11);
        return <String, dynamic>{
          'total': 60,
          'items': List<Map<String, Object?>>.generate(
            50,
            (index) => <String, Object?>{
              'serverId': 'record-$index',
              'occurredAt':
                  start.add(Duration(minutes: index)).toIso8601String(),
              'metricMinutes': 5,
              'payload': <String, Object?>{
                'startTime':
                    start.add(Duration(minutes: index)).toIso8601String(),
                'durationMinutes': 5,
                'processName': call.processName ?? 'Code.exe',
                'windowTitle': 'History record $index',
                'category': call.category ?? 'coding',
                'manualLabel': 'History record $index',
              },
            },
          ),
        };
      },
    );

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.trackerLogHistory,
      size: const Size(1400, 1000),
      overrides: <Override>[
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
    );
    await pumpUntilFound(
      tester,
      find.byType(TrackerLogHistoryPage),
      maxPumps: 20,
    );
    await pumpUntil(tester, () => store.activityRecordsCalls.isNotEmpty);

    await tester.tap(find.byKey(AppKeys.trackerLogHistoryNextPageButton));
    await tester.pump();
    await pumpUntil(tester, () => store.activityRecordsCalls.last.offset == 50);

    await tester.tap(_filterTile('Code.exe'));
    await tester.pump();
    await pumpUntil(
      tester,
      () =>
          store.activityRecordsCalls.last.processName == 'Code.exe' &&
          store.activityRecordsCalls.last.offset == 0,
    );
    expect(_filterTile('Code.exe', selected: true), findsOneWidget);
    expect(_filterTile('\u5168\u90e8\u5e94\u7528', selected: false),
        findsOneWidget);

    await tester.tap(_filterTile('Code.exe'));
    await tester.pump();
    await pumpUntil(
      tester,
      () =>
          _filterTile('\u5168\u90e8\u5e94\u7528', selected: true)
              .evaluate()
              .isNotEmpty &&
          _filterTile('Code.exe', selected: false).evaluate().isNotEmpty,
    );

    await tester.tap(_filterTile('Code.exe'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => _filterTile('Code.exe', selected: true).evaluate().isNotEmpty,
    );

    await tester.tap(find.text('全部应用'));
    await tester.pump();
    await pumpUntil(
      tester,
      () =>
          _filterTile('\u5168\u90e8\u5e94\u7528', selected: true)
              .evaluate()
              .isNotEmpty &&
          _filterTile('Code.exe', selected: false).evaluate().isNotEmpty,
    );
  });

  testWidgets('log history date controls and search empty state update queries',
      (tester) async {
    final store = TrackingStoreTestDouble(
      activityRecordsResponseBuilder: (_) => <String, dynamic>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'visible-record',
            'occurredAt': DateTime(2026, 6, 11, 9).toIso8601String(),
            'metricMinutes': 5,
            'payload': <String, Object?>{
              'startTime': DateTime(2026, 6, 11, 9).toIso8601String(),
              'durationMinutes': 5,
              'processName': 'Code.exe',
              'windowTitle': 'Tracker implementation',
              'category': 'coding',
              'manualLabel': 'Visible tracker work',
            },
          },
        ],
      },
    );

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.trackerLogHistory,
      size: const Size(1400, 1000),
      overrides: <Override>[
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
    );
    await pumpUntilFound(
      tester,
      find.byType(TrackerLogHistoryPage),
      maxPumps: 20,
    );
    await pumpUntilFound(tester, find.text('Visible tracker work'));
    final firstStart = store.activityRecordsCalls.last.start;

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await pumpUntil(
      tester,
      () => store.activityRecordsCalls.last.start != firstStart,
    );

    await tester.enterText(find.byType(TextField), 'missing term');
    await tester.pump();
    expect(find.text('Visible tracker work'), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Visible tracker work'), findsOneWidget);
  });
}

Finder _filterTile(String label, {bool? selected}) {
  return find.byElementPredicate(
    (element) {
      if (element.widget is! ListTile) {
        return false;
      }
      var hasLabel = false;
      var hasSelectedIcon = false;
      var hasUnselectedIcon = false;
      void visit(Element child) {
        final widget = child.widget;
        if (widget is Text && widget.data == label) {
          hasLabel = true;
        }
        if (widget is Icon && widget.icon == Icons.filter_alt) {
          hasSelectedIcon = true;
        }
        if (widget is Icon && widget.icon == Icons.filter_alt_outlined) {
          hasUnselectedIcon = true;
        }
        child.visitChildElements(visit);
      }

      element.visitChildElements(visit);
      if (!hasLabel) {
        return false;
      }
      if (selected == true) {
        return hasSelectedIcon;
      }
      if (selected == false) {
        return hasUnselectedIcon;
      }
      return hasSelectedIcon || hasUnselectedIcon;
    },
    description: 'tracker filter tile "$label"',
  );
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}
