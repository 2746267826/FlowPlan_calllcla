import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

enum ActivityHeatmapScale {
  hour,
  day,
  month,
  year,
}

extension ActivityHeatmapScaleLabel on ActivityHeatmapScale {
  String get label {
    switch (this) {
      case ActivityHeatmapScale.hour:
        return '\u5c0f\u65f6';
      case ActivityHeatmapScale.day:
        return '\u65e5';
      case ActivityHeatmapScale.month:
        return '\u6708';
      case ActivityHeatmapScale.year:
        return '\u5e74';
    }
  }
}

class ActivityHistorySummary {
  final DateTime? firstRecordAt;
  final DateTime? lastRecordAt;
  final int totalRecords;

  const ActivityHistorySummary({
    required this.firstRecordAt,
    required this.lastRecordAt,
    required this.totalRecords,
  });

  bool get hasData => firstRecordAt != null && lastRecordAt != null;

  int get trackedDays {
    if (!hasData) {
      return 0;
    }
    final first = DateTime(
      firstRecordAt!.year,
      firstRecordAt!.month,
      firstRecordAt!.day,
    );
    final last = DateTime(
      lastRecordAt!.year,
      lastRecordAt!.month,
      lastRecordAt!.day,
    );
    return last.difference(first).inDays + 1;
  }

  ActivityHeatmapScale get recommendedScale {
    if (trackedDays < 3) {
      return ActivityHeatmapScale.hour;
    }
    if (trackedDays < 45) {
      return ActivityHeatmapScale.day;
    }
    if (trackedDays < 400) {
      return ActivityHeatmapScale.month;
    }
    return ActivityHeatmapScale.year;
  }
}

class ActivityHeatmapBucket {
  final DateTime start;
  final DateTime end;
  final String shortLabel;
  final String longLabel;
  final int completedCount;
  final int totalMinutes;

  const ActivityHeatmapBucket({
    required this.start,
    required this.end,
    required this.shortLabel,
    required this.longLabel,
    required this.completedCount,
    required this.totalMinutes,
  });

  bool get hasData => completedCount > 0 || totalMinutes > 0;
}

class ActivityHeatmapSeries {
  final ActivityHeatmapScale scale;
  final DateTime anchorDate;
  final String title;
  final String subtitle;
  final List<ActivityHeatmapBucket> buckets;
  final int maxMinutes;
  final ActivityHistorySummary historySummary;

  const ActivityHeatmapSeries({
    required this.scale,
    required this.anchorDate,
    required this.title,
    required this.subtitle,
    required this.buckets,
    required this.maxMinutes,
    required this.historySummary,
  });
}

class TrackerRepository {
  final AppDatabase _db;

  TrackerRepository(this._db);

  Future<ActivityHistorySummary> getHistorySummary() async {
    final firstRecord = await (_db.select(_db.activityRecords)
          ..orderBy([(r) => OrderingTerm(expression: r.startTime)])
          ..limit(1))
        .getSingleOrNull();
    final lastRecord = await (_db.select(_db.activityRecords)
          ..orderBy([(r) => OrderingTerm.desc(r.startTime)])
          ..limit(1))
        .getSingleOrNull();
    final countExpression = _db.activityRecords.id.count();
    final countQuery = _db.selectOnly(_db.activityRecords)
      ..addColumns([countExpression]);
    final totalRecords = await countQuery
        .map((row) => row.read(countExpression) ?? 0)
        .getSingle();

    return ActivityHistorySummary(
      firstRecordAt: firstRecord?.startTime,
      lastRecordAt: lastRecord?.endTime ?? lastRecord?.startTime,
      totalRecords: totalRecords,
    );
  }

