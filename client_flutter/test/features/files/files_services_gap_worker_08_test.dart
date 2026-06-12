import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/core/server_api/file_context_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('repository reports explicit errors for server root edge cases',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final localOnly = FileContextRepository(db);
    final folder = await localOnly.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\local-only-root',
      displayName: 'Local Only Root',
    );

    await expectLater(localOnly.deleteRoot(folder.id), throwsStateError);

    final api = _RepositoryApi(
      driveRootFixtures: [
        <String, Object?>{
          'id': 'root-denied',
          'rootUid': 'root-denied-uid',
          'name': 'Denied Root',
        },
      ],
      deleteOk: false,
      scanOk: false,
    );
    final repository = FileContextRepository(db, null, null, () async => api);
    final remoteRoot = (await repository.listFolders()).singleWhere(
      (item) => item.remoteId == 'root-denied',
    );

    await expectLater(repository.deleteRoot(remoteRoot.id), throwsStateError);
    await expectLater(
      repository.requestServerRootScan(remoteRoot.id),
      throwsStateError,
    );

    expect(api.deletedRootIds, ['root-denied']);
    expect(api.scanRootIds, ['root-denied']);
    expect(await repository.getFolderById(remoteRoot.id), isNotNull);
  });

  test('repository binding records missing local directory metadata', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = _RepositoryApi(
      driveRootFixtures: [
        <String, Object?>{
          'id': 'root-bind',
          'rootUid': 'root-bind-uid',
          'name': 'Bindable Root',
        },
      ],
    );
    final repository = FileContextRepository(
      db,
      DataOperationLogRepository(db),
      null,
      () async => api,
    );
    final root = (await repository.listFolders()).single;

    final bound = await repository.bindRootLocalDirectory(
      folderId: root.id,
      localPath: r'C:\FlowPlanV2\does-not-exist-worker-08',
    );

    expect(bound.availability, FileAvailability.missing);
    final logs = await DataOperationLogRepository(db).listRecent();
    final bindLog = logs.singleWhere(
      (log) => log.action == 'bind_drive_root_local_directory',
    );
    expect(
      jsonDecode(bindLog.metadataJson!),
      containsPair('exists', false),
    );
  });

  test('repository recommendations keep confirmed links and old recent score',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    final confirmedFolder = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\ConfirmedAssets',
      displayName: 'Confirmed Assets',
    );
    final recentlyUsed = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\LaunchArchive',
      displayName: 'Launch Archive',
      sourceContext: 'launch assets',
    );
    final confirmed = await repository.bindFolderToTask(
      taskId: 808,
      folderId: confirmedFolder.id,
      reason: 'Already selected',
    );
    await repository.recordFolderUsage(
      folderId: recentlyUsed.id,
      action: 'open',
    );
    await db.customStatement(
      'UPDATE file_folders SET last_used_at = ? WHERE id = ?',
      [
        DateTime.now()
            .subtract(const Duration(days: 7))
            .toIso8601String(),
        recentlyUsed.id,
      ],
    );

    final recommendations = await repository.recommendFolders(
      entityType: FileContextEntityType.task,
      entityId: '808',
      title: 'Launch assets',
      limit: 4,
    );
    final links = await repository.ensureFolderRecommendations(
      entityType: FileContextEntityType.task,
      entityId: '808',
      title: 'Launch assets',
      limit: 4,
    );

    expect(recommendations.first.existingLink!.id, confirmed.id);
    expect(recommendations.first.score, 1);
    expect(
      recommendations.map((item) => item.folder.id),
      contains(recentlyUsed.id),
    );
    expect(links.map((link) => link.id), contains(confirmed.id));
  });

  test('repository scanRoot covers image and pdf mime payload boundaries',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-worker08-mime-',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    for (final name in ['asset.gif', 'scan.bmp', 'photo.webp', 'paper.pdf']) {
      await File('${dir.path}${Platform.pathSeparator}$name')
          .writeAsBytes(<int>[1, 2, 3]);
    }
    final repository = FileContextRepository(db);
    final root = await repository.upsertLocalFolder(
      localPath: dir.path,
      displayName: 'Mime Root',
    );

    await repository.scanRoot(folderId: root.id);

    final files = await repository.listFilesForFolder(root.id);
    final mimeByName = {
      for (final file in files) file.displayName: file.mimeType,
    };
    expect(mimeByName['asset.gif'], 'image/gif');
    expect(mimeByName['scan.bmp'], 'image/bmp');
    expect(mimeByName['photo.webp'], 'image/webp');
    expect(mimeByName['paper.pdf'], 'application/pdf');
    expect(
      files
          .where((file) => file.displayName != 'paper.pdf')
          .map((file) => file.previewMode),
      everyElement('image'),
    );
  });

  test('transfer service refreshes empty server payloads and removes jobs',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _service(
      db,
      _CloudApi(transfersPayload: 'not-a-list', downloadPayload: [7]),
    );
    addTearDown(service.dispose);

    await service.refreshServerTransfers();
    expect(service.refreshingServer, isFalse);
    expect(service.serverTransfers, isEmpty);

    final job = _job(status: FileTransferStatus.failed);
    await service.resumeDownload(job).catchError((_) => job);
    expect(service.jobs, isNotEmpty);

    await service.removeJob(job.id);
    expect(service.jobs, isEmpty);
  });

  test('transfer service resets refreshing flag when server refresh fails',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _service(db, _CloudApi(failTransfers: true));
    addTearDown(service.dispose);

    await expectLater(service.refreshServerTransfers(), throwsStateError);

    expect(service.refreshingServer, isFalse);
    expect(service.serverTransfers, isEmpty);
  });

  test('transfer service reports completed zero-byte progress and prepared download failures',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-worker08-prepared-download-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final targetPath = '${dir.path}${Platform.pathSeparator}fallback-name.txt';
    final service = _service(db, _CloudApi());
    addTearDown(service.dispose);

    expect(
      _job(
        status: FileTransferStatus.uploaded,
        totalBytes: 0,
        expectedChunks: 0,
      ).progress,
      1,
    );
    expect(
      _job(
        status: FileTransferStatus.downloading,
        totalBytes: 0,
        expectedChunks: 0,
      ).progress,
      0,
    );

    await expectLater(
      service.downloadPreparedSession(
        <String, Object?>{
          'downloadSession': <String, Object?>{
            'sessionId': 'prepared-zero',
            'storageObjectId': 'storage-zero',
            'totalBytes': 0,
            'chunkSize': 4,
          },
          'node': <String, Object?>{},
        },
        targetPath,
      ),
      throwsStateError,
    );

    final failed = service.jobs.single;
    expect(failed.fileName, 'fallback-name.txt');
    expect(failed.status, FileTransferStatus.failed);
    expect(failed.errorMessage, contains('0'));
    expect(await _auditActions(db), contains('file_transfer.download.failed'));
  });

  test('resumeUpload failure records failed retry job', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-worker08-resume-upload-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}${Platform.pathSeparator}retry.txt');
    await file.writeAsString('retry me');
    final bytes = await file.readAsBytes();
    final service = _service(
      db,
      _CloudApi(
        missingChunks: [0],
        uploadCompleteOk: false,
        uploadCompleteReason: 'retry denied',
      ),
    );
    addTearDown(service.dispose);
    final job = _job(
      direction: FileTransferDirection.upload,
      localPath: file.path,
      fileName: 'retry.txt',
      totalBytes: bytes.length,
      chunkSize: bytes.length,
      expectedChunks: 1,
      status: FileTransferStatus.failed,
      sessionId: 'upload-session-retry',
      checksum: sha256.convert(bytes).toString(),
    );

    await expectLater(service.resumeUpload(job), throwsStateError);

    expect(service.jobs.single.canResume, isTrue);
    expect(await _auditActions(db), contains('file_transfer.upload.failed'));
  });

  test('download range failure records failed retry job', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-worker08-download-fail-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final target = '${dir.path}${Platform.pathSeparator}range.txt';
    final service = _service(
      db,
      _CloudApi(downloadOk: false, downloadReason: 'range denied'),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.resumeDownload(
        _job(
          direction: FileTransferDirection.download,
          localPath: target,
          fileName: 'range.txt',
          totalBytes: 4,
          chunkSize: 2,
          expectedChunks: 2,
          status: FileTransferStatus.failed,
          sessionId: 'download-session-range',
          storageObjectId: 'storage-range',
        ),
      ),
      throwsStateError,
    );

    expect(service.jobs.single.canResume, isTrue);
    expect(await File('$target.flowplanv2.part').exists(), isTrue);
    expect(await _auditActions(db), contains('file_transfer.download.resume'));
  });

  test('download replaces an existing target after checksum validation',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-worker08-download-replace-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final target = File('${dir.path}${Platform.pathSeparator}replace.txt');
    await target.writeAsString('old contents');
    final bytes = utf8.encode('new contents');
    final service = _service(db, _CloudApi(downloadPayload: bytes));
    addTearDown(service.dispose);

    final job = await service.downloadPreparedSession(
      <String, Object?>{
        'downloadSession': <String, Object?>{
          'sessionId': 'prepared-name',
          'storageObjectId': 'storage-name',
          'totalBytes': bytes.length,
          'chunkSize': bytes.length,
          'checksum': sha256.convert(bytes).toString(),
        },
        'node': <String, Object?>{
          'name': 'server-name.txt',
        },
      },
      target.path,
    );

    expect(job.status, FileTransferStatus.downloaded);
    expect(job.fileName, 'server-name.txt');
    expect(await target.readAsString(), 'new contents');
  });

  test('interaction service reports server open plan action messages',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    final root = await repository.upsertLocalFolder(
      localPath: r'C:\FlowPlanV2\OpenPlanRoot',
      displayName: 'Open Plan Root',
    );
    final node = _node(
      id: 1,
      rootFolderId: root.id,
      remoteId: 'node-open-plan',
      storageObjectId: 'storage-open-plan',
      availability: FileAvailability.remoteOnly,
    );
    final api = _RepositoryApi(
      openPlanFixture: <String, dynamic>{
        'action': 'needs_upload_or_relink',
      },
    );
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isFalse);
    expect(result.action, 'needs_upload_or_relink');
    expect(result.needsDownload, isFalse);
    expect(result.message, isNotEmpty);
    expect(api.openPlanNodeIds, ['node-open-plan']);
  });
}

