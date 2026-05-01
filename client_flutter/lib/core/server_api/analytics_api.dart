import 'api_client.dart';

class AnalyticsApi {
  AnalyticsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> activityHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    int? taskId,
  }) {
    return _apiClient.getJson(
      '/analytics/activity-heatmap',
      query: _rangeQuery(
        start: start,
        end: end,
        bucket: bucket,
        processName: processName,
        category: category,
        taskId: taskId,
      ),
    );
  }

  Future<Map<String, dynamic>> trackerHome({
    DateTime? date,
  }) {
    return _apiClient.getJson(
      '/analytics/tracker-home',
      query: {
        if (date != null) 'date': _dateOnly(date),
      },
    );
  }

  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) {
    return _apiClient.getJson(
      '/analytics/activity-day-summary',
      query: {'date': _dateOnly(date)},
    );
  }

  Future<Map<String, dynamic>> rangeAnalysis({
    required DateTime start,
    required DateTime end,
    String bucket = 'day',
  }) {
    return _apiClient.getJson(
      '/analytics/range-analysis',
      query: _rangeQuery(start: start, end: end, bucket: bucket),
    );
  }

  Future<Map<String, dynamic>> filterOptions({
    DateTime? start,
    DateTime? end,
  }) {
    return _apiClient.getJson(
      '/analytics/filter-options',
      query: _rangeQuery(start: start, end: end),
    );
  }

  Future<Map<String, dynamic>> inputHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    String? eventKind,
  }) {
    return _apiClient.getJson(
      '/analytics/input-heatmap',
      query: _rangeQuery(
        start: start,
        end: end,
        bucket: bucket,
        processName: processName,
        category: category,
        eventKind: eventKind,
      ),
    );
  }

  Future<Map<String, dynamic>> activityRangeSummary({
    DateTime? start,
    DateTime? end,
  }) {
    return _apiClient.getJson(
      '/analytics/activity-range-summary',
      query: _rangeQuery(start: start, end: end),
    );
  }

  Future<Map<String, dynamic>> topApps({
    DateTime? start,
    DateTime? end,
    int limit = 20,
  }) {
    return _apiClient.getJson(
      '/analytics/top-apps',
      query: _rangeQuery(start: start, end: end, limit: limit),
    );
  }

  Future<Map<String, dynamic>> topCategories({
    DateTime? start,
    DateTime? end,
    int limit = 20,
  }) {
    return _apiClient.getJson(
      '/analytics/top-categories',
      query: _rangeQuery(start: start, end: end, limit: limit),
    );
  }

  Future<Map<String, dynamic>> taskWorkSummary({
    DateTime? start,
    DateTime? end,
    int? taskId,
    int limit = 50,
  }) {
    return _apiClient.getJson(
      '/analytics/task-work-summary',
      query: _rangeQuery(
        start: start,
        end: end,
        taskId: taskId,
        limit: limit,
      ),
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
    return _apiClient.getJson(
      '/analytics/activity-records',
      query: _rangeQuery(
        start: start,
        end: end,
        processName: processName,
        category: category,
        taskId: taskId,
        limit: limit,
        offset: offset,
      ),
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
    return _apiClient.getJson(
      '/analytics/input-events',
      query: _rangeQuery(
        start: start,
        end: end,
        processName: processName,
        category: category,
        eventKind: eventKind,
        limit: limit,
        offset: offset,
      ),
    );
  }

  Future<Map<String, dynamic>> focusTrends({
    DateTime? start,
    DateTime? end,
  }) {
    return _apiClient.getJson(
      '/analytics/focus-trends',
      query: _rangeQuery(start: start, end: end),
    );
  }

  Map<String, String> _rangeQuery({
    DateTime? start,
    DateTime? end,
    String? bucket,
    String? processName,
    String? category,
    String? eventKind,
    int? taskId,
    int? limit,
    int? offset,
  }) {
    return {
      if (start != null) 'start': start.toIso8601String(),
      if (end != null) 'end': end.toIso8601String(),
      if (bucket != null && bucket.trim().isNotEmpty) 'bucket': bucket,
      if (processName != null && processName.trim().isNotEmpty)
        'processName': processName.trim(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
      if (eventKind != null && eventKind.trim().isNotEmpty)
        'eventKind': eventKind.trim(),
      if (taskId != null) 'taskId': taskId.toString(),
      if (limit != null) 'limit': limit.toString(),
      if (offset != null) 'offset': offset.toString(),
    };
  }

  String _dateOnly(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
