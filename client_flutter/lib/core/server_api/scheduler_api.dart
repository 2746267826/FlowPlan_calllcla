import 'api_client.dart';

class SchedulerApi {
  SchedulerApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> createDraftRun({
    required DateTime startAt,
    required DateTime endAt,
    int defaultTaskMinutes = 60,
    String strategy = 'balanced',
  }) {
    return _apiClient.postJson(
      '/scheduler/runs',
      body: <String, Object?>{
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'defaultTaskMinutes': defaultTaskMinutes,
        'strategy': strategy,
      },
    );
  }

  Future<Map<String, dynamic>> run(String runId) {
    return _apiClient.getJson('/scheduler/runs/$runId');
  }

  Future<Map<String, dynamic>> acceptRun({
    required String runId,
    String? note,
  }) {
    return _apiClient.postJson(
      '/scheduler/runs/$runId/accept',
      body: <String, Object?>{
        'note': note,
      },
    );
  }

  Future<Map<String, dynamic>> rejectRun({
    required String runId,
    String? reason,
  }) {
    return _apiClient.postJson(
      '/scheduler/runs/$runId/reject',
      body: <String, Object?>{
        'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> detectDeviations({
    DateTime? startAt,
    DateTime? endAt,
  }) {
    return _apiClient.postJson(
      '/scheduler/deviations/detect',
      body: <String, Object?>{
        if (startAt != null) 'startAt': startAt.toIso8601String(),
        if (endAt != null) 'endAt': endAt.toIso8601String(),
      },
    );
  }
}