FileTransferService _service(AppDatabase db, _CloudApi api) {
  return FileTransferService(
    apiLoader: () async => api,
    operationLogs: DataOperationLogRepository(db),
  );
}

FileTransferJob _job({
  String direction = FileTransferDirection.download,
  String localPath = r'C:\FlowPlanV2\job.txt',
  String fileName = 'job.txt',
  int totalBytes = 1,
  int chunkSize = 1,
  int expectedChunks = 1,
  int transferredBytes = 0,
  required String status,
  String? sessionId = 'download-session-1',
  String? storageObjectId = 'storage-object-1',
  String? checksum,
  String? serverChecksum,
}) {
  final now = DateTime.utc(2026, 6, 10, 8);
  return FileTransferJob(
    id: 'worker08-$direction-$fileName',
    direction: direction,
    fileName: fileName,
    localPath: localPath,
    totalBytes: totalBytes,
    chunkSize: chunkSize,
    expectedChunks: expectedChunks,
    transferredBytes: transferredBytes,
    status: status,
    createdAt: now,
    updatedAt: now,
    sessionId: sessionId,
    storageObjectId: storageObjectId,
    checksum: checksum,
    serverChecksum: serverChecksum,
  );
}

FileNode _node({
  required int id,
  required int rootFolderId,
  String? remoteId,
  String localPath = '',
  String relativePath = 'remote.txt',
  String availability = FileAvailability.remoteOnly,
  String? storageObjectId,
}) {
  final now = DateTime.utc(2026, 6, 10, 8);
  return FileNode(
    id: id,
    nodeUid: 'node-$id',
    remoteId: remoteId,
    rootFolderId: rootFolderId,
    parentNodeId: null,
    itemType: FileNodeType.file,
    displayName: 'remote.txt',
    localPath: localPath,
    relativePath: relativePath,
    mimeType: 'text/plain',
    sizeBytes: 10,
    modifiedAt: now,
    availability: availability,
    scanBatchId: 'worker08',
    depth: 1,
    hashSha256: 'hash-$id',
    storageObjectId: storageObjectId,
    createdAt: now,
    updatedAt: now,
  );
}

