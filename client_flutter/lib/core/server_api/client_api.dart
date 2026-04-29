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
}
