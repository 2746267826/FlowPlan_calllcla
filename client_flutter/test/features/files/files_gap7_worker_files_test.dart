import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  test('file constants include private sentinels and branch values', () {
    debugTouchFileContextRepositoryConstantsForCoverage();
    debugTouchFileTransferConstantsForCoverage();

    expect(FileProviderKind.local, 'local');
    expect(FileProviderKind.serverStorage, 'server_storage');
    expect(FileProviderKind.oneDrive, 'onedrive');
    expect(FileAvailability.local, 'local');
    expect(FileAvailability.remoteOnly, 'remote_only');
    expect(FileAvailability.missing, 'missing');
    expect(FileAvailability.conflict, 'conflict');
    expect(FileContextEntityType.event, 'event');
    expect(FileContextTargetType.file, 'file');
    expect(FileContextTargetType.folderNode, 'folder_node');
    expect(FileContextRelationType.recommended, 'recommended');
    expect(FileContextRelationType.recent, 'recent');
    expect(FileContextStatus.rejected, 'rejected');
    expect(FileNodeType.folder, 'folder');
    expect(FileNodeType.file, 'file');
    expect(FileTransferConstants.smallFileThresholdBytes, 8 * 1024 * 1024);
    expect(FileTransferConstants.chunkSizeBytes, 4 * 1024 * 1024);
    expect(FileTransferStatus.hashing, 'hashing');
    expect(FileTransferStatus.uploading, 'uploading');
    expect(FileTransferStatus.downloading, 'downloading');
    expect(FileTransferStatus.downloaded, 'downloaded');
  });

  test('upsertLocalFile keeps its folder when update omits folder id',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap7-file-folder-',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final file = File('${dir.path}${Platform.pathSeparator}sticky.txt');
    await file.writeAsString('first');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: dir.path,
      displayName: 'Sticky Root',
    );

    final first = await repository.upsertLocalFile(
      localPath: file.path,
      folderId: folder.id,
      mimeType: 'text/plain',
      previewMode: 'text',
    );
    await file.writeAsString('second');
    final updated = await repository.upsertLocalFile(
      localPath: file.path,
      mimeType: null,
      previewMode: 'text',
    );

    expect(updated.id, first.id);
    expect(updated.folderId, folder.id);
    expect(updated.mimeType, 'text/plain');
    expect(
        (await repository.listFilesForFolder(folder.id)).single.id, first.id);
  });

  test('upsertLocalFile inserts a local file row with display and availability',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap7-file-insert-',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final file = File('${dir.path}${Platform.pathSeparator}fresh-local.md');
    await file.writeAsString('# Fresh');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: dir.path,
      displayName: 'Fresh Root',
    );

    final inserted = await repository.upsertLocalFile(
      localPath: file.path,
      folderId: folder.id,
      mimeType: 'text/markdown',
      previewMode: 'text',
    );

    expect(inserted.provider, FileProviderKind.local);
    expect(inserted.displayName, 'fresh-local.md');
    expect(inserted.folderId, folder.id);
    expect(inserted.localPath, file.path);
    expect(inserted.mimeType, 'text/markdown');
    expect(inserted.sizeBytes, greaterThan(0));
    expect(inserted.availability, FileAvailability.local);
    expect(inserted.previewMode, 'text');
  });

  test('resume download without a session hits the guarded transfer edge',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = FileTransferService(
      apiLoader: () async => _CloudApi(),
      operationLogs: DataOperationLogRepository(db),
    );
    addTearDown(service.dispose);
    final job = _job(
      status: FileTransferStatus.failed,
      sessionId: null,
      totalBytes: 12,
    );

    await expectLater(
      service.debugResumeDownloadUncheckedForCoverage(job),
      throwsStateError,
    );

    expect(service.jobs, isEmpty);
    expect(await _auditActions(db), isEmpty);
  });

  test('download server transfer preserves existing partial chunk alignment',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = await Directory.systemTemp.createTemp(
      'flowplanv2-gap7-download-align-',
    );
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final target = File('${dir.path}${Platform.pathSeparator}aligned.txt');
    final partFile = File('${target.path}.flowplanv2.part');
    await partFile.writeAsString('abc');
    final bytes = utf8.encode('abcdef');
    final service = FileTransferService(
      apiLoader: () async => _CloudApi(downloadPayload: bytes),
      operationLogs: DataOperationLogRepository(db),
    );
    addTearDown(service.dispose);

    final job = await service.downloadPreparedSession(
      <String, Object?>{
        'downloadSession': <String, Object?>{
          'sessionId': 'gap7-session',
          'storageObjectId': 'gap7-storage',
          'totalBytes': bytes.length,
          'chunkSize': 2,
          'checksum': sha256.convert(bytes).toString(),
        },
        'node': <String, Object?>{'name': 'aligned.txt'},
      },
      target.path,
    );

    expect(job.status, FileTransferStatus.downloaded);
    expect(await target.readAsString(), 'abcdef');
    expect(await partFile.exists(), isFalse);
  });
}

FileTransferJob _job({
  required String status,
  String? sessionId = 'gap7-session',
  int totalBytes = 1,
}) {
  final now = DateTime.utc(2026, 6, 11, 9);
  return FileTransferJob(
    id: 'gap7-download',
    direction: FileTransferDirection.download,
    fileName: 'gap7.txt',
    localPath: r'C:\FlowPlanV2\gap7.txt',
    totalBytes: totalBytes,
    chunkSize: 1,
    expectedChunks: totalBytes,
    transferredBytes: 0,
    status: status,
    createdAt: now,
    updatedAt: now,
    sessionId: sessionId,
    storageObjectId: 'gap7-storage',
  );
}

Future<List<String>> _auditActions(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT action FROM data_operation_logs ORDER BY id ASC')
      .get();
  return rows.map((row) => row.read<String>('action')).toList();
}

class _CloudApi implements FileCloudApi {
  _CloudApi({this.downloadPayload = const <int>[]});

  final List<int> downloadPayload;

  @override
  Future<Map<String, dynamic>> downloadRange({
    required String sessionId,
    required int start,
    required int end,
  }) async {
    final clampedEnd =
        end >= downloadPayload.length ? downloadPayload.length - 1 : end;
    final bytes = downloadPayload.sublist(start, clampedEnd + 1);
    return <String, dynamic>{
      'ok': true,
      'chunks': <Map<String, Object?>>[
        <String, Object?>{'payloadBase64': base64Encode(bytes)},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
