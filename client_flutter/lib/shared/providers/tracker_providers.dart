part of 'app_providers.dart';

// 鈹€鈹€ Tracker Repository 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TrackerRepository(db);
}, dependencies: [databaseProvider]);

// 鈹€鈹€ Activity Record Repository 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final activityRecordRepositoryProvider =
    Provider<ActivityRecordRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ActivityRecordRepository(db);
}, dependencies: [databaseProvider]);

final activityFusionRepositoryProvider =
    Provider<ActivityFusionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  final syncRecorder = ref.watch(syncWriteRecorderProvider);
  return ActivityFusionRepository(db, operationLogs, syncRecorder);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
  syncWriteRecorderProvider,
]);

final blockingEventActualCandidateServiceProvider =
    Provider<BlockingEventActualCandidateService>((ref) {
  final db = ref.watch(databaseProvider);
  return BlockingEventActualCandidateService(
    db,
    ref.watch(actualActivityLogRepositoryProvider),
    ref.watch(activityRecordRepositoryProvider),
  );
}, dependencies: [
  databaseProvider,
  actualActivityLogRepositoryProvider,
  activityRecordRepositoryProvider,
]);

final activityFusionServiceProvider = Provider<ActivityFusionService>((ref) {
  return ActivityFusionService(
    ref.watch(activityRecordRepositoryProvider),
    ref.watch(activityLogServiceProvider),
    ref.watch(inputActivityEventServiceProvider),
    ref.watch(activityFusionRepositoryProvider),
    ref.watch(taskRepositoryProvider),
    ref.watch(fileContextRepositoryProvider),
    ref.watch(actualActivityLogRepositoryProvider),
  );
}, dependencies: [
  activityRecordRepositoryProvider,
  activityLogServiceProvider,
  inputActivityEventServiceProvider,
  activityFusionRepositoryProvider,
  taskRepositoryProvider,
  fileContextRepositoryProvider,
  actualActivityLogRepositoryProvider,
]);

final activityLogServiceProvider = Provider<ActivityLogService>((ref) {
  final db = ref.watch(databaseProvider);
  return ActivityLogService(db);
}, dependencies: [databaseProvider]);

final inputActivityEventServiceProvider =
    Provider<InputActivityEventService>((ref) {
  final db = ref.watch(databaseProvider);
  return InputActivityEventService(db);
}, dependencies: [databaseProvider]);

final activityLogRefreshTickProvider = StateProvider<int>((ref) => 0);

final inputEventProcessOptionsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  return _loadServerInputProcessOptions(ref);
});

final activityDaySummaryProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final date = ref.watch(selectedDateProvider);
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final serverResponse = await store.activityDaySummary(date: date);

  final serverInsights = _asStringMap(serverResponse['insights']);
  final serverMinutes = _intValue(serverInsights['totalMinutes']);

  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  final localRecords =
      await ref.read(activityLogServiceProvider).readEntriesBetween(start, end, limit: 5000);
  final localMinutes = localRecords
      .where((e) => !e.isIgnored && e.durationMinutes != null)
      .fold<int>(0, (sum, e) => sum + (e.durationMinutes ?? 0));

  if (localMinutes > 0 && serverMinutes < localMinutes * 0.5) {
    final db = ref.read(databaseProvider);
    final localRows = await db.customSelect(
      '''
      SELECT * FROM activity_records
      WHERE start_time < ? AND (end_time >= ? OR end_time IS NULL)
      ORDER BY start_time ASC
      ''',
      variables: [
        Variable<String>(end.toIso8601String()),
        Variable<String>(start.toIso8601String()),
      ],
    ).get();
    final localRecordsList = localRows.map((row) {
      final data = row.data;
      final startTime = _dateValue(data['start_time']) ?? start;
      final endTime = _dateValue(data['end_time']);
      final dur = _intValue(data['duration_minutes']);
      return <String, Object?>{
        'serverId': 'local-${data['id']}',
        'objectType': 'activity_record',
        'occurredAt': startTime.toIso8601String(),
        'metricMinutes': dur > 0 ? dur : (endTime != null ? endTime.difference(startTime).inMinutes : 1),
        'metricCount': 1,
        'payload': <String, Object?>{
          'startTime': startTime.toIso8601String(),
          if (endTime != null) 'endTime': endTime.toIso8601String(),
          'durationMinutes': dur > 0 ? dur : (endTime != null ? endTime.difference(startTime).inMinutes : 1),
          'processName': data['process_name'],
          'windowTitle': data['window_title'],
          'packageName': data['package_name'],
          'category': data['category'],
          'linkedTaskId': data['linked_task_id'],
          'keyCount': data['key_count'],
          'mouseClicks': data['mouse_clicks'],
          'mouseMovePx': data['mouse_move_px'],
          'scrollPx': data['scroll_px'],
          'manualLabel': data['manual_label'],
        },
      };
    }).toList();

    final totalMin = localRecordsList.fold<int>(
      0,
      (sum, r) => sum + _intValue(r['metricMinutes']),
    );
    final totalKeys = localRows.fold<int>(
      0,
      (sum, r) => sum + _intValue(r.data['key_count']),
    );
    final totalClicks = localRows.fold<int>(
      0,
      (sum, r) => sum + _intValue(r.data['mouse_clicks']),
    );
    final totalMove = localRows.fold<int>(
      0,
      (sum, r) => sum + _intValue(r.data['mouse_move_px']),
    );
    final totalScroll = localRows.fold<int>(
      0,
      (sum, r) => sum + _intValue(r.data['scroll_px']),
    );

    return <String, dynamic>{
      'range': serverResponse['range'],
      'source': 'local-fallback',
      'insights': <String, Object?>{
        'recordCount': localRecordsList.length,
        'totalMinutes': totalMin,
        'focusMinutes': totalMin,
        'totalKeys': totalKeys,
        'totalClicks': totalClicks,
        'totalMovePx': totalMove,
        'totalScrollPx': totalScroll,
        'productiveRecordCount': localRecordsList.length,
        'sequenceRecordCount': 0,
        'topProcesses': <Object?>[],
        'topCategories': <Object?>[],
        'busiestRecords': localRecordsList.take(3).toList(),
      },
      'sessions': <Object?>[],
      'previewRecords': localRecordsList,
    };
  }

  return serverResponse;
});