Future<List<String>> _auditActions(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT action FROM data_operation_logs ORDER BY id ASC')
      .get();
  return rows.map((row) => row.read<String>('action')).toList();
}

class _RepositoryApi implements FileContextApi {
  _RepositoryApi({
    this.driveRootFixtures = const <Map<String, Object?>>[],
    this.deleteOk = true,
    this.scanOk = true,
    this.openPlanFixture,
  });

  final List<Map<String, Object?>> driveRootFixtures;
  final List<Map<String, Object?>> driveNodeFixtures =
      const <Map<String, Object?>>[];
  final bool deleteOk;
  final bool scanOk;
  final Map<String, dynamic>? openPlanFixture;
  final deletedRootIds = <String>[];
  final scanRootIds = <String>[];
  final openPlanNodeIds = <String>[];

  @override
  Future<Map<String, dynamic>> driveRoots({String? query}) async {
    return <String, dynamic>{'roots': driveRootFixtures};
  }

  @override
  Future<Map<String, dynamic>> driveNodes({
    String? rootId,
    String? parentId,
    String? query,
    int limit = 300,
    int offset = 0,
  }) async {
    return <String, dynamic>{'nodes': driveNodeFixtures};
  }

  @override
  Future<Map<String, dynamic>> deleteDriveRoot({
    required String rootId,
  }) async {
    deletedRootIds.add(rootId);
    return <String, dynamic>{
      'ok': deleteOk,
      if (!deleteOk) 'error': 'delete rejected',
    };
  }