  Future<ActivityHeatmapSeries> getHeatmapSeries({
    required ActivityHeatmapScale scale,
    required DateTime anchorDate,
    required ActivityHistorySummary historySummary,
  }) async {
    switch (scale) {
      case ActivityHeatmapScale.hour:
        return _buildHourlySeries(anchorDate, historySummary);
      case ActivityHeatmapScale.day:
        return _buildDailySeries(anchorDate, historySummary);
      case ActivityHeatmapScale.month:
        return _buildMonthlySeries(anchorDate, historySummary);
      case ActivityHeatmapScale.year:
        return _buildYearlySeries(anchorDate, historySummary);
    }
  }

  Future<ActivityHeatmapSeries> _buildHourlySeries(
    DateTime anchorDate,
    ActivityHistorySummary historySummary,
  ) async {
    final start = DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
    final end = start.add(const Duration(days: 1));
    final records = await _getRecordsBetween(start, end);
    final bucketWindows = List<_BucketWindow>.generate(
      24,
      (hour) {
        final bucketStart = DateTime(start.year, start.month, start.day, hour);
        return _BucketWindow(
          start: bucketStart,
          end: bucketStart.add(const Duration(hours: 1)),
        );
      },
    );
    final bucketStats = _accumulateBucketStats(records, bucketWindows);

    final buckets = <ActivityHeatmapBucket>[];
    for (var hour = 0; hour < 24; hour++) {
      final bucketStart = bucketWindows[hour].start;
      final counter = bucketStats[hour];
      buckets.add(
        ActivityHeatmapBucket(
          start: bucketStart,
          end: bucketWindows[hour].end,
          shortLabel: hour.toString().padLeft(2, '0'),
          longLabel:
              '${start.month}\u6708${start.day}\u65e5 ${hour.toString().padLeft(2, '0')}:00',
          completedCount: counter.completedCount,
          totalMinutes: counter.totalMinutes,
        ),
      );
    }

    return ActivityHeatmapSeries(
      scale: ActivityHeatmapScale.hour,
      anchorDate: anchorDate,
      title:
          '${anchorDate.month}\u6708${anchorDate.day}\u65e5\u9010\u5c0f\u65f6\u5206\u5e03',
      subtitle:
          '\u9002\u5408\u521a\u5f00\u59cb\u4f7f\u7528\u65f6\u67e5\u770b\u4e00\u5929\u5185\u6bcf\u4e2a\u5c0f\u65f6\u7684\u6d3b\u52a8\u5f3a\u5ea6\u3002',
      buckets: buckets,
      maxMinutes: _maxMinutes(buckets),
      historySummary: historySummary,
    );
  }

  Future<ActivityHeatmapSeries> _buildDailySeries(
    DateTime anchorDate,
    ActivityHistorySummary historySummary,
  ) async {
    final start = DateTime(anchorDate.year, anchorDate.month);
    final end = DateTime(anchorDate.year, anchorDate.month + 1);
    final daysInMonth = end.difference(start).inDays;
    final records = await _getRecordsBetween(start, end);
    final bucketWindows = List<_BucketWindow>.generate(
      daysInMonth,
      (index) {
        final bucketStart = DateTime(
          anchorDate.year,
          anchorDate.month,
          index + 1,
        );
        return _BucketWindow(
          start: bucketStart,
          end: bucketStart.add(const Duration(days: 1)),
        );
      },
    );
    final bucketStats = _accumulateBucketStats(records, bucketWindows);

    final buckets = <ActivityHeatmapBucket>[];
    for (var day = 1; day <= daysInMonth; day++) {
      final bucketStart = bucketWindows[day - 1].start;
      final counter = bucketStats[day - 1];
      buckets.add(
        ActivityHeatmapBucket(
          start: bucketStart,
          end: bucketWindows[day - 1].end,
          shortLabel: '$day',
          longLabel:
              '${anchorDate.year}\u5e74${anchorDate.month}\u6708$day\u65e5',
          completedCount: counter.completedCount,
          totalMinutes: counter.totalMinutes,
        ),
      );
    }

    return ActivityHeatmapSeries(
      scale: ActivityHeatmapScale.day,
      anchorDate: anchorDate,
      title:
          '${anchorDate.year}\u5e74${anchorDate.month}\u6708\u6bcf\u65e5\u5206\u5e03',
      subtitle:
          '\u9002\u5408\u4f7f\u7528\u5929\u6570\u4e0d\u591a\u65f6\u67e5\u770b\u4e00\u4e2a\u6708\u5185\u6bcf\u5929\u7684\u6d3b\u8dc3\u7a0b\u5ea6\u3002',
      buckets: buckets,
      maxMinutes: _maxMinutes(buckets),
      historySummary: historySummary,
    );
  }

