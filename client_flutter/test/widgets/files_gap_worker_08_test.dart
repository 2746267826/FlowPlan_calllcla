import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_transfer_center_page.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/test_database.dart';

void main() {
  testWidgets('transfer center handles upload picker cancel and failures',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _ScriptedTransferService(db)
      ..uploadError = StateError('upload blocked');
    final picker = _Picker();
    await _pumpTransferCenter(tester, service: service, picker: picker);

    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pump();

    expect(service.uploadPaths, isEmpty);

    picker.pickResult = FilePickerResult([
      PlatformFile(
        name: 'blocked.txt',
        path: r'C:\FlowPlanV2\blocked.txt',
        size: 7,
      ),
    ]);
    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pump();
    await tester.pump();

    expect(service.uploadPaths, [r'C:\FlowPlanV2\blocked.txt']);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('transfer center resumes, downloads, deletes, and refreshes rows',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final failedDownload = _job(
      id: 'download-retry',
      direction: FileTransferDirection.download,
      fileName: 'retry.bin',
      totalBytes: 2 * 1024 * 1024,
      transferredBytes: 1024,
      status: FileTransferStatus.failed,
      sessionId: 'download-session',
      storageObjectId: 'storage-download',
      errorMessage: 'previous failure',
    );
    final uploaded = _job(
      id: 'uploaded-job',
      direction: FileTransferDirection.upload,
      fileName: 'server-copy.bin',
      totalBytes: 2 * 1024 * 1024 * 1024,
      transferredBytes: 2 * 1024 * 1024 * 1024,
      status: FileTransferStatus.uploaded,
      storageObjectId: 'storage-uploaded',
      speedBytesPerSecond: 1536,
    );
    final service = _ScriptedTransferService(db)
      ..seedJobs([failedDownload, uploaded])
      ..serverRows = [
        <String, dynamic>{
          'direction': FileTransferDirection.upload,
          'status': 'completed',
          'fileName': 'server-row.bin',
          'storageObjectId': 'storage-row',
          'totalBytes': 1536,
          'receivedBytes': 1536,
          'receivedChunks': 1,
          'expectedChunks': 1,
        },
        <String, dynamic>{
          'direction': FileTransferDirection.download,
          'status': 'failed',
          'fileName': 'failed-row.bin',
          'totalBytes': 0,
          'receivedBytes': 0,
          'errorMessage': 'server row failed',
        },
      ]
      ..resumeDownloadError = StateError('retry blocked')
      ..downloadUploadedError = StateError('uploaded download blocked')
      ..downloadRowError = StateError('row download blocked');
    final picker = _Picker(savePath: r'C:\FlowPlanV2\downloaded.bin');

    await _pumpTransferCenter(tester, service: service, picker: picker);

    expect(find.textContaining('2.00 GB'), findsOneWidget);
    expect(find.textContaining('1.5 KB/s'), findsOneWidget);
    expect(find.textContaining('2.0 MB'), findsOneWidget);
    expect(find.textContaining('previous failure'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.play_arrow));
    await tester.pump();
    await tester.pump();

    expect(service.resumedDownloads, ['download-retry']);
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.download).first);
    await tester.pump();
    await tester.pump();

    expect(service.downloadedUploadedJobs, ['uploaded-job']);
    expect(picker.saveRequests.first['fileName'], 'server-copy.bin');
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.download).last);
    await tester.pump();
    await tester.pump();

    expect(service.downloadedRows.single['fileName'], 'server-row.bin');
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.delete_outline).first);
    await tester.pump();

    expect(service.jobs.map((job) => job.id), isNot(contains('download-retry')));

    await tester.tap(find.byIcon(Icons.refresh).first);
    await tester.pump();

    expect(service.refreshCalls, 1);
  });
}

Future<void> _pumpTransferCenter(
  WidgetTester tester, {
  required _ScriptedTransferService service,
  required _Picker picker,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPicker = _currentPickerOrNull();
  FilePicker.platform = picker;
  addTearDown(() {
    FilePicker.platform = previousPicker ?? _Picker();
  });
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileTransferServiceProvider.overrideWith((ref) => service),
      ],
      child: const MaterialApp(home: FileTransferCenterPage()),
    ),
  );
  await tester.pump();
}

