import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('uploadFile transitions through chunks to uploaded state', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-success-');
    final file = File('${tempDir.path}${Platform.pathSeparator}upload.txt');
    final bytes = utf8.encode('upload me');
    await file.writeAsBytes(bytes);
    final api = FakeFileCloudApi(
      missingChunks: <int>[0],
      uploadCompleteChecksum: sha256.convert(bytes).toString(),
      transfersFixture: <Map<String, Object?>>[
        <String, Object?>{'id': 'server-transfer-1', 'status': 'uploaded'},
      ],
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);

    await service.uploadFile(file.path);

    final job = service.jobs.single;
    expect(job.direction, FileTransferDirection.upload);
    expect(job.status, FileTransferStatus.uploaded);
    expect(job.transferredBytes, bytes.length);
    expect(job.storageObjectId, 'storage-object-1');
    expect(job.canDownload, isTrue);
    expect(api.createdUploadSessions.single['fileName'], 'upload.txt');
    expect(api.uploadedChunks.single['chunkIndex'], 0);
    expect(api.uploadedChunks.single['bytes'], bytes);
    expect(service.serverTransfers.single['id'], 'server-transfer-1');
    expect(await _auditActions(db), contains('file_transfer.upload.complete'));
  });

  test('resumeUpload skips already-present chunks and completes', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-resume-');
    final file = File('${tempDir.path}${Platform.pathSeparator}resume.bin');
    final bytes = <int>[1, 2, 3, 4, 5, 6];
    await file.writeAsBytes(bytes);
    final api = FakeFileCloudApi(
      missingChunks: <int>[1],
      receivedBytes: 3,
      uploadCompleteChecksum: sha256.convert(bytes).toString(),
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.upload,
      localPath: file.path,
      fileName: 'resume.bin',
      totalBytes: 6,
      chunkSize: 3,
      expectedChunks: 2,
      transferredBytes: 3,
      status: FileTransferStatus.failed,
      sessionId: 'upload-session-1',
      checksum: sha256.convert(bytes).toString(),
    );

    await service.resumeUpload(job);

    final resumed = service.jobs.single;
    expect(resumed.status, FileTransferStatus.uploaded);
    expect(resumed.transferredBytes, 6);
    expect(api.createdUploadSessions, isEmpty);
    expect(api.uploadedChunks.single['chunkIndex'], 1);
    expect(api.uploadedChunks.single['startByte'], 3);
    expect(api.uploadedChunks.single['bytes'], <int>[4, 5, 6]);
    expect(await _auditActions(db), contains('file_transfer.upload.resume'));
  });

  test('resumeUpload without session starts a fresh upload', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-fresh-resume-');
    final file = File('${tempDir.path}${Platform.pathSeparator}fresh.txt');
    final bytes = utf8.encode('fresh retry');
    await file.writeAsBytes(bytes);
    final checksum = sha256.convert(bytes).toString();
    final api = FakeFileCloudApi(
      missingChunks: <int>[0],
      uploadCompleteChecksum: checksum,
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.upload,
      localPath: file.path,
      fileName: 'fresh.txt',
      totalBytes: bytes.length,
      chunkSize: bytes.length,
      expectedChunks: 1,
      status: FileTransferStatus.failed,
    );

    await service.resumeUpload(job);

    final uploaded = service.jobs.single;
    expect(uploaded.status, FileTransferStatus.uploaded);
    expect(uploaded.fileName, 'fresh.txt');
    expect(api.createdUploadSessions, hasLength(1));
    expect(api.uploadedChunks.single['bytes'], bytes);
  });

  test('zero byte upload completes without chunk writes', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-empty-');
    final file = File('${tempDir.path}${Platform.pathSeparator}empty.bin');
    await file.writeAsBytes(const <int>[]);
    final api = FakeFileCloudApi(
      missingChunks: const <int>[],
      uploadCompleteChecksum: sha256.convert(const <int>[]).toString(),
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);

    await service.uploadFile(file.path);

    final job = service.jobs.single;
    expect(job.status, FileTransferStatus.uploaded);
    expect(job.totalBytes, 0);
    expect(job.expectedChunks, 0);
    expect(job.progress, 1);
    expect(api.uploadedChunks, isEmpty);
    expect(api.completedUploadSessionIds, <String>['upload-session-1']);
  });

  test('upload rejects a missing local file before creating a job', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _createService(db, FakeFileCloudApi());
    addTearDown(service.dispose);

    await expectLater(
      service.uploadFile(r'C:\FlowPlanV2\missing-upload.bin'),
      throwsStateError,
    );

    expect(service.jobs, isEmpty);
    expect(await _auditActions(db), isEmpty);
  });

  test('upload failure leaves job failed and records audit', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-failure-');
    final file = File('${tempDir.path}${Platform.pathSeparator}broken.txt');
    await file.writeAsString('broken');
    final api = FakeFileCloudApi(
      missingChunks: <int>[0],
      uploadCompleteOk: false,
      uploadCompleteReason: 'complete denied',
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);

    await expectLater(
      service.uploadFile(file.path),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('complete denied'),
        ),
      ),
    );

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(await _auditActions(db), contains('file_transfer.upload.failed'));
  });

  test('upload session failure records job metadata for retry', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-session-failure-');
    final file = File('${tempDir.path}${Platform.pathSeparator}denied.txt');
    final bytes = utf8.encode('session denied');
    await file.writeAsBytes(bytes);
    final api = FakeFileCloudApi(failCreateUploadSession: true);
    final service = _createService(db, api);
    addTearDown(service.dispose);

    await expectLater(
      service.uploadFile(file.path),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('upload session denied'),
        ),
      ),
    );

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(failed.checksum, sha256.convert(bytes).toString());
    expect(
        api.createdUploadSessions.single['metadata'],
        containsPair(
          'flowplanv2_transfer_job_id',
          failed.id,
        ));
    expect(api.uploadedChunks, isEmpty);
    expect(await _auditActions(db), <String>[
      'file_transfer.upload.start',
      'file_transfer.upload.failed',
    ]);
  });

  test('upload hash mismatch fails after server completion', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-hash-mismatch-');
    final file = File('${tempDir.path}${Platform.pathSeparator}hash.txt');
    await file.writeAsString('hash mismatch');
    final api = FakeFileCloudApi(
      missingChunks: <int>[0],
      uploadCompleteChecksum: 'server-hash-does-not-match',
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);

    await expectLater(service.uploadFile(file.path), throwsStateError);

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(
        failed.checksum, sha256.convert(await file.readAsBytes()).toString());
    expect(api.transferRequests, isEmpty);
    expect(await _auditActions(db), contains('file_transfer.upload.failed'));
  });

  test('downloadFromServerTransfer writes file and marks downloaded', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-success-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}downloaded.txt';
    final bytes = utf8.encode('download me');
    final checksum = sha256.convert(bytes).toString();
    final api = FakeFileCloudApi(downloadPayload: bytes);
    final service = _createService(db, api);
    addTearDown(service.dispose);

    final job = await service.downloadFromServerTransfer(
      <String, Object?>{
        'storageObjectId': 'storage-object-1',
        'fileName': 'downloaded.txt',
        'totalBytes': bytes.length,
        'chunkSize': 4,
        'checksum': checksum,
      },
      targetPath,
    );

    expect(job.status, FileTransferStatus.downloaded);
    expect(service.jobs.single.status, FileTransferStatus.downloaded);
    expect(await File(targetPath).readAsBytes(), bytes);
    expect(await File('$targetPath.flowplanv2.part').exists(), isFalse);
    expect(api.createdDownloadSessions.single['storageObjectId'],
        'storage-object-1');
    expect(api.downloadRanges.map((range) => range['start']), <int>[0, 4, 8]);
    expect(
        await _auditActions(db), contains('file_transfer.download.complete'));
  });

  test('downloadUploadedJob forwards checksum metadata from uploaded job',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-uploaded-job-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}copy.txt';
    final bytes = utf8.encode('copy from upload');
    final checksum = sha256.convert(bytes).toString();
    final api = FakeFileCloudApi(downloadPayload: bytes);
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final source = _transferJob(
      direction: FileTransferDirection.upload,
      localPath: r'C:\FlowPlanV2\copy.txt',
      fileName: 'copy.txt',
      totalBytes: bytes.length,
      chunkSize: 5,
      expectedChunks: 3,
      transferredBytes: bytes.length,
      status: FileTransferStatus.uploaded,
      storageObjectId: 'storage-copy',
      checksum: 'local-old-hash',
      serverChecksum: checksum,
    );

    final job = await service.downloadUploadedJob(source, targetPath);

    expect(job.status, FileTransferStatus.downloaded);
    expect(
        api.createdDownloadSessions.single['storageObjectId'], 'storage-copy');
    expect(api.createdDownloadSessions.single['checksum'], checksum);
    expect(
        api.createdDownloadSessions.single['metadata'],
        containsPair(
          'flowplanv2_transfer_job_id',
          job.id,
        ));
  });

  test('resumeDownload continues from aligned part file', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-resume-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}resume.txt';
    final bytes = utf8.encode('abcde');
    await File('$targetPath.flowplanv2.part')
        .writeAsBytes(bytes.take(2).toList());
    final api = FakeFileCloudApi(downloadPayload: bytes);
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.download,
      localPath: targetPath,
      fileName: 'resume.txt',
      totalBytes: bytes.length,
      chunkSize: 2,
      expectedChunks: 3,
      transferredBytes: 2,
      status: FileTransferStatus.failed,
      sessionId: 'download-session-1',
      storageObjectId: 'storage-object-1',
      checksum: sha256.convert(bytes).toString(),
      serverChecksum: sha256.convert(bytes).toString(),
    );

    final completed = await service.resumeDownload(job);

    expect(completed.status, FileTransferStatus.downloaded);
    expect(await File(targetPath).readAsBytes(), bytes);
    expect(api.downloadRanges.map((range) => range['start']), <int>[2, 4]);
    expect(service.jobs.single.transferredBytes, bytes.length);
    expect(await _auditActions(db), contains('file_transfer.download.resume'));
  });

  test('resumeDownload truncates unaligned part file before retry', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-align-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}align.txt';
    final bytes = utf8.encode('abcdef');
    await File('$targetPath.flowplanv2.part')
        .writeAsBytes(bytes.take(3).toList());
    final checksum = sha256.convert(bytes).toString();
    final api = FakeFileCloudApi(downloadPayload: bytes);
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.download,
      localPath: targetPath,
      fileName: 'align.txt',
      totalBytes: bytes.length,
      chunkSize: 2,
      expectedChunks: 3,
      transferredBytes: 3,
      status: FileTransferStatus.failed,
      sessionId: 'download-session-1',
      storageObjectId: 'storage-object-1',
      checksum: checksum,
      serverChecksum: checksum,
    );

    final completed = await service.resumeDownload(job);

    expect(completed.status, FileTransferStatus.downloaded);
    expect(api.downloadRanges.map((range) => range['start']), <int>[2, 4]);
    expect(await File(targetPath).readAsString(), 'abcdef');
  });

  test('download session failure leaves job failed and records audit',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-failure-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}failed.txt';
    final api = FakeFileCloudApi(failCreateDownloadSession: true);
    final service = _createService(db, api);
    addTearDown(service.dispose);

    await expectLater(
      service.downloadFromServerTransfer(
        <String, Object?>{
          'storageObjectId': 'storage-object-1',
          'fileName': 'failed.txt',
          'totalBytes': 6,
          'chunkSize': 3,
        },
        targetPath,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('download session denied'),
        ),
      ),
    );

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(await _auditActions(db), contains('file_transfer.download.failed'));
  });

  test('download rejects source without storage object before creating a job',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _createService(db, FakeFileCloudApi());
    addTearDown(service.dispose);

    await expectLater(
      service.downloadFromServerTransfer(
        const <String, Object?>{
          'fileName': 'missing-storage.txt',
          'totalBytes': 4,
        },
        r'C:\FlowPlanV2\missing-storage.txt',
      ),
      throwsStateError,
    );

    expect(service.jobs, isEmpty);
    expect(await _auditActions(db), isEmpty);
  });

  test('download failure from empty chunks keeps retryable part file',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-empty-chunks-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}empty.txt';
    final api = FakeFileCloudApi(
      downloadPayload: const <int>[],
      emptyDownloadChunks: true,
    );
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.download,
      localPath: targetPath,
      fileName: 'empty.txt',
      totalBytes: 4,
      chunkSize: 2,
      expectedChunks: 2,
      status: FileTransferStatus.failed,
      sessionId: 'download-session-1',
      storageObjectId: 'storage-empty',
    );

    await expectLater(
      service.resumeDownload(job),
      throwsStateError,
    );

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(failed.canResume, isTrue);
    expect(failed.errorMessage, contains('Bad state'));
    expect(await File('$targetPath.flowplanv2.part').exists(), isTrue);
    expect(api.downloadRanges.single, <String, int>{'start': 0, 'end': 1});
    expect(
      await _auditActions(db),
      containsAll(<String>[
        'file_transfer.download.resume',
        'file_transfer.download.failed',
      ]),
    );
  });

  test('download hash mismatch leaves partial file for retry', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-hash-mismatch-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}hash.txt';
    final bytes = utf8.encode('server bytes');
    final api = FakeFileCloudApi(downloadPayload: bytes);
    final service = _createService(db, api);
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.download,
      localPath: targetPath,
      fileName: 'hash.txt',
      totalBytes: bytes.length,
      chunkSize: bytes.length,
      expectedChunks: 1,
      status: FileTransferStatus.failed,
      sessionId: 'download-session-1',
      storageObjectId: 'storage-hash',
      checksum: 'wrong-server-hash',
      serverChecksum: 'wrong-server-hash',
    );

    await expectLater(
      service.resumeDownload(job),
      throwsStateError,
    );

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(failed.canResume, isTrue);
    expect(failed.errorMessage, contains('hash'));
    expect(failed.errorMessage, contains('wrong-server-hash'));
    expect(await File(targetPath).exists(), isFalse);
    expect(await File('$targetPath.flowplanv2.part').readAsBytes(), bytes);
    expect(
      await _auditActions(db),
      containsAll(<String>[
        'file_transfer.download.resume',
        'file_transfer.download.failed',
      ]),
    );
  });

  test('downloadPreparedSession validates session and storage identifiers',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _createService(db, FakeFileCloudApi());
    addTearDown(service.dispose);

    await expectLater(
      service.downloadPreparedSession(
        const <String, Object?>{
          'downloadSession': <String, Object?>{},
          'node': <String, Object?>{},
        },
        r'C:\FlowPlanV2\prepared.txt',
      ),
      throwsStateError,
    );
    await expectLater(
      service.downloadPreparedSession(
        const <String, Object?>{
          'downloadSession': <String, Object?>{
            'sessionId': 'download-session-1',
          },
          'node': <String, Object?>{},
        },
        r'C:\FlowPlanV2\prepared.txt',
      ),
      throwsStateError,
    );

    expect(service.jobs, isEmpty);
  });

  test('downloadPreparedSession uses nested storage metadata and node hash',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-prepared-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}prepared.txt';
    final bytes = utf8.encode('prepared file');
    final checksum = sha256.convert(bytes).toString();
    final api = FakeFileCloudApi(downloadPayload: bytes);
    final service = _createService(db, api);
    addTearDown(service.dispose);

    final job = await service.downloadPreparedSession(
      <String, Object?>{
        'downloadSession': <String, Object?>{
          'sessionId': 'prepared-session',
          'totalBytes': bytes.length.toString(),
          'chunkSize': 4.0,
        },
        'node': <String, Object?>{
          'displayName': 'prepared.txt',
          'hashSha256': checksum,
          'storage': <String, Object?>{
            'storageObjectId': 'storage-prepared',
          },
        },
      },
      targetPath,
    );

    expect(job.status, FileTransferStatus.downloaded);
    expect(job.sessionId, 'prepared-session');
    expect(job.storageObjectId, 'storage-prepared');
    expect(job.totalBytes, bytes.length);
    expect(job.chunkSize, 4);
    expect(job.checksum, checksum);
    expect(api.createdDownloadSessions, isEmpty);
    expect(await File(targetPath).readAsBytes(), bytes);
  });

  test('downloadPreparedSession records failed zero-byte metadata for retry',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-download-prepared-zero-');
    final targetPath = '${tempDir.path}${Platform.pathSeparator}zero.bin';
    final service = _createService(db, FakeFileCloudApi());
    addTearDown(service.dispose);

    await expectLater(
      service.downloadPreparedSession(
        const <String, Object?>{
          'downloadSession': <String, Object?>{
            'sessionId': 'prepared-zero',
            'storageObjectId': 'storage-zero',
          },
          'node': <String, Object?>{
            'name': 'zero.bin',
            'sizeBytes': 0,
          },
        },
        targetPath,
      ),
      throwsStateError,
    );

    final failed = service.jobs.single;
    expect(failed.status, FileTransferStatus.failed);
    expect(failed.totalBytes, 0);
    expect(failed.sessionId, 'prepared-zero');
    expect(failed.storageObjectId, 'storage-zero');
    expect(await _auditActions(db), contains('file_transfer.download.failed'));
  });

  test('resumeDownload rejects jobs missing session or storage identifiers',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _createService(db, FakeFileCloudApi());
    addTearDown(service.dispose);
    final job = _transferJob(
      direction: FileTransferDirection.download,
      localPath: r'C:\FlowPlanV2\missing.txt',
      fileName: 'missing.txt',
      totalBytes: 10,
      chunkSize: 5,
      expectedChunks: 2,
      status: FileTransferStatus.failed,
    );

    await expectLater(service.resumeDownload(job), throwsStateError);

    expect(service.jobs, isEmpty);
  });

  test(
      'load restores persisted jobs and clearCompletedJobs removes terminal jobs',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final persisted = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'persisted-upload',
        'direction': FileTransferDirection.upload,
        'fileName': 'done.txt',
        'localPath': r'C:\FlowPlanV2\done.txt',
        'totalBytes': '0',
        'chunkSize': null,
        'expectedChunks': null,
        'transferredBytes': null,
        'status': FileTransferStatus.uploaded,
        'createdAt': 'not-a-date',
        'updatedAt': 'not-a-date',
        'storageObjectId': 'storage-done',
      },
      <String, Object?>{
        'id': 'persisted-active',
        'direction': FileTransferDirection.download,
        'fileName': 'active.txt',
        'localPath': r'C:\FlowPlanV2\active.txt',
        'totalBytes': 10.0,
        'chunkSize': 5.0,
        'expectedChunks': 2.0,
        'transferredBytes': 5.0,
        'status': FileTransferStatus.downloading,
        'createdAt': DateTime.utc(2026, 6, 8).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 6, 8, 1).toIso8601String(),
      },
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flowplanv2.file_transfer.jobs.v1': jsonEncode(persisted),
    });
    final service = _createService(db, FakeFileCloudApi());
    addTearDown(service.dispose);

    await service.load();

    expect(service.loaded, isTrue);
    expect(service.jobs.map((job) => job.id), <String>[
      'persisted-upload',
      'persisted-active',
    ]);
    expect(service.jobs.first.progress, 1);
    expect(service.jobs.last.progress, 0.5);
    await service.load();
    await service.clearCompletedJobs();

    expect(service.jobs.single.id, 'persisted-active');
  });
}

