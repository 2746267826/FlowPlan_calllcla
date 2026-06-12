import 'package:flowplanv2/features/task/presentation/quick_add_bar.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets('quick add tracker validates input, records and stops activity',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = _FakeActivityRecordRepository(db);
    var currentTime = DateTime.utc(2026, 6, 8, 9);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      overrides: <Override>[
        activityRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: QuickAddBar(now: () => currentTime),
          ),
        ),
      ),
    );

    expect(find.text('现在在做：'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();
    expect(repository.startedLabels, isEmpty);

    await tester.enterText(find.byType(TextField), '  Draft coverage notes  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repository.startedLabels, <String>['Draft coverage notes']);
    expect(find.text('Draft coverage notes'), findsOneWidget);
    expect(find.text('0s'), findsOneWidget);
    expect(find.text('现在在做：'), findsNothing);

    currentTime = currentTime.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining(RegExp(r'1m \d+s')), findsOneWidget);

    await tester.tap(find.text('结束'));
    await tester.pump();

    expect(repository.endedIds, <int>[101]);
    expect(find.text('现在在做：'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'「Draft coverage notes」已记录 1m \d+s')),
      findsOneWidget,
    );
  });
}

class _FakeActivityRecordRepository extends ActivityRecordRepository {
  _FakeActivityRecordRepository(super.db);

  final startedLabels = <String>[];
  final endedIds = <int>[];

  @override
  Future<int> startRecord({
    required DateTime startTime,
    String? manualLabel,
    String? processName,
    String? windowTitle,
    String? packageName,
    String? category,
    String? deviceId,
    String? platform,
    int? linkedTaskId,
    bool isAuto = false,
    String source = 'manual',
  }) async {
    startedLabels.add(manualLabel ?? '');
    return 101;
  }

  @override
  Future<void> endRecord(
    int id,
    DateTime endTime, {
    dynamic telemetry,
  }) async {
    endedIds.add(id);
  }
}
