import '../server_api/activity_understanding_api.dart';

class ActivityUnderstandingServerFirstStore {
  ActivityUnderstandingServerFirstStore(this._api);

  final ActivityUnderstandingApi _api;

  Future<Map<String, dynamic>> buildSegments({
    required DateTime date,
    bool includeTrackedInputEvents = true,
    bool includeRawActivityLogs = true,
    bool includeActivityRecords = true,
  }) {
    return _api.buildSegments(
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
    return _api.segments(
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
    return _api.confirmSegment(
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
    return _api.rejectSegment(segmentId: segmentId, reason: reason);
  }

  Future<Map<String, dynamic>> sendFeedback({
    required String segmentId,
    String feedbackType = 'modified',
    String? outcome,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    return _api.sendFeedback(
      segmentId: segmentId,
      feedbackType: feedbackType,
      outcome: outcome,
      payload: payload,
    );
  }
}
