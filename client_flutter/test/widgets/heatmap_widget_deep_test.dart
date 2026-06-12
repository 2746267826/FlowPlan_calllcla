import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/widgets/heatmap_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const emptyStateText =
      '\u5f53\u524d\u65f6\u95f4\u8303\u56f4\u8fd8\u6ca1\u6709\u6d3b\u52a8\u6570\u636e';
  const analyzeLabel = '\u67e5\u770b\u533a\u95f4\u5206\u6790';
  const clearAnalysisLabel = '\u6536\u8d77\u533a\u95f4\u5206\u6790';
  const drillToHoursLabel = '\u8fdb\u5165\u9010\u5c0f\u65f6';
  const filterHourLabel = '\u6309\u6b64\u5c0f\u65f6\u7b5b\u9009\u5217\u8868';
  const clearFilterLabel = '\u53d6\u6d88\u5217\u8868\u7b5b\u9009';

  ActivityHeatmapBucket bucket({
    required DateTime start,
    required String shortLabel,
    required String longLabel,
    int completedCount = 0,
    int totalMinutes = 0,
  }) {
    return ActivityHeatmapBucket(
      start: start,
      end: start.add(const Duration(hours: 1)),
      shortLabel: shortLabel,
      longLabel: longLabel,
      completedCount: completedCount,
      totalMinutes: totalMinutes,
    );
  }

  ActivityHeatmapSeries series({
    ActivityHeatmapScale scale = ActivityHeatmapScale.day,
    DateTime? anchorDate,
    List<ActivityHeatmapBucket> buckets = const <ActivityHeatmapBucket>[],
    int? maxMinutes,
  }) {
    final anchor = anchorDate ?? DateTime(2026, 6, 9);
    return ActivityHeatmapSeries(
      scale: scale,
      anchorDate: anchor,
      title: 'Activity density',
      subtitle: 'Recent tracking activity',
      buckets: buckets,
      maxMinutes: maxMinutes ??
          buckets.fold<int>(
            1,
            (current, item) =>
                item.totalMinutes > current ? item.totalMinutes : current,
          ),
      historySummary: ActivityHistorySummary(
        firstRecordAt: anchor.subtract(const Duration(days: 4)),
        lastRecordAt: anchor,
        totalRecords: 42,
      ),
    );
  }

  Future<void> pumpHeatmap(
    WidgetTester tester, {
    required ActivityHeatmapSeries series,
    ActivityHeatmapScale? selectedScaleOverride,
    ActivityHeatmapBucket? activeFilterBucket,
    ActivityHeatmapBucket? activeAnalysisBucket,
    ValueChanged<ActivityHeatmapScale?>? onScaleChanged,
    ValueChanged<ActivityHeatmapBucket>? onFilterBucket,
    ValueChanged<ActivityHeatmapBucket>? onAnalyzeBucket,
    ValueChanged<ActivityHeatmapBucket>? onDrillDownBucket,
    VoidCallback? onClearBucketFilter,
    VoidCallback? onClearAnalysisBucket,
    Size size = const Size(900, 900),
    double width = 760,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: HeatmapWidget(
                  series: series,
                  selectedScaleOverride: selectedScaleOverride,
                  activeFilterBucket: activeFilterBucket,
                  activeAnalysisBucket: activeAnalysisBucket,
                  onScaleChanged: onScaleChanged ?? (_) {},
                  onFilterBucket: onFilterBucket ?? (_) {},
                  onAnalyzeBucket: onAnalyzeBucket ?? (_) {},
                  onDrillDownBucket: onDrillDownBucket ?? (_) {},
                  onClearBucketFilter: onClearBucketFilter ?? () {},
                  onClearAnalysisBucket: onClearAnalysisBucket ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color cellBackgroundColor(WidgetTester tester, String shortLabel) {
    final cell = find.ancestor(
      of: find.text(shortLabel),
      matching: find.byType(AnimatedContainer),
    );
    expect(cell, findsOneWidget);
    final widget = tester.widget<AnimatedContainer>(cell);
    final decoration = widget.decoration;
    expect(decoration, isA<BoxDecoration>());
    return (decoration! as BoxDecoration).color!;
  }

  group('HeatmapWidget', () {
    testWidgets('renders empty state without a selected bucket card',
        (tester) async {
      await pumpHeatmap(
        tester,
        series: series(buckets: const <ActivityHeatmapBucket>[]),
      );

      expect(find.text('Activity density'), findsOneWidget);
      expect(find.text('Recent tracking activity'), findsOneWidget);
      expect(find.text(emptyStateText), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.text(analyzeLabel), findsNothing);
      expect(find.text(filterHourLabel), findsNothing);
    });

    testWidgets('renders density labels and color buckets', (tester) async {
      final base = DateTime(2026, 6, 9);
      final data = <ActivityHeatmapBucket>[
        bucket(
          start: base,
          shortLabel: 'B0',
          longLabel: 'No activity',
        ),
        bucket(
          start: base.add(const Duration(days: 1)),
          shortLabel: 'B25',
          longLabel: 'Low activity',
          completedCount: 1,
          totalMinutes: 25,
        ),
        bucket(
          start: base.add(const Duration(days: 2)),
          shortLabel: 'B50',
          longLabel: 'Medium activity',
          completedCount: 2,
          totalMinutes: 50,
        ),
        bucket(
          start: base.add(const Duration(days: 3)),
          shortLabel: 'B75',
          longLabel: 'High activity',
          completedCount: 3,
          totalMinutes: 75,
        ),
        bucket(
          start: base.add(const Duration(days: 4)),
          shortLabel: 'B100',
          longLabel: 'Peak activity',
          completedCount: 4,
          totalMinutes: 100,
        ),
      ];

      await pumpHeatmap(
        tester,
        series: series(buckets: data, maxMinutes: 100),
      );

      expect(find.text('0 \u5206\u949f'), findsOneWidget);
      expect(find.text('25 \u5206\u949f'), findsOneWidget);
      expect(find.text('4 \u6761\u8bb0\u5f55'), findsWidgets);
      expect(find.text('Peak activity'), findsOneWidget);
      expect(cellBackgroundColor(tester, 'B0'), const Color(0xFFEAEFF2));
      expect(cellBackgroundColor(tester, 'B25'), const Color(0xFFCDE7DE));
      expect(cellBackgroundColor(tester, 'B50'), const Color(0xFF93D2C1));
      expect(cellBackgroundColor(tester, 'B75'), const Color(0xFF4CB7A1));
      expect(cellBackgroundColor(tester, 'B100'), const Color(0xFF178D80));
    });

    testWidgets('selects buckets and dispatches scale analysis drill callbacks',
        (tester) async {
      ActivityHeatmapScale? changedScale = ActivityHeatmapScale.hour;
      ActivityHeatmapBucket? analyzed;
      ActivityHeatmapBucket? drilled;
      var clearAnalysisCount = 0;
      final base = DateTime(2026, 6, 9);
      final first = bucket(
        start: base,
        shortLabel: 'D1',
        longLabel: 'First day',
        completedCount: 1,
        totalMinutes: 15,
      );
      final second = bucket(
        start: base.add(const Duration(days: 1)),
        shortLabel: 'D2',
        longLabel: 'Second day',
        completedCount: 2,
        totalMinutes: 35,
      );
      final heatmapSeries = series(buckets: <ActivityHeatmapBucket>[
        first,
        second,
      ]);

      final semantics = tester.ensureSemantics();

      await pumpHeatmap(
        tester,
        series: heatmapSeries,
        selectedScaleOverride: ActivityHeatmapScale.day,
        onScaleChanged: (scale) => changedScale = scale,
        onAnalyzeBucket: (bucket) => analyzed = bucket,
        onDrillDownBucket: (bucket) => drilled = bucket,
        onClearAnalysisBucket: () => clearAnalysisCount++,
      );

      expect(find.text('Second day'), findsOneWidget);
      await tester.tap(find.text('D1'));
      await tester.pump();
      expect(find.text('First day'), findsOneWidget);

      final analyzeButton = find.widgetWithText(FilledButton, analyzeLabel);
      expect(analyzeButton, findsOneWidget);
      expect(find.bySemanticsLabel(analyzeLabel), findsWidgets);
      semantics.dispose();
      await tester.tap(analyzeButton);
      await tester.pump();
      expect(analyzed, same(first));

      await tester.tap(find.widgetWithText(OutlinedButton, drillToHoursLabel));
      await tester.pump();
      expect(drilled, same(first));

      await tester.tap(
        find.widgetWithText(ChoiceChip, ActivityHeatmapScale.month.label),
      );
      await tester.pump();
      expect(changedScale, ActivityHeatmapScale.month);

      await tester.tap(find.widgetWithText(ChoiceChip, '\u81ea\u52a8'));
      await tester.pump();
      expect(changedScale, isNull);

      await pumpHeatmap(
        tester,
        series: heatmapSeries,
        selectedScaleOverride: ActivityHeatmapScale.day,
        activeAnalysisBucket: first,
        onClearAnalysisBucket: () => clearAnalysisCount++,
      );
      expect(find.text(clearAnalysisLabel), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, clearAnalysisLabel));
      await tester.pump();
      expect(clearAnalysisCount, 1);
    });

    testWidgets('hour filter action toggles between filter and clear callbacks',
        (tester) async {
      ActivityHeatmapBucket? filtered;
      var clearFilterCount = 0;
      final selectedHour = bucket(
        start: DateTime(2026, 6, 9, 15),
        shortLabel: '15',
        longLabel: '15:00',
        completedCount: 3,
        totalMinutes: 42,
      );
      final heatmapSeries = series(
        scale: ActivityHeatmapScale.hour,
        buckets: <ActivityHeatmapBucket>[selectedHour],
      );

      await pumpHeatmap(
        tester,
        series: heatmapSeries,
        onFilterBucket: (bucket) => filtered = bucket,
        onClearBucketFilter: () => clearFilterCount++,
      );

      await tester.tap(find.widgetWithText(FilledButton, filterHourLabel));
      await tester.pump();
      expect(filtered, same(selectedHour));

      await pumpHeatmap(
        tester,
        series: heatmapSeries,
        activeFilterBucket: selectedHour,
        onClearBucketFilter: () => clearFilterCount++,
      );
      expect(find.text(clearFilterLabel), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, clearFilterLabel));
      await tester.pump();
      expect(clearFilterCount, 1);
    });

    testWidgets('compact width uses constrained cell sizing and short labels',
        (tester) async {
      final base = DateTime(2026, 6, 9);
      final data = List<ActivityHeatmapBucket>.generate(7, (index) {
        final minutes = index == 3 ? 45 : 0;
        return bucket(
          start: base.add(Duration(days: index)),
          shortLabel: 'C$index',
          longLabel: 'Compact $index',
          completedCount: minutes > 0 ? index + 1 : 0,
          totalMinutes: minutes,
        );
      });

      await pumpHeatmap(
        tester,
        series: series(buckets: data, maxMinutes: 45),
        size: const Size(320, 900),
        width: 320,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('45 \u5206'), findsOneWidget);
      expect(find.text('4 \u6761'), findsOneWidget);

      final compactCell = find.ancestor(
        of: find.text('C3'),
        matching: find.byType(AnimatedContainer),
      );
      expect(compactCell, findsOneWidget);
      final size = tester.getSize(compactCell);
      expect(size.width, lessThanOrEqualTo(60));
      expect(size.height, lessThanOrEqualTo(60));
    });

    testWidgets('ultra compact width uses labels without spaces',
        (tester) async {
      final base = DateTime(2026, 6, 9);
      final data = List<ActivityHeatmapBucket>.generate(7, (index) {
        final minutes = index == 3 ? 45 : 0;
        return bucket(
          start: base.add(Duration(days: index)),
          shortLabel: 'U$index',
          longLabel: 'Ultra compact $index',
          completedCount: minutes > 0 ? 4 : 0,
          totalMinutes: minutes,
        );
      });

      await pumpHeatmap(
        tester,
        series: series(buckets: data, maxMinutes: 45),
        size: const Size(240, 900),
        width: 240,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('45\u5206'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.replaceAll(' ', '') ==
                  '\u539f\u59cb\u8bb0\u5f55\uff1a4\u6761',
        ),
        findsOneWidget,
      );

      final ultraCompactCell = find.ancestor(
        of: find.text('U3'),
        matching: find.byType(AnimatedContainer),
      );
      expect(ultraCompactCell, findsOneWidget);
      expect(tester.getSize(ultraCompactCell).width, lessThan(48));
    });
  });
}
