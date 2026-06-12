import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  Future<int> insertRecord(
    AppDatabase db, {
    required DateTime start,
    DateTime? end,
    int? durationMinutes,
    String processName = 'Code.exe',
    String category = 'coding',
  }) async {
    final effectiveDuration =
        durationMinutes ?? (end == null ? 0 : end.difference(start).inMinutes);
    return db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: start,
            endTime: Value(end),
            durationMinutes: Value(effectiveDuration),
            processName: Value(processName),
            category: Value(category),
            isAuto: const Value(true),
            source: const Value('tracker_repository_test'),
          ),
        );
  }

  group('ActivityHistorySummary', () {
    test('reports empty history and scale thresholds', () {
      const empty = ActivityHistorySummary(
        firstRecordAt: null,
        lastRecordAt: null,
        totalRecords: 0,
      );
      expect(empty.hasData, isFalse);
      expect(empty.trackedDays, 0);
      expect(empty.recommendedScale, ActivityHeatmapScale.hour);

      ActivityHistorySummary summaryForDays(int days) {
        final first = DateTime(2026, 1);
        return ActivityHistorySummary(
          firstRecordAt: first,
          lastRecordAt: first.add(Duration(days: days - 1, hours: 2)),
          totalRecords: days,
        );
      }

      expect(summaryForDays(2).recommendedScale, ActivityHeatmapScale.hour);
      expect(summaryForDays(3).recommendedScale, ActivityHeatmapScale.day);
      expect(summaryForDays(44).recommendedScale, ActivityHeatmapScale.day);
      expect(summaryForDays(45).recommendedScale, ActivityHeatmapScale.month);
      expect(summaryForDays(399).recommendedScale, ActivityHeatmapScale.month);
      expect(summaryForDays(400).recommendedScale, ActivityHeatmapScale.year);
    });
  });

  group('TrackerRepository', () {
    test('history summary uses first start last end and total rows', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = TrackerRepository(db);

      expect((await repository.getHistorySummary()).hasData, isFalse);

      final first = DateTime(2026, 6, 1, 9);
      final last = DateTime(2026, 6, 3, 14);
      await insertRecord(
        db,
        start: last,
        end: last.add(const Duration(minutes: 20)),
      );
      await insertRecord(
        db,
        start: first,
        end: first.add(const Duration(minutes: 10)),
      );
      await insertRecord(
        db,
        start: DateTime(2026, 6, 2, 11),
        durationMinutes: 30,
      );

      final summary = await repository.getHistorySummary();
      expect(summary.firstRecordAt, first);
      expect(summary.lastRecordAt, last.add(const Duration(minutes: 20)));
      expect(summary.totalRecords, 3);
      expect(summary.trackedDays, 3);
      expect(summary.recommendedScale, ActivityHeatmapScale.day);
    });

    test('hourly series accumulates overlaps and open-record duration fallback',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = TrackerRepository(db);
      final anchor = DateTime(2026, 6, 10, 9);

      await insertRecord(
        db,
        start: DateTime(2026, 6, 10, 9, 30),
        end: DateTime(2026, 6, 10, 10, 15),
      );
      await insertRecord(
        db,
        start: DateTime(2026, 6, 10, 11, 50),
        durationMinutes: 20,
      );
      await insertRecord(
        db,
        start: DateTime(2026, 6, 11),
        end: DateTime(2026, 6, 11, 1),
      );

      final series = await repository.getHeatmapSeries(
        scale: ActivityHeatmapScale.hour,
        anchorDate: anchor,
        historySummary: const ActivityHistorySummary(
          firstRecordAt: null,
          lastRecordAt: null,
          totalRecords: 0,
        ),
      );

      expect(series.scale, ActivityHeatmapScale.hour);
      expect(series.buckets, hasLength(24));
      expect(series.buckets[9].completedCount, 1);
      expect(series.buckets[9].totalMinutes, 30);
      expect(series.buckets[10].completedCount, 1);
      expect(series.buckets[10].totalMinutes, 15);
      expect(series.buckets[11].completedCount, 1);
      expect(series.buckets[11].totalMinutes, 10);
      expect(series.buckets[12].completedCount, 1);
      expect(series.buckets[12].totalMinutes, 10);
      expect(series.maxMinutes, 30);
      expect(series.buckets[0].hasData, isFalse);
    });

    test('daily monthly and yearly series bucket the same records by scale',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = TrackerRepository(db);

      await insertRecord(
        db,
        start: DateTime(2025, 12, 31, 23, 30),
        end: DateTime(2026, 1, 1, 0, 30),
      );
      await insertRecord(
        db,
        start: DateTime(2026, 6, 10, 9),
        end: DateTime(2026, 6, 10, 10),
      );
      await insertRecord(
        db,
        start: DateTime(2026, 6, 30, 23, 45),
        end: DateTime(2026, 7, 1, 0, 15),
      );

      final history = ActivityHistorySummary(
        firstRecordAt: DateTime(2025, 12, 31, 23, 30),
        lastRecordAt: DateTime(2026, 7, 1, 0, 15),
        totalRecords: 3,
      );

      final daily = await repository.getHeatmapSeries(
        scale: ActivityHeatmapScale.day,
        anchorDate: DateTime(2026, 6, 15),
        historySummary: history,
      );
      expect(daily.buckets, hasLength(30));
      expect(daily.buckets[9].completedCount, 1);
      expect(daily.buckets[9].totalMinutes, 60);
      expect(daily.buckets[29].completedCount, 1);
      expect(daily.buckets[29].totalMinutes, 15);

      final monthly = await repository.getHeatmapSeries(
        scale: ActivityHeatmapScale.month,
        anchorDate: DateTime(2026, 6, 15),
        historySummary: history,
      );
      expect(monthly.buckets, hasLength(12));
      expect(monthly.buckets[0].totalMinutes, 30);
      expect(monthly.buckets[5].completedCount, 2);
      expect(monthly.buckets[5].totalMinutes, 75);
      expect(monthly.buckets[6].totalMinutes, 15);

      final yearly = await repository.getHeatmapSeries(
        scale: ActivityHeatmapScale.year,
        anchorDate: DateTime(2026, 6, 15),
        historySummary: history,
      );
      expect(yearly.buckets, hasLength(2));
      expect(yearly.buckets[0].shortLabel, '2025');
      expect(yearly.buckets[0].totalMinutes, 30);
      expect(yearly.buckets[1].shortLabel, '2026');
      expect(yearly.buckets[1].totalMinutes, 120);
    });

    test('getRecordsForDate returns overlapping records ordered by start',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = TrackerRepository(db);

      final previousNight = await insertRecord(
        db,
        start: DateTime(2026, 6, 9, 23, 50),
        end: DateTime(2026, 6, 10, 0, 10),
        processName: 'Terminal.exe',
      );
      final morning = await insertRecord(
        db,
        start: DateTime(2026, 6, 10, 9),
        end: DateTime(2026, 6, 10, 9, 30),
        processName: 'Code.exe',
      );
      await insertRecord(
        db,
        start: DateTime(2026, 6, 11),
        end: DateTime(2026, 6, 11, 1),
      );

      final records = await repository.getRecordsForDate(
        DateTime(2026, 6, 10, 12),
      );

      expect(records.map((record) => record.id), <int>[
        previousNight,
        morning,
      ]);
      expect(records.map((record) => record.processName), <String?>[
        'Terminal.exe',
        'Code.exe',
      ]);
    });
  });
}
