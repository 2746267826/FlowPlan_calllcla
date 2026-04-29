import 'api_client.dart';

class AiPolicyApi {
  AiPolicyApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> toolPolicies() {
    return _apiClient.getJson('/ai/tool-policies');
  }

  Future<Map<String, dynamic>> upsertToolPolicy({
    required String toolName,
    String permissionLevel = 'draft_only',
    String riskLevel = 'low',
    List<String> allowedScopes = const <String>[],
    List<String> deniedScopes = const <String>[],
    bool requiresConfirmation = true,
    bool requiresSecondConfirm = false,
  }) {
    return _apiClient.patchJson(
      '/ai/tool-policies/$toolName',
      body: <String, Object?>{
        'permissionLevel': permissionLevel,
        'riskLevel': riskLevel,
        'allowedScopes': allowedScopes,
        'deniedScopes': deniedScopes,
        'requiresConfirmation': requiresConfirmation,
        'requiresSecondConfirm': requiresSecondConfirm,
      },
    );
  }

  Future<Map<String, dynamic>> createContextSnapshot({
    String? conversationId,
    String contextType = 'mixed',
    Map<String, Object?> sensitivePolicy = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/ai/context/snapshots',
      body: <String, Object?>{
        'conversationId': conversationId,
        'contextType': contextType,
        'sensitivePolicy': sensitivePolicy,
      },
    );
  }
}