final inputHeatmapSummaryProvider =
    FutureProvider.family<InputHeatmapSummary, InputEventQuery>((ref, query) async {
  ref.watch(activityLogRefreshTickProvider);
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final response = await store.inputHeatmap(
    start: query.start,
    end: query.end,
    bucket: 'hour',
    processName: query.processName,
  );
  return _inputHeatmapSummaryFromServer(query, response);
});

final selectedDateInputBehaviorSummaryProvider =
    FutureProvider<InputHeatmapSummary>((ref) async {
  ref.watch(activityLogRefreshTickProvider);
  final selectedDate = ref.watch(selectedDateProvider);
  final start = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final end = start.add(const Duration(days: 1));
  final query = InputEventQuery(start: start, end: end);
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final response = await store.inputHeatmap(
    start: start,
    end: end,
    bucket: 'hour',
  );
  return _inputHeatmapSummaryFromServer(query, response);
});

// 鈹€鈹€ 鐑姏鍥炬暟鎹紙杩囧幓涓€骞达級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final activityHeatmapScaleOverrideProvider =
    StateProvider<ActivityHeatmapScale?>((ref) => null);

final activityHistorySummaryProvider =
    FutureProvider<ActivityHistorySummary>((ref) async {
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final response = await store.trackingSummary();
  return _activityHistorySummaryFromServer(response);
});

final activityHeatmapSeriesProvider =
    FutureProvider<ActivityHeatmapSeries>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);
  final override = ref.watch(activityHeatmapScaleOverrideProvider);
  final summary = await ref.watch(activityHistorySummaryProvider.future);
  final scale = override ?? summary.recommendedScale;
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final range = _activityHeatmapRange(scale, selectedDate);
  final response = await store.activityHeatmap(
    start: range.start,
    end: range.end,
    bucket: _serverBucketForScale(scale),
  );
  return _activityHeatmapSeriesFromServer(
    response,
    scale: scale,
    anchorDate: selectedDate,
    historySummary: summary,
  );
});

// 鈹€鈹€ 鎷栨嫿鐘舵€?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
// 鍏ㄥ眬锛氬綋鍓嶆嫋鎷藉厜鏍囨槸鍚﹀湪鏃堕棿杞翠笂鏂?
final dragHoveringTimelineProvider = StateProvider<bool>((ref) => false);

// 鈹€鈹€ 褰撴棩娲诲姩璁板綍娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final activityRecordsForDateProvider =
    FutureProvider<List<ActivityRecord>>((ref) async {
  final response = await ref.watch(activityDaySummaryProvider.future);
  return _activityRecordsFromServerPreview(response);
});

final activityInsightsProvider = Provider<ActivityInsights>((ref) {
  final summaryAsync = ref.watch(activityDaySummaryProvider);
  return summaryAsync.maybeWhen(
    data: _activityInsightsFromServer,
    orElse: ActivityInsights.empty,
  );
});

final workSessionsForDateProvider = Provider<List<WorkSession>>((ref) {
  final summaryAsync = ref.watch(activityDaySummaryProvider);
  return summaryAsync.maybeWhen(
    data: _workSessionsFromServer,
    orElse: () => const <WorkSession>[],
  );
});

final activityLogEntriesForDateProvider =
    FutureProvider<List<ActivityLogEntry>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final date = ref.watch(selectedDateProvider);
  final service = ref.watch(activityLogServiceProvider);
  return service.readEntriesForDate(date);
});

final activityLogStoragePathProvider = FutureProvider<String>((ref) {
  final service = ref.watch(activityLogServiceProvider);
  return service.getStoragePath();
});

final activityLogArchiveDirectoryPathProvider = FutureProvider<String>((ref) {
  final service = ref.watch(activityLogServiceProvider);
  return service.getArchiveDirectoryPath();
});

final inputEventArchiveDirectoryPathProvider = FutureProvider<String>((ref) {
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.getArchiveDirectoryPath();
});

final activityLogArchiveDaysProvider =
    FutureProvider<List<ActivityLogArchiveDay>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(activityLogServiceProvider);
  return service.listArchiveDays();
});

