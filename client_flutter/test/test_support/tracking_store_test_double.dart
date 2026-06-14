import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';

class InputHeatmapCall {
  const InputHeatmapCall({
    required this.start,
    required this.end,
    required this.bucket,
    required this.processName,
    required this.category,
    required this.eventKind,
  });

  final DateTime? start;
  final DateTime? end;
  final String bucket;
  final String? processName;
  final String? category;
  final String? eventKind;
}

class ActivityHeatmapCall {
  const ActivityHeatmapCall({
    required this.start,
    required this.end,
    required this.bucket,
    required this.processName,
    required this.category,
    required this.taskId,
  });

  final DateTime? start;
  final DateTime? end;
  final String bucket;
  final String? processName;
  final String? category;
  final int? taskId;
}

class RangeAnalysisCall {
  const RangeAnalysisCall({
    required this.start,
    required this.end,
    required this.bucket,
  });

  final DateTime start;
  final DateTime end;
  final String bucket;
}

class ActivityDaySummaryCall {
  const ActivityDaySummaryCall({required this.date});

  final DateTime date;
}

class ActivityRecordsCall {
  const ActivityRecordsCall({
    required this.start,
    required this.end,
    required this.processName,
    required this.category,
    required this.taskId,
    required this.limit,
    required this.offset,
  });

  final DateTime? start;
  final DateTime? end;
  final String? processName;
  final String? category;
  final int? taskId;
  final int limit;
  final int offset;
}

class InputEventsCall {
  const InputEventsCall({
    required this.start,
    required this.end,
    required this.processName,
    required this.category,
    required this.eventKind,
    required this.limit,
    required this.offset,
  });

  final DateTime? start;
  final DateTime? end;
  final String? processName;
  final String? category;
  final String? eventKind;
  final int limit;
  final int offset;
}

class TrackingStoreTestDouble implements TrackingServerFirstStore {
  TrackingStoreTestDouble({
    this.processOptions = const <String>[],
    this.categoryOptions = const <String>[],
    this.activityDaySummaryResponseBuilder,
    this.trackingSummaryResponseBuilder,
    this.activityHeatmapResponseBuilder,
    this.rangeAnalysisResponseBuilder,
    this.inputHeatmapResponseBuilder,
    this.activityRecordsResponseBuilder,
    this.inputEventsResponseBuilder,
  });

  List<String> processOptions;
  List<String> categoryOptions;
  final Map<String, dynamic> Function(ActivityDaySummaryCall call)?
      activityDaySummaryResponseBuilder;
  final Map<String, dynamic> Function()? trackingSummaryResponseBuilder;
  final Map<String, dynamic> Function(ActivityHeatmapCall call)?
      activityHeatmapResponseBuilder;
  final Map<String, dynamic> Function(RangeAnalysisCall call)?
      rangeAnalysisResponseBuilder;
  final Map<String, dynamic> Function(InputHeatmapCall call)?
      inputHeatmapResponseBuilder;
  final Map<String, dynamic> Function(ActivityRecordsCall call)?
      activityRecordsResponseBuilder;
  final Map<String, dynamic> Function(InputEventsCall call)?
      inputEventsResponseBuilder;

  final activityDaySummaryCalls = <ActivityDaySummaryCall>[];
  final activityHeatmapCalls = <ActivityHeatmapCall>[];
  final rangeAnalysisCalls = <RangeAnalysisCall>[];
  final inputHeatmapCalls = <InputHeatmapCall>[];
  final activityRecordsCalls = <ActivityRecordsCall>[];
  final inputEventsCalls = <InputEventsCall>[];
  final filterOptionsCalls = <({DateTime? start, DateTime? end})>[];

  Object? activityDaySummaryError;
  Object? trackingSummaryError;
  Object? activityHeatmapError;
  Object? rangeAnalysisError;
  Object? filterOptionsError;
  Object? inputHeatmapError;
  Object? activityRecordsError;
  Object? inputEventsError;

