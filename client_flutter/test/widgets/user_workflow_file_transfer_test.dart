import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_transfer_center_page.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/test_database.dart';

void main() {
  testWidgets('file transfer upload shows progress, success, retry, and cancel',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = FakeFileTransferService(db);
    FilePicker.platform = FakeFilePicker('/virtual/report.pdf');

    await _pumpFileTransferCenter(
      tester,
      service: service,
    );

    expect(find.byType(FileTransferCenterPage), findsOneWidget);
    expect(find.byKey(AppKeys.fileTransferStartButton), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.fileTransferStartButton));
    await tester.pump();

    expect(service.uploadedPaths, <String>['/virtual/report.pdf']);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text(FileTransferStatus.uploading), findsOneWidget);
    expect(find.textContaining('512 B / 1.0 KB'), findsOneWidget);

    service.completeUpload();
    await tester.pump();

    expect(find.text(FileTransferStatus.uploaded), findsOneWidget);
    expect(find.textContaining('1.0 KB / 1.0 KB'), findsOneWidget);
    expect(find.textContaining('storage-object-1'), findsNothing);

    service.failUpload('checksum mismatch');
    await tester.pump();

    expect(find.text(FileTransferStatus.failed), findsOneWidget);
    expect(find.textContaining('checksum mismatch'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(service.resumeUploadCalls, 1);
    expect(find.text(FileTransferStatus.uploaded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(service.removedJobIds, contains('upload-1'));
    expect(find.text('report.pdf'), findsNothing);
  });

  testWidgets('file transfer upload cancellation does not enqueue a job', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = FakeFileTransferService(db);
    FilePicker.platform = FakeFilePicker(null);

    await _pumpFileTransferCenter(
      tester,
      service: service,
    );

    await tester.tap(find.byKey(AppKeys.fileTransferStartButton));
    await tester.pump();

    expect(service.uploadedPaths, isEmpty);
    expect(service.jobs, isEmpty);
  });

  testWidgets('file transfer downloads uploaded jobs and handles save cancel', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = FakeFileTransferService(db)..completeUpload();
    final picker = FakeFilePicker('/virtual/report.pdf')
      ..queuedSavePaths.addAll(<String?>[
        null,
        '/downloads/report-copy.pdf',
      ]);
    FilePicker.platform = picker;

    await _pumpFileTransferCenter(
      tester,
      service: service,
    );

    await tester.tap(find.widgetWithText(FilledButton, '下载'));
    await tester.pump();

    expect(service.downloadedUploadedJobs, isEmpty);
    expect(picker.saveRequests.single['fileName'], 'report.pdf');

    await tester.tap(find.widgetWithText(FilledButton, '下载'));
    await tester.pump();

    expect(service.downloadedUploadedJobs.single['jobId'], 'upload-1');
    expect(
      service.downloadedUploadedJobs.single['targetPath'],
      '/downloads/report-copy.pdf',
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
      'file transfer server rows gate downloads and surface download failure', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = FakeFileTransferService(db)
      ..serverRows = <Map<String, dynamic>>[
        <String, dynamic>{
          'direction': FileTransferDirection.upload,
          'status': 'completed',
          'fileName': 'server-ready.txt',
          'totalBytes': '2048',
          'receivedBytes': 1024.8,
          'receivedChunks': 1,
          'expectedChunks': 2,
          'storageObjectId': 'server-storage-1',
        },
        <String, dynamic>{
          'direction': FileTransferDirection.download,
          'status': 'failed',
          'fileName': 'server-failed.txt',
          'totalBytes': 0,
          'receivedBytes': 0,
          'errorMessage': 'remote checksum failed',
        },
      ]
      ..downloadFromServerError = StateError('download blocked');
    final picker = FakeFilePicker('/virtual/report.pdf')
      ..queuedSavePaths.add('/downloads/server-ready.txt');
    FilePicker.platform = picker;

    await _pumpFileTransferCenter(
      tester,
      service: service,
    );

    expect(find.text('server-ready.txt'), findsOneWidget);
    expect(find.text('server-failed.txt'), findsOneWidget);
    expect(find.textContaining('1.0 KB / 2.0 KB'), findsOneWidget);
    expect(find.textContaining('remote checksum failed'), findsOneWidget);

    final serverReadyTile = find.ancestor(
      of: find.text('server-ready.txt'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(
        of: serverReadyTile,
        matching: find.widgetWithText(FilledButton, '下载'),
      ),
    );
    await tester.pump();

    expect(service.downloadedServerRows.single['fileName'], 'server-ready.txt');
    expect(service.downloadedServerRows.single['targetPath'],
        '/downloads/server-ready.txt');
    expect(find.textContaining('download blocked'), findsOneWidget);
  });
}

Future<void> _pumpFileTransferCenter(
  WidgetTester tester, {
  required FakeFileTransferService service,
}) async {
  final previousFilePicker = FilePicker.platform;
  addTearDown(() {
    FilePicker.platform = previousFilePicker;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileTransferServiceProvider.overrideWith((ref) => service),
      ],
      child: const MaterialApp(
        home: FileTransferCenterPage(),
      ),
    ),
  );
  await tester.pump();
}