  @override
  Future<Map<String, dynamic>> scanDriveRoot({
    required String rootId,
    String? rootPath,
    int maxNodes = 0,
  }) async {
    scanRootIds.add(rootId);
    return <String, dynamic>{
      'ok': scanOk,
      if (!scanOk) 'reason': 'scan rejected',
    };
  }

  @override
  Future<Map<String, dynamic>> openPlan({
    required String nodeId,
    Map<String, Object?> localIdentity = const <String, Object?>{},
  }) async {
    openPlanNodeIds.add(nodeId);
    return openPlanFixture ?? <String, dynamic>{'action': 'open_local'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CloudApi implements FileCloudApi {
  _CloudApi({
    this.missingChunks = const <int>[],
    this.uploadCompleteOk = true,
    this.uploadCompleteReason = 'upload denied',
    this.downloadPayload = const <int>[],
    this.downloadOk = true,
    this.downloadReason = 'download denied',
    this.transfersPayload = const <Map<String, Object?>>[],
    this.failTransfers = false,
  });

  final List<int> missingChunks;
  final int receivedBytes = 0;
  final bool uploadCompleteOk;
  final String uploadCompleteReason;
  final List<int> downloadPayload;
  final bool downloadOk;
  final String downloadReason;
  final Object? transfersPayload;
  final bool failTransfers;

  @override
  Future<Map<String, dynamic>> missingUploadChunks(String sessionId) async {
    return <String, dynamic>{
      'missingChunks': missingChunks,
      'session': <String, Object?>{'receivedBytes': receivedBytes},
    };
  }

  @override
  Future<Map<String, dynamic>> uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required int startByte,
    required Uint8List bytes,
    String? checksum,
  }) async {
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeUploadSession(String sessionId) async {
    return <String, dynamic>{
      'ok': uploadCompleteOk,
      if (!uploadCompleteOk) 'reason': uploadCompleteReason,
      if (uploadCompleteOk)
        'storageObject': <String, Object?>{
          'storageObjectId': 'storage-worker08',
        },
    };
  }

  @override
  Future<Map<String, dynamic>> downloadRange({
    required String sessionId,
    required int start,
    required int end,
  }) async {
    if (!downloadOk) {
      return <String, dynamic>{'ok': false, 'reason': downloadReason};
    }
    final clampedEnd =
        end >= downloadPayload.length ? downloadPayload.length - 1 : end;
    final bytes = downloadPayload.sublist(start, clampedEnd + 1);
    return <String, dynamic>{
      'ok': true,
      'chunks': [
        <String, Object?>{'payloadBase64': base64Encode(bytes)},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> transfers({
    String? direction,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    if (failTransfers) {
      throw StateError('transfers offline');
    }
    return <String, dynamic>{'transfers': transfersPayload};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
