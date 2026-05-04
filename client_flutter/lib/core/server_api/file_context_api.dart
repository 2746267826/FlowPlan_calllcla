import 'api_client.dart';

class FileContextApi {
  FileContextApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> roots({String? query}) {
    return _apiClient.getJson(
      '/files/roots',
      query: <String, String>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> driveRoots({String? query}) {
    return _apiClient.getJson(
      '/files/drive/roots',
      query: <String, String>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> upsertRoot({
    String? rootUid,
    required String name,
    required String rootUri,
    String providerType = 'server_storage',
    String? rootDisplayPath,
    bool isManaged = false,
    String syncPolicy = 'metadata_only',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/roots',
      body: <String, Object?>{
        'rootUid': rootUid,
        'name': name,
        'rootUri': rootUri,
        'providerType': providerType,
        'rootDisplayPath': rootDisplayPath,
        'isManaged': isManaged,
        'syncPolicy': syncPolicy,
        'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> nodes({
    String? rootId,
    String? parentId,
    String? query,
    int limit = 300,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/files/nodes',
      query: <String, String>{
        if (rootId != null) 'rootId': rootId,
        if (parentId != null) 'parentId': parentId,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> driveNodes({
    String? rootId,
    String? parentId,
    String? query,
    int limit = 300,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/files/drive/nodes',
      query: <String, String>{
        if (rootId != null && rootId.trim().isNotEmpty) 'rootId': rootId,
        if (parentId != null && parentId.trim().isNotEmpty) 'parentId': parentId,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> driveNode(String nodeId) {
    return _apiClient.getJson('/files/drive/nodes/$nodeId');
  }

  Future<Map<String, dynamic>> openPlan({
    required String nodeId,
    Map<String, Object?> localIdentity = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/drive/nodes/$nodeId/open-plan',
      body: <String, Object?>{
        'localIdentity': localIdentity,
      },
    );
  }

  Future<Map<String, dynamic>> upsertDeviceLocation({
    required String nodeId,
    required String localPath,
    String availability = 'available',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/drive/nodes/$nodeId/device-location',
      body: <String, Object?>{
        'localPath': localPath,
        'availability': availability,
        'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> createDownloadRequest({
    required String nodeId,
    String? targetPath,
  }) {
    return _apiClient.postJson(
      '/files/drive/nodes/$nodeId/download-request',
      body: <String, Object?>{
        'targetPath': targetPath,
      },
    );
  }

  Future<Map<String, dynamic>> scanDriveRoot({
    required String rootId,
    String? rootPath,
    int maxNodes = 0,
  }) {
    return _apiClient.postJson(
      '/files/drive/roots/$rootId/scan',
      body: <String, Object?>{
        'rootPath': rootPath,
        'maxNodes': maxNodes,
      },
    );
  }

  Future<Map<String, dynamic>> deleteDriveRoot({
    required String rootId,
  }) {
    return _apiClient.deleteJson(
      '/files/drive/roots/${Uri.encodeComponent(rootId)}',
    );
  }

  Future<Map<String, dynamic>> relinkNode({
    required String nodeId,
    required String localPath,
    String? reason,
    Map<String, Object?> identity = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/drive/nodes/$nodeId/relink',
      body: <String, Object?>{
        'localPath': localPath,
        'reason': reason,
        'identity': identity,
      },
    );
  }

  Future<Map<String, dynamic>> applyNodeSnapshot({
    required String rootId,
    required List<Map<String, Object?>> nodes,
    String scanStatus = 'completed',
  }) {
    return _apiClient.postJson(
      '/files/nodes/snapshot',
      body: <String, Object?>{
        'rootId': rootId,
        'nodes': nodes,
        'scanStatus': scanStatus,
      },
    );
  }

  Future<Map<String, dynamic>> linkNodeToEntity({
    required String nodeId,
    required String entityType,
    required String entityId,
    String relationType = 'manual',
    double confidence = 1,
    String? reason,
  }) {
    return _apiClient.postJson(
      '/files/context-links',
      body: <String, Object?>{
        'nodeId': nodeId,
        'entityType': entityType,
        'entityId': entityId,
        'relationType': relationType,
        'confidence': confidence,
        'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> logNodeOperation({
    required String nodeId,
    required String operation,
    String status = 'success',
    String? sourcePath,
    String? targetPath,
    String? errorMessage,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/nodes/$nodeId/log',
      body: <String, Object?>{
        'operation': operation,
        'status': status,
        'sourcePath': sourcePath,
        'targetPath': targetPath,
        'errorMessage': errorMessage,
        'metadata': metadata,
      },
    );
  }
}