FileTransferService _createService(
  AppDatabase db,
  FakeFileCloudApi api,
) {
  return FileTransferService(
    apiLoader: () async => api,
    operationLogs: DataOperationLogRepository(db),
  );
}

Future<Directory> _createTempDir(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

FileTransferJob _transferJob({
  required String direction,
  required String localPath,
  required String fileName,
  required int totalBytes,
  required int chunkSize,
  required int expectedChunks,
  int transferredBytes = 0,
  required String status,
  String? sessionId,
  String? storageObjectId,
  String? checksum,
  String? serverChecksum,
}) {
  final now = DateTime.utc(2026, 6, 9, 12);
  return FileTransferJob(
    id: 'job-$direction-$fileName',
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

Future<List<String>> _auditActions(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT action FROM data_operation_logs ORDER BY id ASC',
      )
      .get();
  return rows.map<String>((row) => row.read<String>('action')).toList();
}

class FakeFileCloudApi implements FileCloudApi {
  FakeFileCloudApi({
    this.missingChunks = const <int>[0],
    this.receivedBytes = 0,
    this.uploadCompleteOk = true,
    this.uploadCompleteReason = 'upload denied',
    this.uploadCompleteChecksum,
    this.downloadPayload = const <int>[],
    this.downloadOk = true,
    this.downloadReason = 'download denied',
    this.failCreateUploadSession = false,
    this.failCreateDownloadSession = false,
    this.emptyDownloadChunks = false,
    this.transfersFixture = const <Map<String, Object?>>[],
  });

  final List<int> missingChunks;
  final int receivedBytes;
  final bool uploadCompleteOk;
  final String uploadCompleteReason;
  final String? uploadCompleteChecksum;
  final List<int> downloadPayload;
  final bool downloadOk;
  final String downloadReason;
  final bool failCreateUploadSession;
  final bool failCreateDownloadSession;
  final bool emptyDownloadChunks;
  final List<Map<String, Object?>> transfersFixture;

  final createdUploadSessions = <Map<String, Object?>>[];
  final missingUploadSessionIds = <String>[];
  final uploadedChunks = <Map<String, Object?>>[];
  final completedUploadSessionIds = <String>[];
  final createdDownloadSessions = <Map<String, Object?>>[];
  final downloadRanges = <Map<String, int>>[];
  final transferRequests = <Map<String, Object?>>[];

  @override
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
  }) async {
    createdUploadSessions.add(<String, Object?>{
      'fileName': fileName,
      'totalBytes': totalBytes,
      'providerKey': providerKey,
      'chunkSize': chunkSize,
      'checksum': checksum,
      'objectKey': objectKey,
      'localPath': localPath,
      'remoteId': remoteId,
      'metadata': metadata,
    });
    if (failCreateUploadSession) {
      throw StateError('upload session denied');
    }
    return <String, dynamic>{
      'uploadSession': <String, Object?>{'sessionId': 'upload-session-1'},
    };
  }

  @override
  Future<Map<String, dynamic>> missingUploadChunks(String sessionId) async {
    missingUploadSessionIds.add(sessionId);
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
    uploadedChunks.add(<String, Object?>{
      'sessionId': sessionId,
      'chunkIndex': chunkIndex,
      'startByte': startByte,
      'bytes': bytes.toList(growable: false),
      'checksum': checksum,
    });
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeUploadSession(String sessionId) async {
    completedUploadSessionIds.add(sessionId);
    return <String, dynamic>{
      'ok': uploadCompleteOk,
      if (!uploadCompleteOk) 'reason': uploadCompleteReason,
      if (uploadCompleteOk)
        'storageObject': <String, Object?>{
          'storageObjectId': 'storage-object-1',
        },
      if (uploadCompleteOk && uploadCompleteChecksum != null)
        'checksum': uploadCompleteChecksum,
    };
  }

  @override
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
  }) async {
    if (failCreateDownloadSession) {
      throw StateError('download session denied');
    }
    createdDownloadSessions.add(<String, Object?>{
      'storageObjectId': storageObjectId,
      'providerKey': providerKey,
      'fileName': fileName,
      'remoteId': remoteId,
      'localPath': localPath,
      'totalBytes': totalBytes,
      'chunkSize': chunkSize,
      'checksum': checksum,
      'metadata': metadata,
    });
    return <String, dynamic>{
      'downloadSession': <String, Object?>{
        'sessionId': 'download-session-1',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> downloadRange({
    required String sessionId,
    required int start,
    required int end,
  }) async {
    downloadRanges.add(<String, int>{'start': start, 'end': end});
    if (!downloadOk) {
      return <String, dynamic>{'ok': false, 'reason': downloadReason};
    }
    if (emptyDownloadChunks) {
      return <String, dynamic>{'ok': true, 'chunks': const <Object>[]};
    }
    if (start >= downloadPayload.length) {
      return <String, dynamic>{'ok': true, 'chunks': const <Object>[]};
    }
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
    return <String, dynamic>{'transfers': transfersFixture};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
