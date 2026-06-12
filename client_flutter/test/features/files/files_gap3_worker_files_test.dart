import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/core/server_api/file_context_api.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/features/files/services/local_file_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('repository path fallback and lookup branches stay observable',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap3-path-fallback-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}lookup.txt');
    await file.writeAsString('lookup');
    final repository = FileContextRepository(db);

    final folder = await repository.upsertLocalFolder(
      localPath: '${tempDir.path}${Platform.pathSeparator}',
      displayName: '   ',
    );
    final item = await repository.upsertLocalFile(
      localPath: file.path,
      folderId: folder.id,
      mimeType: 'text/plain',
      previewMode: 'text',
    );
    final lookedUp = await repository.getFileById(item.id);

    expect(folder.displayName, isNot(isEmpty));
    expect(folder.displayName, isNot(contains(Platform.pathSeparator)));
    expect(lookedUp!.displayName, 'lookup.txt');

    await db.customStatement(
      '''
      CREATE TEMP TRIGGER gap3_delete_folder_after_update
      AFTER UPDATE ON file_folders
      WHEN NEW.id = ${folder.id}
      BEGIN
        DELETE FROM file_folders WHERE id = NEW.id;
      END
      ''',
    );
    await expectLater(
      repository.upsertLocalFolder(
        localPath: '${tempDir.path}${Platform.pathSeparator}',
        displayName: 'Renamed',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('repository searches server drive nodes and keeps cached local identity',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap3-drive-cache-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final localCopy = File(
      '${tempDir.path}${Platform.pathSeparator}release-plan.md',
    );
    await localCopy.writeAsString('# Release plan');
    final api = _FeatureFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-gap3',
          'rootUid': 'root-gap3-uid',
          'name': 'Queryable Drive',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'folder-gap3',
          'nodeUid': 'folder-gap3-uid',
          'nodeType': FileNodeType.folder,
          'displayName': 'Design',
          'relativePath': 'Design',
        },
        <String, Object?>{
          'id': 'file-gap3',
          'nodeUid': 'file-gap3-uid',
          'parentId': 'folder-gap3',
          'nodeType': FileNodeType.file,
          'displayName': 'release-plan.md',
          'relativePath': 'Design/release-plan.md',
          'mimeType': 'text/markdown',
          'sizeBytes': '19',
          'hashSha256': 'hash-original',
          'storage': <String, Object?>{
            'storageObjectId': 'storage-original',
          },
          'currentDevice': <String, Object?>{
            'localPath': localCopy.path,
            'availability': FileAvailability.local,
          },
        },
      ],
    );
    final repository = FileContextRepository(db, null, null, () async => api);

    final root = (await repository.listFolders()).single;
    final rootNode = await repository.getRootNode(root.id);
    final rootChildren = await repository.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: rootNode!.id,
    );
    final folderNode = rootChildren.single;
    final searchResults = await repository.searchNodes(
      rootFolderId: root.id,
      query: ' plan ',
      limit: 7,
    );

    expect(root.provider, FileProviderKind.serverStorage);
    expect(root.availability, FileAvailability.remoteOnly);
    expect(folderNode.displayName, 'Design');
    expect(searchResults.single.displayName, 'release-plan.md');
    expect(api.driveNodeRequests.last, containsPair('query', 'plan'));
    expect(api.driveNodeRequests.last, containsPair('limit', 7));
    expect(
      (await repository.breadcrumbForNode(searchResults.single))
          .map((node) => node.displayName),
      <String>['Queryable Drive', 'Design', 'release-plan.md'],
    );

    api.nodeFixtures
      ..clear()
      ..add(<String, Object?>{
        'id': 'file-gap3',
        'nodeUid': 'file-gap3-uid',
        'parentId': 'folder-gap3',
        'nodeType': FileNodeType.file,
        'displayName': 'release-plan-renamed.md',
        'relativePath': 'Design/release-plan-renamed.md',
        'mimeType': 'text/markdown',
        'sizeBytes': 21.7,
        'hashSha256': 'hash-updated',
      });

    await repository.refreshDriveNodes(
      rootFolderId: root.id,
      parentNodeId: folderNode.id,
    );
    final updated = (await repository.searchNodes(
      rootFolderId: root.id,
      query: 'renamed',
    ))
        .single;

    expect(
      api.driveNodeRequests,
      contains(containsPair('parentId', 'folder-gap3')),
    );
    expect(updated.localPath, localCopy.path);
    expect(updated.sizeBytes, 21);
    expect(updated.storageObjectId, 'storage-original');
    expect(updated.hashSha256, 'hash-updated');
  });

  test('repository server root scan and delete surface explicit edge errors',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap3-root-errors-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final api = _FeatureFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-delete',
          'rootUid': 'root-delete-uid',
          'name': 'Delete Drive',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
      scanOk: false,
      deleteOk: false,
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final remoteRoot = (await repository.listFolders()).single;
    final localRoot = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Local Only',
    );

    await expectLater(
      repository.requestServerRootScan(localRoot.id),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.requestServerRootScan(remoteRoot.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('scan denied'),
        ),
      ),
    );
    await expectLater(
      repository.deleteRoot(localRoot.id),
      throwsA(isA<StateError>()),
    );
    await db.customStatement(
      'UPDATE file_folders SET provider = ?, remote_id = ? WHERE id = ?',
      [FileProviderKind.serverStorage, 'local-now-remote', localRoot.id],
    );
    await expectLater(
      FileContextRepository(db).deleteRoot(localRoot.id),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.relocateFolder(
        folderId: 404404,
        newLocalPath: tempDir.path,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.deleteRoot(remoteRoot.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('delete denied'),
        ),
      ),
    );

    api.deleteOk = true;
    await repository.deleteRoot(remoteRoot.id);

    expect(api.deletedRootIds, <String>['root-delete', 'root-delete']);
    expect(await repository.getFolderById(remoteRoot.id), isNull);
  });

  test('repository update guards catch disappearing folders files and links',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap3-update-guards-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final repository = FileContextRepository(db);
    final localRoot = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Guard Root',
    );
    await db.customStatement(
      '''
      CREATE TEMP TRIGGER gap3_delete_relocated_folder
      AFTER UPDATE ON file_folders
      WHEN NEW.id = ${localRoot.id}
      BEGIN
        DELETE FROM file_folders WHERE id = NEW.id;
      END
      ''',
    );
    await expectLater(
      repository.relocateFolder(
        folderId: localRoot.id,
        newLocalPath: '${tempDir.path}${Platform.pathSeparator}moved',
      ),
      throwsA(isA<StateError>()),
    );

    final bindDb = createTestDatabase();
    addTearDown(bindDb.close);
    final bindApi = _FeatureFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-bind-guard',
          'rootUid': 'root-bind-guard-uid',
          'name': 'Bind Guard',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
    );
    final bindRepository =
        FileContextRepository(bindDb, null, null, () async => bindApi);
    final remoteRoot = (await bindRepository.listFolders()).single;
    await bindDb.customStatement(
      '''
      CREATE TEMP TRIGGER gap3_delete_bound_folder
      AFTER UPDATE ON file_folders
      WHEN NEW.id = ${remoteRoot.id}
      BEGIN
        DELETE FROM file_folders WHERE id = NEW.id;
      END
      ''',
    );
    await expectLater(
      bindRepository.bindRootLocalDirectory(
        folderId: remoteRoot.id,
        localPath: tempDir.path,
      ),
      throwsA(isA<StateError>()),
    );

    final fileDb = createTestDatabase();
    addTearDown(fileDb.close);
    final fileRepository = FileContextRepository(fileDb);
    final fileRoot = await fileRepository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'File Guard',
    );
    final guardedFile =
        File('${tempDir.path}${Platform.pathSeparator}guarded.txt');
    await guardedFile.writeAsString('first');
    final firstFile = await fileRepository.upsertLocalFile(
      localPath: guardedFile.path,
      folderId: fileRoot.id,
      mimeType: 'text/plain',
      previewMode: 'text',
    );
    await fileDb.customStatement(
      '''
      CREATE TEMP TRIGGER gap3_delete_file_after_update
      AFTER UPDATE ON file_items
      WHEN NEW.id = ${firstFile.id}
      BEGIN
        DELETE FROM file_items WHERE id = NEW.id;
      END
      ''',
    );
    await guardedFile.writeAsString('second');
    await expectLater(
      fileRepository.upsertLocalFile(
        localPath: guardedFile.path,
        folderId: fileRoot.id,
        mimeType: 'text/plain',
        previewMode: 'text',
      ),
      throwsA(isA<StateError>()),
    );

    final linkDb = createTestDatabase();
    addTearDown(linkDb.close);
    final linkRepository = FileContextRepository(linkDb);
    final linkRoot = await linkRepository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\LinkGuard',
      displayName: 'Link Guard',
    );
    final manualLink = await linkRepository.bindFolderToTask(
      taskId: 77,
      folderId: linkRoot.id,
      reason: 'Manual guard',
    );
    final reconfirmed = await linkRepository.confirmLink(manualLink.id);
    expect(reconfirmed.relationType, FileContextRelationType.manual);

    final confirmGuard = await linkRepository.createRecommendationLink(
      entityType: FileContextEntityType.task,
      entityId: 'confirm-guard',
      folderId: linkRoot.id,
      confidence: 0.4,
      reason: 'Guarded confirm',
    );
    await linkDb.customStatement(
      '''
      CREATE TEMP TRIGGER gap3_delete_link_after_confirm
      AFTER UPDATE ON file_context_links
      WHEN NEW.id = ${confirmGuard.id}
      BEGIN
        DELETE FROM file_context_links WHERE id = NEW.id;
      END
      ''',
    );
    await expectLater(
      linkRepository.confirmLink(confirmGuard.id),
      throwsA(isA<StateError>()),
    );

    final upsertGuard = await linkRepository.createRecommendationLink(
      entityType: FileContextEntityType.task,
      entityId: 'upsert-guard',
      folderId: linkRoot.id,
      confidence: 0.31,
      reason: 'Initial recommendation',
    );
    await linkDb.customStatement(
      '''
      CREATE TEMP TRIGGER gap3_delete_link_after_upsert
      AFTER UPDATE ON file_context_links
      WHEN NEW.id = ${upsertGuard.id}
      BEGIN
        DELETE FROM file_context_links WHERE id = NEW.id;
      END
      ''',
    );
    await expectLater(
      linkRepository.createRecommendationLink(
        entityType: FileContextEntityType.task,
        entityId: 'upsert-guard',
        folderId: linkRoot.id,
        confidence: 0.7,
        reason: 'Updated recommendation',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('scanRoot maps remaining file kinds and tolerates snapshot upload failure',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap3-scan-kinds-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    for (final entry in <String, List<int>>{
      'config.yaml': utf8.encode('name: flow'),
      'table.csv': utf8.encode('a,b\n1,2'),
      'anim.gif': <int>[71, 73, 70],
      'paint.bmp': <int>[66, 77],
      'image.webp': <int>[82, 73, 70, 70],
      'manual.pdf': utf8.encode('%PDF'),
      'unknown.filetype': <int>[1, 2, 3],
    }.entries) {
      await File('${tempDir.path}${Platform.pathSeparator}${entry.key}')
          .writeAsBytes(entry.value);
    }
    final api = _FeatureFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-snapshot-fail',
          'rootUid': 'root-snapshot-fail-uid',
          'name': 'Snapshot Failure Drive',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
    )..failApplyNodeSnapshot = true;
    final repository = FileContextRepository(
      db,
      DataOperationLogRepository(db),
      null,
      () async => api,
    );
    final root = (await repository.listFolders()).single;
    await repository.bindRootLocalDirectory(
      folderId: root.id,
      localPath: '${tempDir.path}${Platform.pathSeparator}',
    );

    final result = await repository.scanRoot(folderId: root.id);
    final files = await repository.listFilesForFolder(root.id);
    final byName = <String, FileItem>{
      for (final file in files) file.displayName: file,
    };

    expect(result.scannedCount, 8);
    expect(api.appliedSnapshots, hasLength(1));
    expect(byName['config.yaml']!.mimeType, 'text/yaml');
    expect(byName['config.yaml']!.previewMode, 'text');
    expect(byName['table.csv']!.mimeType, 'text/csv');
    expect(byName['table.csv']!.previewMode, 'text');
    expect(byName['anim.gif']!.mimeType, 'image/gif');
    expect(byName['anim.gif']!.previewMode, 'image');
    expect(byName['paint.bmp']!.mimeType, 'image/bmp');
    expect(byName['paint.bmp']!.previewMode, 'image');
    expect(byName['image.webp']!.mimeType, 'image/webp');
    expect(byName['image.webp']!.previewMode, 'image');
    expect(byName['manual.pdf']!.mimeType, 'application/pdf');
    expect(byName['manual.pdf']!.previewMode, 'none');
    expect(byName['unknown.filetype']!.mimeType, isNull);

    await File('${tempDir.path}${Platform.pathSeparator}config.yaml')
        .writeAsString('name: flow\nupdated: true\n');
    final secondResult = await repository.scanRoot(folderId: root.id);
    final updatedConfig = (await repository.listFilesForFolder(root.id))
        .singleWhere((file) => file.displayName == 'config.yaml');

    expect(secondResult.scannedCount, 8);
    expect(api.appliedSnapshots, hasLength(2));
    expect(
      updatedConfig.sizeBytes,
      greaterThan(byName['config.yaml']!.sizeBytes!),
    );
  });

  test('folder usage syncs offline and high-score recommendations explain match',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = _repositoryWithSync(db);
    final usageFolder = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\UsageOnly',
      displayName: 'Usage Only',
    );
    await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\AlphaLaunchProposalDesign',
      displayName: 'Alpha Launch Proposal Design',
      sourceContext: 'alpha launch proposal design roadmap assets',
    );

    await repository.recordFolderUsage(
      folderId: usageFolder.id,
      action: 'context-open',
      entityType: FileContextEntityType.task,
      entityId: 'task-gap3',
      source: 'files-gap3',
      metadata: <String, Object?>{'surface': 'repository'},
    );
    final recommendations = await repository.recommendFolders(
      entityType: FileContextEntityType.task,
      entityId: 'task-gap3',
      title: 'alpha launch proposal design roadmap assets',
      description: 'proposal design launch alpha assets',
    );

    final mutationRows = await db.customSelect(
      'SELECT object_type, action, payload_json FROM offline_mutations '
      'WHERE object_type = ? ORDER BY id ASC',
      variables: [Variable<String>('file_folder_usage')],
    ).get();
    expect(mutationRows, hasLength(1));
    expect(mutationRows.single.read<String>('action'), 'create');
    expect(
      jsonDecode(mutationRows.single.read<String>('payload_json')),
      containsPair('source', 'files-gap3'),
    );
    expect(recommendations.first.folder.displayName,
        'Alpha Launch Proposal Design');
    expect(recommendations.first.score, greaterThan(0.5));
    expect(recommendations.first.reason.trim(), isNotEmpty);
  });

  test('transfer service clears terminal jobs and resets failed refresh state',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final persisted = <Map<String, Object?>>[
      _jobJson('uploaded', FileTransferDirection.upload,
          FileTransferStatus.uploaded),
      _jobJson('downloaded', FileTransferDirection.download,
          FileTransferStatus.downloaded),
      _jobJson(
          'failed', FileTransferDirection.download, FileTransferStatus.failed),
      _jobJson('queued', FileTransferDirection.upload, FileTransferStatus.queued),
      _jobJson('uploading', FileTransferDirection.upload,
          FileTransferStatus.uploading),
      _jobJson('downloading', FileTransferDirection.download,
          FileTransferStatus.downloading),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flowplanv2.file_transfer.jobs.v1': jsonEncode(persisted),
    });
    final api = _FeatureFileCloudApi(
      transferRows: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'server-transfer-gap3',
          'direction': FileTransferDirection.upload,
          'status': 'completed',
        },
      ],
    );
    final service = FileTransferService(
      apiLoader: () async => api,
      operationLogs: DataOperationLogRepository(db),
    );
    addTearDown(service.dispose);

    await service.load();
    await service.clearCompletedJobs();
    api.failTransfers = true;
    await expectLater(service.refreshServerTransfers(), throwsStateError);
    api.failTransfers = false;
    await service.refreshServerTransfers();

    expect(
      service.jobs.map((job) => job.id),
      <String>['queued', 'uploading', 'downloading'],
    );
    expect(service.refreshingServer, isFalse);
    expect(service.serverTransfers.single['id'], 'server-transfer-gap3');
    expect(api.transferRequests, hasLength(2));
  });

  test('local identity handles zero-byte files and explicit storage metadata',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap3-identity-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final empty = File('${tempDir.path}${Platform.pathSeparator}empty.bin');
    await empty.writeAsBytes(const <int>[]);

    final identity =
        await const LocalFileIdentityService().identify('  ${empty.path}  ');

    expect(identity, isNotNull);
    expect(identity!.sizeBytes, 0);
    expect(identity.hashSha256, sha256.convert(const <int>[]).toString());
    expect(
      identity.toJson(storageObjectId: 'storage-empty'),
      containsPair('storageObjectId', 'storage-empty'),
    );
  });
}

