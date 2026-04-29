import '../../../core/database/app_database.dart';

class ActivityInsightSlice {
  final String label;
  final int minutes;
  final int keys;
  final int clicks;
  final int movePx;
  final int scrollPx;
  final int sessions;

  const ActivityInsightSlice({
    required this.label,
    required this.minutes,
    required this.keys,
    required this.clicks,
    required this.movePx,
    required this.scrollPx,
    required this.sessions,
  });

  int get inputScore => keys + (clicks * 4);
}

class ActivityInsightRecord {
  final ActivityRecord record;
  final int inputScore;

  const ActivityInsightRecord({
    required this.record,
    required this.inputScore,
  });
}

class ActivityInsights {
  final List<ActivityRecord> records;
  final int totalMinutes;
  final int focusMinutes;
  final int totalKeys;
  final int totalClicks;
  final int totalMovePx;
  final int totalScrollPx;
  final int sequenceRecordCount;
  final List<ActivityInsightSlice> topProcesses;
  final List<ActivityInsightSlice> topCategories;
  final List<ActivityInsightRecord> busiestRecords;

  const ActivityInsights({
    required this.records,
    required this.totalMinutes,
    required this.focusMinutes,
    required this.totalKeys,
    required this.totalClicks,
    required this.totalMovePx,
    required this.totalScrollPx,
    required this.sequenceRecordCount,
    required this.topProcesses,
    required this.topCategories,
    required this.busiestRecords,
  });

  factory ActivityInsights.empty() {
    return const ActivityInsights(
      records: <ActivityRecord>[],
      totalMinutes: 0,
      focusMinutes: 0,
      totalKeys: 0,
      totalClicks: 0,
      totalMovePx: 0,
      totalScrollPx: 0,
      sequenceRecordCount: 0,
      topProcesses: <ActivityInsightSlice>[],
      topCategories: <ActivityInsightSlice>[],
      busiestRecords: <ActivityInsightRecord>[],
    );
  }

  double get keysPerMinute {
    if (focusMinutes <= 0) {
      return 0;
    }
    return totalKeys / focusMinutes;
  }

  double get clickPerHour {
    if (totalMinutes <= 0) {
      return 0;
    }
    return totalClicks / (totalMinutes / 60);
  }

  int get activeProcessCount => topProcesses.length;

  int get productiveRecordCount => records
      .where(
        (record) =>
            record.keyCount > 0 ||
            record.mouseClicks > 0 ||
            record.mouseMovePx > 0 ||
            record.scrollPx > 0,
      )
      .length;

  static ActivityInsights fromRecords(List<ActivityRecord> allRecords) {
    if (allRecords.isEmpty) {
      return ActivityInsights.empty();
    }

    final records = List<ActivityRecord>.from(allRecords)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final processBuckets = <String, _ActivityBucket>{};
    final categoryBuckets = <String, _ActivityBucket>{};
    final busiest = <ActivityInsightRecord>[];

    var totalMinutes = 0;
    var focusMinutes = 0;
    var totalKeys = 0;
    var totalClicks = 0;
    var totalMovePx = 0;
    var totalScrollPx = 0;
    var sequenceRecordCount = 0;

    for (final record in records) {
      final inputScore = record.keyCount + (record.mouseClicks * 4);

      totalMinutes += record.durationMinutes;
      totalKeys += record.keyCount;
      totalClicks += record.mouseClicks;
      totalMovePx += record.mouseMovePx;
      totalScrollPx += record.scrollPx;

      if (record.keySequence != null && record.keySequence!.trim().isNotEmpty) {
        sequenceRecordCount += 1;
      }

      if (record.keyCount > 0 ||
          record.mouseClicks > 0 ||
          record.mouseMovePx > 0 ||
          record.scrollPx > 0) {
        focusMinutes += record.durationMinutes;
      }

      final processLabel = _preferredProcessLabel(record);
      processBuckets.putIfAbsent(processLabel, _ActivityBucket.new).add(record);

      final categoryLabel = _preferredCategoryLabel(record);
      categoryBuckets
          .putIfAbsent(categoryLabel, _ActivityBucket.new)
          .add(record);

      busiest.add(ActivityInsightRecord(record: record, inputScore: inputScore));
    }

    busiest.sort((a, b) {
      final byScore = b.inputScore.compareTo(a.inputScore);
      if (byScore != 0) {
        return byScore;
      }
      return b.record.durationMinutes.compareTo(a.record.durationMinutes);
    });

    return ActivityInsights(
      records: records,
      totalMinutes: totalMinutes,
      focusMinutes: focusMinutes,
      totalKeys: totalKeys,
      totalClicks: totalClicks,
      totalMovePx: totalMovePx,
      totalScrollPx: totalScrollPx,
      sequenceRecordCount: sequenceRecordCount,
      topProcesses: _sortBuckets(processBuckets),
      topCategories: _sortBuckets(categoryBuckets),
      busiestRecords: busiest.take(3).toList(growable: false),
    );
  }

  static String _preferredProcessLabel(ActivityRecord record) {
    final process = record.processName?.trim();
    final title = record.windowTitle?.trim();
    if (process != null && process.isNotEmpty) {
      return process;
    }
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return '\u672a\u77e5\u5e94\u7528';
  }

  static String _preferredCategoryLabel(ActivityRecord record) {
    final category = record.category?.trim();
    if (category != null && category.isNotEmpty) {
      return category;
    }
    return '\u672a\u5206\u7c7b';
  }

  static List<ActivityInsightSlice> _sortBuckets(
    Map<String, _ActivityBucket> buckets,
  ) {
    final slices = buckets.entries
        .map(
          (entry) => ActivityInsightSlice(
            label: entry.key,
            minutes: entry.value.minutes,
            keys: entry.value.keys,
            clicks: entry.value.clicks,
            movePx: entry.value.movePx,
            scrollPx: entry.value.scrollPx,
            sessions: entry.value.sessions,
          ),
        )
        .toList();

    slices.sort((a, b) {
      final byMinutes = b.minutes.compareTo(a.minutes);
      if (byMinutes != 0) {
        return byMinutes;
      }
      return b.inputScore.compareTo(a.inputScore);
    });

    return slices.take(5).toList(growable: false);
  }
}

class _ActivityBucket {
  int minutes = 0;
  int keys = 0;
  int clicks = 0;
  int movePx = 0;
  int scrollPx = 0;
  int sessions = 0;

  void add(ActivityRecord record) {
    minutes += record.durationMinutes;
    keys += record.keyCount;
    clicks += record.mouseClicks;
    movePx += record.mouseMovePx;
    scrollPx += record.scrollPx;
    sessions += 1;
  }
}