final inputEventArchiveDaysProvider =
    FutureProvider<List<ActivityLogArchiveDay>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.listArchiveDays();
});

final activityLogArchiveEntriesForDateProvider =
    FutureProvider.family<List<ActivityLogEntry>, DateTime>((ref, date) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(activityLogServiceProvider);
  return service.readArchivedEntriesForDate(date);
});

final inputEventArchiveEntriesForDateProvider =
    FutureProvider.family<List<TrackedInputEvent>, DateTime>((ref, date) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.readArchivedEventsForDate(date);
});

final recentTrackedInputEventsProvider =
    FutureProvider<List<TrackedInputEvent>>((ref) async {
  ref.watch(activityLogRefreshTickProvider);
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final response = await store.inputEvents(
    limit: 12,
  );
  return _trackedInputEventsFromServer(response);
});

class TrackerHistoryFilterOptions {
  final List<String> processOptions;
  final List<String> categoryOptions;

  const TrackerHistoryFilterOptions({
    required this.processOptions,
    required this.categoryOptions,
  });

  const TrackerHistoryFilterOptions.empty()
      : processOptions = const <String>[],
        categoryOptions = const <String>[];
}

class TrackerRangeAnalysisSnapshot {
  final ActivityHeatmapBucket bucket;
  final List<ActivityRecord> records;
  final List<ActivityLogEntry> logEntries;
  final ActivityInsights insights;
  final List<WorkSession> sessions;

  const TrackerRangeAnalysisSnapshot({
    required this.bucket,
    required this.records,
    required this.logEntries,
    required this.insights,
    required this.sessions,
  });
}

final trackerHistorySearchQueryProvider = StateProvider<String>((ref) => '');

final trackerHistorySelectedProcessProvider =
    StateProvider<String?>((ref) => null);

final trackerHistorySelectedCategoryProvider =
    StateProvider<String?>((ref) => null);

final trackerHistorySelectedTaskIdProvider = StateProvider<int?>((ref) => null);

final trackerHistoryOnlyWithInputProvider =
    StateProvider<bool>((ref) => false);

final trackerHistorySelectedHeatmapBucketProvider =
    StateProvider<ActivityHeatmapBucket?>((ref) => null);

final trackerHistorySelectedAnalysisBucketProvider =
    StateProvider<ActivityHeatmapBucket?>((ref) => null);

final trackerRangeAnalysisRecordsProvider =
    FutureProvider<List<ActivityRecord>>((ref) async {
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return const <ActivityRecord>[];
  }

  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final response = await store.rangeAnalysis(
    start: bucket.start,
    end: bucket.end,
    bucket: _serverBucketForScale(_scaleForBucket(bucket)),
  );
  return _activityRecordsFromServerPreview(response);
});

final trackerRangeAnalysisLogEntriesProvider =
    FutureProvider<List<ActivityLogEntry>>((ref) async {
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return const <ActivityLogEntry>[];
  }
  return const <ActivityLogEntry>[];
});

final trackerRangeAnalysisProvider =
    Provider<AsyncValue<TrackerRangeAnalysisSnapshot?>>((ref) {
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return const AsyncData(null);
  }

  final recordsAsync = ref.watch(trackerRangeAnalysisRecordsProvider);
  final logsAsync = ref.watch(trackerRangeAnalysisLogEntriesProvider);
  final rangeAnalysisAsync = ref.watch(trackerRangeAnalysisViewModelProvider);

  for (final async in [recordsAsync, logsAsync, rangeAnalysisAsync]) {
    if (async.hasError) {
      return AsyncValue.error(
        async.error!,
        async.stackTrace ?? StackTrace.current,
      );
    }
  }

  final records = recordsAsync.asData?.value;
  final logEntries = logsAsync.asData?.value;
  final rangeAnalysis = rangeAnalysisAsync.asData?.value;
  if (records == null || logEntries == null || rangeAnalysis == null) {
    return const AsyncLoading();
  }

  return AsyncData(
    TrackerRangeAnalysisSnapshot(
      bucket: bucket,
      records: records,
      logEntries: logEntries,
      insights: _activityInsightsFromServer(rangeAnalysis),
      sessions: _workSessionsFromServer(rangeAnalysis),
    ),
  );
});

final trackerRangeAnalysisViewModelProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return const <String, dynamic>{};
  }
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  return store.rangeAnalysis(
    start: bucket.start,
    end: bucket.end,
    bucket: _serverBucketForScale(_scaleForBucket(bucket)),
  );
});

final trackerHistoryFilterOptionsProvider =
    Provider<TrackerHistoryFilterOptions>((ref) {
  final optionsAsync = ref.watch(trackerServerFilterOptionsProvider);
  return optionsAsync.maybeWhen(
    data: _filterOptionsFromServer,
    orElse: TrackerHistoryFilterOptions.empty,
  );
});

final trackerServerFilterOptionsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);
  final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
  final end = start.add(const Duration(days: 1));
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  return store.filterOptions(start: start, end: end);
});

Future<List<String>> _loadServerInputProcessOptions(Ref ref) async {
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  final response = await store.filterOptions();
  return _filterOptionsFromServer(response).processOptions;
}