  Future<ActivityHeatmapSeries> _buildMonthlySeries(
    DateTime anchorDate,
    ActivityHistorySummary historySummary,
  ) async {
    final start = DateTime(anchorDate.year);
    final end = DateTime(anchorDate.year + 1);
    final records = await _getRecordsBetween(start, end);
    final bucketWindows = List<_BucketWindow>.generate(
      12,
      (index) {
        final bucketStart = DateTime(anchorDate.year, index + 1);
        return _BucketWindow(
          start: bucketStart,
          end: DateTime(anchorDate.year, index + 2),
        );
      },
    );
    final bucketStats = _accumulateBucketStats(records, bucketWindows);

    final buckets = <ActivityHeatmapBucket>[];
    for (var month = 1; month <= 12; month++) {
      final bucketStart = bucketWindows[month - 1].start;
      final counter = bucketStats[month - 1];
      buckets.add(
        ActivityHeatmapBucket(
          start: bucketStart,
          end: bucketWindows[month - 1].end,
          shortLabel: '${month}\u6708',
          longLabel: '${anchorDate.year}\u5e74$month\u6708',
          completedCount: counter.completedCount,
          totalMinutes: counter.totalMinutes,
        ),
      );
    }

    return ActivityHeatmapSeries(
      scale: ActivityHeatmapScale.month,
      anchorDate: anchorDate,
      title: '${anchorDate.year}\u5e74\u9010\u6708\u5206\u5e03',
      subtitle:
          '\u9002\u5408\u5df2\u7ecf\u79ef\u7d2f\u4e00\u6bb5\u65f6\u95f4\u540e\uff0c\u4ece\u6708\u4efd\u5c3a\u5ea6\u56de\u770b\u4e00\u5e74\u4e2d\u7684\u53d8\u5316\u3002',
      buckets: buckets,
      maxMinutes: _maxMinutes(buckets),
      historySummary: historySummary,
    );
  }

  Future<ActivityHeatmapSeries> _buildYearlySeries(
    DateTime anchorDate,
    ActivityHistorySummary historySummary,
  ) async {
    final firstYear = historySummary.firstRecordAt?.year ?? anchorDate.year;
    final lastYear = anchorDate.year;
    final start = DateTime(firstYear);
    final end = DateTime(lastYear + 1);
    final records = await _getRecordsBetween(start, end);

    final yearCount = (lastYear - firstYear) + 1;
    final bucketWindows = List<_BucketWindow>.generate(
      yearCount,
      (index) {
        final year = firstYear + index;
        return _BucketWindow(
          start: DateTime(year),
          end: DateTime(year + 1),
        );
      },
    );
    final bucketStats = _accumulateBucketStats(records, bucketWindows);

    final buckets = <ActivityHeatmapBucket>[];
    for (var year = firstYear; year <= lastYear; year++) {
      final bucketStart = bucketWindows[year - firstYear].start;
      final counter = bucketStats[year - firstYear];
      buckets.add(
        ActivityHeatmapBucket(
          start: bucketStart,
          end: bucketWindows[year - firstYear].end,
          shortLabel: '$year',
          longLabel: '$year\u5e74',
          completedCount: counter.completedCount,
          totalMinutes: counter.totalMinutes,
        ),
      );
    }

    return ActivityHeatmapSeries(
      scale: ActivityHeatmapScale.year,
      anchorDate: anchorDate,
      title: '\u5386\u53f2\u5e74\u5ea6\u5206\u5e03',
      subtitle:
          '\u9002\u5408\u4f7f\u7528\u65f6\u95f4\u8f83\u957f\u540e\uff0c\u4ece\u5e74\u5ea6\u5c3a\u5ea6\u6d4f\u89c8\u957f\u671f\u6d3b\u52a8\u79ef\u7d2f\u3002',
      buckets: buckets,
      maxMinutes: _maxMinutes(buckets),
      historySummary: historySummary,
    );
  }