class FakeFilePicker extends FilePicker {
  FakeFilePicker(this.path);

  final String? path;
  final queuedSavePaths = <String?>[];
  final saveRequests = <Map<String, Object?>>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (path == null) {
      return null;
    }
    return FilePickerResult([
      PlatformFile(path: path, name: 'report.pdf', size: 1024),
    ]);
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
    if (queuedSavePaths.isEmpty) {
      return null;
    }
    return queuedSavePaths.removeAt(0);
  }
}

class FakeFileTransferService extends FileTransferService {
  FakeFileTransferService(AppDatabase db)
      : super(
          apiLoader: () async => throw UnimplementedError(),
          operationLogs: DataOperationLogRepository(
            db,
            SyncWriteRecorder(
              mutationStore: OfflineMutationStore(db),
              stateStore: SyncObjectStateStore(db),
            ),
          ),
        );

  final uploadedPaths = <String>[];
  final removedJobIds = <String>[];
  final downloadedUploadedJobs = <Map<String, Object?>>[];
  final downloadedServerRows = <Map<String, Object?>>[];
  List<Map<String, dynamic>> serverRows = const <Map<String, dynamic>>[];
  Object? downloadUploadedJobError;
  Object? downloadFromServerError;
  var resumeUploadCalls = 0;
  var _jobs = <FileTransferJob>[];

  @override
  List<FileTransferJob> get jobs => List.unmodifiable(_jobs);

  @override
  List<Map<String, dynamic>> get serverTransfers => serverRows;

  @override
  bool get refreshingServer => false;

  @override
  Future<void> uploadFile(String path) async {
    uploadedPaths.add(path);
    _jobs = [
      _job(
        status: FileTransferStatus.uploading,
        transferredBytes: 512,
      ),
    ];
    notifyListeners();
  }

  void completeUpload() {
    _jobs = [
      _job(
        status: FileTransferStatus.uploaded,
        transferredBytes: 1024,
        storageObjectId: 'storage-object-1',
      ),
    ];
    notifyListeners();
  }

  void failUpload(String message) {
    _jobs = [
      _job(
        status: FileTransferStatus.failed,
        transferredBytes: 512,
        errorMessage: message,
      ),
    ];
    notifyListeners();
  }

  @override
  Future<void> resumeUpload(FileTransferJob job) async {
    resumeUploadCalls++;
    completeUpload();
  }

  @override
  Future<void> removeJob(String jobId) async {
    removedJobIds.add(jobId);
    _jobs = <FileTransferJob>[];
    notifyListeners();
  }

  @override
  Future<void> refreshServerTransfers() async {}

  @override
  Future<FileTransferJob> downloadUploadedJob(
    FileTransferJob source,
    String targetPath,
  ) async {
    downloadedUploadedJobs.add(<String, Object?>{
      'jobId': source.id,
      'targetPath': targetPath,
    });
    final error = downloadUploadedJobError;
    if (error != null) {
      throw error;
    }
    return source.copyWith(
      direction: FileTransferDirection.download,
      localPath: targetPath,
      status: FileTransferStatus.downloaded,
      transferredBytes: source.totalBytes,
    );
  }

  @override
  Future<FileTransferJob> downloadFromServerTransfer(
    Map<String, Object?> source,
    String targetPath,
  ) async {
    downloadedServerRows.add(<String, Object?>{
      ...source,
      'targetPath': targetPath,
    });
    final error = downloadFromServerError;
    if (error != null) {
      throw error;
    }
    return _job(
      status: FileTransferStatus.downloaded,
      transferredBytes: 1024,
      direction: FileTransferDirection.download,
      localPath: targetPath,
    );
  }

  @override
  Future<void> clearCompletedJobs() async {
    _jobs = <FileTransferJob>[];
    notifyListeners();
  }

  FileTransferJob _job({
    required String status,
    required int transferredBytes,
    String direction = FileTransferDirection.upload,
    String localPath = '/virtual/report.pdf',
    String? storageObjectId,
    String? errorMessage,
  }) {
    return FileTransferJob(
      id: 'upload-1',
      direction: direction,
      fileName: 'report.pdf',
      localPath: localPath,
      totalBytes: 1024,
      chunkSize: 1024,
      expectedChunks: 1,
      transferredBytes: transferredBytes,
      status: status,
      createdAt: DateTime.utc(2026, 6, 8),
      updatedAt: DateTime.utc(2026, 6, 8, 0, 1),
      storageObjectId: storageObjectId,
      errorMessage: errorMessage,
    );
  }
}
