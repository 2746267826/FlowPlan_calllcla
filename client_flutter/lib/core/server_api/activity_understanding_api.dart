import 'api_client.dart';

class ActivityUnderstandingApi {
  ActivityUnderstandingApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> buildSegments({
    required DateTime date,
    bool includeTrackedInputEvents = true,
    bool includeRawActivityLogs = true,
    bool includeActivityRecords = true,
  }) {
    return _apiClient.postJson(
      '/activity-understanding/build-segments',
      body: <String, Object?>{
        'date': date.toIso8601String(),
        'includeTrackedInputEvents': includeTrackedInputEvents,
        'includeRawActivityLogs': includeRawActivityLogs,
        'includeActivityRecords': includeActivityRecords,
      },
    );
  }

  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/activity-understanding/segments',
      query: <String, String>{
        if (startAt != null) 'startAt': startAt.toIso8601String(),
        if (endAt != null) 'endAt': endAt.toIso8601String(),
        if (status != null) 'status': status,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> confirmSegment({
    required String segmentId,
    String? title,
    String? taskId,
    String? note,
  }) {
    return _apiClient.postJson(
      '/activity-understanding/segments/$segmentId/confirm',
      body: <String, Object?>{
        'title': title,
        'taskId': taskId,
        'note': note,
      },
    );
  }

  Future<Map<String, dynamic>> rejectSegment({
    required String segmentId,
    String? reason,
  }) {
    return _apiClient.postJson(
      '/activity-understanding/segments/$segmentId/reject',
      body: <String, Object?>{
        'reason': reason,
      },
    );
  }
}
