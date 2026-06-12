import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('file constants expose sealed values used by repository and transfer UI',
      () {
    expect(FileProviderKind.local, 'local');
    expect(FileProviderKind.serverStorage, 'server_storage');
    expect(FileProviderKind.oneDrive, 'onedrive');
    expect(FileAvailability.local, 'local');
    expect(FileAvailability.remoteOnly, 'remote_only');
    expect(FileAvailability.missing, 'missing');
    expect(FileAvailability.conflict, 'conflict');
    expect(FileContextEntityType.task, 'task');
    expect(FileContextEntityType.event, 'event');
    expect(FileContextEntityType.project, 'project');
    expect(FileContextTargetType.folder, 'folder');
    expect(FileContextTargetType.fileNode, 'file_node');
    expect(FileContextRelationType.manual, 'manual');
    expect(FileContextRelationType.historical, 'historical');
    expect(FileContextStatus.candidate, 'candidate');
    expect(FileContextStatus.confirmed, 'confirmed');
    expect(FileNodeType.folder, 'folder');
    expect(FileNodeType.file, 'file');
    expect(FileTransferConstants.smallFileThresholdBytes, 8 * 1024 * 1024);
    expect(FileTransferConstants.chunkSizeBytes, 4 * 1024 * 1024);
    expect(FileTransferDirection.upload, 'upload');
    expect(FileTransferDirection.download, 'download');
    expect(FileTransferStatus.queued, 'queued');
    expect(FileTransferStatus.failed, 'failed');
  });

  test('scanRoot refresh preserves existing local file folder binding', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap6-repository-existing-folder-',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final file = File('${dir.path}${Platform.pathSeparator}keep-folder.txt');
    await file.writeAsString('keep folder');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: dir.path,
      displayName: 'Existing Folder',
    );

    await repository.scanRoot(folderId: folder.id);
    final first = (await repository.listFilesForFolder(folder.id)).single;
    await file.writeAsString('keep folder updated');

    await repository.scanRoot(folderId: folder.id);
    final updated = (await repository.listFilesForFolder(folder.id)).single;

    expect(first.folderId, folder.id);
    expect(updated.folderId, folder.id);
    expect(updated.displayName, 'keep-folder.txt');
  });

  test('resumeDownload records failed job when resume precondition fails',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap6-download-precondition-',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final service = FileTransferService(
      apiLoader: () async => _NoopCloudApi(),
      operationLogs: DataOperationLogRepository(db),
    );
    addTearDown(service.dispose);
    final job = _job(
      localPath: '${dir.path}${Platform.pathSeparator}zero.txt',
      totalBytes: 0,
      status: FileTransferStatus.failed,
      sessionId: 'download-gap6',
      storageObjectId: 'storage-gap6',
    );

    await expectLater(service.resumeDownload(job), throwsStateError);

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(failed.errorMessage, contains('0'));
    expect(await _auditActions(db), <String>[
      'file_transfer.download.resume',
      'file_transfer.download.failed',
    ]);
  });
}

FileTransferJob _job({
  required String localPath,
  required int totalBytes,
  required String status,
  String? sessionId,
  String? storageObjectId,
}) {
  final now = DateTime.utc(2026, 6, 11, 8);
  return FileTransferJob(
    id: 'gap6-download-precondition',
    direction: FileTransferDirection.download,
    fileName: 'zero.txt',
    localPath: localPath,
    totalBytes: totalBytes,
    chunkSize: 1,
    expectedChunks: 0,
    transferredBytes: 0,
    status: status,
    createdAt: now,
    updatedAt: now,
    sessionId: sessionId,
    storageObjectId: storageObjectId,
  );
}

Future<List<String>> _auditActions(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT action FROM data_operation_logs ORDER BY id ASC')
      .get();
  return rows.map((row) => row.read<String>('action')).toList();
}

class _NoopCloudApi implements FileCloudApi {
  @override
  Future<Map<String, dynamic>> downloadRange({
    required String sessionId,
    required int start,
    required int end,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'bytes': base64Encode(Uint8List(0)),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
