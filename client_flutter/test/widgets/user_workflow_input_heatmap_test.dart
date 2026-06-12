import 'package:flowplanv2/features/tracker/presentation/input_heatmap_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/tracking_store_test_double.dart';

void main() {
  test('custom range query falls back to the last seven days without a range',
      () {
    final now = DateTime(2026, 6, 12, 15, 30);

    final query = debugBuildCustomInputHeatmapQueryWithoutRange(
      now: now,
      processName: 'Code.exe',
    );

    expect(query.start, DateTime(2026, 6, 6));
    expect(query.end, DateTime(2026, 6, 13));
    expect(query.processName, 'Code.exe');
  });

  Future<void> pumpHeatmapPage(
    WidgetTester tester, {
    required TrackingStoreTestDouble store,
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingServerFirstStoreProvider.overrideWith((ref) async => store),
        ],
        child: const MaterialApp(home: InputHeatmapPage()),
      ),
    );
    await tester.pump();
    await _pumpFrames(tester);
  }

  Map<String, dynamic> heatmapResponse(InputHeatmapCall call) {
    final processName = call.processName ?? 'Code.exe';
    return <String, dynamic>{
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'bucketStart': DateTime(2026, 6, 9, 10).toIso8601String(),
          'eventCount': 13,
          'keyboardEventCount': 7,
          'mouseButtonEventCount': 2,
          'wheelEventCount': 4,
          'mouseMoveEventCount': 0,
          'mouseMoveDistance': 0,
        },
      ],
      'keyCounts': <String, Object?>{'65': 7},
      'mouseCounts': <String, Object?>{
        'left': 2,
        'wheel_down': 4,
      },
      'topKeys': <Map<String, Object?>>[
        <String, Object?>{'keyCode': 65, 'count': 7},
      ],
      'processIntensities': <Map<String, Object?>>[
        <String, Object?>{
          'processName': processName,
          'totalEvents': 13,
          'keyEvents': 7,
          'mouseButtonEvents': 2,
          'wheelEvents': 4,
          'mouseMoveEvents': 0,
          'moveDistance': 0,
          'activeMinutes': 60,
          'intensityScore': 55,
        },
      ],
    };
  }

  testWidgets('renders heatmap summary and reloads selected process', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe', 'Chrome.exe'],
      inputHeatmapResponseBuilder: heatmapResponse,
    );

    await pumpHeatmapPage(tester, store: store);

    expect(store.inputHeatmapCalls, hasLength(1));
    expect(store.inputHeatmapCalls.single.bucket, 'hour');
    expect(store.inputHeatmapCalls.single.processName, isNull);
    expect(find.text('A 7'), findsOneWidget);
    expect(find.text('Code.exe'), findsWidgets);
    expect(find.text('13'), findsWidgets);

    final dropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String?>,
    );
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await _pumpFrames(tester);
    await tester.tap(find.text('Chrome.exe').last);
    await _pumpFrames(tester);

    expect(store.inputHeatmapCalls.last.processName, 'Chrome.exe');
    expect(find.text('Chrome.exe'), findsWidgets);

    await tester.tap(find.byType(ChoiceChip).at(1));
    await _pumpFrames(tester);

    final latestCall = store.inputHeatmapCalls.last;
    expect(latestCall.processName, 'Chrome.exe');
    expect(
        latestCall.end!.difference(latestCall.start!), const Duration(days: 7));
  });

  testWidgets('renders server heatmap error state', (tester) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe'],
    )..inputHeatmapError = StateError('heatmap boom');

    await pumpHeatmapPage(tester, store: store);

    expect(store.inputHeatmapCalls, hasLength(1));
    expect(find.textContaining('heatmap boom'), findsWidgets);
  });

  testWidgets('renders empty heatmap and export notice without data', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe'],
    );

    await pumpHeatmapPage(tester, store: store);

    expect(store.inputHeatmapCalls, hasLength(1));
    expect(find.text('0'), findsWidgets);
    expect(find.text('当前筛选条件下暂无键盘输入记录。'), findsOneWidget);
    expect(find.text('当前筛选条件下暂无鼠标输入记录。'), findsOneWidget);

    await tester.tap(find.byTooltip('导出当前筛选结果'));
    await tester.pump();

    expect(find.textContaining('当前筛选导出已迁移到服务端诊断包流程'), findsOneWidget);
  });

  testWidgets('keeps prior heatmap data when manual refresh fails', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      processOptions: const <String>['Code.exe'],
      inputHeatmapResponseBuilder: heatmapResponse,
    );

    await pumpHeatmapPage(tester, store: store);
    expect(find.text('A 7'), findsOneWidget);

    store.inputHeatmapError = StateError('second heatmap boom');
    await tester.tap(find.byTooltip('手动刷新'));
    await _pumpFrames(tester, 8);

    expect(store.inputHeatmapCalls, hasLength(2));
    expect(find.text('A 7'), findsOneWidget);
    expect(find.textContaining('second heatmap boom'), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
