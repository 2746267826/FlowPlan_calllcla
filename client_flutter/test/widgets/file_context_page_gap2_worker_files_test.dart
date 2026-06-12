import 'dart:async';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets(
      'file page covers loading, error, empty, mobile layout, and route action',
      (tester) async {
    final loadingRepository = FakeFileContextRepository()
      ..listFoldersCompleter = Completer<List<FileFolder>>();

    await pumpFileContextPageHarness(
      tester,
      repository: loadingRepository,
      withRouter: true,
      size: const Size(760, 820),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loadingRepository.listFoldersCompleter!.complete(const <FileFolder>[]);
    await tester.pump();
    await tester.pump();

    expect(
      find.widgetWithIcon(FilledButton, Icons.create_new_folder_outlined),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Transfer center route'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final errorRepository = FakeFileContextRepository()
      ..listFoldersError = StateError('roots unavailable');

    await pumpFileContextPageHarness(tester, repository: errorRepository);
    await tester.pump();

    expect(find.textContaining('roots unavailable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final root = fileFolderFixture(
      id: 1,
      displayName: 'Mobile Root',
      remoteId: 'mobile-root',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'mobile-root-node',
      depth: 0,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode],
    );

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      size: const Size(760, 820),
    );
    await tester.pump();

    expect(find.byType(ListView), findsWidgets);
    expect(find.text('Mobile Root'), findsWidgets);
    expect(find.widgetWithIcon(IconButton, Icons.arrow_upward), findsOneWidget);
  });

  testWidgets(
      'file page exposes pinned roots, root menu, reveal callbacks, and search',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap2-reveal-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final noteFile = File('${directory.path}${Platform.pathSeparator}note.txt')
      ..writeAsStringSync('note');
    final pinnedRoot = fileFolderFixture(
      id: 1,
      displayName: 'Pinned Root',
      localPath: directory.path,
      remoteId: 'pinned-root',
      pinned: true,
      availability: FileAvailability.local,
    );
    final otherRoot = fileFolderFixture(
      id: 2,
      displayName: 'Other Root',
      remoteId: 'other-root',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: pinnedRoot.id,
      itemType: FileNodeType.folder,
      displayName: pinnedRoot.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'pinned-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final noteNode = fileNodeFixture(
      id: 11,
      rootFolderId: pinnedRoot.id,
      parentNodeId: rootNode.id,
      displayName: 'note.txt',
      localPath: noteFile.path,
      relativePath: 'note.txt',
      remoteId: 'note-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [pinnedRoot, otherRoot],
      nodes: [rootNode, noteNode],
    );
    final interaction = RecordingInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interaction,
    );
    await pumpFileContextUntilFound(tester, find.text('note.txt'));

    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsWidgets);

    await tester.longPress(find.text('Pinned Root').first);
    await tester.pump();

    expect(interaction.revealedFolderIds, [pinnedRoot.id]);
    expect(repository.recordedFolderActions, ['reveal']);

    await tester.longPress(find.text('note.txt').first);
    await tester.pump();

    expect(interaction.revealedNodeIds, [noteNode.id]);
    expect(repository.recordedNodeActions, contains('reveal_file_node'));

    await tester.enterText(find.byType(TextField).first, 'note');
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('note.txt'));

    expect(repository.refreshDriveNodeRequests.last['query'], 'note');
    expect(repository.searchRequests.last['query'], 'note');
    expect(repository.searchRequests.last['rootFolderId'], pinnedRoot.id);
  });

  testWidgets(
      'file details cover remote, pdf, unsupported, and text refresh branches',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap2-details-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final firstText = File('${directory.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('alpha body');
    final secondText = File('${directory.path}${Platform.pathSeparator}b.txt')
      ..writeAsStringSync('beta body');
    final pdfFile = File('${directory.path}${Platform.pathSeparator}paper.pdf')
      ..writeAsStringSync('%PDF');
    final binaryFile =
        File('${directory.path}${Platform.pathSeparator}blob.bin')
          ..writeAsBytesSync(<int>[1, 2, 3]);
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Details Root',
      localPath: directory.path,
      remoteId: 'details-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'details-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final remoteNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'remote-plan.md',
      localPath: '',
      relativePath: 'remote-plan.md',
      remoteId: 'remote-plan-node',
      availability: FileAvailability.remoteOnly,
      sizeBytes: 2 * 1024 * 1024,
    );
    final pdfNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'paper.pdf',
      localPath: pdfFile.path,
      relativePath: 'paper.pdf',
      remoteId: 'paper-node',
      mimeType: 'application/pdf',
      availability: FileAvailability.local,
    );
    final binaryNode = fileNodeFixture(
      id: 13,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'blob.bin',
      localPath: binaryFile.path,
      relativePath: 'blob.bin',
      remoteId: 'blob-node',
      mimeType: 'application/octet-stream',
      availability: FileAvailability.local,
    );
    final firstTextNode = fileNodeFixture(
      id: 14,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'a.txt',
      localPath: firstText.path,
      relativePath: 'a.txt',
      remoteId: 'a-node',
      availability: FileAvailability.local,
    );
    final secondTextNode = fileNodeFixture(
      id: 15,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'b.txt',
      localPath: secondText.path,
      relativePath: 'b.txt',
      remoteId: 'b-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [
        rootNode,
        remoteNode,
        pdfNode,
        binaryNode,
        firstTextNode,
        secondTextNode,
      ],
    );
    final interaction = RecordingInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interaction,
    );
    await pumpFileContextUntilFound(tester, find.text('remote-plan.md'));

    await _selectNode(tester, 'remote-plan.md');
    await pumpFileContextUntilFound(tester, find.text('Download'));

    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    await _selectNode(tester, 'paper.pdf');
    await pumpFileContextUntilFound(
        tester, find.byIcon(Icons.picture_as_pdf_outlined));
    await tester.tap(find.textContaining('PDF').last);
    await tester.pump();

    expect(interaction.openedNodeIds, contains(pdfNode.id));

    await _selectNode(tester, 'blob.bin');
    await tester.pump();

    expect(find.byIcon(Icons.insert_drive_file_outlined), findsWidgets);
    expect(find.textContaining('当前文件类型暂不支持'), findsOneWidget);

    await _selectNode(tester, 'a.txt');
    await _pumpUntilEditableText(tester, 'alpha body');
    await _selectNode(tester, 'b.txt');
    await _pumpUntilEditableText(tester, 'beta body');

    expect(interaction.previewedNodeIds,
        containsAll([firstTextNode.id, secondTextNode.id]));
    expect(find.text('alpha body'), findsNothing);
  });

  testWidgets(
      'remote download creates parent directory and records device location',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap2-download-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final nestedTarget = File(
      '${directory.path}${Platform.pathSeparator}nested${Platform.pathSeparator}remote.txt',
    );
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Download Root',
      localPath: directory.path,
      remoteId: 'download-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'download-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final remoteNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'remote.txt',
      localPath: '',
      relativePath: 'nested/remote.txt',
      remoteId: 'remote-node',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-remote',
      sizeBytes: 2 * 1024 * 1024,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, remoteNode],
    );
    final contextApi = FakeFileContextApi();
    final transferService = WritingDownloadTransferService(db);
    final interaction = DownloadRequiredInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      contextApi: contextApi,
      interactionService: interaction,
      transferService: transferService,
      withRouter: true,
    );
    await pumpFileContextUntilFound(tester, find.text('remote.txt'));

    await _tapNodeOpenButton(tester, 'remote.txt');
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    expect(find.textContaining('2.0 MB'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    ));
    await tester.pumpAndSettle();
    await _waitForAsyncCondition(
      tester,
      () => contextApi.deviceLocations.isNotEmpty,
      maxPumps: 40,
    );

    expect(nestedTarget.existsSync(), isTrue);
    expect(contextApi.downloadRequests.single['nodeId'], 'remote-node');
    expect(contextApi.downloadRequests.single['targetPath'], nestedTarget.path);
    expect(transferService.preparedDownloads.single['targetPath'],
        nestedTarget.path);
    expect(contextApi.deviceLocations.single['nodeId'], 'remote-node');
    expect(contextApi.deviceLocations.single['localPath'], nestedTarget.path);
    expect(
      (contextApi.deviceLocations.single['metadata']
          as Map<String, Object?>)['source'],
      'drive_download_completed',
    );
    expect(find.text('Transfer center route'), findsOneWidget);
  });

  testWidgets(
      'server storage and version failure paths surface snackbar errors',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap2-version-fail-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final file = File('${directory.path}${Platform.pathSeparator}Proposal.txt')
      ..writeAsStringSync('proposal');
    final copyTarget =
        File('${directory.path}${Platform.pathSeparator}copy.txt');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Version Failure Root',
      localPath: directory.path,
      remoteId: 'version-failure-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'version-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final node = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Proposal.txt',
      localPath: file.path,
      relativePath: 'Proposal.txt',
      remoteId: 'proposal-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, node],
    );
    final cloudApi = FakeFileCloudApi(
      registerOk: false,
      refreshVersionsOk: false,
      downloadVersionCopyOk: false,
      prepareRestoreOk: false,
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-7',
          'displayName': 'Proposal version',
          'versionRef': 'kopia:version-7',
        },
      ],
    );
    final picker = FakeFilePicker(savePath: copyTarget.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: picker,
    );
    await pumpFileContextUntilFound(tester, find.text('Proposal.txt'));

    await _selectNode(tester, 'Proposal.txt');
    await pumpFileContextUntilFound(tester, find.text('Proposal version'));

    await _tapIcon(tester, Icons.cloud_upload_outlined);
    await pumpFileContextUntilFound(
        tester, find.textContaining('register denied'));

    await _tapIcon(tester, Icons.history);
    await pumpFileContextUntilFound(
        tester, find.textContaining('refresh denied'));

    await _tapIcon(tester, Icons.download_outlined);
    await pumpFileContextUntilFound(tester, find.textContaining('copy denied'));

    await _tapIcon(tester, Icons.rule_folder_outlined);
    await pumpFileContextUntilFound(
        tester, find.textContaining('restore denied'));

    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        'proposal-node');
    expect(cloudApi.refreshedVersions.single['fileId'], node.id.toString());
    expect(cloudApi.downloadedVersionCopies.single['versionId'], 'version-7');
    expect(cloudApi.preparedRestores.single['versionId'], 'version-7');
    expect(picker.saveRequests.single['fileName'], 'Proposal.kopia-copy.txt');
  });

  testWidgets(
      'server storage and version success paths surface snackbars and arguments',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap2-version-success-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final file = File('${directory.path}${Platform.pathSeparator}Proposal.txt')
      ..writeAsStringSync('proposal');
    final copyTarget =
        File('${directory.path}${Platform.pathSeparator}copy.txt');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Version Success Root',
      localPath: directory.path,
      remoteId: 'version-success-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'version-success-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final node = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Proposal.txt',
      localPath: file.path,
      relativePath: 'Proposal.txt',
      remoteId: 'proposal-success-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, node],
    );
    final cloudApi = FakeFileCloudApi(
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-success-7',
          'displayName': 'Proposal success version',
          'versionRef': 'kopia:version-success-7',
        },
      ],
    );
    final picker = FakeFilePicker(savePath: copyTarget.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: picker,
    );
    await pumpFileContextUntilFound(tester, find.text('Proposal.txt'));

    await _selectNode(tester, 'Proposal.txt');
    await pumpFileContextUntilFound(
      tester,
      find.text('Proposal success version'),
    );

    await _tapServerActionButton(tester, Icons.cloud_upload_outlined);
    await _waitForAsyncCondition(
      tester,
      () =>
          cloudApi.registeredStorageObjects.isNotEmpty &&
          find.byType(SnackBar).evaluate().isNotEmpty,
      maxPumps: 40,
    );
    expect(find.byType(SnackBar), findsOneWidget);
    await _clearSnackBars(tester);

    await _tapServerActionButton(tester, Icons.history);
    await _waitForAsyncCondition(
      tester,
      () =>
          cloudApi.refreshedVersions.isNotEmpty &&
          find.byType(SnackBar).evaluate().isNotEmpty,
      maxPumps: 40,
    );
    expect(find.byType(SnackBar), findsOneWidget);
    await _clearSnackBars(tester);

    await _tapVersionActionIcon(
      tester,
      versionName: 'Proposal success version',
      icon: Icons.download_outlined,
    );
    await _waitForAsyncCondition(
      tester,
      () =>
          cloudApi.downloadedVersionCopies.isNotEmpty &&
          find.byType(SnackBar).evaluate().isNotEmpty,
      maxPumps: 40,
    );
    expect(find.byType(SnackBar), findsOneWidget);

    expect(cloudApi.registeredStorageObjects.single['localPath'], file.path);
    expect(
        cloudApi.registeredStorageObjects.single['fileName'], 'Proposal.txt');
    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        'proposal-success-node');
    expect(
      (cloudApi.registeredStorageObjects.single['metadata']
          as Map<String, Object?>)['fileNodeId'],
      node.id,
    );
    expect(cloudApi.refreshedVersions.single['fileId'], node.id.toString());
    expect(cloudApi.refreshedVersions.single['filePath'], file.path);
    expect(cloudApi.refreshedVersions.single['displayName'], 'Proposal.txt');
    expect(cloudApi.downloadedVersionCopies.single['versionId'],
        'version-success-7');
    expect(
        cloudApi.downloadedVersionCopies.single['targetPath'], copyTarget.path);
    expect(picker.saveRequests.single['fileName'], 'Proposal.kopia-copy.txt');
  });
}

