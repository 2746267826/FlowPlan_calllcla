import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';

class FileCloudApi {
  FileCloudApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> dashboard() {
    return _apiClient.getJson('/files/dashboard');
  }

  Future<Map<String, dynamic>> providers() {
    return _apiClient.getJson('/files/providers');
  }

  Future<Map<String, dynamic>> upsertProvider(
    String providerKey, {
    required String providerType,
    required String displayName,
    int priority = 100,
    String status = 'enabled',
    String syncMode = 'manual',
    String? rootRemoteId,
    String? localMirrorPath,
    String? mobileDownloadRoot,
    Map<String, Object?> capabilities = const <String, Object?>{},
    Map<String, Object?> config = const <String, Object?>{},
  }) {
    return _apiClient.patchJson(
      '/files/providers/$providerKey',
      body: <String, Object?>{
        'providerType': providerType,
        'displayName': displayName,
        'priority': priority,
        'status': status,
        'syncMode': syncMode,
        'rootRemoteId': rootRemoteId,
        'localMirrorPath': localMirrorPath,
        'mobileDownloadRoot': mobileDownloadRoot,
        'capabilities': capabilities,
        'config': config,
      },
    );
  }

  Future<Map<String, dynamic>> applyTreeSnapshot({
    required String providerKey,
    required String treeRevision,
    required List<Map<String, Object?>> nodes,
    bool markMissing = false,
  }) {
    return _apiClient.postJson(
      '/files/tree/snapshot',
      body: <String, Object?>{
        'providerKey': providerKey,
        'treeRevision': treeRevision,
        'nodes': nodes,
        'markMissing': markMissing,
      },
    );
  }