TrackerHistoryFilterOptions _filterOptionsFromServer(
  Map<String, dynamic> response,
) {
  final processes = _stringList(response['processOptions']);
  final categories = _stringList(response['categoryOptions']);
  return TrackerHistoryFilterOptions(
    processOptions: processes,
    categoryOptions: categories,
  );
}

ActivityInsights _activityInsightsFromServer(Map<String, dynamic> response) {
  final insights = _asStringMap(response['insights']);
  final previewRecords = _activityRecordsFromServerPreview(response);
  final busiestRecords = previewRecords
      .take(3)
      .map(
        (record) => ActivityInsightRecord(
          record: record,
          inputScore: record.keyCount + (record.mouseClicks * 4),
        ),
      )
      .toList(growable: false);
  return ActivityInsights(
    records: previewRecords,
    totalMinutes: _intValue(insights['totalMinutes']),
    focusMinutes: _intValue(insights['focusMinutes']),
    totalKeys: _intValue(insights['totalKeys']),
    totalClicks: _intValue(insights['totalClicks']),
    totalMovePx: _intValue(insights['totalMovePx']),
    totalScrollPx: _intValue(insights['totalScrollPx']),
    sequenceRecordCount: _intValue(insights['sequenceRecordCount']),
    productiveRecordCountOverride:
        _intValue(insights['productiveRecordCount']),
    topProcesses: _insightSlices(insights['topProcesses']),
    topCategories: _insightSlices(insights['topCategories']),
    busiestRecords: busiestRecords,
  );
}

List<ActivityInsightSlice> _insightSlices(Object? value) {
  return _mapList(value)
      .map(
        (item) => ActivityInsightSlice(
          label: _stringValue(item['label'] ?? item['name']) ?? 'unknown',
          minutes: _intValue(item['minutes'] ?? item['totalMinutes']),
          keys: _intValue(item['keys']),
          clicks: _intValue(item['clicks']),
          movePx: _intValue(item['movePx']),
          scrollPx: _intValue(item['scrollPx']),
          sessions: _intValue(item['sessions'] ?? item['recordCount']),
        ),
      )
      .toList(growable: false);
}

