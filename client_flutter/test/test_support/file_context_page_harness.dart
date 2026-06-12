import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/core/server_api/file_context_api.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_context_page.dart';
import 'package:flowplanv2/features/files/presentation/file_context_panel.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final fileContextHarnessNow = DateTime.utc(2026, 6, 9, 8);

FileFolder fileFolderFixture({
  int id = 1,
  String folderUid = 'folder-1',
  String provider = FileProviderKind.serverStorage,
  String displayName = 'Server Drive A',
  String? localPath,
  String? remoteId = 'root-a',
  String? parentPath,
  String? sourceContext,
  bool pinned = false,
  String availability = FileAvailability.remoteOnly,
}) {
  return FileFolder(
    id: id,
    folderUid: folderUid,
    provider: provider,
    displayName: displayName,
    localPath: localPath,
    remoteId: remoteId,
    parentPath: parentPath,
    sourceContext: sourceContext,
    pinned: pinned,
    availability: availability,
    useCount: 0,
    lastUsedAt: null,
    metadataJson: '{}',
    createdAt: fileContextHarnessNow,
    updatedAt: fileContextHarnessNow,
  );
}

FileNode fileNodeFixture({
  required int id,
  required int rootFolderId,
  String nodeUid = 'node',
  String? remoteId,
  int? parentNodeId,
  String itemType = FileNodeType.file,
  String displayName = 'Sprint brief.txt',
  String localPath = '',
  String relativePath = 'Sprint brief.txt',
  String? mimeType = 'text/plain',
  int? sizeBytes = 128,
  String availability = FileAvailability.remoteOnly,
  String? storageObjectId,
  int depth = 1,
}) {
  return FileNode(
    id: id,
    nodeUid: '$nodeUid-$id',
    remoteId: remoteId,
    rootFolderId: rootFolderId,
    parentNodeId: parentNodeId,
    itemType: itemType,
    displayName: displayName,
    localPath: localPath,
    relativePath: relativePath,
    mimeType: itemType == FileNodeType.folder ? null : mimeType,
    sizeBytes: itemType == FileNodeType.folder ? null : sizeBytes,
    modifiedAt: fileContextHarnessNow,
    availability: availability,
    scanBatchId: 'test-scan',
    depth: depth,
    hashSha256: 'hash-$id',
    storageObjectId: storageObjectId,
    createdAt: fileContextHarnessNow,
    updatedAt: fileContextHarnessNow,
  );
}

FileContextLink fileContextLinkFixture({
  required int id,
  required String entityType,
  required String entityId,
  required String targetType,
  required int targetId,
  String relationType = FileContextRelationType.recommended,
  String status = FileContextStatus.candidate,
  double confidence = 0.72,
  String? reason = 'Matches the current work title',
}) {
  return FileContextLink(
    id: id,
    linkUid: 'link-$id',
    entityType: entityType,
    entityId: entityId,
    targetType: targetType,
    targetId: targetId,
    relationType: relationType,
    confidence: confidence,
    reason: reason,
    status: status,
    createdAt: fileContextHarnessNow,
    updatedAt: fileContextHarnessNow,
    confirmedAt:
        status == FileContextStatus.confirmed ? fileContextHarnessNow : null,
  );
}

Future<void> pumpFileContextPageHarness(
  WidgetTester tester, {
  required FakeFileContextRepository repository,
  FakeFileContextApi? contextApi,
  FakeFileCloudApi? cloudApi,
  FakeFilePicker? filePicker,
  FileContextInteractionService? interactionService,
  FileTransferService? transferService,
  bool withRouter = false,
  Size size = const Size(1280, 900),
}) async {
  await _pumpHarness(
    tester,
    repository: repository,
    contextApi: contextApi,
    cloudApi: cloudApi,
    filePicker: filePicker,
    interactionService: interactionService,
    transferService: transferService,
    withRouter: withRouter,
    size: size,
    child: const FileContextPage(),
  );
}

Future<void> pumpEntityFileContextPanelHarness(
  WidgetTester tester, {
  required FakeFileContextRepository repository,
  String entityType = FileContextEntityType.task,
  String entityId = 'task-42',
  String title = 'Alpha launch brief',
  String? description = 'Prepare sprint launch assets',
  Size size = const Size(900, 720),
}) async {
  await _pumpHarness(
    tester,
    repository: repository,
    size: size,
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: EntityFileContextPanel(
          entityType: entityType,
          entityId: entityId,
          title: title,
          description: description,
        ),
      ),
    ),
  );
}

