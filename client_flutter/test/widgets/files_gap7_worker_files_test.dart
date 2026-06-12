import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_context_page.dart';
import 'package:flowplanv2/features/files/presentation/file_context_panel.dart';
import 'package:flowplanv2/features/files/presentation/file_transfer_center_page.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets('file page refreshes previews and runs storage success actions',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync(
      'flowplanv2-gap7-page-success-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, dir));
    final imageFile = File('${dir.path}${Platform.pathSeparator}broken.png')
      ..writeAsStringSync('not a png');
    final firstText = File('${dir.path}${Platform.pathSeparator}alpha.txt')
      ..writeAsStringSync('alpha body');
    final secondText = File('${dir.path}${Platform.pathSeparator}beta.txt')
      ..writeAsStringSync('beta body');
    final versionCopy =
        File('${dir.path}${Platform.pathSeparator}alpha-copy.txt');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Page Root',
      localPath: dir.path,
      remoteId: 'page-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: 'Page Root',
      localPath: dir.path,
      relativePath: '',
      remoteId: 'page-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final imageNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'broken.png',
      localPath: imageFile.path,
      relativePath: 'broken.png',
      remoteId: 'broken-image-node',
      mimeType: 'image/png',
      availability: FileAvailability.local,
    );
    final alphaNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'alpha.txt',
      localPath: firstText.path,
      relativePath: 'alpha.txt',
      remoteId: 'alpha-node',
      availability: FileAvailability.local,
    );
    final betaNode = fileNodeFixture(
      id: 13,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'beta.txt',
      localPath: secondText.path,
      relativePath: 'beta.txt',
      remoteId: 'beta-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, imageNode, alphaNode, betaNode],
    );
    final cloudApi = FakeFileCloudApi(
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-gap7',
          'displayName': 'Gap7 version',
          'versionRef': 'kopia:gap7',
        },
      ],
    );
    final picker = FakeFilePicker(savePath: versionCopy.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: picker,
      interactionService: _Gap7InteractionService(repository),
    );
    await pumpFileContextUntilFound(tester, find.text('broken.png'));

    await _selectFilePageNode(tester, 'broken.png');
    await pumpFileContextUntilFound(tester, find.byType(Image));
    expect(find.byType(Image), findsOneWidget);

    await _selectFilePageNode(tester, 'alpha.txt');
    await _pumpUntilEditableText(tester, 'alpha body');
    await pumpFileContextUntilFound(tester, find.text('Gap7 version'));

    await _tapFirstIcon(tester, Icons.cloud_upload_outlined);
    await _pumpUntil(
        tester, () => cloudApi.registeredStorageObjects.isNotEmpty);
    await _pumpUntilSnackBar(tester);
    ScaffoldMessenger.of(tester.element(find.byType(FileContextPage)))
        .clearSnackBars();
    await tester.pump();
    await _tapFirstIcon(tester, Icons.history);
    await _pumpUntil(tester, () => cloudApi.refreshedVersions.isNotEmpty);
    await _pumpUntilSnackBar(tester);
    ScaffoldMessenger.of(tester.element(find.byType(FileContextPage)))
        .clearSnackBars();
    await tester.pump();
    await _tapFirstIcon(tester, Icons.download_outlined);
    await _pumpUntil(tester, () => cloudApi.downloadedVersionCopies.isNotEmpty);
    await _pumpUntilSnackBar(tester);

    expect(
        cloudApi.registeredStorageObjects.single['fileNodeId'], 'alpha-node');
    expect(
        cloudApi.refreshedVersions.single['fileId'], alphaNode.id.toString());
    expect(
        cloudApi.downloadedVersionCopies.single['versionId'], 'version-gap7');
    expect(picker.saveRequests.single['fileName'], 'alpha.kopia-copy.txt');

    await _selectFilePageNode(tester, 'beta.txt');
    await _pumpUntilEditableText(tester, 'beta body');
    await _pumpUntil(
      tester,
      () => cloudApi.versionRequests.contains(betaNode.id.toString()),
    );

    expect(find.text('alpha body'), findsNothing);
  });

  testWidgets(
      'panel reloads for event entity and picker falls back root safely',
      (tester) async {
    final firstRoot = fileFolderFixture(id: 1, displayName: 'First Root');
    final secondRoot = fileFolderFixture(id: 2, displayName: 'Second Root');
    final secondRootNode = fileNodeFixture(
      id: 20,
      rootFolderId: secondRoot.id,
      itemType: FileNodeType.folder,
      displayName: 'Second Root',
      relativePath: '',
      depth: 0,
    );
    final rootLevelFile = fileNodeFixture(
      id: 21,
      rootFolderId: secondRoot.id,
      parentNodeId: secondRootNode.id,
      displayName: 'Root local path note.txt',
      localPath: r'C:\FlowPlanV2\root-note.txt',
      relativePath: '',
      availability: FileAvailability.local,
    );
    final repository = _ReloadingPanelRepository(
      roots: [firstRoot, secondRoot],
      nodes: [secondRootNode, rootLevelFile],
    );

    await tester.pumpWidget(_PanelHarness(repository: repository));
    await tester.pump();

    expect(repository.ensureRequests.single['entityType'],
        FileContextEntityType.task);
    await tester.pumpWidget(_PanelHarness(
      repository: repository,
      entityType: FileContextEntityType.event,
      entityId: 'event-7',
      title: 'Event launch brief',
    ));
    await tester.pump();

    expect(repository.ensureRequests.last['entityType'],
        FileContextEntityType.event);

    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Second Root'));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Root').last);
    await tester.pump();
    repository.roots.removeWhere((root) => root.id == secondRoot.id);
    await tester.enterText(find.byType(TextField).last, 'no-match');
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('First Root'));

    expect(find.text('Root local path note.txt'), findsNothing);
  });

  testWidgets('panel picker binds root-level file using local path subtitle', (
    tester,
  ) async {
    final root = fileFolderFixture(id: 1, displayName: 'Picker Root');
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: 'Picker Root',
      relativePath: '',
      depth: 0,
    );
    final rootLevelFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Root level note.txt',
      localPath: r'C:\FlowPlanV2\Root level note.txt',
      relativePath: '',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, rootLevelFile],
    );

    await tester.pumpWidget(_PanelHarness(repository: repository));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Root level note.txt'));

    expect(find.text(r'C:\FlowPlanV2\Root level note.txt'), findsOneWidget);
    final fileTile = find.ancestor(
      of: find.text('Root level note.txt'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: fileTile,
        matching: find.byType(TextButton),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(repository.boundNodeIds, [rootLevelFile.id]);
    expect(repository.recordedNodeActions, contains('bind_file_node'));
  });

  testWidgets('transfer center downloads a completed server row successfully',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _Gap7TransferService(db)
      ..serverRows = <Map<String, dynamic>>[
        <String, dynamic>{
          'direction': FileTransferDirection.upload,
          'status': 'completed',
          'fileName': 'ready.txt',
          'storageObjectId': 'storage-ready',
          'totalBytes': 2048,
          'receivedBytes': 2048,
          'receivedChunks': 1,
          'expectedChunks': 1,
        },
      ];
    final picker = _Picker(savePath: r'C:\FlowPlanV2\ready-copy.txt');

    await _pumpTransferCenter(tester, service: service, picker: picker);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.download));
    await tester.pump();
    await tester.pump();

    expect(service.downloadedRows.single['fileName'], 'ready.txt');
    expect(service.downloadedRows.single['targetPath'],
        r'C:\FlowPlanV2\ready-copy.txt');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('transfer center shows blue status for active download', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _Gap7TransferService(db)
      ..seedJobs([
        _job(
          id: 'active-download',
          direction: FileTransferDirection.download,
          status: FileTransferStatus.downloading,
        ),
      ]);

    await _pumpTransferCenter(tester, service: service, picker: _Picker());

    expect(find.text(FileTransferStatus.downloading), findsOneWidget);
    final chipText = tester.widget<Text>(
      find.text(FileTransferStatus.downloading),
    );
    expect((chipText.style?.color ?? Colors.transparent), Colors.blue);
  });
}

