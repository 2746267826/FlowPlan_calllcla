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
      'file page relocates missing preview nodes and covers folder image reveal',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap3-page-preview-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final existingFolder = Directory(
      '${directory.path}${Platform.pathSeparator}existing-folder',
    )..createSync();
    final brokenImage = File(
      '${directory.path}${Platform.pathSeparator}broken.png',
    )..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final relocatedFolder = Directory(
      '${directory.path}${Platform.pathSeparator}relocated-root',
    )..createSync();
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Preview Root',
      localPath: directory.path,
      remoteId: 'preview-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'preview-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final missingFolderNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      itemType: FileNodeType.folder,
      displayName: 'missing-folder',
      localPath: '${directory.path}${Platform.pathSeparator}missing-folder',
      relativePath: 'missing-folder',
      remoteId: null,
      availability: FileAvailability.missing,
    );
    final existingFolderNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      itemType: FileNodeType.folder,
      displayName: 'existing-folder',
      localPath: existingFolder.path,
      relativePath: 'existing-folder',
      remoteId: 'existing-folder-node',
      availability: FileAvailability.local,
    );
    final imageNode = fileNodeFixture(
      id: 13,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'broken.png',
      localPath: brokenImage.path,
      relativePath: 'broken.png',
      remoteId: 'broken-image-node',
      mimeType: 'image/png',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, missingFolderNode, existingFolderNode, imageNode],
    );
    final interaction = _RecordingInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interaction,
      filePicker: FakeFilePicker(directoryPath: relocatedFolder.path),
    );
    await pumpFileContextUntilFound(tester, find.text('missing-folder'));

    await _selectNode(tester, 'missing-folder');
    await _tapPreviewTextButton(tester, 'missing-folder');
    await tester.pump();

    expect(repository.boundRootPaths.single['folderId'], root.id);
    expect(repository.boundRootPaths.single['localPath'], relocatedFolder.path);

    await _selectNode(tester, 'existing-folder');
    await _tapPreviewIcon(
      tester,
      'existing-folder',
      Icons.drive_file_move_outline,
    );
    await tester.pump();

    expect(interaction.revealedNodeIds, <int>[existingFolderNode.id]);

    await _selectNode(tester, 'broken.png');
    await tester.pumpAndSettle();

    expect(find.text('broken.png'), findsWidgets);
  });

  testWidgets('remote preview open and warning download surface failures',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap3-page-download-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Download Failure Root',
      localPath: directory.path,
      remoteId: 'download-failure-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'download-failure-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final remoteNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'remote-failure.txt',
      localPath: '',
      relativePath: 'nested/remote-failure.txt',
      remoteId: 'remote-failure-node',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-remote-failure',
      sizeBytes: 2048,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, remoteNode],
    );
    final contextApi = FakeFileContextApi(downloadRequestOk: false);
    final transferService = _FailingPreparedDownloadTransferService(db);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      contextApi: contextApi,
      interactionService: _DownloadRequiredInteractionService(repository),
      transferService: transferService,
      withRouter: true,
    );
    await pumpFileContextUntilFound(tester, find.text('remote-failure.txt'));

    await _selectNode(tester, 'remote-failure.txt');
    await _tapPreviewIcon(tester, 'remote-failure.txt', Icons.open_in_new);
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pump();

    await _tapWarningDownload(tester, 'remote-failure.txt');
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await pumpFileContextUntilFound(
      tester,
      find.textContaining('download denied'),
    );

    expect(contextApi.downloadRequests.single['nodeId'], 'remote-failure-node');
    expect(transferService.preparedResponses, isEmpty);
  });

  testWidgets(
      'snapshot failures and version success actions refresh detail pane',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap3-page-versions-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final firstFile = File(
      '${directory.path}${Platform.pathSeparator}Proposal.txt',
    )..writeAsStringSync('proposal');
    final secondFile = File(
      '${directory.path}${Platform.pathSeparator}Notes.txt',
    )..writeAsStringSync('notes');
    final copyTarget = File(
      '${directory.path}${Platform.pathSeparator}Proposal.copy.txt',
    );
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
    final firstNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Proposal.txt',
      localPath: firstFile.path,
      relativePath: 'Proposal.txt',
      remoteId: 'proposal-success-node',
      availability: FileAvailability.local,
    );
    final secondNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Notes.txt',
      localPath: secondFile.path,
      relativePath: 'Notes.txt',
      remoteId: 'notes-success-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, firstNode, secondNode],
    );
    final cloudApi = _SnapshotThrowingCloudApi(
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-success-1',
          'displayName': 'Proposal version',
          'versionRef': 'kopia:version-success-1',
        },
      ],
    );

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: FakeFilePicker(savePath: copyTarget.path),
    );
    await pumpFileContextUntilFound(tester, find.text('Proposal.txt'));

    await tester.tap(find.byIcon(Icons.history_toggle_off));
    await pumpFileContextUntilFound(
      tester,
      find.textContaining('snapshot offline'),
    );

    await _selectNode(tester, 'Proposal.txt');
    await pumpFileContextUntilFound(tester, find.text('Proposal version'));

    await _tapIcon(tester, Icons.cloud_upload_outlined);
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.registeredStorageObjects.isNotEmpty,
      maxPumps: 20,
    );
    await _tapIcon(tester, Icons.history);
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.refreshedVersions.isNotEmpty,
      maxPumps: 20,
    );
    await _tapIcon(tester, Icons.download_outlined);
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.downloadedVersionCopies.isNotEmpty,
      maxPumps: 20,
    );

    await _selectNode(tester, 'Notes.txt');
    await pumpFileContextUntilFound(tester, find.text('Notes.txt'));

    expect(cloudApi.createdSnapshots.single['rootPath'], directory.path);
    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        'proposal-success-node');
    expect(
      cloudApi.refreshedVersions.single['fileId'],
      firstNode.id.toString(),
    );
    expect(cloudApi.downloadedVersionCopies.single['versionId'],
        'version-success-1');
  });

  testWidgets('text preview editor reloads when selected node changes',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap3-page-text-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final firstFile = File('${directory.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('alpha body');
    final secondFile = File('${directory.path}${Platform.pathSeparator}b.txt')
      ..writeAsStringSync('beta body');
    final blockedFile = File(
      '${directory.path}${Platform.pathSeparator}blocked.txt',
    )..writeAsStringSync('blocked');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Text Preview Root',
      localPath: directory.path,
      remoteId: 'text-preview-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'text-preview-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final firstNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'a.txt',
      localPath: firstFile.path,
      relativePath: 'a.txt',
      remoteId: 'a-text-node',
      availability: FileAvailability.local,
    );
    final secondNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'b.txt',
      localPath: secondFile.path,
      relativePath: 'b.txt',
      remoteId: 'b-text-node',
      availability: FileAvailability.local,
    );
    final blockedNode = fileNodeFixture(
      id: 13,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'blocked.txt',
      localPath: blockedFile.path,
      relativePath: 'blocked.txt',
      remoteId: 'blocked-text-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, firstNode, secondNode, blockedNode],
    );
    final interaction = _ScriptedPreviewInteractionService(
      repository,
      blockedNodeId: blockedNode.id,
    );

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interaction,
    );
    await pumpFileContextUntilFound(tester, find.text('a.txt'));

    await _selectNode(tester, 'a.txt');
    await _pumpUntilEditableText(tester, 'alpha body');
    await _selectNode(tester, 'b.txt');
    await _pumpUntilEditableText(tester, 'beta body');
    await _selectNode(tester, 'blocked.txt');
    await pumpFileContextUntilFound(tester, find.text('preview disabled'));

    expect(interaction.previewedNodeIds, <int>[
      firstNode.id,
      secondNode.id,
      blockedNode.id,
    ]);
  });
}

