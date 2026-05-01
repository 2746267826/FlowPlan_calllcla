import '../server_api/scheduler_api.dart';

class SchedulerServerFirstStore {
  SchedulerServerFirstStore(this._api);

  final SchedulerApi _api;

  Future<Map<String, dynamic>> createDraftRun({
    required DateTime startAt,
    required DateTime endAt,
    int defaultTaskMinutes = 60,
    String strategy = 'balanced',
  }) {
    return _api.createDraftRun(
      startAt: startAt,
      endAt: endAt,
      defaultTaskMinutes: defaultTaskMinutes,
      strategy: strategy,
    );
  }

  Future<Map<String, dynamic>> run(String runId) {
    return _api.run(runId);
  }

  Future<Map<String, dynamic>> acceptRun({
    required String runId,
    String? note,
  }) {
    return _api.acceptRun(runId: runId, note: note);
  }

  Future<Map<String, dynamic>> rejectRun({
    required String runId,
    String? reason,
  }) {
    return _api.rejectRun(runId: runId, reason: reason);
  }

  Future<Map<String, dynamic>> detectDeviations({
    DateTime? startAt,
    DateTime? endAt,
  }) {
    return _api.detectDeviations(startAt: startAt, endAt: endAt);
  }
}
