import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/file_context_api.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('local folder upsert is idempotent by normalized path', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    const path = r'C:\FlowPlanV2\client-tests';

    final first = await repository.upsertLocalFolder(
      localPath: path,
      displayName: 'Client tests',
      pinned: true,
    );
    final second = await repository.upsertLocalFolder(
      localPath: path,
      displayName: 'Client tests renamed',
    );

    final folders = await repository.listFolders();
    expect(second.id, first.id);
    expect(folders, hasLength(1));
    expect(folders.single.displayName, 'Client tests renamed');
  });

  test('folder upsert and relink create audit and offline sync side effects',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-folder-side-effects-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final movedDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}Moved Root',
    );
    await movedDir.create();
    final repository = _repositoryWithSideEffects(db);

    final folder = await repository.upsertLocalFolder(
      localPath: '${tempDir.path}${Platform.pathSeparator}Original Root',
      displayName: 'Original Root',
      metadata: const <String, Object?>{'owner': 'files-worker-l'},
    );
    final relocated = await repository.relocateFolder(
      folderId: folder.id,
      newLocalPath: movedDir.path,
    );

    expect(relocated.availability, FileAvailability.local);
    final logs = await DataOperationLogRepository(db).listRecent();
    expect(
        logs.map((log) => log.action),
        containsAll(<String>[
          'create_file_folder',
          'relocate_file_root',
        ]));
    final createLog = logs.singleWhere(
      (log) => log.action == 'create_file_folder',
    );
    expect(
      jsonDecode(createLog.afterJson!),
      containsPair(
          'metadataJson',
          jsonEncode(<String, Object?>{
            'owner': 'files-worker-l',
          })),
    );
    final mutationRows = await db
        .customSelect(
          'SELECT object_type, local_id, action FROM offline_mutations '
          'ORDER BY id ASC',
        )
        .get();
    expect(
      mutationRows.map((row) => row.read<String>('object_type')),
      contains('audit_log'),
    );
    final folderMutationRows = mutationRows
        .where((row) => row.read<String>('object_type') == 'file_folder')
        .toList(growable: false);
    expect(
      folderMutationRows.map((row) => row.read<String>('object_type')),
      everyElement('file_folder'),
    );
    expect(
      folderMutationRows.map((row) => row.read<String>('action')),
      <String>['create', 'update'],
    );
    final stateRows = await db.customSelect(
      'SELECT sync_state FROM sync_object_states '
      'WHERE object_type = ? AND local_id = ?',
      variables: [
        Variable<String>('file_folder'),
        Variable<String>(folder.id.toString()),
      ],
    ).get();
    expect(stateRows.single.read<String>('sync_state'), 'pending_create');
  });

  test('scanLocalFolder indexes local files with preview metadata', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-file-scan-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await File('${tempDir.path}${Platform.pathSeparator}notes.txt')
        .writeAsString('scan me');
    await File('${tempDir.path}${Platform.pathSeparator}image.png')
        .writeAsBytes(<int>[137, 80, 78, 71]);
    await Directory('${tempDir.path}${Platform.pathSeparator}nested').create();
    await File(
      '${tempDir.path}${Platform.pathSeparator}nested'
      '${Platform.pathSeparator}ignored.txt',
    ).writeAsString('not scanned by the shallow scanner');

    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Scan Root',
    );

    final scanned = await repository.scanLocalFolder(
      folderId: folder.id,
      limit: 10,
    );

    expect(scanned.map((file) => file.displayName), [
      'image.png',
      'notes.txt',
    ]);
    final textFile = scanned.singleWhere(
      (file) => file.displayName == 'notes.txt',
    );
    expect(textFile.previewMode, 'text');
    expect(textFile.mimeType, 'text/plain');
    expect(textFile.availability, FileAvailability.local);
    expect(textFile.sizeBytes, 7);
    expect(scanned.any((file) => file.displayName == 'ignored.txt'), isFalse);
  });

  test('scanLocalFolder returns cached files when root disappears', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-file-scan-missing-',
    );
    final localFile = File(
      '${tempDir.path}${Platform.pathSeparator}cached.txt',
    );
    await localFile.writeAsString('cached');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Cached Root',
    );
    await repository.scanLocalFolder(folderId: folder.id);
    await tempDir.delete(recursive: true);

    final cached = await repository.scanLocalFolder(folderId: folder.id);

    expect(cached.map((file) => file.displayName), <String>['cached.txt']);
    expect(cached.single.availability, FileAvailability.local);
  });

  test('folder recommendations can be confirmed and rejected', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    final alpha = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\AlphaLaunch',
      displayName: 'Alpha Launch Assets',
      sourceContext: 'proposal design launch',
      pinned: true,
    );
    final archive = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\Archive',
      displayName: 'Archive',
    );
    await repository.recordFolderUsage(
      folderId: alpha.id,
      action: 'open',
      entityType: FileContextEntityType.task,
      entityId: 'task-42',
      metadata: <String, Object?>{'source': 'test'},
    );

    final recommendations = await repository.recommendFolders(
      entityType: FileContextEntityType.task,
      entityId: 'task-42',
      title: 'Alpha launch proposal',
      description: 'Prepare launch design',
    );

    expect(recommendations.first.folder.id, alpha.id);
    expect(recommendations.first.score, greaterThan(0.12));

    final links = await repository.ensureFolderRecommendations(
      entityType: FileContextEntityType.task,
      entityId: 'task-42',
      title: 'Alpha launch proposal',
      description: 'Prepare launch design',
    );
    expect(links, isNotEmpty);
    expect(links.first.status, FileContextStatus.candidate);

    final confirmed = await repository.confirmLink(links.first.id);
    expect(confirmed.status, FileContextStatus.confirmed);
    expect(confirmed.relationType, FileContextRelationType.manual);

    final rejected = await repository.createRecommendationLink(
      entityType: FileContextEntityType.task,
      entityId: 'task-42',
      folderId: archive.id,
      confidence: 0.4,
      reason: 'Too old',
    );
    await repository.rejectLink(rejected.id);

    final visibleLinks = await repository.listLinksForEntity(
      entityType: FileContextEntityType.task,
      entityId: 'task-42',
    );
    expect(visibleLinks.map((link) => link.id), contains(confirmed.id));
    expect(visibleLinks.map((link) => link.id), isNot(contains(rejected.id)));

    final confirmedFolders = await repository.listConfirmedFoldersForEntity(
      entityType: FileContextEntityType.task,
      entityId: 'task-42',
    );
    expect(confirmedFolders.single.id, alpha.id);
  });

  test('file version records are listed by latest modification first',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-file-version-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final localFile = File(
      '${tempDir.path}${Platform.pathSeparator}brief.md',
    );
    await localFile.writeAsString('# Brief');

    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Version Root',
    );
    final file = await repository.upsertLocalFile(
      localPath: localFile.path,
      folderId: folder.id,
      previewMode: 'text',
      metadata: <String, Object?>{'purpose': 'version-test'},
    );

    await repository.addVersionRecord(
      fileId: file.id,
      versionRef: 'snapshot-old',
      displayName: 'Old snapshot',
      modifiedAt: DateTime.utc(2026, 6, 8, 8),
      checksum: 'old-hash',
    );
    final latest = await repository.addVersionRecord(
      fileId: file.id,
      versionRef: 'snapshot-new',
      displayName: 'New snapshot',
      modifiedAt: DateTime.utc(2026, 6, 8, 9),
      checksum: 'new-hash',
      metadata: <String, Object?>{'verified': true},
    );

    final versions = await repository.listFileVersions(file.id);

    expect(versions.map((version) => version.versionRef), [
      'snapshot-new',
      'snapshot-old',
    ]);
    expect(versions.first.checksum, 'new-hash');
    expect(
      jsonDecode(latest.metadataJson),
      containsPair('verified', true),
    );
  });

  test('server drive roots can be cached, scanned, browsed, and deleted',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-drive-root-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-1',
          'rootUid': 'root-uid-1',
          'name': 'Server Drive',
          'rootDisplayPath': '/drive/server',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'node-folder',
          'nodeUid': 'node-folder-uid',
          'nodeType': FileNodeType.folder,
          'displayName': 'Design',
          'relativePath': 'Design',
        },
        <String, Object?>{
          'id': 'node-file',
          'nodeUid': 'node-file-uid',
          'nodeType': FileNodeType.file,
          'displayName': 'brief.txt',
          'relativePath': 'Design/brief.txt',
          'mimeType': 'text/plain',
          'sizeBytes': 42,
          'hashSha256': 'hash-42',
          'storage': <String, Object?>{'storageObjectId': 'object-42'},
        },
      ],
    );
    final repository = FileContextRepository(db, null, null, () async => api);

    final folders = await repository.listFolders();
    final root = folders.singleWhere(
      (folder) => folder.remoteId == 'root-1',
    );

    expect(root.provider, FileProviderKind.serverStorage);
    expect(root.availability, FileAvailability.remoteOnly);
    expect(await repository.getRootNode(root.id), isNotNull);

    final bound = await repository.bindRootLocalDirectory(
      folderId: root.id,
      localPath: tempDir.path,
    );
    expect(bound.localPath, tempDir.path);
    expect(bound.availability, FileAvailability.local);

    await repository.requestServerRootScan(root.id);
    expect(api.scanRequests, 1);

    final rootNode = await repository.getRootNode(root.id);
    expect(rootNode, isNotNull);
    final children = await repository.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: rootNode!.id,
    );
    expect(
        children.map((node) => node.displayName),
        containsAll(<String>[
          'Design',
          'brief.txt',
        ]));
    final fileNode = children.singleWhere(
      (node) => node.remoteId == 'node-file',
    );
    expect(fileNode.isFile, isTrue);
    expect(fileNode.sizeBytes, 42);
    expect(fileNode.storageObjectId, 'object-42');

    final searchResults = await repository.searchNodes(
      rootFolderId: root.id,
      query: 'brief',
    );
    expect(searchResults.single.remoteId, 'node-file');

    await repository.deleteRoot(root.id);
    expect(api.deletedRootIds, <String>['root-1']);
    expect(await repository.getFolderById(root.id), isNull);
    expect(await repository.listChildNodes(rootFolderId: root.id), isEmpty);
  });

  test('server drive root display name falls back to root display path',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-path-only',
          'rootUid': 'root-path-only-uid',
          'rootDisplayPath': '/drive/path-only',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[],
    );
    final repository = FileContextRepository(db, null, null, () async => api);

    final root = (await repository.listFolders()).single;
    final rootNode = await repository.getRootNode(root.id);

    expect(root.displayName, '/drive/path-only');
    expect(rootNode!.displayName, '/drive/path-only');
  });

  test('scanRoot builds a browsable tree with breadcrumbs and node links',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-node-tree-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final designDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}Design',
    );
    await designDir.create();
    final briefFile = File(
      '${designDir.path}${Platform.pathSeparator}brief.md',
    );
    await briefFile.writeAsString('# Launch brief');

    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Tree Root',
    );
    final progress = <FileScanProgress>[];

    final result = await repository.scanRoot(
      folderId: folder.id,
      onProgress: progress.add,
    );

    expect(result.scannedCount, 3);
    expect(result.truncated, isFalse);
    expect(progress.last.done, isTrue);

    final rootChildren = await repository.listChildNodes(
      rootFolderId: folder.id,
      parentNodeId: result.rootNode.id,
    );
    expect(rootChildren.single.displayName, 'Design');
    expect(rootChildren.single.isFolder, isTrue);

    final designChildren = await repository.listChildNodes(
      rootFolderId: folder.id,
      parentNodeId: rootChildren.single.id,
    );
    final briefNode = designChildren.single;
    expect(briefNode.displayName, 'brief.md');
    expect(briefNode.isFile, isTrue);
    expect(briefNode.mimeType, 'text/markdown');

    final breadcrumb = await repository.breadcrumbForNode(briefNode);
    expect(breadcrumb.map((node) => node.displayName), [
      'Tree Root',
      'Design',
      'brief.md',
    ]);

    final searchResults = await repository.searchNodes(
      rootFolderId: folder.id,
      query: 'brief',
    );
    expect(searchResults.single.id, briefNode.id);

    final link = await repository.bindNodeToEntity(
      entityType: FileContextEntityType.task,
      entityId: 'task-tree',
      node: briefNode,
      reason: 'User selected the launch brief',
    );
    expect(link.targetType, FileContextTargetType.fileNode);
    expect(link.status, FileContextStatus.confirmed);

    final files = await repository.listFilesForFolder(folder.id);
    expect(files.single.displayName, 'brief.md');
    expect(files.single.previewMode, 'text');
  });

  test('scanRoot keeps cached tree when a previously scanned root is missing',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-node-tree-missing-',
    );
    final childFile = File(
      '${tempDir.path}${Platform.pathSeparator}cached.md',
    );
    await childFile.writeAsString('# Cached');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Missing After Scan',
    );
    final first = await repository.scanRoot(folderId: folder.id);
    await tempDir.delete(recursive: true);

    final second = await repository.scanRoot(folderId: folder.id);

    expect(second.rootNode.id, first.rootNode.id);
    expect(second.scannedCount, 0);
    expect(second.truncated, isFalse);
    expect(
      (await repository.getFolderById(folder.id))!.availability,
      FileAvailability.missing,
    );
    final cachedChildren = await repository.listChildNodes(
      rootFolderId: folder.id,
      parentNodeId: first.rootNode.id,
    );
    expect(cachedChildren.single.displayName, 'cached.md');
  });

  test('scanRoot pushes local snapshot payload for a bound server drive root',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-drive-snapshot-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await File('${tempDir.path}${Platform.pathSeparator}brief.md')
        .writeAsString('# Brief');
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-snapshot',
          'rootUid': 'root-snapshot-uid',
          'name': 'Snapshot Drive',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;
    await repository.bindRootLocalDirectory(
      folderId: root.id,
      localPath: tempDir.path,
    );

    final result = await repository.scanRoot(folderId: root.id);

    expect(result.scannedCount, 2);
    expect(api.appliedSnapshots, hasLength(1));
    final snapshot = api.appliedSnapshots.single;
    expect(snapshot['rootId'], 'root-snapshot');
    expect(snapshot['scanStatus'], 'completed');
    final nodes = (snapshot['nodes']! as List).cast<Map<String, Object?>>();
    expect(
        nodes.map((node) => node['name']),
        containsAll(<String>[
          'Snapshot Drive',
          'brief.md',
        ]));
    final fileNode = nodes.singleWhere((node) => node['name'] == 'brief.md');
    expect(fileNode['mimeType'], 'text/markdown');
    expect(fileNode['relativePath'], 'brief.md');
    expect(fileNode['metadata'], containsPair('rootFolderId', root.id));
    expect(fileNode['metadata'], contains('localNodeId'));
    expect(api.driveNodeRequests, isNotEmpty);
  });

  test('recordFileNodeOperation writes audit metadata for retryable actions',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-node-operation-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final localFile = File('${tempDir.path}${Platform.pathSeparator}open.txt');
    await localFile.writeAsString('open me');
    final repository = _repositoryWithSideEffects(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Operation Root',
    );
    final scan = await repository.scanRoot(folderId: folder.id);
    final node = (await repository.listChildNodes(
      rootFolderId: folder.id,
      parentNodeId: scan.rootNode.id,
    ))
        .single;

    await repository.recordFileNodeOperation(
      node: node,
      action: 'preview_file_node',
      entityType: FileContextEntityType.task,
      entityId: 'task-open',
      metadata: const <String, Object?>{'retryable': false},
    );

    final logs = await DataOperationLogRepository(db).listRecent();
    final operationLog = logs.singleWhere(
      (log) => log.action == 'preview_file_node',
    );
    expect(operationLog.entityType, 'file_node');
    expect(operationLog.entityId, node.id.toString());
    final metadata =
        jsonDecode(operationLog.metadataJson!) as Map<String, dynamic>;
    expect(metadata['entity_type'], FileContextEntityType.task);
    expect(metadata['entity_id'], 'task-open');
    expect(metadata['local_path'], localFile.path);
    expect(metadata['retryable'], isFalse);
  });

  test('local roots reject server-only operations and missing scans', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\missing-root-for-test',
      displayName: 'Missing Root',
    );

    await repository.requestServerRootScan(folder.id);
    expect(await repository.getFolderById(folder.id), isNotNull);
    await expectLater(repository.deleteRoot(folder.id), throwsStateError);
    await expectLater(
      repository.bindRootLocalDirectory(
        folderId: folder.id,
        localPath: r'C:\FlowPlanV2\new-place',
      ),
      throwsStateError,
    );
    await expectLater(
      repository.scanRoot(folderId: folder.id),
      throwsStateError,
    );
  });

  test('server drive failures preserve local cache for retry', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-failure',
          'rootUid': 'root-failure-uid',
          'name': 'Failure Drive',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
      scanOk: false,
      deleteOk: false,
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;

    await expectLater(
      repository.requestServerRootScan(root.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('scan denied'),
        ),
      ),
    );
    await expectLater(
      repository.deleteRoot(root.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('delete denied'),
        ),
      ),
    );

    expect(await repository.getFolderById(root.id), isNotNull);
    expect(api.scanRequests, 1);
    expect(api.deletedRootIds, <String>['root-failure']);
  });

  test('bindRootLocalDirectory updates cached root node availability',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-bind-root-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final missingPath =
        '${tempDir.path}${Platform.pathSeparator}missing-local-cache';
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-bind',
          'rootUid': 'root-bind-uid',
          'name': 'Bindable Drive',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;

    final bound = await repository.bindRootLocalDirectory(
      folderId: root.id,
      localPath: missingPath,
    );

    expect(bound.localPath, missingPath);
    expect(bound.parentPath, tempDir.path);
    expect(bound.availability, FileAvailability.missing);
    final rootNode = await repository.getRootNode(root.id);
    expect(rootNode, isNotNull);
    expect(rootNode!.localPath, missingPath);
    expect(rootNode.availability, FileAvailability.missing);
  });

  test('cached server roots survive refresh failures and keep local binding',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-root-cache-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-cache',
          'rootUid': 'root-cache-uid',
          'name': 'Cached Drive',
        },
      ],
      nodeFixtures: const <Map<String, Object?>>[],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;
    await repository.bindRootLocalDirectory(
      folderId: root.id,
      localPath: tempDir.path,
    );

    api.failDriveRoots = true;
    final cachedAfterFailure = (await repository.listFolders()).single;
    expect(cachedAfterFailure.id, root.id);
    expect(cachedAfterFailure.localPath, tempDir.path);
    expect(cachedAfterFailure.availability, FileAvailability.local);

    api
      ..failDriveRoots = false
      ..rootFixtures[0] = <String, Object?>{
        'id': 'root-cache',
        'rootUid': 'root-cache-uid',
        'name': 'Renamed Cached Drive',
      };
    final refreshed = (await repository.listFolders()).single;
    expect(refreshed.id, root.id);
    expect(refreshed.displayName, 'Renamed Cached Drive');
    expect(refreshed.localPath, tempDir.path);
    expect(refreshed.availability, FileAvailability.local);
  });

  test('relocateFolder updates path derived fields and availability', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-relocate-root-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final originalDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}Original Root',
    );
    final relocatedDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}Relocated Root',
    );
    await originalDir.create();
    await relocatedDir.create();
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: originalDir.path,
      displayName: 'Original Root',
    );

    final relocated = await repository.relocateFolder(
      folderId: folder.id,
      newLocalPath: relocatedDir.path,
    );

    expect(relocated.id, folder.id);
    expect(relocated.localPath, relocatedDir.path);
    expect(relocated.parentPath, tempDir.path);
    expect(relocated.displayName, 'Relocated Root');
    expect(relocated.availability, FileAvailability.local);
  });

  test('scanRoot respects maxNodes and reports truncation', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-truncated-scan-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await File('${tempDir.path}${Platform.pathSeparator}a.txt')
        .writeAsString('a');
    await File('${tempDir.path}${Platform.pathSeparator}b.txt')
        .writeAsString('b');
    await Directory('${tempDir.path}${Platform.pathSeparator}c-folder')
        .create();
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Truncated Root',
    );
    final progress = <FileScanProgress>[];

    final result = await repository.scanRoot(
      folderId: folder.id,
      maxNodes: 2,
      onProgress: progress.add,
    );

    expect(result.scannedCount, 2);
    expect(result.truncated, isTrue);
    expect(progress.single.done, isTrue);
    expect(progress.single.scannedCount, 2);
    final rootChildren = await repository.listChildNodes(
      rootFolderId: folder.id,
      parentNodeId: result.rootNode.id,
    );
    expect(rootChildren, hasLength(1));
    expect(rootChildren.single.displayName, 'a.txt');
  });

  test('refreshDriveNodes forwards query and caches searchable results',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-query',
          'rootUid': 'root-query-uid',
          'name': 'Queryable Drive',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'node-query-file',
          'nodeUid': 'node-query-file-uid',
          'nodeType': FileNodeType.file,
          'displayName': 'brief-search-result.txt',
          'relativePath': 'Results/brief-search-result.txt',
          'mimeType': 'text/plain',
          'sizeBytes': 9,
        },
      ],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;

    final results = await repository.searchNodes(
      rootFolderId: root.id,
      query: 'brief',
      limit: 17,
    );

    expect(api.driveNodeRequests, hasLength(1));
    expect(api.driveNodeRequests.single, containsPair('rootId', 'root-query'));
    expect(api.driveNodeRequests.single, containsPair('query', 'brief'));
    expect(api.driveNodeRequests.single, containsPair('limit', 17));
    expect(api.driveNodeRequests.single['parentId'], isNull);
    expect(results.single.remoteId, 'node-query-file');
    expect(results.single.displayName, 'brief-search-result.txt');
  });

  test('refreshDriveNodes failure preserves cached node metadata for retry',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-node-cache',
          'rootUid': 'root-node-cache-uid',
          'name': 'Node Cache Drive',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'node-cache-file',
          'nodeUid': 'node-cache-file-uid',
          'nodeType': FileNodeType.file,
          'displayName': 'cached.pdf',
          'relativePath': 'cached.pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': '99',
          'hashSha256': 'hash-cached',
          'storage': <String, Object?>{
            'storageObjectId': 'storage-cached',
          },
          'currentDevice': <String, Object?>{
            'localPath': r'C:\FlowPlanV2\cached.pdf',
            'availability': FileAvailability.local,
          },
        },
      ],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;
    final rootNode = await repository.getRootNode(root.id);
    final cached = await repository.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: rootNode!.id,
    );
    api.failDriveNodes = true;

    final afterFailure = await repository.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
    );

    expect(afterFailure.single.id, cached.single.id);
    expect(afterFailure.single.hashSha256, 'hash-cached');
    expect(afterFailure.single.storageObjectId, 'storage-cached');
    expect(afterFailure.single.localPath, r'C:\FlowPlanV2\cached.pdf');
    expect(afterFailure.single.availability, FileAvailability.local);
  });

  test('recordFolderUsage persists usage rows and recent folder state',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\UsageTarget',
      displayName: 'Usage Target',
    );

    await repository.recordFolderUsage(
      folderId: folder.id,
      action: 'open',
      entityType: FileContextEntityType.task,
      entityId: 'task-usage',
      source: 'context-panel',
      metadata: <String, Object?>{'surface': 'test'},
    );
    await repository.recordFolderUsage(
      folderId: folder.id,
      action: 'preview',
      entityType: FileContextEntityType.report,
      entityId: 'report-usage',
      source: 'file-browser',
      metadata: <String, Object?>{'index': 2},
    );

    final updated = await repository.getFolderById(folder.id);
    expect(updated!.useCount, 2);
    expect(updated.lastUsedAt, isNotNull);
    final recent = await repository.listRecentFolders();
    expect(recent.single.id, folder.id);
    final usageRows = await db
        .customSelect(
          'SELECT * FROM file_folder_usages ORDER BY id ASC',
        )
        .get();
    expect(usageRows, hasLength(2));
    expect(usageRows.first.read<String>('action'), 'open');
    expect(usageRows.first.data['entity_id'], 'task-usage');
    expect(
      jsonDecode(usageRows.first.read<String>('metadata_json')),
      containsPair('surface', 'test'),
    );
    expect(usageRows.last.read<String>('source'), 'file-browser');
    expect(
      jsonDecode(usageRows.last.read<String>('metadata_json')),
      containsPair('index', 2),
    );
  });

  test('upsertLocalFile preserves folder when folderId is omitted', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-file-folder-preserve-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final localFile = File(
      '${tempDir.path}${Platform.pathSeparator}preserve.md',
    );
    await localFile.writeAsString('# Preserve');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Preserved Folder',
    );
    final first = await repository.upsertLocalFile(
      localPath: localFile.path,
      folderId: folder.id,
      previewMode: 'text',
      metadata: <String, Object?>{'phase': 'first'},
    );

    final updated = await repository.upsertLocalFile(
      localPath: localFile.path,
      previewMode: 'text',
      metadata: <String, Object?>{'phase': 'second'},
    );

    expect(updated.id, first.id);
    expect(updated.folderId, folder.id);
    expect(jsonDecode(updated.metadataJson), containsPair('phase', 'second'));
    expect(
        (await repository.listFilesForFolder(folder.id)).single.id, first.id);
  });

  test('folder and file bind helpers update existing links without downgrading',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = _repositoryWithSideEffects(db);
    final folder = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\LinkTarget',
      displayName: 'Link Target',
    );

    final taskLink = await repository.bindFolderToTask(
      taskId: 42,
      folderId: folder.id,
      reason: 'Manual task binding',
    );
    final refreshedTaskLink = await repository.createRecommendationLink(
      entityType: FileContextEntityType.task,
      entityId: '42',
      folderId: folder.id,
      confidence: 0.25,
      reason: 'Suggested later',
    );
    final eventLink = await repository.bindFolderToEvent(
      eventId: 7,
      folderId: folder.id,
      reason: 'Event attachment',
    );

    expect(refreshedTaskLink.id, taskLink.id);
    expect(refreshedTaskLink.status, FileContextStatus.confirmed);
    expect(refreshedTaskLink.relationType, FileContextRelationType.manual);
    expect(refreshedTaskLink.confidence, 1);
    expect(refreshedTaskLink.reason, 'Suggested later');
    expect(eventLink.entityType, FileContextEntityType.event);
    expect(eventLink.entityId, '7');
    expect(eventLink.status, FileContextStatus.confirmed);
    final links = await repository.listLinksForEntity(
      entityType: FileContextEntityType.task,
      entityId: '42',
    );
    expect(links.single.id, taskLink.id);
    await expectLater(repository.confirmLink(9999), throwsStateError);
    await repository.rejectLink(9999);

    final mutationRows = await db.customSelect(
      'SELECT object_type, action FROM offline_mutations '
      'WHERE object_type = ? ORDER BY id ASC',
      variables: [Variable<String>('file_context_link')],
    ).get();
    expect(
      mutationRows.map((row) => row.read<String>('action')),
      containsAllInOrder(<String>['create', 'update', 'create']),
    );
  });

  test('upsertLocalFile and version records write sync mutations', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-file-sync-side-effects-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final localFile = File('${tempDir.path}${Platform.pathSeparator}sync.md');
    await localFile.writeAsString('# Sync');
    final repository = _repositoryWithSideEffects(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Sync Root',
    );

    final created = await repository.upsertLocalFile(
      localPath: localFile.path,
      folderId: folder.id,
      mimeType: 'text/markdown',
      previewMode: 'text',
      metadata: <String, Object?>{'phase': 'create'},
    );
    await localFile.writeAsString('# Sync updated');
    final updated = await repository.upsertLocalFile(
      localPath: localFile.path,
      mimeType: null,
      previewMode: 'text',
      metadata: <String, Object?>{'phase': 'update'},
    );
    final version = await repository.addVersionRecord(
      fileId: created.id,
      versionRef: 'snapshot-sync',
      displayName: 'sync.md',
      sizeBytes: 16,
      modifiedAt: DateTime.utc(2026, 6, 10, 10),
      checksum: 'sync-checksum',
      sourceDevice: 'desktop',
      sourceBackend: 'kopia',
      note: 'sync note',
      metadata: <String, Object?>{'verified': true},
    );

    expect(updated.id, created.id);
    expect(updated.folderId, folder.id);
    expect(updated.mimeType, 'text/markdown');
    expect(jsonDecode(updated.metadataJson), containsPair('phase', 'update'));
    expect(version.sourceDevice, 'desktop');
    expect(version.note, 'sync note');
    expect(jsonDecode(version.metadataJson), containsPair('verified', true));
    final mutationRows = await db.customSelect(
      'SELECT object_type, action FROM offline_mutations '
      'WHERE object_type IN (?, ?) ORDER BY id ASC',
      variables: [
        Variable<String>('file_item'),
        Variable<String>('file_version_record'),
      ],
    ).get();
    expect(
      mutationRows.map((row) => row.read<String>('object_type')),
      <String>['file_item', 'file_item', 'file_version_record'],
    );
    expect(
      mutationRows.map((row) => row.read<String>('action')),
      <String>['create', 'update', 'create'],
    );
  });

  test(
      'server node refresh preserves local cache when remote update omits path',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-parent',
          'rootUid': 'root-parent-uid',
          'name': 'Parent Drive',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'parent-remote',
          'nodeUid': 'parent-node-uid',
          'nodeType': FileNodeType.folder,
          'displayName': 'Parent',
          'relativePath': 'Parent',
          'currentDevice': <String, Object?>{
            'localPath': r'C:\FlowPlanV2\Parent',
            'availability': FileAvailability.local,
          },
        },
        <String, Object?>{
          'id': 'child-remote',
          'nodeUid': 'child-node-uid',
          'parentId': 'parent-remote',
          'nodeType': FileNodeType.file,
          'displayName': 'child.txt',
          'relativePath': 'Parent/child.txt',
          'sizeBytes': '12',
          'storage': <String, Object?>{
            'storageObjectId': 'storage-child',
          },
          'currentDevice': <String, Object?>{
            'localPath': r'C:\FlowPlanV2\Parent\child.txt',
            'availability': FileAvailability.local,
          },
        },
      ],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;
    final rootNode = await repository.getRootNode(root.id);
    await repository.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: rootNode!.id,
    );
    final cachedParent = (await repository.searchNodes(
      rootFolderId: root.id,
      query: 'Parent',
    ))
        .singleWhere((node) => node.remoteId == 'parent-remote');
    final cachedChild = (await repository.searchNodes(
      rootFolderId: root.id,
      query: 'child',
    ))
        .single;

    api.nodeFixtures
      ..clear()
      ..addAll(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'parent-remote',
          'nodeUid': 'parent-node-uid',
          'nodeType': FileNodeType.folder,
          'displayName': 'Parent Renamed',
          'relativePath': 'Parent Renamed',
        },
        <String, Object?>{
          'id': 'child-remote',
          'nodeUid': 'child-node-uid',
          'parentId': 'parent-remote',
          'nodeType': FileNodeType.file,
          'displayName': 'child-renamed.txt',
          'relativePath': 'Parent Renamed/child-renamed.txt',
          'sizeBytes': 18.8,
          'hashSha256': 'hash-updated',
        },
      ]);
    await repository.refreshDriveNodes(rootFolderId: root.id);

    final updatedParent = (await repository.getNodeById(cachedParent.id))!;
    final updatedChild = (await repository.getNodeById(cachedChild.id))!;
    expect(updatedParent.displayName, 'Parent Renamed');
    expect(updatedParent.localPath, r'C:\FlowPlanV2\Parent');
    expect(updatedChild.displayName, 'child-renamed.txt');
    expect(updatedChild.parentNodeId, cachedParent.id);
    expect(updatedChild.localPath, r'C:\FlowPlanV2\Parent\child.txt');
    expect(updatedChild.sizeBytes, 18);
    expect(updatedChild.hashSha256, 'hash-updated');
    expect(updatedChild.storageObjectId, 'storage-child');
  });

  test('server node refresh falls back to name and existing display name',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeFileContextApi(
      rootFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root-display-fallback',
          'rootUid': 'root-display-fallback-uid',
          'name': 'Fallback Drive',
        },
      ],
      nodeFixtures: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'node-display-fallback',
          'nodeUid': 'node-display-fallback-uid',
          'nodeType': FileNodeType.file,
          'displayName': 'Original Display',
          'relativePath': 'original.txt',
        },
      ],
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final root = (await repository.listFolders()).single;
    final rootNode = await repository.getRootNode(root.id);
    await repository.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: rootNode!.id,
    );
    final cached = (await repository.searchNodes(
      rootFolderId: root.id,
      query: 'Original',
    ))
        .single;

    api.nodeFixtures
      ..clear()
      ..add(<String, Object?>{
        'id': 'node-display-fallback',
        'nodeUid': 'node-display-fallback-uid',
        'nodeType': FileNodeType.file,
        'name': 'Name Fallback',
        'relativePath': 'name-fallback.txt',
      });
    await repository.refreshDriveNodes(rootFolderId: root.id);
    final nameFallback = (await repository.getNodeById(cached.id))!;

    api.nodeFixtures
      ..clear()
      ..add(<String, Object?>{
        'id': 'node-display-fallback',
        'nodeUid': 'node-display-fallback-uid',
        'nodeType': FileNodeType.file,
        'relativePath': 'still-name-fallback.txt',
      });
    await repository.refreshDriveNodes(rootFolderId: root.id);
    final existingFallback = (await repository.getNodeById(cached.id))!;

    expect(nameFallback.displayName, 'Name Fallback');
    expect(existingFallback.displayName, 'Name Fallback');
  });

  test('scanRoot indexes image previews and progress at 100-node boundaries',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'flowplanv2-large-scan-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await File('${tempDir.path}${Platform.pathSeparator}cover.jpg')
        .writeAsBytes(<int>[255, 216, 255, 217]);
    for (var i = 0; i < 99; i++) {
      await File(
        '${tempDir.path}${Platform.pathSeparator}note-${i.toString().padLeft(2, '0')}.txt',
      ).writeAsString('note $i');
    }
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: tempDir.path,
      displayName: 'Large Scan',
    );
    final progress = <FileScanProgress>[];

    final result = await repository.scanRoot(
      folderId: folder.id,
      onProgress: progress.add,
    );

    expect(result.scannedCount, 101);
    expect(progress.map((item) => item.done), containsAll(<bool>[false, true]));
    expect(progress.first.scannedCount, 100);
    final files = await repository.listFilesForFolder(folder.id);
    final image = files.singleWhere((file) => file.displayName == 'cover.jpg');
    expect(image.mimeType, 'image/jpeg');
    expect(image.previewMode, 'image');
    expect(await repository.searchNodes(rootFolderId: folder.id, query: '   '),
        isEmpty);
  });

  test('server operations without API are no-ops or explicit state errors',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);

    await repository.syncDriveRootsFromServer();
    await repository.requestServerRootScan(12345);
    await repository.refreshDriveNodes(rootFolderId: 12345);
    await expectLater(repository.deleteRoot(12345), throwsStateError);
    await expectLater(
      repository.scanRoot(folderId: 12345),
      throwsStateError,
    );
    await expectLater(
      repository.bindRootLocalDirectory(
        folderId: 12345,
        localPath: r'C:\FlowPlanV2\missing',
      ),
      throwsStateError,
    );
  });
}

FileContextRepository _repositoryWithSideEffects(AppDatabase db) {
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

class FakeFileContextApi implements FileContextApi {
  FakeFileContextApi({
    required this.rootFixtures,
    required this.nodeFixtures,
    this.scanOk = true,
    this.deleteOk = true,
  });

  final List<Map<String, Object?>> rootFixtures;
  final List<Map<String, Object?>> nodeFixtures;
  final bool scanOk;
  final bool deleteOk;
  var scanRequests = 0;
  var failDriveRoots = false;
  var failDriveNodes = false;
  var failApplyNodeSnapshot = false;
  final deletedRootIds = <String>[];
  final driveRootQueries = <String?>[];
  final driveNodeRequests = <Map<String, Object?>>[];
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
    scanRequests++;
    return <String, dynamic>{
      'ok': scanOk,
      'rootId': rootId,
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