  @override
  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) async {
    final call = ActivityDaySummaryCall(date: date);
    activityDaySummaryCalls.add(call);
    final error = activityDaySummaryError;
    if (error != null) {
      throw error;
    }
    return activityDaySummaryResponseBuilder?.call(call) ??
        _emptyActivityDaySummary();
  }

  @override
  Future<Map<String, dynamic>> trackingSummary({
    DateTime? start,
    DateTime? end,
  }) async {
    final error = trackingSummaryError;
    if (error != null) {
      throw error;
    }
    return trackingSummaryResponseBuilder?.call() ??
        <String, dynamic>{
          'canonicalObjectCounts': <String, Object?>{
            'activity_record': 0,
          },
          'latestReceivedAtByKind': <String, Object?>{},
        };
  }

  @override
  Future<Map<String, dynamic>> activityHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    int? taskId,
  }) async {
    final call = ActivityHeatmapCall(
      start: start,
      end: end,
      bucket: bucket,
      processName: processName,
      category: category,
      taskId: taskId,
    );
    activityHeatmapCalls.add(call);
    final error = activityHeatmapError;
    if (error != null) {
      throw error;
    }
    return activityHeatmapResponseBuilder?.call(call) ??
        <String, dynamic>{'buckets': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> rangeAnalysis({
    required DateTime start,
    required DateTime end,
    String bucket = 'day',
  }) async {
    final call = RangeAnalysisCall(start: start, end: end, bucket: bucket);
    rangeAnalysisCalls.add(call);
    final error = rangeAnalysisError;
    if (error != null) {
      throw error;
    }
    return rangeAnalysisResponseBuilder?.call(call) ??
        _emptyActivityDaySummary();
  }

  @override
  Future<Map<String, dynamic>> filterOptions({
    DateTime? start,
    DateTime? end,
  }) async {
    filterOptionsCalls.add((start: start, end: end));
    final error = filterOptionsError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'processOptions': processOptions,
      'categoryOptions': categoryOptions,
    };
  }

  @override
  Future<Map<String, dynamic>> inputHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'hour',
    String? processName,
    String? category,
    String? eventKind,
  }) async {
    final call = InputHeatmapCall(
      start: start,
      end: end,
      bucket: bucket,
      processName: processName,
      category: category,
      eventKind: eventKind,
    );
    inputHeatmapCalls.add(call);
    final error = inputHeatmapError;
    if (error != null) {
      throw error;
    }
    return inputHeatmapResponseBuilder?.call(call) ??
        <String, dynamic>{'buckets': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> activityRecords({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    int? taskId,
    int limit = 100,
    int offset = 0,
  }) async {
    final call = ActivityRecordsCall(
      start: start,
      end: end,
      processName: processName,
      category: category,
      taskId: taskId,
      limit: limit,
      offset: offset,
    );
    activityRecordsCalls.add(call);
    final error = activityRecordsError;
    if (error != null) {
      throw error;
    }
    return activityRecordsResponseBuilder?.call(call) ??
        <String, dynamic>{
          'items': <Map<String, Object?>>[],
        };
  }

  @override
  Future<Map<String, dynamic>> inputEvents({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    String? eventKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final call = InputEventsCall(
      start: start,
      end: end,
      processName: processName,
      category: category,
      eventKind: eventKind,
      limit: limit,
      offset: offset,
    );
    inputEventsCalls.add(call);
    final error = inputEventsError;
    if (error != null) {
      throw error;
    }
    return inputEventsResponseBuilder?.call(call) ??
        <String, dynamic>{
          'items': <Map<String, Object?>>[],
        };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _emptyActivityDaySummary() {
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': 0,
      'totalMinutes': 0,
      'focusMinutes': 0,
      'totalKeys': 0,
      'totalClicks': 0,
      'totalMovePx': 0,
      'totalScrollPx': 0,
      'productiveRecordCount': 0,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[],
      'topCategories': <Map<String, Object?>>[],
      'busiestRecords': <Map<String, Object?>>[],
    },
    'previewRecords': <Map<String, Object?>>[],
    'sessions': <Map<String, Object?>>[],
  };
}
