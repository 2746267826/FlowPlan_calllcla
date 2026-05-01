import 'api_client.dart';

class AiApi {
  AiApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> settings() {
    return _apiClient.getJson('/ai/settings');
  }

  Future<Map<String, dynamic>> upsertProvider({
    required String providerKey,
    String providerType = 'openai_compatible',
    required String displayName,
    required String baseUrl,
    required String model,
    String? apiKey,
    String status = 'enabled',
    double temperature = 0.2,
    int maxOutputTokens = 1600,
    bool isDefault = true,
    Map<String, Object?> options = const <String, Object?>{},
  }) {
    return _apiClient.patchJson(
      '/ai/settings/$providerKey',
      body: <String, Object?>{
        'providerType': providerType,
        'displayName': displayName,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
        'status': status,
        'temperature': temperature,
        'maxOutputTokens': maxOutputTokens,
        'isDefault': isDefault,
        'options': options,
      },
    );
  }

  Future<Map<String, dynamic>> testProvider(String providerKey) {
    return _apiClient.postJson('/ai/settings/$providerKey/test');
  }

  Future<Map<String, dynamic>> context() {
    return _apiClient.getJson('/ai/context');
  }

  Future<Map<String, dynamic>> conversations({
    String? status,
    int limit = 50,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/ai/conversations',
      query: <String, String>{
        if (status != null) 'status': status,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> createConversation({
    String title = 'AI 对话',
    String source = 'flowplanv2',
    String? providerKey,
    String? model,
    Map<String, Object?> contextScope = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/ai/conversations',
      body: <String, Object?>{
        'title': title,
        'source': source,
        'providerKey': providerKey,
        'model': model,
        'contextScope': contextScope,
      },
    );
  }

  Future<Map<String, dynamic>> messages(String conversationId) {
    return _apiClient.getJson('/ai/conversations/$conversationId/messages');
  }

  Future<Map<String, dynamic>> sendMessage({
    String? conversationId,
    required String content,
    String source = 'flowplanv2',
    String? providerKey,
    String? model,
    String? title,
    Map<String, Object?> contextScope = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/ai/messages',
      body: <String, Object?>{
        'conversationId': conversationId,
        'content': content,
        'source': source,
        'providerKey': providerKey,
        'model': model,
        'title': title,
        'contextScope': contextScope,
      },
    );
  }

  Future<Map<String, dynamic>> toolDrafts({
    String? status,
    int limit = 80,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/ai/tool-drafts',
      query: <String, String>{
        if (status != null) 'status': status,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> reviewDraft({
    required String draftId,
    required String status,
    String? reviewNote,
  }) {
    return _apiClient.patchJson(
      '/ai/tool-drafts/$draftId',
      body: <String, Object?>{
        'status': status,
        'reviewNote': reviewNote,
      },
    );
  }

  Future<Map<String, dynamic>> confirmDraft({
    required String draftId,
    String reviewNote = '用户确认执行',
  }) {
    return _apiClient.postJson(
      '/ai/tool-drafts/$draftId/confirm',
      body: <String, Object?>{
        'reviewNote': reviewNote,
      },
    );
  }
}