  Future<Map<String, dynamic>> tree({
    String? providerKey,
    String? parentRemoteId,
    String? query,
    int limit = 300,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/files/tree',
      query: <String, String>{
        if (providerKey != null) 'providerKey': providerKey,
        if (parentRemoteId != null) 'parentRemoteId': parentRemoteId,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> createUploadSession({
    required String fileName,
    required int totalBytes,
    String providerKey = 'server_storage',
    int chunkSize = 5 * 1024 * 1024,
    String? checksum,
    String? objectKey,
    String? localPath,
    String? remoteId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/upload-sessions',
      body: <String, Object?>{
        'providerKey': providerKey,
        'fileName': fileName,
        'totalBytes': totalBytes,
        'chunkSize': chunkSize,
        'checksum': checksum,
        'objectKey': objectKey,
        'localPath': localPath,
        'remoteId': remoteId,
        'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required int startByte,
    required Uint8List bytes,
    String? checksum,
  }) {
    return _apiClient.putJson(
      '/files/upload-sessions/$sessionId/chunks/$chunkIndex',
      body: <String, Object?>{
        'startByte': startByte,
        'endByte': startByte + bytes.length - 1,
        'payloadBase64': base64Encode(bytes),
        'checksum': checksum,
      },
    );
  }

  Future<Map<String, dynamic>> missingUploadChunks(String sessionId) {
    return _apiClient.getJson(
      '/files/upload-sessions/$sessionId/missing-chunks',
    );
  }

  Future<Map<String, dynamic>> completeUploadSession(String sessionId) {
    return _apiClient.postJson('/files/upload-sessions/$sessionId/complete');
  }

  Future<Map<String, dynamic>> createDownloadSession({
    String? storageObjectId,
    String? providerKey,
    String? fileName,
    String? remoteId,
    String? localPath,
    int? totalBytes,
    int? chunkSize,
    String? checksum,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/download-sessions',
      body: <String, Object?>{
        'storageObjectId': storageObjectId,
        'providerKey': providerKey,
        'fileName': fileName,
        'remoteId': remoteId,
        'localPath': localPath,
        'totalBytes': totalBytes,
        'chunkSize': chunkSize,
        'checksum': checksum,
        'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> downloadRange({
    required String sessionId,
    required int start,
    required int end,
  }) {
    return _apiClient.getJson(
      '/files/download-sessions/$sessionId/range',
      query: <String, String>{
        'start': start.toString(),
        'end': end.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> transfers({
    String? direction,
    String? status,
    int limit = 100,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/files/transfers',
      query: <String, String>{
        if (direction != null) 'direction': direction,
        if (status != null) 'status': status,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> transferProgress(String sessionId) {
    return _apiClient.getJson('/files/transfers/$sessionId/progress');
  }

  Future<Map<String, dynamic>> upsertNetworkPresence({
    String networkType = 'unknown',
    String? wifiSsidHash,
    String? localIp,
    int? localPort,
    String? publicIpHash,
    String natType = 'unknown',
    int ttlMinutes = 10,
    Map<String, Object?> capabilities = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/network-presence',
      body: <String, Object?>{
        'networkType': networkType,
        'wifiSsidHash': wifiSsidHash,
        'localIp': localIp,
        'localPort': localPort,
        'publicIpHash': publicIpHash,
        'natType': natType,
        'ttlMinutes': ttlMinutes,
        'capabilities': capabilities,
      },
    );
  }

  Future<Map<String, dynamic>> networkPresence() {
    return _apiClient.getJson('/files/network-presence');
  }

  Future<Map<String, dynamic>> transferCandidates(String sessionId) {
    return _apiClient.getJson('/files/transfers/$sessionId/candidates');
  }

  Future<Map<String, dynamic>> upsertTransferCandidate({
    required String sessionId,
    String candidateType = 'lan_hint',
    String protocol = 'server_api',
    String? sourceAddress,
    int? sourcePort,
    String? targetAddress,
    int? targetPort,
    int priority = 100,
    String status = 'pending',
    int? latencyMs,
    int? bandwidthEstimate,
    String? failureReason,
  }) {
    return _apiClient.postJson(
      '/files/transfers/$sessionId/candidates',
      body: <String, Object?>{
        'candidateType': candidateType,
        'protocol': protocol,
        'sourceAddress': sourceAddress,
        'sourcePort': sourcePort,
        'targetAddress': targetAddress,
        'targetPort': targetPort,
        'priority': priority,
        'status': status,
        'latencyMs': latencyMs,
        'bandwidthEstimate': bandwidthEstimate,
        'failureReason': failureReason,
      },
    );
  }

  Future<Map<String, dynamic>> appendTransferEvent({
    required String sessionId,
    required String eventType,
    String? message,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/transfers/$sessionId/events',
      body: <String, Object?>{
        'eventType': eventType,
        'message': message,
        'payload': payload,
      },
    );
  }

  Future<Map<String, dynamic>> storageStatus() {
    return _apiClient.getJson('/files/storage/status');
  }

  Future<Map<String, dynamic>> storageObjects({
    String? localPath,
    String? nodeId,
    int limit = 100,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/files/storage/objects',
      query: <String, String>{
        if (localPath != null && localPath.trim().isNotEmpty)
          'localPath': localPath.trim(),
        if (nodeId != null && nodeId.trim().isNotEmpty) 'nodeId': nodeId.trim(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> registerStorageObject({
    required String localPath,
    String? fileName,
    String? objectKey,
    String? fileNodeId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/files/storage/register',
      body: <String, Object?>{
        'localPath': localPath,
        'fileName': fileName,
        'objectKey': objectKey,
        'fileNodeId': fileNodeId,
        'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> createKopiaSnapshot({
    required String rootPath,
    String? rootId,
  }) {
    return _apiClient.postJson(
      '/files/kopia/snapshots',
      body: <String, Object?>{
        'rootPath': rootPath,
        'rootId': rootId,
      },
    );
  }

  Future<Map<String, dynamic>> refreshKopiaVersions({
    required String fileId,
    required String filePath,
    String? displayName,
  }) {
    return _apiClient.postJson(
      '/files/kopia/versions/refresh',
      body: <String, Object?>{
        'fileId': fileId,
        'filePath': filePath,
        'displayName': displayName,
      },
    );
  }

  Future<Map<String, dynamic>> versions(String fileId) {
    return _apiClient.getJson('/files/versions/$fileId');
  }

  Future<Map<String, dynamic>> createVersionDownloadRequest({
    required String versionId,
    String targetMode = 'download_copy',
    String? targetPath,
    String? auditNote,
  }) {
    return _apiClient.postJson(
      '/files/versions/$versionId/download-requests',
      body: <String, Object?>{
        'targetMode': targetMode,
        'targetPath': targetPath,
        'auditNote': auditNote,
      },
    );
  }

  Future<Map<String, dynamic>> downloadVersionCopy({
    required String versionId,
    required String targetPath,
    String? auditNote,
  }) {
    return _apiClient.postJson(
      '/files/versions/$versionId/download-copy',
      body: <String, Object?>{
        'targetPath': targetPath,
        'auditNote': auditNote,
      },
    );
  }

  Future<Map<String, dynamic>> prepareVersionRestore({
    required String versionId,
    String? targetPath,
  }) {
    return _apiClient.postJson(
      '/files/versions/$versionId/restore-prepare',
      body: <String, Object?>{
        'targetPath': targetPath,
      },
    );
  }

  Future<Map<String, dynamic>> conflicts() {
    return _apiClient.getJson('/files/conflicts');
  }

  Future<Map<String, dynamic>> createConflict({
    String? fileUid,
    required String path,
    required String providerA,
    required String providerB,
    required Map<String, Object?> versionA,
    required Map<String, Object?> versionB,
    String reason = 'provider_version_mismatch',
  }) {
    return _apiClient.postJson(
      '/files/conflicts',
      body: <String, Object?>{
        'fileUid': fileUid,
        'path': path,
        'providerA': providerA,
        'providerB': providerB,
        'versionA': versionA,
        'versionB': versionB,
        'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> resolveConflict({
    required String conflictId,
    required Map<String, Object?> resolution,
  }) {
    return _apiClient.postJson(
      '/files/conflicts/$conflictId/resolve',
      body: <String, Object?>{
        'resolution': resolution,
      },
    );
  }
}