Future<void> _selectNode(WidgetTester tester, String nodeName) async {
  final tile = find.ancestor(
    of: find.text(nodeName).first,
    matching: find.byType(ListTile),
  );
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

Future<void> _tapNodeOpenButton(WidgetTester tester, String nodeName) async {
  final tile = find.ancestor(
    of: find.text(nodeName).first,
    matching: find.byType(ListTile),
  );
  await tester.tap(
    find
        .descendant(
          of: tile,
          matching: find.widgetWithIcon(IconButton, Icons.open_in_new),
        )
        .first,
  );
  await tester.pump();
}

Future<void> _tapIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> _tapServerActionButton(WidgetTester tester, IconData icon) async {
  final finder = find.widgetWithIcon(OutlinedButton, icon);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _tapVersionActionIcon(
  WidgetTester tester, {
  required String versionName,
  required IconData icon,
}) async {
  final tile = find.ancestor(
    of: find.text(versionName),
    matching: find.byType(ListTile),
  );
  expect(tile, findsOneWidget);
  final button = find.descendant(
    of: tile,
    matching: find.widgetWithIcon(IconButton, icon),
  );
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

Future<void> _clearSnackBars(WidgetTester tester) async {
  final messenger = find.byType(ScaffoldMessenger);
  expect(messenger, findsWidgets);
  tester.state<ScaffoldMessengerState>(messenger.first).clearSnackBars();
  await tester.pump();
  await _pumpUntil(
    tester,
    () => find.byType(SnackBar).evaluate().isEmpty,
    maxPumps: 20,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for condition.');
}

Future<void> _waitForAsyncCondition(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for async condition.');
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

Future<void> _disposeWidgetAndDeleteTemp(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
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
  });
}

class DownloadRequiredInteractionService extends FileContextInteractionService {
  DownloadRequiredInteractionService(FakeFileContextRepository repository)
      : super(repository: repository);

  final openPlanNodes = <int>[];

  @override
  Future<FileNodeOpenResult> openNodeWithPlan(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    openPlanNodes.add(node.id);
    return FileNodeOpenResult(
      opened: false,
      action: 'download_then_open',
      localIdentity: <String, Object?>{
        if (node.storageObjectId != null)
          'storageObjectId': node.storageObjectId,
      },
      message: 'Server copy requires a download',
    );
  }
}

class RecordingInteractionService extends FileContextInteractionService {
  RecordingInteractionService(this.repository) : super(repository: repository);

  final FakeFileContextRepository repository;
  final revealedFolderIds = <int>[];
  final revealedNodeIds = <int>[];
  final openedNodeIds = <int>[];
  final previewedNodeIds = <int>[];

  @override
  Future<bool> revealFolder(
    FileFolder folder, {
    String? entityType,
    String? entityId,
  }) async {
    revealedFolderIds.add(folder.id);
    await repository.recordFolderUsage(
      folderId: folder.id,
      action: 'reveal',
      entityType: entityType,
      entityId: entityId,
      metadata: <String, Object?>{'path': folder.localPath},
    );
    return true;
  }

  @override
  Future<bool> revealNode(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    revealedNodeIds.add(node.id);
    await repository.recordFileNodeOperation(
      node: node,
      action: 'reveal_file_node',
      entityType: entityType,
      entityId: entityId,
    );
    return true;
  }

  @override
  Future<bool> openNode(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    openedNodeIds.add(node.id);
    return true;
  }

  @override
  Future<FileNodeOpenResult> openNodeWithPlan(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    openedNodeIds.add(node.id);
    return FileNodeOpenResult(
      opened: true,
      action: 'open_local',
      localIdentity: <String, Object?>{'localPath': node.localPath},
      localPath: node.localPath,
    );
  }

  @override
  Future<FilePreviewResult> previewTextNode(FileNode node) async {
    previewedNodeIds.add(node.id);
    await repository.recordFileNodeOperation(
      node: node,
      action: 'preview_file_node',
    );
    return FilePreviewResult(
      canPreview: true,
      displayName: node.displayName,
      content: File(node.localPath).readAsStringSync(),
      message: null,
    );
  }
}

class WritingDownloadTransferService extends FileTransferService {
  WritingDownloadTransferService(AppDatabase db)
      : super(
          apiLoader: () async => throw UnimplementedError(),
          operationLogs: DataOperationLogRepository(db),
        );

  final preparedDownloads = <Map<String, Object?>>[];

  @override
  Future<FileTransferJob> downloadPreparedSession(
    Map<String, Object?> response,
    String targetPath,
  ) async {
    preparedDownloads.add(<String, Object?>{
      'response': response,
      'targetPath': targetPath,
    });
    await File(targetPath).writeAsString('downloaded remote copy');
    return FileTransferJob(
      id: 'gap2-download-${preparedDownloads.length}',
      direction: FileTransferDirection.download,
      fileName: 'remote.txt',
      localPath: targetPath,
      totalBytes: 22,
      chunkSize: 22,
      expectedChunks: 1,
      transferredBytes: 22,
      status: FileTransferStatus.downloaded,
      createdAt: fileContextHarnessNow,
      updatedAt: fileContextHarnessNow,
      sessionId: 'download-session-1',
      storageObjectId: 'storage-object-1',
      checksum: 'checksum',
      serverChecksum: 'checksum',
    );
  }
}
