import 'dart:convert';
import 'dart:typed_data';

import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('file cloud API forwards every command to the expected endpoint',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <_CapturedRequest>[];
    final api = FileCloudApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(_CapturedRequest.from(request));
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );

    await api.dashboard();
    await api.providers();
    await api.upsertProvider(
      'local drive',
      providerType: 'local',
      displayName: 'Local Drive',
      priority: 7,
      status: 'paused',
      syncMode: 'mirror',
      rootRemoteId: 'root-1',
      localMirrorPath: r'C:\mirror',
      mobileDownloadRoot: '/downloads',
      capabilities: const <String, Object?>{'download': true},
      config: const <String, Object?>{'region': 'local'},
    );
    await api.applyTreeSnapshot(
      providerKey: 'drive',
      treeRevision: 'rev-1',
      markMissing: true,
      nodes: const <Map<String, Object?>>[
        <String, Object?>{'remoteId': 'node-1'},
      ],
    );
    await api.tree(
      providerKey: 'drive',
      parentRemoteId: 'parent-1',
      query: '  invoice  ',
      limit: 12,
      offset: 3,
    );
    await api.tree(query: '   ');
    await api.createUploadSession(
      fileName: 'plan.txt',
      totalBytes: 42,
      providerKey: 'drive',
      chunkSize: 8,
      checksum: 'sha',
      objectKey: 'object-1',
      localPath: r'C:\plan.txt',
      remoteId: 'remote-1',
      metadata: const <String, Object?>{'taskId': 'task-1'},
    );
    await api.uploadChunk(
      sessionId: 'session 1',
      chunkIndex: 2,
      startByte: 8,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      checksum: 'chunk-sha',
    );
    await api.missingUploadChunks('session 1');
    await api.completeUploadSession('session 1');
    await api.createDownloadSession(
      storageObjectId: 'object-1',
      providerKey: 'drive',
      fileName: 'plan.txt',
      remoteId: 'remote-1',
      localPath: r'C:\plan.txt',
      totalBytes: 42,
      chunkSize: 8,
      checksum: 'sha',
      metadata: const <String, Object?>{'source': 'test'},
    );
    await api.downloadRange(sessionId: 'session 1', start: 4, end: 9);
    await api.transfers(direction: 'upload', status: 'failed', limit: 9);
    await api.transfers();
    await api.transferProgress('session 1');
    await api.upsertNetworkPresence(
      networkType: 'wifi',
      wifiSsidHash: 'ssid',
      localIp: '127.0.0.1',
      localPort: 8282,
      publicIpHash: 'public',
      natType: 'open',
      ttlMinutes: 30,
      capabilities: const <String, Object?>{'lan': true},
    );
    await api.networkPresence();
    await api.transferCandidates('session 1');
    await api.upsertTransferCandidate(
      sessionId: 'session 1',
      candidateType: 'relay',
      protocol: 'https',
      sourceAddress: 'a',
      sourcePort: 1,
      targetAddress: 'b',
      targetPort: 2,
      priority: 3,
      status: 'ready',
      latencyMs: 4,
      bandwidthEstimate: 5,
      failureReason: 'none',
    );
    await api.appendTransferEvent(
      sessionId: 'session 1',
      eventType: 'retry',
      message: 'Retrying',
      payload: const <String, Object?>{'attempt': 2},
    );
    await api.storageStatus();
    await api.storageObjects(
      localPath: '  C:/plan.txt  ',
      nodeId: ' node-1 ',
      limit: 8,
      offset: 2,
    );
    await api.storageObjects(localPath: ' ', nodeId: ' ');
    await api.registerStorageObject(
      localPath: r'C:\plan.txt',
      fileName: 'plan.txt',
      objectKey: 'object-1',
      fileNodeId: 'node-1',
      metadata: const <String, Object?>{'hash': 'sha'},
    );
    await api.createKopiaSnapshot(rootPath: r'C:\root', rootId: 'root-1');
    await api.refreshKopiaVersions(
      fileId: 'file-1',
      filePath: r'C:\root\plan.txt',
      displayName: 'Plan',
    );
    await api.versions('file 1');
    await api.createVersionDownloadRequest(
      versionId: 'version 1',
      targetMode: 'restore',
      targetPath: r'C:\restore.txt',
      auditNote: 'restore note',
    );
    await api.downloadVersionCopy(
      versionId: 'version 1',
      targetPath: r'C:\copy.txt',
      auditNote: 'copy note',
    );
    await api.prepareVersionRestore(
      versionId: 'version 1',
      targetPath: r'C:\restore.txt',
    );
    await api.conflicts();
    await api.createConflict(
      fileUid: 'file-uid',
      path: '/plan.txt',
      providerA: 'local',
      providerB: 'drive',
      versionA: const <String, Object?>{'etag': 'a'},
      versionB: const <String, Object?>{'etag': 'b'},
      reason: 'manual',
    );
    await api.resolveConflict(
      conflictId: 'conflict 1',
      resolution: const <String, Object?>{'winner': 'local'},
    );

    expect(
      requests.map((request) => '${request.method} ${request.path}').toList(),
      <String>[
        'GET /api/files/dashboard',
        'GET /api/files/providers',
        'PATCH /api/files/providers/local%20drive',
        'POST /api/files/tree/snapshot',
        'GET /api/files/tree',
        'GET /api/files/tree',
        'POST /api/files/upload-sessions',
        'PUT /api/files/upload-sessions/session%201/chunks/2',
        'GET /api/files/upload-sessions/session%201/missing-chunks',
        'POST /api/files/upload-sessions/session%201/complete',
        'POST /api/files/download-sessions',
        'GET /api/files/download-sessions/session%201/range',
        'GET /api/files/transfers',
        'GET /api/files/transfers',
        'GET /api/files/transfers/session%201/progress',
        'POST /api/files/network-presence',
        'GET /api/files/network-presence',
        'GET /api/files/transfers/session%201/candidates',
        'POST /api/files/transfers/session%201/candidates',
        'POST /api/files/transfers/session%201/events',
        'GET /api/files/storage/status',
        'GET /api/files/storage/objects',
        'GET /api/files/storage/objects',
        'POST /api/files/storage/register',
        'POST /api/files/kopia/snapshots',
        'POST /api/files/kopia/versions/refresh',
        'GET /api/files/versions/file%201',
        'POST /api/files/versions/version%201/download-requests',
        'POST /api/files/versions/version%201/download-copy',
        'POST /api/files/versions/version%201/restore-prepare',
        'GET /api/files/conflicts',
        'POST /api/files/conflicts',
        'POST /api/files/conflicts/conflict%201/resolve',
      ],
    );

    expect(requests[2].jsonBody['providerType'], 'local');
    expect(requests[2].jsonBody['rootRemoteId'], 'root-1');
    expect(requests[3].jsonBody['markMissing'], isTrue);
    expect(requests[4].query, containsPair('q', 'invoice'));
    expect(requests[5].query, isNot(contains('q')));
    expect(requests[6].jsonBody['chunkSize'], 8);
    expect(requests[7].jsonBody, <String, Object?>{
      'startByte': 8,
      'endByte': 10,
      'payloadBase64': base64Encode(<int>[1, 2, 3]),
      'checksum': 'chunk-sha',
    });
    expect(requests[11].query, <String, String>{'start': '4', 'end': '9'});
    expect(requests[12].query, containsPair('status', 'failed'));
    expect(requests[13].query, isNot(contains('status')));
    expect(requests[15].jsonBody['ttlMinutes'], 30);
    expect(requests[18].jsonBody['failureReason'], 'none');
    expect(requests[19].jsonBody['payload'], <String, Object?>{'attempt': 2});
    expect(requests[21].query, containsPair('localPath', 'C:/plan.txt'));
    expect(requests[21].query, containsPair('nodeId', 'node-1'));
    expect(requests[22].query, isNot(contains('localPath')));
    expect(requests[23].jsonBody['fileNodeId'], 'node-1');
    expect(requests[24].jsonBody['rootId'], 'root-1');
    expect(requests[25].jsonBody['displayName'], 'Plan');
    expect(requests[27].jsonBody['targetMode'], 'restore');
    expect(requests[28].jsonBody['auditNote'], 'copy note');
    expect(requests[29].jsonBody['targetPath'], r'C:\restore.txt');
    expect(requests[31].jsonBody['reason'], 'manual');
    expect(requests[32].jsonBody['resolution'], <String, Object?>{
      'winner': 'local',
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.jsonBody,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.queryParameters,
      jsonBody: request.body.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
    );
  }

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, Object?> jsonBody;
}
