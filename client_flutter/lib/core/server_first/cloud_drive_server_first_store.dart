import '../server_api/file_context_api.dart';

class CloudDriveServerFirstStore {
  CloudDriveServerFirstStore(this._api);

  final FileContextApi _api;

  Future<Map<String, dynamic>> roots({String? query}) {
    return _api.driveRoots(query: query);
  }

  Future<Map<String, dynamic>> nodes({
    String? rootId,
    String? parentId,
    String? query,
    int limit = 300,
    int offset = 0,
  }) {
    return _api.driveNodes(
      rootId: rootId,
      parentId: parentId,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> node(String nodeId) {
    return _api.driveNode(nodeId);
  }

  Future<Map<String, dynamic>> openPlan({
    required String nodeId,
    Map<String, Object?> localIdentity = const <String, Object?>{},
  }) {
    return _api.openPlan(nodeId: nodeId, localIdentity: localIdentity);
  }

  Future<Map<String, dynamic>> registerDeviceLocation({
    required String nodeId,
    required String localPath,
    String availability = 'available',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _api.upsertDeviceLocation(
      nodeId: nodeId,
      localPath: localPath,
      availability: availability,
      metadata: metadata,
    );
  }

  Future<Map<String, dynamic>> requestDownload({
    required String nodeId,
    String? targetPath,
  }) {
    return _api.createDownloadRequest(nodeId: nodeId, targetPath: targetPath);
  }

  Future<Map<String, dynamic>> relink({
    required String nodeId,
    required String localPath,
    String? reason,
    Map<String, Object?> identity = const <String, Object?>{},
  }) {
    return _api.relinkNode(
      nodeId: nodeId,
      localPath: localPath,
      reason: reason,
      identity: identity,
    );
  }

  Future<Map<String, dynamic>> logOperation({
    required String nodeId,
    required String operation,
    String status = 'success',
    String? sourcePath,
    String? targetPath,
    String? errorMessage,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _api.logNodeOperation(
      nodeId: nodeId,
      operation: operation,
      status: status,
      sourcePath: sourcePath,
      targetPath: targetPath,
      errorMessage: errorMessage,
      metadata: metadata,
    );
  }
}