FileContextRepository _repositoryWithSync(AppDatabase db) {
  final recorder = SyncWriteRecorder(
    mutationStore: OfflineMutationStore(db),
    stateStore: SyncObjectStateStore(db),
  );
  return FileContextRepository(
    db,
    DataOperationLogRepository(db, recorder),
    recorder,
  );
}

Map<String, Object?> _jobJson(
  String id,
  String direction,
  String status,
) {
  return <String, Object?>{
    'id': id,
    'direction': direction,
    'fileName': '$id.bin',
    'localPath': r'C:\FlowPlanV2\transfer.bin',
    'totalBytes': 10,
    'chunkSize': 5,
    'expectedChunks': 2,
    'transferredBytes': status == FileTransferStatus.queued ? 0 : 5,
    'status': status,
    'createdAt': DateTime.utc(2026, 6, 10, 8).toIso8601String(),
    'updatedAt': DateTime.utc(2026, 6, 10, 8, 1).toIso8601String(),
    if (direction == FileTransferDirection.download)
      'storageObjectId': 'storage-$id',
    if (status != FileTransferStatus.queued) 'sessionId': 'session-$id',
  };
}

class _FeatureFileContextApi implements FileContextApi {
  _FeatureFileContextApi({
    required this.rootFixtures,
    required List<Map<String, Object?>> nodeFixtures,
    this.scanOk = true,
    this.deleteOk = true,
  }) : nodeFixtures = List<Map<String, Object?>>.from(nodeFixtures);