Future<void> _pumpTransferCenter(
  WidgetTester tester, {
  required _Gap7TransferService service,
  required _Picker picker,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPicker = _currentPickerOrNull();
  FilePicker.platform = picker;
  addTearDown(() {
    FilePicker.platform = previousPicker ?? _Picker();
  });
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
  required String status,
}) {
  final now = DateTime.utc(2026, 6, 11, 10);
  return FileTransferJob(
    id: id,
    direction: direction,
    fileName: '$id.txt',
    localPath: r'C:\FlowPlanV2\active.txt',
    totalBytes: 100,
    chunkSize: 50,
    expectedChunks: 2,
    transferredBytes: 50,
    status: status,
    createdAt: now,
    updatedAt: now,
    sessionId: 'session-$id',
    storageObjectId: 'storage-$id',
  );
}

class _PanelHarness extends StatelessWidget {
  const _PanelHarness({
    required this.repository,
    this.entityType = FileContextEntityType.task,
    this.entityId = 'task-42',
    this.title = 'Alpha launch brief',
  });

  final FakeFileContextRepository repository;
  final String entityType;
  final String entityId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        fileContextRepositoryProvider.overrideWithValue(repository),
        fileContextApiProvider
            .overrideWith((ref) async => FakeFileContextApi()),
        fileCloudApiProvider.overrideWith((ref) async => FakeFileCloudApi()),
        fileContextInteractionServiceProvider.overrideWithValue(
          FileContextInteractionService(repository: repository),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: EntityFileContextPanel(
              entityType: entityType,
              entityId: entityId,
              title: title,
              description: 'Prepare assets',
            ),
          ),
        ),
      ),
    );
  }
}