List<WorkSession> _workSessionsFromServer(Map<String, dynamic> response) {
  return _mapList(response['sessions'])
      .map((item) {
        final start = _dateValue(item['startTime']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final duration = _intValue(item['durationMinutes'], fallback: 1);
        final end = _dateValue(item['endTime']) ??
            start.add(Duration(minutes: duration));
        final processNames = _stringList(item['processNames']);
        final categories = _stringList(item['categories']);
        return WorkSession(
          startTime: start,
          endTime: end,
          label: _stringValue(item['label']) ??
              (categories.isNotEmpty
                  ? categories.first
                  : processNames.isNotEmpty
                      ? processNames.first
                      : '服务端工作会话'),
          processName: _stringValue(item['processName']) ??
              (processNames.isEmpty ? null : processNames.first),
          category: _stringValue(item['category']) ??
              (categories.isEmpty ? null : categories.first),
          records: const <ActivityRecord>[],
          durationMinutes: duration,
          keyCount: _intValue(item['keyCount']),
          mouseClicks: _intValue(item['mouseClicks']),
          mouseMovePx: _intValue(item['mouseMovePx']),
          scrollPx: _intValue(item['scrollPx']),
          processNames: processNames,
          categories: categories,
          interruptionCount: _intValue(item['interruptionCount']),
          rawRecordCountOverride: _intValue(item['rawRecordCount']),
        );
      })
      .toList(growable: false);
}

List<ActivityRecord> _activityRecordsFromServerPreview(
  Map<String, dynamic> response,
) {
  final preview = response['previewRecords'];
  if (preview is List) {
    return _activityRecordsFromServer({'items': preview});
  }
  return _activityRecordsFromServer(response);
}

List<ActivityRecord> activityRecordsFromServerPreview(
  Map<String, dynamic> response,
) =>
    _activityRecordsFromServerPreview(response);

ActivityInsights activityInsightsFromServer(Map<String, dynamic> response) =>
    _activityInsightsFromServer(response);

List<WorkSession> workSessionsFromServer(Map<String, dynamic> response) =>
    _workSessionsFromServer(response);

ActivityHistorySummary _activityHistorySummaryFromServer(
  Map<String, dynamic> response,
) {
  final counts = _asStringMap(response['canonicalObjectCounts']);
  final latest = _asStringMap(response['latestReceivedAtByKind']);
  final totalRecords = counts.values.fold<int>(
    0,
    (sum, value) => sum + _intValue(value),
  );
  DateTime? lastRecordAt;
  for (final value in latest.values) {
    final parsed = _dateValue(value);
    if (parsed != null &&
        (lastRecordAt == null || parsed.isAfter(lastRecordAt))) {
      lastRecordAt = parsed;
    }
  }
  return ActivityHistorySummary(
    firstRecordAt: totalRecords > 0 && lastRecordAt != null
        ? lastRecordAt.subtract(const Duration(days: 30))
        : null,
    lastRecordAt: lastRecordAt,
    totalRecords: totalRecords,
  );
}

({DateTime start, DateTime end}) _activityHeatmapRange(
  ActivityHeatmapScale scale,
  DateTime anchorDate,
) {
  switch (scale) {
    case ActivityHeatmapScale.hour:
      final start = DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
      return (start: start, end: start.add(const Duration(days: 1)));
    case ActivityHeatmapScale.day:
      final start = DateTime(anchorDate.year, anchorDate.month);
      return (start: start, end: DateTime(anchorDate.year, anchorDate.month + 1));
    case ActivityHeatmapScale.month:
    case ActivityHeatmapScale.year:
      final start = DateTime(anchorDate.year);
      return (start: start, end: DateTime(anchorDate.year + 1));
  }
}

String _serverBucketForScale(ActivityHeatmapScale scale) {
  return switch (scale) {
    ActivityHeatmapScale.hour => 'hour',
    ActivityHeatmapScale.day => 'day',
    ActivityHeatmapScale.month => 'month',
    ActivityHeatmapScale.year => 'month',
  };
}

ActivityHeatmapScale _scaleForBucket(ActivityHeatmapBucket bucket) {
  final span = bucket.end.difference(bucket.start);
  if (span.inHours <= 1) {
    return ActivityHeatmapScale.hour;
  }
  if (span.inDays <= 1) {
    return ActivityHeatmapScale.day;
  }
  if (span.inDays <= 32) {
    return ActivityHeatmapScale.month;
  }
  return ActivityHeatmapScale.year;
}

ActivityHeatmapSeries _activityHeatmapSeriesFromServer(
  Map<String, dynamic> response, {
  required ActivityHeatmapScale scale,
  required DateTime anchorDate,
  required ActivityHistorySummary historySummary,
}) {
  final completedByBucket = <String, int>{};
  final minutesByBucket = <String, int>{};
  for (final row in _serverBuckets(response)) {
    final start = _dateValue(row['bucketStart']);
    if (start == null) {
      continue;
    }
    final key = _activityBucketKey(scale, start);
    completedByBucket[key] =
        (completedByBucket[key] ?? 0) + _intValue(row['recordCount']);
    minutesByBucket[key] =
        (minutesByBucket[key] ?? 0) + _intValue(row['totalMinutes']);
  }
  final buckets = _activityHeatmapSkeletonBuckets(scale, anchorDate)
      .map((bucket) {
    final key = _activityBucketKey(scale, bucket.start);
    return ActivityHeatmapBucket(
      start: bucket.start,
      end: bucket.end,
      shortLabel: bucket.shortLabel,
      longLabel: bucket.longLabel,
      completedCount: completedByBucket[key] ?? 0,
      totalMinutes: minutesByBucket[key] ?? 0,
    );
  }).toList(growable: false);
  return ActivityHeatmapSeries(
    scale: scale,
    anchorDate: anchorDate,
    title: _heatmapTitle(scale, anchorDate),
    subtitle: '数据来自服务端汇总后的追踪事实，而不是本机临时缓冲。',
    buckets: buckets,
    maxMinutes: buckets.fold<int>(
      0,
      (max, item) => item.totalMinutes > max ? item.totalMinutes : max,
    ),
    historySummary: historySummary,
  );
}

List<ActivityHeatmapBucket> _activityHeatmapSkeletonBuckets(
  ActivityHeatmapScale scale,
  DateTime anchorDate,
) {
  final buckets = <ActivityHeatmapBucket>[];
  switch (scale) {
    case ActivityHeatmapScale.hour:
      final start = DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
      for (var hour = 0; hour < 24; hour++) {
        final bucketStart = DateTime(start.year, start.month, start.day, hour);
        buckets.add(
          ActivityHeatmapBucket(
            start: bucketStart,
            end: bucketStart.add(const Duration(hours: 1)),
            shortLabel: _bucketShortLabel(scale, bucketStart),
            longLabel: _bucketLongLabel(scale, bucketStart),
            completedCount: 0,
            totalMinutes: 0,
          ),
        );
      }
      break;
    case ActivityHeatmapScale.day:
      final monthStart = DateTime(anchorDate.year, anchorDate.month);
      final daysInMonth =
          DateTime(anchorDate.year, anchorDate.month + 1).difference(monthStart).inDays;
      for (var day = 1; day <= daysInMonth; day++) {
        final bucketStart = DateTime(anchorDate.year, anchorDate.month, day);
        buckets.add(
          ActivityHeatmapBucket(
            start: bucketStart,
            end: bucketStart.add(const Duration(days: 1)),
            shortLabel: _bucketShortLabel(scale, bucketStart),
            longLabel: _bucketLongLabel(scale, bucketStart),
            completedCount: 0,
            totalMinutes: 0,
          ),
        );
      }
      break;
    case ActivityHeatmapScale.month:
    case ActivityHeatmapScale.year:
      for (var month = 1; month <= 12; month++) {
        final bucketStart = DateTime(anchorDate.year, month);
        buckets.add(
          ActivityHeatmapBucket(
            start: bucketStart,
            end: DateTime(anchorDate.year, month + 1),
            shortLabel: _bucketShortLabel(scale, bucketStart),
            longLabel: _bucketLongLabel(scale, bucketStart),
            completedCount: 0,
            totalMinutes: 0,
          ),
        );
      }
      break;
  }
  return buckets;
}

String _activityBucketKey(ActivityHeatmapScale scale, DateTime start) {
  final local = start.toLocal();
  return switch (scale) {
    ActivityHeatmapScale.hour =>
      '${local.year}-${local.month}-${local.day}-${local.hour}',
    ActivityHeatmapScale.day => '${local.year}-${local.month}-${local.day}',
    ActivityHeatmapScale.month => '${local.year}-${local.month}',
    ActivityHeatmapScale.year => '${local.year}-${local.month}',
  };
}

List<ActivityRecord> _activityRecordsFromServer(Map<String, dynamic> response) {
  final records = <ActivityRecord>[];
  for (final item in _serverItems(response)) {
    final payload = _payload(item);
    final start = _dateValue(
          payload['startTime'] ??
              payload['start_time'] ??
              payload['startedAt'] ??
              item['occurredAt'],
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final durationMinutes = _intValue(
      payload['durationMinutes'] ??
          payload['duration_minutes'] ??
          item['metricMinutes'],
      fallback: 1,
    );
    final end = _dateValue(
          payload['endTime'] ?? payload['end_time'] ?? payload['endedAt'],
        ) ??
        start.add(Duration(minutes: durationMinutes));
    records.add(
      ActivityRecord(
        id: _stablePositiveId(_stringValue(item['serverId']) ?? start.toIso8601String()),
        startTime: start,
        endTime: end,
        durationMinutes: durationMinutes,
        manualLabel: _stringValue(
          payload['manualLabel'] ?? payload['manual_label'] ?? payload['label'],
        ),
        processName: _stringValue(
          payload['processName'] ?? payload['process_name'] ?? payload['packageName'],
        ),
        windowTitle: _stringValue(
          payload['windowTitle'] ?? payload['window_title'] ?? payload['title'],
        ),
        packageName: _stringValue(payload['packageName'] ?? payload['package_name']),
        category: _stringValue(payload['category']),
        appUsageRuleId: _stringValue(payload['appUsageRuleId']),
        linkedTaskId: _intOrNull(payload['linkedTaskId'] ?? payload['linked_task_id']),
        keyCount: _intValue(payload['keyCount'] ?? payload['key_count']),
        mouseClicks: _intValue(payload['mouseClicks'] ?? payload['mouse_clicks']),
        mouseMovePx: _intValue(payload['mouseMovePx'] ?? payload['mouse_move_px']),
        scrollPx: _intValue(payload['scrollPx'] ?? payload['scroll_px']),
        keySequence: _stringValue(payload['keySequence']),
        isAuto: payload['isAuto'] is bool ? payload['isAuto'] as bool : true,
        source: _stringValue(item['objectType']) ?? 'server',
      ),
    );
  }
  records.sort((left, right) => left.startTime.compareTo(right.startTime));
  return records;
}

InputHeatmapSummary _inputHeatmapSummaryFromServer(
  InputEventQuery query,
  Map<String, dynamic> response,
) {
  var total = 0;
  var keyboard = 0;
  var mouseButton = 0;
  var wheel = 0;
  var mouseMove = 0;
  var distance = 0;
  final activeHours = <String>{};
  final byHour = <int, _InputHourCounter>{
    for (var hour = 0; hour < 24; hour++) hour: _InputHourCounter(hour),
  };
  for (final row in _serverBuckets(response)) {
    final start = _dateValue(row['bucketStart']);
    if (start == null) {
      continue;
    }
    final hour = start.toLocal().hour;
    final counter = byHour[hour]!;
    counter.totalEvents += _intValue(row['eventCount']);
    counter.keyEvents += _intValue(row['keyboardEventCount']);
    counter.mouseButtonEvents += _intValue(row['mouseButtonEventCount']);
    counter.wheelEvents += _intValue(row['wheelEventCount']);
    counter.mouseMoveEvents += _intValue(row['mouseMoveEventCount']);
    counter.moveDistance += _intValue(row['mouseMoveDistance']);
    activeHours.add(start.toIso8601String());
    total += _intValue(row['eventCount']);
    keyboard += _intValue(row['keyboardEventCount']);
    mouseButton += _intValue(row['mouseButtonEventCount']);
    wheel += _intValue(row['wheelEventCount']);
    mouseMove += _intValue(row['mouseMoveEventCount']);
    distance += _intValue(row['mouseMoveDistance']);
  }
  final hourly = byHour.values.map((item) => item.toBucket()).toList()
    ..sort((left, right) => left.hour.compareTo(right.hour));
  final keyCounts = _intMap(response['keyCounts']);
  final mouseCounts = _stringIntMap(response['mouseCounts']);
  final topKeys = _inputKeyStats(response['topKeys'], keyboard);
  final processIntensities = _inputProcessIntensities(response['processIntensities']);
  return InputHeatmapSummary(
    query: query,
    totalEventCount: total,
    activeMinuteCount: activeHours.length * 60,
    keyboardEventCount: keyboard,
    mouseButtonEventCount: mouseButton,
    wheelEventCount: wheel,
    mouseMoveEventCount: mouseMove,
    mouseMoveDistance: distance,
    keyCounts: keyCounts,
    mouseCounts: mouseCounts,
    topKeys: topKeys,
    processIntensities: processIntensities,
    hourlyDistribution: hourly,
  );
}

Map<int, int> _intMap(Object? value) {
  final source = _asStringMap(value);
  if (source.isEmpty) {
    return const <int, int>{};
  }
  final result = <int, int>{};
  for (final entry in source.entries) {
    final key = int.tryParse(entry.key);
    final count = _intValue(entry.value);
    if (key != null && count > 0) {
      result[key] = count;
    }
  }
  return result;
}

Map<String, int> _stringIntMap(Object? value) {
  final source = _asStringMap(value);
  if (source.isEmpty) {
    return const <String, int>{};
  }
  final result = <String, int>{};
  for (final entry in source.entries) {
    final key = entry.key.trim();
    final count = _intValue(entry.value);
    if (key.isNotEmpty && count > 0) {
      result[key] = count;
    }
  }
  return result;
}

List<InputKeyStat> _inputKeyStats(Object? value, int keyboardTotal) {
  final items = _mapList(value);
  if (items.isEmpty) {
    return const <InputKeyStat>[];
  }
  return items
      .map((item) {
        final keyCode = _intOrNull(item['keyCode'] ?? item['key_code']);
        final count = _intValue(item['count'] ?? item['eventCount']);
        if (keyCode == null || count <= 0) {
          return null;
        }
        return InputKeyStat(
          keyCode: keyCode,
          label: _stringValue(item['label']) ?? inputKeyLabelForCode(keyCode),
          count: count,
          share: item['share'] is num
              ? (item['share'] as num).toDouble()
              : (keyboardTotal > 0 ? count / keyboardTotal : 0),
        );
      })
      .whereType<InputKeyStat>()
      .toList(growable: false);
}

List<InputProcessIntensity> _inputProcessIntensities(Object? value) {
  final items = _mapList(value);
  if (items.isEmpty) {
    return const <InputProcessIntensity>[];
  }
  return items
      .map((item) {
        final processName = _stringValue(item['processName'] ?? item['process_name']);
        if (processName == null) {
          return null;
        }
        return InputProcessIntensity(
          processName: processName,
          totalEvents: _intValue(item['totalEvents'] ?? item['eventCount']),
          keyEvents: _intValue(item['keyEvents'] ?? item['keyboardEventCount']),
          mouseButtonEvents: _intValue(item['mouseButtonEvents'] ?? item['mouseButtonEventCount']),
          wheelEvents: _intValue(item['wheelEvents'] ?? item['wheelEventCount']),
          mouseMoveEvents: _intValue(item['mouseMoveEvents'] ?? item['mouseMoveEventCount']),
          moveDistance: _intValue(item['moveDistance'] ?? item['mouseMoveDistance']),
          activeMinutes: _intValue(item['activeMinutes']),
          intensityScore: _intValue(item['intensityScore']),
        );
      })
      .whereType<InputProcessIntensity>()
      .toList(growable: false);
}

List<TrackedInputEvent> _trackedInputEventsFromServer(
  Map<String, dynamic> response,
) {
  final events = <TrackedInputEvent>[];
  for (final item in _serverItems(response)) {
    final payload = _payload(item);
    final timestamp = _dateValue(
          payload['timestamp'] ?? payload['occurredAt'] ?? item['occurredAt'],
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final uid = _stringValue(
          payload['eventUid'] ?? payload['event_uid'] ?? item['serverId'],
        ) ??
        timestamp.toIso8601String();
    events.add(
      TrackedInputEvent(
        eventUid: uid,
        sequenceId: _intValue(
          payload['sequenceId'] ?? payload['sequence_id'],
          fallback: _stablePositiveId(uid),
        ),
        timestamp: timestamp,
        kind: TrackedInputEventKindValue.fromValue(
          _stringValue(payload['eventKind'] ?? payload['kind']) ?? 'key_down',
        ),
        eventCount: _intValue(payload['eventCount'] ?? item['metricCount'], fallback: 1),
        recordId: _intOrNull(payload['recordId']),
        isIgnored: payload['isIgnored'] is bool ? payload['isIgnored'] as bool : false,
        processName: _stringValue(payload['processName'] ?? payload['process_name']),
        className: _stringValue(payload['className']),
        windowTitle: _stringValue(payload['windowTitle'] ?? payload['window_title']),
        category: _stringValue(payload['category']),
        activityLabel: _stringValue(payload['activityLabel']),
        keyCode: _intOrNull(payload['keyCode']),
        keyLabel: _stringValue(payload['keyLabel']),
        mouseButton: _stringValue(payload['mouseButton']),
        wheelDelta: _intValue(payload['wheelDelta']),
        deltaX: _intValue(payload['deltaX']),
        deltaY: _intValue(payload['deltaY']),
        moveDistance: _intValue(payload['moveDistance'] ?? payload['move_distance']),
        tokenText: _stringValue(payload['tokenText']),
      ),
    );
  }
  return events;
}

List<Map<String, Object?>> _serverItems(Map<String, dynamic> response) {
  final items = response['items'];
  if (items is! List) {
    return const <Map<String, Object?>>[];
  }
  return items
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final items = value
      .map(_stringValue)
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList()
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return items;
}

List<Map<String, Object?>> _serverBuckets(Map<String, dynamic> response) {
  final buckets = response['buckets'];
  if (buckets is! List) {
    return const <Map<String, Object?>>[];
  }
  return buckets
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

Map<String, Object?> _payload(Map<String, Object?> item) {
  final payload = item['payload'];
  if (payload is Map<String, dynamic>) {
    return Map<String, Object?>.from(payload);
  }
  if (payload is Map) {
    return Map<String, Object?>.from(payload);
  }
  return const <String, Object?>{};
}

Map<String, Object?> _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}

DateTime? _dateValue(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) {
      return parsed.round();
    }
  }
  return fallback;
}

int? _intOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return num.tryParse(value)?.round();
  }
  return null;
}