FilePicker? _currentPickerOrNull() {
  try {
    return FilePicker.platform;
  } catch (_) {
    return null;
  }
}

FileTransferJob _job({
  required String id,
  required String direction,
  required String fileName,
  required int totalBytes,
  int transferredBytes = 0,
  int chunkSize = 1024,
  int expectedChunks = 1,
  required String status,
  String localPath = r'C:\FlowPlanV2\job.bin',
  String? sessionId,
  String? storageObjectId,
  String? errorMessage,
  double speedBytesPerSecond = 0,
}) {
  final now = DateTime.utc(2026, 6, 10, 9);
  return FileTransferJob(
    id: id,
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
    errorMessage: errorMessage,
    speedBytesPerSecond: speedBytesPerSecond,
  );
}

class _ScriptedTransferService extends FileTransferService {
  _ScriptedTransferService(AppDatabase db)
      : super(
          apiLoader: () async => throw UnimplementedError(),
          operationLogs: DataOperationLogRepository(db),
        );

  final _jobs = <FileTransferJob>[];
  var serverRows = <Map<String, dynamic>>[];
  Object? uploadError;
  Object? resumeDownloadError;
  Object? downloadUploadedError;
  Object? downloadRowError;
  final uploadPaths = <String>[];
  final resumedDownloads = <String>[];
  final downloadedUploadedJobs = <String>[];
  final downloadedRows = <Map<String, Object?>>[];
  var refreshCalls = 0;

  void seedJobs(List<FileTransferJob> jobs) {
    _jobs
      ..clear()
      ..addAll(jobs);
  }

  @override
  List<FileTransferJob> get jobs => List.unmodifiable(_jobs);

  @override
  List<Map<String, dynamic>> get serverTransfers =>
      List.unmodifiable(serverRows);

  @override
  Future<void> uploadFile(String path) async {
    uploadPaths.add(path);
    final error = uploadError;
    if (error != null) throw error;
  }

  @override
  Future<FileTransferJob> resumeDownload(FileTransferJob job) async {
    resumedDownloads.add(job.id);
    final error = resumeDownloadError;
    if (error != null) throw error;
    return job.copyWith(status: FileTransferStatus.downloaded);
  }

  @override
  Future<void> resumeUpload(FileTransferJob job) async {
    throw StateError('upload resume was not expected');
  }

  @override
  Future<FileTransferJob> downloadUploadedJob(
    FileTransferJob source,
    String targetPath,
  ) async {
    downloadedUploadedJobs.add(source.id);
    final error = downloadUploadedError;
    if (error != null) throw error;
    return source.copyWith(
      direction: FileTransferDirection.download,
      localPath: targetPath,
      status: FileTransferStatus.downloaded,
    );
  }

  @override
  Future<FileTransferJob> downloadFromServerTransfer(
    Map<String, Object?> source,
    String targetPath,
  ) async {
    downloadedRows.add(source);
    final error = downloadRowError;
    if (error != null) throw error;
    return _job(
      id: 'row-download',
      direction: FileTransferDirection.download,
      fileName: source['fileName']?.toString() ?? 'download',
      totalBytes: source['totalBytes'] is int ? source['totalBytes']! as int : 0,
      transferredBytes:
          source['totalBytes'] is int ? source['totalBytes']! as int : 0,
      status: FileTransferStatus.downloaded,
      localPath: targetPath,
    );
  }

  @override
  Future<void> removeJob(String jobId) async {
    _jobs.removeWhere((job) => job.id == jobId);
    notifyListeners();
  }

  @override
  Future<void> clearCompletedJobs() async {
    _jobs.removeWhere((job) =>
        job.status == FileTransferStatus.uploaded ||
        job.status == FileTransferStatus.downloaded ||
        job.status == FileTransferStatus.failed);
    notifyListeners();
  }

  @override
  Future<void> refreshServerTransfers() async {
    refreshCalls += 1;
    notifyListeners();
  }
}

class _Picker extends FilePicker {
  _Picker({this.savePath});

  FilePickerResult? pickResult;
  String? savePath;
  final saveRequests = <Map<String, Object?>>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    Uint8List? bytes,
  }) async {
    return pickResult;
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