  Future<List<ActivityRecord>> getRecordsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _getRecordsBetween(start, end);
  }

  Future<List<ActivityRecord>> _getRecordsBetween(
    DateTime start,
    DateTime end,
  ) {
    return (_db.select(_db.activityRecords)
          ..where((r) =>
              r.startTime.isSmallerThanValue(end) &
              (r.endTime.isNull() | r.endTime.isBiggerOrEqualValue(start)))
          ..orderBy([(r) => OrderingTerm(expression: r.startTime)]))
        .get();
  }

  List<_BucketCounter> _accumulateBucketStats(
    List<ActivityRecord> records,
    List<_BucketWindow> bucketWindows,
  ) {
    final stats = List<_BucketCounter>.generate(
      bucketWindows.length,
      (_) => const _BucketCounter(),
    );

    for (final record in records) {
      for (var index = 0; index < bucketWindows.length; index += 1) {
        final bucket = bucketWindows[index];
        final overlapMinutes = _calculateOverlapMinutes(
          record: record,
          bucketStart: bucket.start,
          bucketEnd: bucket.end,
        );
        if (overlapMinutes <= 0) {
          continue;
        }
        stats[index] = stats[index].addOverlap(overlapMinutes);
      }
    }
    return stats;
  }

  int _calculateOverlapMinutes({
    required ActivityRecord record,
    required DateTime bucketStart,
    required DateTime bucketEnd,
  }) {
    final recordStart = record.startTime;
    final recordEnd = _effectiveRecordEnd(record);
    if (!recordStart.isBefore(bucketEnd) || !recordEnd.isAfter(bucketStart)) {
      return 0;
    }

    final overlapStart =
        recordStart.isAfter(bucketStart) ? recordStart : bucketStart;
    final overlapEnd = recordEnd.isBefore(bucketEnd) ? recordEnd : bucketEnd;
    if (!overlapEnd.isAfter(overlapStart)) {
      return 0;
    }

    final overlapSeconds = overlapEnd.difference(overlapStart).inSeconds;
    if (overlapSeconds <= 0) {
      return 0;
    }

    return (overlapSeconds / 60).ceil();
  }

  DateTime _effectiveRecordEnd(ActivityRecord record) {
    final explicitEnd = record.endTime;
    if (explicitEnd != null && explicitEnd.isAfter(record.startTime)) {
      return explicitEnd;
    }

    final durationMinutes =
        record.durationMinutes > 0 ? record.durationMinutes : 1;
    return record.startTime.add(Duration(minutes: durationMinutes));
  }

  static int _maxMinutes(List<ActivityHeatmapBucket> buckets) {
    var maxMinutes = 1;
    for (final bucket in buckets) {
      if (bucket.totalMinutes > maxMinutes) {
        maxMinutes = bucket.totalMinutes;
      }
    }
    return maxMinutes;
  }
}

class _BucketCounter {
  final int completedCount;
  final int totalMinutes;

  const _BucketCounter({
    this.completedCount = 0,
    this.totalMinutes = 0,
  });

  _BucketCounter addOverlap(int overlapMinutes) {
    return _BucketCounter(
      completedCount: completedCount + 1,
      totalMinutes: totalMinutes + overlapMinutes,
    );
  }
}

class _BucketWindow {
  final DateTime start;
  final DateTime end;

  const _BucketWindow({
    required this.start,
    required this.end,
  });
}