int _stablePositiveId(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

String _bucketShortLabel(ActivityHeatmapScale scale, DateTime start) {
  return switch (scale) {
    ActivityHeatmapScale.hour => start.hour.toString().padLeft(2, '0'),
    ActivityHeatmapScale.day => start.day.toString(),
    ActivityHeatmapScale.month => '${start.month}',
    ActivityHeatmapScale.year => '${start.month}',
  };
}

String _bucketLongLabel(ActivityHeatmapScale scale, DateTime start) {
  return switch (scale) {
    ActivityHeatmapScale.hour =>
      '${start.month}月${start.day}日 ${start.hour.toString().padLeft(2, '0')}:00',
    ActivityHeatmapScale.day => '${start.year}年${start.month}月${start.day}日',
    ActivityHeatmapScale.month => '${start.year}年${start.month}月',
    ActivityHeatmapScale.year => '${start.year}年${start.month}月',
  };
}

String _heatmapTitle(ActivityHeatmapScale scale, DateTime anchorDate) {
  return switch (scale) {
    ActivityHeatmapScale.hour =>
      '${anchorDate.month}月${anchorDate.day}日逐小时分布',
    ActivityHeatmapScale.day =>
      '${anchorDate.year}年${anchorDate.month}月每日分布',
    ActivityHeatmapScale.month => '${anchorDate.year}年每月分布',
    ActivityHeatmapScale.year => '${anchorDate.year}年每月分布',
  };
}

class _InputHourCounter {
  _InputHourCounter(this.hour);

  final int hour;
  int totalEvents = 0;
  int keyEvents = 0;
  int mouseButtonEvents = 0;
  int wheelEvents = 0;
  int mouseMoveEvents = 0;
  int moveDistance = 0;

  InputHourDistributionBucket toBucket() {
    return InputHourDistributionBucket(
      hour: hour,
      totalEvents: totalEvents,
      keyEvents: keyEvents,
      mouseButtonEvents: mouseButtonEvents,
      wheelEvents: wheelEvents,
      mouseMoveEvents: mouseMoveEvents,
      moveDistance: moveDistance,
      activeMinutes: totalEvents > 0 ? 60 : 0,
      intensityScore: totalEvents + (moveDistance ~/ 100),
    );
  }
}

// 鈹€鈹€ 服务端分页查询 Providers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

class ServerRecordQuery {
  final DateTime? start;
  final DateTime? end;
  final String? processName;
  final String? category;
  final int? taskId;
  final int limit;
  final int offset;

  const ServerRecordQuery({
    this.start,
    this.end,
    this.processName,
    this.category,
    this.taskId,
    this.limit = 100,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerRecordQuery &&
        other.start == start &&
        other.end == end &&
        other.processName == processName &&
        other.category == category &&
        other.taskId == taskId &&
        other.limit == limit &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(start, end, processName, category, taskId, limit, offset);
}

class ServerInputEventQuery {
  final DateTime? start;
  final DateTime? end;
  final String? processName;
  final String? category;
  final String? eventKind;
  final int limit;
  final int offset;

  const ServerInputEventQuery({
    this.start,
    this.end,
    this.processName,
    this.category,
    this.eventKind,
    this.limit = 100,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerInputEventQuery &&
        other.start == start &&
        other.end == end &&
        other.processName == processName &&
        other.category == category &&
        other.eventKind == eventKind &&
        other.limit == limit &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(start, end, processName, category, eventKind, limit, offset);
}

final serverActivityRecordsPageProvider =
    FutureProvider.family<Map<String, dynamic>, ServerRecordQuery>((ref, query) async {
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  return store.activityRecords(
    start: query.start,
    end: query.end,
    processName: query.processName,
    category: query.category,
    taskId: query.taskId,
    limit: query.limit,
    offset: query.offset,
  );
});

final serverInputEventsPageProvider =
    FutureProvider.family<Map<String, dynamic>, ServerInputEventQuery>((ref, query) async {
  final store = await ref.watch(trackingServerFirstStoreProvider.future);
  return store.inputEvents(
    start: query.start,
    end: query.end,
    processName: query.processName,
    category: query.category,
    eventKind: query.eventKind,
    limit: query.limit,
    offset: query.offset,
  );
});

final trackingUploadDiagnosticsProvider =
    FutureProvider<Map<String, Object?>>((ref) async {
  final service = await ref.watch(trackingUploadServiceProvider.future);
  return service.buildUploadDiagnostics();
});
