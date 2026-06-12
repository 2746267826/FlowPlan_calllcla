import 'dart:convert';
import 'dart:typed_data';

import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/core/server_api/file_context_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  group('FileCloudApi', () {
    test('upload and download sessions send transfer metadata', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileCloudApi(
        _apiClient(
          db,
          requests,
          responseFor: (request) {
            if (request.url.path.endsWith('/files/upload-sessions')) {
              return <String, Object?>{
                'uploadSession': <String, Object?>{'sessionId': 'upload-1'},
              };
            }
            if (request.url.path.endsWith('/files/download-sessions')) {
              return <String, Object?>{
                'downloadSession': <String, Object?>{'sessionId': 'download-1'},
              };
            }
            return const <String, Object?>{};
          },
        ),
      );

      await api.createUploadSession(
        fileName: 'brief.txt',
        totalBytes: 42,
        providerKey: 'server_storage',
        chunkSize: 21,
        checksum: 'local-hash',
        objectKey: 'object-key',
        localPath: r'C:\FlowPlanV2\brief.txt',
        remoteId: 'remote-1',
        metadata: const <String, Object?>{'job': 'upload-1'},
      );
      await api.createDownloadSession(
        storageObjectId: 'storage-1',
        providerKey: 'server_storage',
        fileName: 'brief.txt',
        remoteId: 'remote-1',
        localPath: r'C:\FlowPlanV2\download.txt',
        totalBytes: 42,
        chunkSize: 21,
        checksum: 'server-hash',
        metadata: const <String, Object?>{'job': 'download-1'},
      );

      expect(requests.map((request) => request.method), <String>[
        'POST',
        'POST',
      ]);
      expect(requests.first.path, '/api/files/upload-sessions');
      expect(requests.first.jsonBody, <String, Object?>{
        'providerKey': 'server_storage',
        'fileName': 'brief.txt',
        'totalBytes': 42,
        'chunkSize': 21,
        'checksum': 'local-hash',
        'objectKey': 'object-key',
        'localPath': r'C:\FlowPlanV2\brief.txt',
        'remoteId': 'remote-1',
        'metadata': <String, Object?>{'job': 'upload-1'},
      });
      expect(requests.last.path, '/api/files/download-sessions');
      expect(requests.last.jsonBody, <String, Object?>{
        'storageObjectId': 'storage-1',
        'providerKey': 'server_storage',
        'fileName': 'brief.txt',
        'remoteId': 'remote-1',
        'localPath': r'C:\FlowPlanV2\download.txt',
        'totalBytes': 42,
        'chunkSize': 21,
        'checksum': 'server-hash',
        'metadata': <String, Object?>{'job': 'download-1'},
      });
    });

    test('chunk upload encodes payload and range fields', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileCloudApi(_apiClient(db, requests));

      await api.uploadChunk(
        sessionId: 'session/with space',
        chunkIndex: 3,
        startByte: 6,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        checksum: 'chunk-hash',
      );

      expect(
        requests.single.path,
        '/api/files/upload-sessions/session/with%20space/chunks/3',
      );
      expect(requests.single.jsonBody, <String, Object?>{
        'startByte': 6,
        'endByte': 8,
        'payloadBase64': base64Encode(<int>[1, 2, 3]),
        'checksum': 'chunk-hash',
      });
    });

    test('query endpoints omit blank optional filters and keep pagination',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileCloudApi(_apiClient(db, requests));

      await api.tree(
        providerKey: 'server_storage',
        parentRemoteId: 'parent-1',
        query: '  launch  ',
        limit: 12,
        offset: 3,
      );
      await api.tree(query: '   ');
      await api.transfers(
        direction: 'upload',
        status: 'completed',
        limit: 9,
        offset: 2,
      );
      await api.storageObjects(localPath: '  ', nodeId: 'node-1');
      await api.downloadRange(sessionId: 'download-1', start: 4, end: 7);

      expect(requests[0].pathAndQuery,
          '/api/files/tree?providerKey=server_storage&parentRemoteId=parent-1&q=launch&limit=12&offset=3');
      expect(requests[1].pathAndQuery, '/api/files/tree?limit=300&offset=0');
      expect(requests[2].pathAndQuery,
          '/api/files/transfers?direction=upload&status=completed&limit=9&offset=2');
      expect(requests[3].pathAndQuery,
          '/api/files/storage/objects?nodeId=node-1&limit=100&offset=0');
      expect(requests[4].pathAndQuery,
          '/api/files/download-sessions/download-1/range?start=4&end=7');
    });

    test(
        'provider, storage, snapshot, and conflict commands keep request shape',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileCloudApi(_apiClient(db, requests));

      await api.upsertProvider(
        'server_storage',
        providerType: 'local_object_store',
        displayName: 'Server Storage',
        priority: 7,
        status: 'enabled',
        syncMode: 'manual',
        rootRemoteId: 'root-1',
        localMirrorPath: r'C:\mirror',
        mobileDownloadRoot: r'C:\downloads',
        capabilities: const <String, Object?>{'upload': true},
        config: const <String, Object?>{'bucket': 'local'},
      );
      await api.applyTreeSnapshot(
        providerKey: 'server_storage',
        treeRevision: 'rev-1',
        markMissing: true,
        nodes: const <Map<String, Object?>>[
          <String, Object?>{'remoteId': 'node-1'},
        ],
      );
      await api.registerStorageObject(
        localPath: r'C:\FlowPlanV2\a.txt',
        fileName: 'a.txt',
        objectKey: 'objects/a',
        fileNodeId: 'node-1',
        metadata: const <String, Object?>{'hash': 'abc'},
      );
      await api.createConflict(
        fileUid: 'file-1',
        path: r'C:\FlowPlanV2\a.txt',
        providerA: 'local',
        providerB: 'server',
        versionA: const <String, Object?>{'hash': 'a'},
        versionB: const <String, Object?>{'hash': 'b'},
        reason: 'hash_mismatch',
      );
      await api.resolveConflict(
        conflictId: 'conflict-1',
        resolution: const <String, Object?>{'winner': 'local'},
      );

      expect(requests.map((request) => request.method), <String>[
        'PATCH',
        'POST',
        'POST',
        'POST',
        'POST',
      ]);
      expect(requests[0].path, '/api/files/providers/server_storage');
      expect(requests[0].jsonBody,
          containsPair('capabilities', <String, Object?>{'upload': true}));
      expect(requests[1].path, '/api/files/tree/snapshot');
      expect(requests[1].jsonBody, containsPair('markMissing', true));
      expect(requests[2].path, '/api/files/storage/register');
      expect(requests[2].jsonBody, containsPair('fileNodeId', 'node-1'));
      expect(requests[3].path, '/api/files/conflicts');
      expect(requests[3].jsonBody, containsPair('reason', 'hash_mismatch'));
      expect(requests[4].path, '/api/files/conflicts/conflict-1/resolve');
      expect(requests[4].jsonBody,
          containsPair('resolution', <String, Object?>{'winner': 'local'}));
    });
  });

  group('FileContextApi', () {
    test('drive queries trim optional filters and page requests', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileContextApi(_apiClient(db, requests));

      await api.driveRoots(query: '  alpha  ');
      await api.driveRoots(query: '   ');
      await api.driveNodes(
        rootId: ' root-1 ',
        parentId: ' parent-1 ',
        query: '  brief ',
        limit: 17,
        offset: 5,
      );
      await api.driveNodes(rootId: '   ', parentId: '   ', query: '   ');
      await api.nodes(rootId: 'root-2', parentId: 'parent-2', query: 'context');

      expect(requests[0].pathAndQuery, '/api/files/drive/roots?q=alpha');
      expect(requests[1].pathAndQuery, '/api/files/drive/roots');
      expect(requests[2].pathAndQuery,
          '/api/files/drive/nodes?rootId=+root-1+&parentId=+parent-1+&q=brief&limit=17&offset=5');
      expect(requests[3].pathAndQuery,
          '/api/files/drive/nodes?limit=300&offset=0');
      expect(requests[4].pathAndQuery,
          '/api/files/nodes?rootId=root-2&parentId=parent-2&q=context&limit=300&offset=0');
    });

    test(
        'drive node commands forward local identity, metadata, and encoded ids',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileContextApi(_apiClient(db, requests));

      await api.openPlan(
        nodeId: 'node-1',
        localIdentity: const <String, Object?>{'hash': 'local-hash'},
      );
      await api.upsertDeviceLocation(
        nodeId: 'node-1',
        localPath: r'C:\FlowPlanV2\node.txt',
        availability: 'available',
        metadata: const <String, Object?>{'device': 'win'},
      );
      await api.createDownloadRequest(
        nodeId: 'node-1',
        targetPath: r'C:\FlowPlanV2\downloads\node.txt',
      );
      await api.scanDriveRoot(rootId: 'root-1', rootPath: r'C:\FlowPlanV2');
      await api.deleteDriveRoot(rootId: 'root/with space');
      await api.relinkNode(
        nodeId: 'node-1',
        localPath: r'C:\FlowPlanV2\relinked.txt',
        reason: 'user-selected',
        identity: const <String, Object?>{'size': 42},
      );

      expect(requests.map((request) => request.path), <String>[
        '/api/files/drive/nodes/node-1/open-plan',
        '/api/files/drive/nodes/node-1/device-location',
        '/api/files/drive/nodes/node-1/download-request',
        '/api/files/drive/roots/root-1/scan',
        '/api/files/drive/roots/root%2Fwith%20space',
        '/api/files/drive/nodes/node-1/relink',
      ]);
      expect(
          requests[0].jsonBody,
          containsPair(
              'localIdentity', <String, Object?>{'hash': 'local-hash'}));
      expect(requests[1].jsonBody,
          containsPair('metadata', <String, Object?>{'device': 'win'}));
      expect(requests[2].jsonBody,
          containsPair('targetPath', r'C:\FlowPlanV2\downloads\node.txt'));
      expect(requests[3].jsonBody, containsPair('maxNodes', 0));
      expect(requests[4].method, 'DELETE');
      expect(requests[5].jsonBody, containsPair('reason', 'user-selected'));
    });

    test('snapshot, links, and node logs preserve payloads', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final api = FileContextApi(_apiClient(db, requests));

      await api.upsertRoot(
        rootUid: 'root-uid',
        name: 'Root',
        rootUri: r'C:\FlowPlanV2',
        providerType: 'local',
        rootDisplayPath: 'FlowPlanV2',
        isManaged: true,
        syncPolicy: 'full',
        metadata: const <String, Object?>{'source': 'test'},
      );
      await api.applyNodeSnapshot(
        rootId: 'root-1',
        scanStatus: 'partial',
        nodes: const <Map<String, Object?>>[
          <String, Object?>{'nodeUid': 'node-uid'},
        ],
      );
      await api.linkNodeToEntity(
        nodeId: 'node-1',
        entityType: 'task',
        entityId: 'task-1',
        relationType: 'manual',
        confidence: 0.8,
        reason: 'selected',
      );
      await api.logNodeOperation(
        nodeId: 'node-1',
        operation: 'download',
        status: 'failed',
        sourcePath: '/server/node.txt',
        targetPath: r'C:\FlowPlanV2\node.txt',
        errorMessage: 'hash mismatch',
        metadata: const <String, Object?>{'retryable': true},
      );

      expect(requests.map((request) => request.path), <String>[
        '/api/files/roots',
        '/api/files/nodes/snapshot',
        '/api/files/context-links',
        '/api/files/nodes/node-1/log',
      ]);
      expect(requests[0].jsonBody,
          containsPair('metadata', <String, Object?>{'source': 'test'}));
      expect(requests[1].jsonBody, containsPair('scanStatus', 'partial'));
      expect(requests[2].jsonBody, containsPair('confidence', 0.8));
      expect(
          requests[3].jsonBody, containsPair('errorMessage', 'hash mismatch'));
      expect(requests[3].jsonBody,
          containsPair('metadata', <String, Object?>{'retryable': true}));
    });
  });
}

ApiClient _apiClient(
  AppDatabase db,
  List<_RecordedRequest> requests, {
  Map<String, Object?> Function(http.Request request)? responseFor,
}) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      requests.add(_RecordedRequest.fromRequest(request));
      final payload =
          responseFor?.call(request) ?? const <String, Object?>{'ok': true};
      return http.Response(jsonEncode(payload), 200);
    }),
  );
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
  });

  factory _RecordedRequest.fromRequest(http.Request request) {
    return _RecordedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.query,
      body: request.body,
    );
  }

  final String method;
  final String path;
  final String query;
  final String body;

  String get pathAndQuery => query.isEmpty ? path : '$path?$query';

  Map<String, dynamic> get jsonBody {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