class _ReloadingPanelRepository extends FakeFileContextRepository {
  _ReloadingPanelRepository({
    super.roots,
    super.nodes,
  });

  final ensureRequests = <Map<String, Object?>>[];

  @override
  Future<List<FileContextLink>> ensureFolderRecommendations({
    required String entityType,
    required String entityId,
    required String title,
    String? description,
    String? location,
    int limit = 5,
  }) async {
    ensureRequests.add(<String, Object?>{
      'entityType': entityType,
      'entityId': entityId,
      'title': title,
      'description': description,
      'location': location,
      'limit': limit,
    });
    return super.ensureFolderRecommendations(
      entityType: entityType,
      entityId: entityId,
      title: title,
      description: description,
      location: location,
      limit: limit,
    );
  }
}

class _Gap7TransferService extends FileTransferService {
  _Gap7TransferService(AppDatabase db)
      : super(
          apiLoader: () async => throw UnimplementedError(),
          operationLogs: DataOperationLogRepository(db),
        );

  final _jobs = <FileTransferJob>[];
  var serverRows = <Map<String, dynamic>>[];
  final downloadedRows = <Map<String, Object?>>[];

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
  Future<FileTransferJob> downloadFromServerTransfer(
    Map<String, Object?> source,
    String targetPath,
  ) async {
    downloadedRows.add(<String, Object?>{
      ...source,
      'targetPath': targetPath,
    });
    return _job(
      id: 'downloaded-row',
      direction: FileTransferDirection.download,
      status: FileTransferStatus.downloaded,
    );
  }
}

class _Picker extends FilePicker {
  _Picker({this.savePath});

  final String? savePath;

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
    return savePath;
  }
}

Future<void> _selectFilePageNode(WidgetTester tester, String nodeName) async {
  final tile = find.ancestor(
    of: find.text(nodeName).first,
    matching: find.byType(ListTile),
  );
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(
    find
        .descendant(
          of: tile,
          matching: find.widgetWithIcon(IconButton, Icons.check_circle_outline),
        )
        .first,
  );
  await tester.pump();
}

Future<void> _tapFirstIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for condition.');
}

Future<void> _pumpUntilEditableText(
  WidgetTester tester,
  String text, {
  int maxPumps = 20,
}) async {
  await _pumpUntil(
    tester,
    () => tester
        .widgetList<EditableText>(find.byType(EditableText))
        .any((widget) => widget.controller.text == text),
    maxPumps: maxPumps,
  );
}

Future<void> _pumpUntilSnackBar(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(SnackBar).evaluate().isNotEmpty,
    maxPumps: 20,
  );
}

Future<void> _disposeWidgetAndDeleteTemp(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 8; attempt += 1) {
    if (!directory.existsSync()) {
      return;
    }
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 7) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

class _Gap7InteractionService extends FileContextInteractionService {
  _Gap7InteractionService(FakeFileContextRepository repository)
      : super(repository: repository);

  @override
  Future<FilePreviewResult> previewTextNode(FileNode node) async {
    return FilePreviewResult(
      canPreview: true,
      displayName: node.displayName,
      content: File(node.localPath).readAsStringSync(),
      message: null,
    );
  }
}