Future<void> pumpFileContextUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 8,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required FakeFileContextRepository repository,
  required Widget child,
  FakeFileContextApi? contextApi,
  FakeFileCloudApi? cloudApi,
  FakeFilePicker? filePicker,
  FileContextInteractionService? interactionService,
  FileTransferService? transferService,
  bool withRouter = false,
  Size size = const Size(1280, 900),
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (filePicker != null) {
    final previousPicker = _currentFilePickerOrNull();
    FilePicker.platform = filePicker;
    addTearDown(() {
      FilePicker.platform = previousPicker ?? FakeFilePicker();
    });
  }

  final app = withRouter
      ? MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => child,
              ),
              GoRoute(
                path: AppRoutes.fileTransfers,
                builder: (context, state) => const Scaffold(
                  body: Text('Transfer center route'),
                ),
              ),
            ],
          ),
        )
      : MaterialApp(home: child);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileContextRepositoryProvider.overrideWithValue(repository),
        fileContextApiProvider.overrideWith(
          (ref) async => contextApi ?? FakeFileContextApi(),
        ),
        fileCloudApiProvider.overrideWith(
          (ref) async => cloudApi ?? FakeFileCloudApi(),
        ),
        if (interactionService != null)
          fileContextInteractionServiceProvider
              .overrideWithValue(interactionService),
        if (transferService != null)
          fileTransferServiceProvider.overrideWith((ref) => transferService),
      ],
      child: app,
    ),
  );
  await tester.pump();
}

FilePicker? _currentFilePickerOrNull() {
  try {
    return FilePicker.platform;
  } catch (_) {
    return null;
  }
}

class FakeFileContextRepository implements FileContextRepository {
  FakeFileContextRepository({
    List<FileFolder> roots = const <FileFolder>[],
    List<FileFolder> rootsAfterSync = const <FileFolder>[],
    List<FileNode> nodes = const <FileNode>[],
    List<FileContextLink> links = const <FileContextLink>[],
    List<int> recommendationFolderIds = const <int>[],
  })  : roots = List<FileFolder>.from(roots),
        rootsAfterSync = List<FileFolder>.from(rootsAfterSync),
        links = List<FileContextLink>.from(links),
        recommendationFolderIds = List<int>.from(recommendationFolderIds) {
    for (final node in nodes) {
      nodesById[node.id] = node;
    }
  }

  List<FileFolder> roots;
  List<FileFolder> rootsAfterSync;
  final Map<int, FileNode> nodesById = <int, FileNode>{};
  List<FileContextLink> links;
  List<int> recommendationFolderIds;

  Object? listFoldersError;
  Object? refreshDriveNodesError;
  Object? listChildNodesError;
  Object? scanError;
  Object? deleteError;
  Completer<List<FileFolder>>? listFoldersCompleter;
  Completer<void>? scanCompleter;

  void Function(FakeFileContextRepository repository, int rootFolderId)?
      onRequestServerRootScan;

  var listFoldersCalls = 0;
  var syncDriveRootsCalls = 0;
  final refreshDriveNodeRequests = <Map<String, Object?>>[];
  final searchRequests = <Map<String, Object?>>[];
  final scanRequests = <int>[];
  final boundRootPaths = <Map<String, Object?>>[];
  final deletedRootIds = <int>[];
  final confirmedLinkIds = <int>[];
  final rejectedLinkIds = <int>[];
  final boundNodeIds = <int>[];
  final recordedNodeActions = <String>[];
  final recordedFolderActions = <String>[];
  final recordedNodeOperations = <Map<String, Object?>>[];
  final recordedFolderUsages = <Map<String, Object?>>[];
  final addedVersionRecords = <Map<String, Object?>>[];

  @override
  Future<List<FileFolder>> listFolders({int limit = 200}) async {
    listFoldersCalls++;
    final error = listFoldersError;
    if (error != null) {
      throw error;
    }
    final completer = listFoldersCompleter;
    if (completer != null) {
      return completer.future;
    }
    return roots.take(limit).toList(growable: false);
  }