Future<void> _selectNode(WidgetTester tester, String nodeName) async {
  final tile = _fileTreeTileFor(nodeName);
  await pumpFileContextUntilFound(tester, tile, maxPumps: 20);
  expect(tile, findsOneWidget);
  await tester.ensureVisible(tile.first);
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

Finder _fileTreeTileFor(String nodeName) {
  return find.byElementPredicate(
    (element) {
      if (element.widget is! ListTile) {
        return false;
      }
      var hasNodeName = false;
      var hasSelectAction = false;
      void visit(Element child) {
        final widget = child.widget;
        if (widget is Text && widget.data == nodeName) {
          hasNodeName = true;
        }
        if (widget is Icon && widget.icon == Icons.check_circle_outline) {
          hasSelectAction = true;
        }
        child.visitChildElements(visit);
      }

      element.visitChildElements(visit);
      return hasNodeName && hasSelectAction;
    },
    description: 'file tree tile "$nodeName"',
  );
}

Future<void> _tapPreviewIcon(
  WidgetTester tester,
  String nodeName,
  IconData icon,
) async {
  final previewList = await _previewListFor(tester, nodeName);
  final button = find
      .descendant(
        of: previewList,
        matching: find.widgetWithIcon(IconButton, icon),
      )
      .first;
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

Future<void> _tapPreviewTextButton(
  WidgetTester tester,
  String nodeName,
) async {
  final previewList = await _previewListFor(tester, nodeName);
  final button = find.descendant(
    of: previewList,
    matching: find.byType(TextButton),
  );
  await tester.ensureVisible(button.first);
  await tester.tap(button.first);
  await tester.pump();
}

Future<void> _tapWarningDownload(
  WidgetTester tester,
  String nodeName,
) async {
  final previewList = await _previewListFor(tester, nodeName);
  final button = find.descendant(
    of: previewList,
    matching: find.widgetWithText(TextButton, 'Download'),
  );
  await tester.ensureVisible(button.first);
  await tester.tap(button.first);
  await tester.pump();
}

Future<Finder> _previewListFor(
  WidgetTester tester,
  String nodeName,
) async {
  final title = _previewTitleFor(nodeName);
  await pumpFileContextUntilFound(tester, title);
  expect(title, findsOneWidget);
  final list = find.ancestor(
    of: title,
    matching: find.byType(ListView),
  );
  expect(list, findsWidgets);
  return list.last;
}

Finder _previewTitleFor(String nodeName) {
  return find.byElementPredicate(
    (element) {
      final widget = element.widget;
      if (widget is! Text || widget.data != nodeName) {
        return false;
      }
      var inListView = false;
      var inListTile = false;
      element.visitAncestorElements((ancestor) {
        inListView = inListView || ancestor.widget is ListView;
        inListTile = inListTile || ancestor.widget is ListTile;
        return true;
      });
      return inListView && !inListTile;
    },
    description: 'preview title text "$nodeName"',
  );
}

Future<void> _tapIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> _pumpUntilEditableText(
  WidgetTester tester,
  String text, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    final matched = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .any((widget) => widget.controller.text == text);
    if (matched) {
      return;
    }
  }
  fail('Timed out waiting for editable text: $text');
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

class _RecordingInteractionService extends FileContextInteractionService {
  _RecordingInteractionService(this.repository) : super(repository: repository);

  final FakeFileContextRepository repository;
  final revealedNodeIds = <int>[];

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
}

class _DownloadRequiredInteractionService
    extends FileContextInteractionService {
  _DownloadRequiredInteractionService(FakeFileContextRepository repository)
      : super(repository: repository);

  @override
  Future<FileNodeOpenResult> openNodeWithPlan(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    return FileNodeOpenResult(
      opened: false,
      action: 'download_then_open',
      localIdentity: <String, Object?>{
        if (node.storageObjectId != null)
          'storageObjectId': node.storageObjectId,
      },
      message: 'download required for this device',
    );
  }
}

class _ScriptedPreviewInteractionService extends FileContextInteractionService {
  _ScriptedPreviewInteractionService(
    this.repository, {
    required this.blockedNodeId,
  }) : super(repository: repository);

  final FakeFileContextRepository repository;
  final int blockedNodeId;
  final previewedNodeIds = <int>[];

  @override
  Future<FilePreviewResult> previewTextNode(FileNode node) async {
    previewedNodeIds.add(node.id);
    if (node.id == blockedNodeId) {
      return FilePreviewResult(
        canPreview: false,
        displayName: node.displayName,
        content: null,
        message: 'preview disabled',
      );
    }
    return FilePreviewResult(
      canPreview: true,
      displayName: node.displayName,
      content: File(node.localPath).readAsStringSync(),
      message: null,
    );
  }
}

class _SnapshotThrowingCloudApi extends FakeFileCloudApi {
  _SnapshotThrowingCloudApi({
    super.versionsFixture = const <Map<String, Object?>>[],
  });

  @override
  Future<Map<String, dynamic>> createKopiaSnapshot({
    required String rootPath,
    String? rootId,
  }) async {
    createdSnapshots.add(<String, Object?>{
      'rootPath': rootPath,
      'rootId': rootId,
    });
    throw StateError('snapshot offline');
  }
}

class _FailingPreparedDownloadTransferService extends FileTransferService {
  _FailingPreparedDownloadTransferService(AppDatabase db)
      : super(
          apiLoader: () async => throw UnimplementedError(),
          operationLogs: DataOperationLogRepository(db),
        );

  final preparedResponses = <Map<String, Object?>>[];

  @override
  Future<FileTransferJob> downloadPreparedSession(
    Map<String, Object?> response,
    String targetPath,
  ) async {
    preparedResponses.add(response);
    throw StateError('prepared download should not start');
  }
}
