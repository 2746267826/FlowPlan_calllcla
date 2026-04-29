import 'api_client.dart';

class ModelsApi {
  const ModelsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> models() => _apiClient.getJson('/models');

  Future<Map<String, dynamic>> llmHealth() => _apiClient.getJson('/models/llm/health');

  Future<Map<String, dynamic>> versions(String modelKey) =>
      _apiClient.getJson('/models/$modelKey/versions');

  Future<Map<String, dynamic>> runs(
    String modelKey, {
    String? status,
    int limit = 80,
  }) {
    final query = <String, String>{
      'limit': limit.toString(),
      if (status != null) 'status': status,
    };
    return _apiClient.getJson('/models/$modelKey/runs', query: query);
  }

  Future<Map<String, dynamic>> feedback({
    required String modelKey,
    required String targetType,
    required String targetId,
    required String feedbackType,
    Map<String, dynamic> feedbackPayload = const {},
    String? modelRunId,
    String source = 'client',
  }) {
    return _apiClient.postJson(
      '/models/$modelKey/feedback',
      body: {
        'targetType': targetType,
        'targetId': targetId,
        'feedbackType': feedbackType,
        'outcome': feedbackType,
        'source': source,
        'feedbackPayload': feedbackPayload,
        if (modelRunId != null) 'modelRunId': modelRunId,
      },
    );
  }

  Future<Map<String, dynamic>> learn(
    String modelKey, {
    bool autoActivate = true,
  }) {
    return _apiClient.postJson(
      '/models/$modelKey/learn',
      body: {'autoActivate': autoActivate},
    );
  }
}