  @override
  Future<void> syncDriveRootsFromServer() async {
    syncDriveRootsCalls++;
    if (rootsAfterSync.isNotEmpty) {
      roots = List<FileFolder>.from(rootsAfterSync);
    }
  }

  @override
  Future<FileFolder?> getFolderById(int id) async {
    return _folderById(id);
  }

  @override
  Future<void> refreshDriveNodes({
    required int rootFolderId,
    int? parentNodeId,
    String? query,
    int limit = 300,
  }) async {
    refreshDriveNodeRequests.add(<String, Object?>{
      'rootFolderId': rootFolderId,
      'parentNodeId': parentNodeId,
      'query': query,
      'limit': limit,
    });
    final error = refreshDriveNodesError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<FileNode?> getRootNode(int rootFolderId) async {
    for (final node in nodesById.values) {
      if (node.rootFolderId == rootFolderId && node.parentNodeId == null) {
        return node;
      }
    }
    return null;
  }

  @override
  Future<FileNode?> getNodeById(int nodeId) async {
    return nodesById[nodeId];
  }

  @override
  Future<List<FileNode>> listChildNodes({
    required int rootFolderId,
    int? parentNodeId,
  }) async {
    final error = listChildNodesError;
    if (error != null) {
      throw error;
    }
    return nodesById.values
        .where(
          (node) =>
              node.rootFolderId == rootFolderId &&
              node.parentNodeId == parentNodeId,
        )
        .toList(growable: false)
      ..sort(_nodeSort);
  }

  @override
  Future<List<FileNode>> searchNodes({
    required int rootFolderId,
    required String query,
    int limit = 120,
  }) async {
    searchRequests.add(<String, Object?>{
      'rootFolderId': rootFolderId,
      'query': query,
      'limit': limit,
    });
    final needle = query.toLowerCase();
    return nodesById.values
        .where(
          (node) =>
              node.rootFolderId == rootFolderId &&
              node.parentNodeId != null &&
              node.displayName.toLowerCase().contains(needle),
        )
        .take(limit)
        .toList(growable: false)
      ..sort(_nodeSort);
  }

  @override
  Future<void> requestServerRootScan(int folderId) async {
    scanRequests.add(folderId);
    final error = scanError;
    if (error != null) {
      throw error;
    }
    final completer = scanCompleter;
    if (completer != null) {
      await completer.future;
    }
    onRequestServerRootScan?.call(this, folderId);
  }

  @override
  Future<FileFolder> bindRootLocalDirectory({
    required int folderId,
    required String localPath,
  }) async {
    boundRootPaths.add(<String, Object?>{
      'folderId': folderId,
      'localPath': localPath,
    });
    final index = roots.indexWhere((root) => root.id == folderId);
    if (index < 0) {
      throw StateError('Folder not found.');
    }
    final updated = _copyFolder(
      roots[index],
      localPath: localPath,
      availability: FileAvailability.local,
    );
    roots[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteRoot(int folderId) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    deletedRootIds.add(folderId);
    roots.removeWhere((root) => root.id == folderId);
    nodesById.removeWhere((_, node) => node.rootFolderId == folderId);
  }

  @override
  Future<List<FileContextLink>> ensureFolderRecommendations({
    required String entityType,
    required String entityId,
    required String title,
    String? description,
    String? location,
    int limit = 5,
  }) async {
    for (final folderId in recommendationFolderIds.take(limit)) {
      final hasVisibleLink = links.any(
        (link) =>
            link.entityType == entityType &&
            link.entityId == entityId &&
            link.targetType == FileContextTargetType.folder &&
            link.targetId == folderId &&
            link.status != FileContextStatus.rejected,
      );
      final wasRejected = links.any(
        (link) =>
            link.entityType == entityType &&
            link.entityId == entityId &&
            link.targetType == FileContextTargetType.folder &&
            link.targetId == folderId &&
            link.status == FileContextStatus.rejected,
      );
      if (!hasVisibleLink && !wasRejected) {
        links.add(
          fileContextLinkFixture(
            id: _nextLinkId(),
            entityType: entityType,
            entityId: entityId,
            targetType: FileContextTargetType.folder,
            targetId: folderId,
          ),
        );
      }
    }
    return listLinksForEntity(entityType: entityType, entityId: entityId);
  }

  @override
  Future<List<FileContextLink>> listLinksForEntity({
    required String entityType,
    required String entityId,
  }) async {
    return links
        .where(
          (link) =>
              link.entityType == entityType &&
              link.entityId == entityId &&
              link.status != FileContextStatus.rejected,
        )
        .toList(growable: false);
  }

  @override
  Future<FileContextLink> confirmLink(int linkId) async {
    confirmedLinkIds.add(linkId);
    final index = links.indexWhere((link) => link.id == linkId);
    if (index < 0) {
      throw StateError('Link not found.');
    }
    final link = links[index];
    final updated = _copyLink(
      link,
      relationType: link.relationType == FileContextRelationType.recommended
          ? FileContextRelationType.manual
          : link.relationType,
      status: FileContextStatus.confirmed,
      confirmedAt: fileContextHarnessNow,
    );
    links[index] = updated;
    return updated;
  }

  @override
  Future<void> rejectLink(int linkId) async {
    rejectedLinkIds.add(linkId);
    final index = links.indexWhere((link) => link.id == linkId);
    if (index < 0) {
      return;
    }
    links[index] = _copyLink(links[index], status: FileContextStatus.rejected);
  }

  @override
  Future<FileContextLink> bindNodeToEntity({
    required String entityType,
    required String entityId,
    required FileNode node,
    String relationType = FileContextRelationType.manual,
    String? reason,
  }) async {
    boundNodeIds.add(node.id);
    final link = fileContextLinkFixture(
      id: _nextLinkId(),
      entityType: entityType,
      entityId: entityId,
      targetType: node.isFolder
          ? FileContextTargetType.folderNode
          : FileContextTargetType.fileNode,
      targetId: node.id,
      relationType: relationType,
      status: FileContextStatus.confirmed,
      confidence: 1,
      reason: reason,
    );
    links.add(link);
    return link;
  }

  @override
  Future<void> recordFileNodeOperation({
    required FileNode node,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    recordedNodeActions.add(action);
    recordedNodeOperations.add(<String, Object?>{
      'nodeId': node.id,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'metadata': metadata,
    });
  }

  @override
  Future<void> recordFolderUsage({
    required int folderId,
    required String action,
    String? entityType,
    String? entityId,
    String source = 'user',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    recordedFolderActions.add(action);
    recordedFolderUsages.add(<String, Object?>{
      'folderId': folderId,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'source': source,
      'metadata': metadata,
    });
  }

  @override
  Future<FileVersionRecord> addVersionRecord({
    required int fileId,
    required String versionRef,
    required String displayName,
    String provider = 'kopia',
    int? sizeBytes,
    DateTime? modifiedAt,
    String? checksum,
    String? sourceDevice,
    String? sourceBackend,
    String? note,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final id = addedVersionRecords.length + 1;
    addedVersionRecords.add(<String, Object?>{
      'fileId': fileId,
      'versionRef': versionRef,
      'displayName': displayName,
      'provider': provider,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAt,
      'checksum': checksum,
      'sourceDevice': sourceDevice,
      'sourceBackend': sourceBackend,
      'note': note,
      'metadata': metadata,
    });
    return FileVersionRecord(
      id: id,
      versionUid: 'version-$id',
      fileId: fileId,
      provider: provider,
      versionRef: versionRef,
      displayName: displayName,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      checksum: checksum,
      sourceDevice: sourceDevice,
      sourceBackend: sourceBackend,
      note: note,
      metadataJson: '{}',
      createdAt: fileContextHarnessNow,
    );
  }

  @override
  Future<List<FileFolder>> listConfirmedFoldersForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final folderIds = links
        .where(
          (link) =>
              link.entityType == entityType &&
              link.entityId == entityId &&
              link.targetType == FileContextTargetType.folder &&
              link.status == FileContextStatus.confirmed,
        )
        .map((link) => link.targetId)
        .toSet();
    return roots.where((root) => folderIds.contains(root.id)).toList();
  }

  void upsertNode(FileNode node) {
    nodesById[node.id] = node;
  }

  FileFolder? _folderById(int id) {
    for (final root in roots) {
      if (root.id == id) {
        return root;
      }
    }
    return null;
  }

  int _nextLinkId() {
    if (links.isEmpty) {
      return 1;
    }
    return links.map((link) => link.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFileContextApi implements FileContextApi {
  FakeFileContextApi({
    this.openPlanAction = 'download_then_open',
    this.downloadRequestOk = true,
    this.throwOpenPlan = false,
    this.openPlanFixture,
    this.downloadRequestFixture,
  });

  final String openPlanAction;
  final bool downloadRequestOk;
  final bool throwOpenPlan;
  final Map<String, dynamic>? openPlanFixture;
  final Map<String, dynamic>? downloadRequestFixture;
  final openPlanNodeIds = <String>[];
  final openPlanRequests = <Map<String, Object?>>[];
  final downloadRequests = <Map<String, Object?>>[];
  final deviceLocations = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> openPlan({
    required String nodeId,
    Map<String, Object?> localIdentity = const <String, Object?>{},
  }) async {
    openPlanNodeIds.add(nodeId);
    openPlanRequests.add(<String, Object?>{
      'nodeId': nodeId,
      'localIdentity': localIdentity,
    });
    if (throwOpenPlan) {
      throw StateError('open-plan offline');
    }
    return openPlanFixture ??
        <String, dynamic>{
          'action': openPlanAction,
          'message': 'Server copy requires a download',
        };
  }

  @override
  Future<Map<String, dynamic>> createDownloadRequest({
    required String nodeId,
    String? targetPath,
  }) async {
    downloadRequests.add(<String, Object?>{
      'nodeId': nodeId,
      'targetPath': targetPath,
    });
    return downloadRequestFixture ??
        <String, dynamic>{
          'ok': downloadRequestOk,
          if (!downloadRequestOk) 'reason': 'download denied',
          if (downloadRequestOk)
            'downloadSession': <String, Object?>{
              'sessionId': 'download-session-1',
              'storageObjectId': 'storage-object-1',
              'totalBytes': 128,
              'chunkSize': 128,
              'checksum': 'server-checksum-1',
            },
          if (downloadRequestOk)
            'node': <String, Object?>{
              'displayName': 'downloaded-file.txt',
              'storage': <String, Object?>{
                'storageObjectId': 'storage-object-1',
                'checksum': 'server-checksum-1',
              },
            },
        };
  }

  @override
  Future<Map<String, dynamic>> upsertDeviceLocation({
    required String nodeId,
    required String localPath,
    String availability = 'available',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    deviceLocations.add(<String, Object?>{
      'nodeId': nodeId,
      'localPath': localPath,
      'availability': availability,
      'metadata': metadata,
    });
    return <String, dynamic>{'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFileCloudApi implements FileCloudApi {
  FakeFileCloudApi({
    this.storageRoot = '/server/storage',
    this.storageObjectsFixture = const <Map<String, Object?>>[],
    this.versionsFixture = const <Map<String, Object?>>[],
    this.snapshotOk = true,
    this.registerOk = true,
    this.refreshVersionsOk = true,
    this.downloadVersionCopyOk = true,
    this.prepareRestoreOk = true,
  });

  final String storageRoot;
  final List<Map<String, Object?>> storageObjectsFixture;
  final List<Map<String, Object?>> versionsFixture;
  final bool snapshotOk;
  final bool registerOk;
  final bool refreshVersionsOk;
  final bool downloadVersionCopyOk;
  final bool prepareRestoreOk;
  final createdSnapshots = <Map<String, Object?>>[];
  final storageObjectRequests = <Map<String, Object?>>[];
  final versionRequests = <String>[];
  final registeredStorageObjects = <Map<String, Object?>>[];
  final refreshedVersions = <Map<String, Object?>>[];
  final downloadedVersionCopies = <Map<String, Object?>>[];
  final preparedRestores = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> storageStatus() async {
    return <String, dynamic>{'rootPath': storageRoot};
  }

  @override
  Future<Map<String, dynamic>> storageObjects({
    String? localPath,
    String? nodeId,
    int limit = 100,
    int offset = 0,
  }) async {
    storageObjectRequests.add(<String, Object?>{
      'localPath': localPath,
      'nodeId': nodeId,
      'limit': limit,
      'offset': offset,
    });
    return <String, dynamic>{'storageObjects': storageObjectsFixture};
  }

  @override
  Future<Map<String, dynamic>> versions(String fileId) async {
    versionRequests.add(fileId);
    return <String, dynamic>{'versions': versionsFixture};
  }

  @override
  Future<Map<String, dynamic>> createKopiaSnapshot({
    required String rootPath,
    String? rootId,
  }) async {
    createdSnapshots.add(<String, Object?>{
      'rootPath': rootPath,
      'rootId': rootId,
    });
    return <String, dynamic>{
      'ok': snapshotOk,
      if (!snapshotOk) 'reason': 'snapshot denied',
    };
  }

  @override
  Future<Map<String, dynamic>> registerStorageObject({
    required String localPath,
    String? fileName,
    String? objectKey,
    String? fileNodeId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    registeredStorageObjects.add(<String, Object?>{
      'localPath': localPath,
      'fileName': fileName,
      'objectKey': objectKey,
      'fileNodeId': fileNodeId,
      'metadata': metadata,
    });
    return <String, dynamic>{
      'ok': registerOk,
      if (!registerOk) 'reason': 'register denied',
    };
  }

  @override
  Future<Map<String, dynamic>> refreshKopiaVersions({
    required String fileId,
    required String filePath,
    String? displayName,
  }) async {
    refreshedVersions.add(<String, Object?>{
      'fileId': fileId,
      'filePath': filePath,
      'displayName': displayName,
    });
    return <String, dynamic>{
      'ok': refreshVersionsOk,
      if (!refreshVersionsOk) 'reason': 'refresh denied',
    };
  }

  @override
  Future<Map<String, dynamic>> downloadVersionCopy({
    required String versionId,
    required String targetPath,
    String? auditNote,
  }) async {
    downloadedVersionCopies.add(<String, Object?>{
      'versionId': versionId,
      'targetPath': targetPath,
      'auditNote': auditNote,
    });
    return <String, dynamic>{
      'ok': downloadVersionCopyOk,
      if (!downloadVersionCopyOk) 'reason': 'copy denied',
    };
  }

  @override
  Future<Map<String, dynamic>> prepareVersionRestore({
    required String versionId,
    String? targetPath,
  }) async {
    preparedRestores.add(<String, Object?>{
      'versionId': versionId,
      'targetPath': targetPath,
    });
    return <String, dynamic>{
      'ok': prepareRestoreOk,
      if (prepareRestoreOk) 'prepare': 'restore plan for $versionId',
      if (!prepareRestoreOk) 'reason': 'restore denied',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFilePicker extends FilePicker {
  FakeFilePicker({this.directoryPath, this.savePath});

  final String? directoryPath;
  final String? savePath;
  final directoryRequests = <Map<String, Object?>>[];
  final saveRequests = <Map<String, Object?>>[];

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    directoryRequests.add(<String, Object?>{
      'dialogTitle': dialogTitle,
      'initialDirectory': initialDirectory,
    });
    return directoryPath;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveRequests.add(<String, Object?>{
      'dialogTitle': dialogTitle,
      'fileName': fileName,
      'initialDirectory': initialDirectory,
    });
    return savePath;
  }
}

int _nodeSort(FileNode left, FileNode right) {
  if (left.isFolder != right.isFolder) {
    return left.isFolder ? -1 : 1;
  }
  return left.displayName.compareTo(right.displayName);
}

FileFolder _copyFolder(
  FileFolder folder, {
  String? localPath,
  String? availability,
}) {
  return FileFolder(
    id: folder.id,
    folderUid: folder.folderUid,
    provider: folder.provider,
    displayName: folder.displayName,
    localPath: localPath ?? folder.localPath,
    remoteId: folder.remoteId,
    parentPath: folder.parentPath,
    sourceContext: folder.sourceContext,
    pinned: folder.pinned,
    availability: availability ?? folder.availability,
    useCount: folder.useCount,
    lastUsedAt: folder.lastUsedAt,
    metadataJson: folder.metadataJson,
    createdAt: folder.createdAt,
    updatedAt: fileContextHarnessNow,
  );
}

FileContextLink _copyLink(
  FileContextLink link, {
  String? relationType,
  String? status,
  DateTime? confirmedAt,
}) {
  return FileContextLink(
    id: link.id,
    linkUid: link.linkUid,
    entityType: link.entityType,
    entityId: link.entityId,
    targetType: link.targetType,
    targetId: link.targetId,
    relationType: relationType ?? link.relationType,
    confidence: link.confidence,
    reason: link.reason,
    status: status ?? link.status,
    createdAt: link.createdAt,
    updatedAt: fileContextHarnessNow,
    confirmedAt: confirmedAt ?? link.confirmedAt,
  );
}