  final List<Map<String, Object?>> rootFixtures;
  final List<Map<String, Object?>> nodeFixtures;
  bool scanOk;
  bool deleteOk;
  bool failDriveRoots = false;
  bool failDriveNodes = false;
  bool failApplyNodeSnapshot = false;
  final driveRootQueries = <String?>[];
  final driveNodeRequests = <Map<String, Object?>>[];
  final scannedRootIds = <String>[];
  final deletedRootIds = <String>[];
  final appliedSnapshots = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> driveRoots({String? query}) async {
    driveRootQueries.add(query);
    if (failDriveRoots) {
      throw StateError('drive roots unavailable');
    }
    return <String, dynamic>{'roots': rootFixtures};
  }

  @override
  Future<Map<String, dynamic>> scanDriveRoot({
    required String rootId,
    String? rootPath,
    int maxNodes = 0,
  }) async {
    scannedRootIds.add(rootId);
    return <String, dynamic>{
      'ok': scanOk,
      if (!scanOk) 'reason': 'scan denied',
    };
  }

  @override
  Future<Map<String, dynamic>> driveNodes({
    String? rootId,
    String? parentId,
    String? query,
    int limit = 300,
    int offset = 0,
  }) async {
    driveNodeRequests.add(<String, Object?>{
      'rootId': rootId,
      'parentId': parentId,
      'query': query,
      'limit': limit,
      'offset': offset,
    });
    if (failDriveNodes) {
      throw StateError('drive nodes unavailable');
    }
    return <String, dynamic>{'nodes': nodeFixtures};
  }

