import '../server_api/activity_understanding_api.dart';
import '../server_api/analytics_api.dart';
import '../server_api/tracking_ingest_api.dart';

class TrackingServerFirstStore {
  const TrackingServerFirstStore({
    required AnalyticsApi analytics,
    required TrackingIngestApi tracking,
    required ActivityUnderstandingApi activityUnderstanding,
  })  : _analytics = analytics,
        _tracking = tracking,
        _activityUnderstanding = activityUnderstanding;

  final AnalyticsApi _analytics;
  final TrackingIngestApi _tracking;
  final ActivityUnderstandingApi _activityUnderstanding;

  Future<Map<String, dynamic>> trackingSummary({
    DateTime? start,
    DateTime? end,
  }) {
    return _tracking.summary(start: start, end: end);
  }

  Future<Map<String, dynamic>> activityHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    int? taskId,
  }) {
    return _analytics.activityHeatmap(
      start: start,
      end: end,
      bucket: bucket,
      processName: processName,
      category: category,
      taskId: taskId,
    );
  }

  Future<Map<String, dynamic>> trackerHome({DateTime? date}) {
    return _analytics.trackerHome(date: date);
  }

  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) {
    return _analytics.activityDaySummary(date: date);
  }

  Future<Map<String, dynamic>> rangeAnalysis({
    required DateTime start,
    required DateTime end,
    String bucket = 'day',
  }) {
    return _analytics.rangeAnalysis(start: start, end: end, bucket: bucket);
  }

  Future<Map<String, dynamic>> filterOptions({
    DateTime? start,
    DateTime? end,
  }) {
    return _analytics.filterOptions(start: start, end: end);
  }

  Future<Map<String, dynamic>> inputHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'hour',
    String? processName,
    String? category,
    String? eventKind,
  }) {
    return _analytics.inputHeatmap(
      start: start,
      end: end,
      bucket: bucket,
      processName: processName,
      category: category,
      eventKind: eventKind,
    );
  }

  Future<Map<String, dynamic>> activityRecords({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    int? taskId,
    int limit = 100,
    int offset = 0,
  }) {
    return _analytics.activityRecords(
      start: start,
      end: end,
      processName: processName,
      category: category,
      taskId: taskId,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> inputEvents({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    String? eventKind,
    int limit = 100,
    int offset = 0,
  }) {
    return _analytics.inputEvents(
      start: start,
      end: end,
      processName: processName,
      category: category,
      eventKind: eventKind,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> buildSegments({
    required DateTime date,
    bool includeTrackedInputEvents = true,
    bool includeRawActivityLogs = true,
    bool includeActivityRecords = true,
  }) {
    return _activityUnderstanding.buildSegments(
      date: date,
      includeTrackedInputEvents: includeTrackedInputEvents,
      includeRawActivityLogs: includeRawActivityLogs,
      includeActivityRecords: includeActivityRecords,
    );
  }

  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) {
    return _activityUnderstanding.segments(
      startAt: startAt,
      endAt: endAt,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> confirmSegment({
    required String segmentId,
    String? title,
    String? taskId,
    String? note,
  }) {
    return _activityUnderstanding.confirmSegment(
      segmentId: segmentId,
      title: title,
      taskId: taskId,
      note: note,
    );
  }

  Future<Map<String, dynamic>> rejectSegment({
    required String segmentId,
    String? reason,
  }) {
    return _activityUnderstanding.rejectSegment(
      segmentId: segmentId,
      reason: reason,
    );
  }
}
