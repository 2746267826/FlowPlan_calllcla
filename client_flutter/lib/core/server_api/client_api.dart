import 'api_client.dart';

class ClientApi {
  ClientApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> bootstrap() {
    return _apiClient.getJson('/client/bootstrap');
  }

  Future<Map<String, dynamic>> settings() {
    return _apiClient.getJson('/client/settings');
  }

  Future<Map<String, dynamic>> settingsPolicy() {
    return _apiClient.getJson('/client/settings-policy');
  }

  Future<Map<String, dynamic>> effectiveSettings() {
    return _apiClient.getJson('/client/settings/effective');
  }

  Future<Map<String, dynamic>> tasks({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) {
    return _apiClient.getJson(
      '/client/tasks',
      query: _query(<String, String?>{
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
        'q': q,
        'limit': limit?.toString(),
      }),
    );
  }

  Future<Map<String, dynamic>> createTask(Map<String, Object?> payload) {
    return _apiClient.postJson('/client/tasks', body: payload);
  }

  Future<Map<String, dynamic>> updateTask({
    required String id,
    required Map<String, Object?> patch,
  }) {
    return _apiClient.patchJson(
      '/client/tasks/${Uri.encodeComponent(id)}',
      body: patch,
    );
  }

  Future<Map<String, dynamic>> completeTask({
    required String id,
    Map<String, Object?> body = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/client/tasks/${Uri.encodeComponent(id)}/complete',
      body: body,
    );
  }

  Future<Map<String, dynamic>> deleteTask(String id) {
    return _apiClient.deleteJson('/client/tasks/${Uri.encodeComponent(id)}');
  }

  Future<Map<String, dynamic>> events({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) {
    return _apiClient.getJson(
      '/client/events',
      query: _query(<String, String?>{
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
        'q': q,
        'limit': limit?.toString(),
      }),
    );
  }

  Future<Map<String, dynamic>> createEvent(Map<String, Object?> payload) {
    return _apiClient.postJson('/client/events', body: payload);
  }

  Future<Map<String, dynamic>> updateEvent({
    required String id,
    required Map<String, Object?> patch,
  }) {
    return _apiClient.patchJson(
      '/client/events/${Uri.encodeComponent(id)}',
      body: patch,
    );
  }

  Future<Map<String, dynamic>> deleteEvent(String id) {
    return _apiClient.deleteJson('/client/events/${Uri.encodeComponent(id)}');
  }

  Future<Map<String, dynamic>> actualRecords({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) {
    return _apiClient.getJson(
      '/client/actual-records',
      query: _query(<String, String?>{
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
        'limit': limit?.toString(),
      }),
    );
  }

  Future<Map<String, dynamic>> pushMutations({
    required String clientBatchId,
    required List<Map<String, Object?>> mutations,
    String? deviceId,
  }) {
    return _apiClient.postJson(
      '/client/mutations',
      body: <String, Object?>{
        'clientBatchId': clientBatchId,
        if (deviceId != null) 'deviceId': deviceId,
        'mutations': mutations,
      },
    );
  }

  Future<Map<String, dynamic>> heartbeat({
    required String deviceId,
    required Map<String, Object?> body,
  }) {
    return _apiClient.postJson(
      '/devices/${Uri.encodeComponent(deviceId)}/heartbeat',
      body: body,
    );
  }

  Future<Map<String, dynamic>> updateSetting({
    required String key,
    required Map<String, Object?> value,
    String scope = 'user.preference',
    bool isSensitive = false,
    String? description,
  }) {
    return _apiClient.patchJson(
      '/client/settings/${Uri.encodeComponent(key)}',
      body: <String, Object?>{
        'value': value,
        'scope': scope,
        'isSensitive': isSensitive,
        if (description != null) 'description': description,
      },
    );
  }

  Future<Map<String, dynamic>> createLocalSnapshotImport(
    Map<String, Object?> snapshot,
  ) {
    return _apiClient.postJson(
      '/client/import/local-snapshot',
      body: <String, Object?>{
        'snapshot': snapshot,
      },
    );
  }

  Future<Map<String, dynamic>> importStatus(String importId) {
    return _apiClient.getJson('/client/import/${Uri.encodeComponent(importId)}');
  }

  Future<Map<String, dynamic>> confirmImport(String importId) {
    return _apiClient.postJson(
      '/client/import/${Uri.encodeComponent(importId)}/confirm',
    );
  }

  Future<Map<String, dynamic>> cancelImport(
    String importId, {
    String? reason,
  }) {
    return _apiClient.postJson(
      '/client/import/${Uri.encodeComponent(importId)}/cancel',
      body: <String, Object?>{
        if (reason != null) 'reason': reason,
      },
    );
  }

  Map<String, String>? _query(Map<String, String?> values) {
    final result = <String, String>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value != null && value.trim().isNotEmpty) {
        result[entry.key] = value;
      }
    }
    return result.isEmpty ? null : result;
  }
}