  @override
  Future<Map<String, dynamic>> deleteDriveRoot({
    required String rootId,
  }) async {
    deletedRootIds.add(rootId);
    return <String, dynamic>{
      'ok': deleteOk,
      if (!deleteOk) 'reason': 'delete denied',
    };
  }

  @override
  Future<Map<String, dynamic>> applyNodeSnapshot({
    required String rootId,
    required List<Map<String, Object?>> nodes,
    String scanStatus = 'completed',
  }) async {
    appliedSnapshots.add(<String, Object?>{
      'rootId': rootId,
      'nodes': nodes,
      'scanStatus': scanStatus,
    });
    if (failApplyNodeSnapshot) {
      throw StateError('snapshot unavailable');
    }
    return <String, dynamic>{'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FeatureFileCloudApi implements FileCloudApi {
  _FeatureFileCloudApi({required this.transferRows});

  final List<Map<String, Object?>> transferRows;
  bool failTransfers = false;
  final transferRequests = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> transfers({
    String? direction,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    transferRequests.add(<String, Object?>{
      'direction': direction,
      'status': status,
      'limit': limit,
      'offset': offset,
    });
    if (failTransfers) {
      throw StateError('transfers unavailable');
    }
    return <String, dynamic>{'transfers': transferRows};
  }

  @override
  Future<Map<String, dynamic>> downloadRange({
    required String sessionId,
    required int start,
    required int end,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'chunks': <Map<String, Object?>>[
        <String, Object?>{'payloadBase64': base64Encode(Uint8List(0))},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
