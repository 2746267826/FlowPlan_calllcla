import 'dart:io';

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
      'snapshot without local path and version actions show real page status',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final dir = Directory.systemTemp.createTempSync(
      'flowplanv2-gap6-page-status-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, dir));
    final file = File('${dir.path}${Platform.pathSeparator}draft.txt')
      ..writeAsStringSync('draft body');
    final copy = File('${dir.path}${Platform.pathSeparator}draft.copy.txt');
    final remoteRoot = fileFolderFixture(
      id: 1,
      displayName: 'Remote Only Root',
      localPath: null,
      remoteId: 'remote-root-gap6',
      availability: FileAvailability.remoteOnly,
    );
    final localRoot = fileFolderFixture(
      id: 2,
      displayName: 'Local Version Root',
      localPath: dir.path,
      remoteId: 'local-root-gap6',
      availability: FileAvailability.local,
    );
    final remoteRootNode = fileNodeFixture(
      id: 10,
      rootFolderId: remoteRoot.id,
      itemType: FileNodeType.folder,
      displayName: remoteRoot.displayName,
      relativePath: '',
      remoteId: 'remote-root-node-gap6',
      depth: 0,
    );
    final localRootNode = fileNodeFixture(
      id: 20,
      rootFolderId: localRoot.id,
      itemType: FileNodeType.folder,
      displayName: localRoot.displayName,
      localPath: dir.path,
      relativePath: '',
      remoteId: 'local-root-node-gap6',
      availability: FileAvailability.local,
      depth: 0,
    );
    final draftNode = fileNodeFixture(
      id: 21,
      rootFolderId: localRoot.id,
      parentNodeId: localRootNode.id,
      displayName: 'draft.txt',
      localPath: file.path,
      relativePath: 'draft.txt',
      remoteId: 'draft-node-gap6',
      availability: FileAvailability.local,
      storageObjectId: 'storage-draft-gap6',
    );
    final repository = FakeFileContextRepository(
      roots: [remoteRoot, localRoot],
      nodes: [remoteRootNode, localRootNode, draftNode],
    );
    final cloudApi = FakeFileCloudApi(
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-gap6',
          'displayName': 'Draft version gap6',
          'versionRef': 'kopia:version-gap6',
        },
      ],
    );

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: FakeFilePicker(savePath: copy.path),
      transferService: FileTransferService(
        apiLoader: () async => cloudApi,
        operationLogs: DataOperationLogRepository(db),
      ),
    );
    await pumpFileContextUntilFound(tester, find.text('Remote Only Root'));

    await tester.tap(find.byIcon(Icons.history_toggle_off));
    await pumpFileContextUntilFound(tester, find.byType(SnackBar));

    await _openRoot(tester, 'Local Version Root');
    await _selectNode(tester, 'draft.txt');
    await pumpFileContextUntilFound(tester, find.text('Draft version gap6'));

    await _tapIcon(tester, Icons.cloud_upload_outlined);
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.registeredStorageObjects.isNotEmpty,
    );
    await _tapIcon(tester, Icons.history);
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.refreshedVersions.isNotEmpty,
    );
    await _tapIcon(tester, Icons.download_outlined);
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.downloadedVersionCopies.isNotEmpty,
    );

    expect(cloudApi.createdSnapshots, isEmpty);
    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        'draft-node-gap6');
    expect(cloudApi.refreshedVersions.single['fileId'], draftNode.id.toString());
    expect(cloudApi.downloadedVersionCopies.single['versionId'], 'version-gap6');
  });

  testWidgets('image and text preview panes reload when selected node changes',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync(
      'flowplanv2-gap6-preview-reload-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, dir));
    final image = File('${dir.path}${Platform.pathSeparator}broken.png')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final firstText = File('${dir.path}${Platform.pathSeparator}first.txt')
      ..writeAsStringSync('first text');
    final secondText = File('${dir.path}${Platform.pathSeparator}second.txt')
      ..writeAsStringSync('second text');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Preview Reload Root',
      localPath: dir.path,
      remoteId: 'preview-reload-root-gap6',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: dir.path,
      relativePath: '',
      remoteId: 'preview-reload-root-node-gap6',
      availability: FileAvailability.local,
      depth: 0,
    );
    final imageNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'broken.png',
      localPath: image.path,
      relativePath: 'broken.png',
      remoteId: 'broken-image-gap6',
      mimeType: 'image/png',
      availability: FileAvailability.local,
    );
    final firstNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'first.txt',
      localPath: firstText.path,
      relativePath: 'first.txt',
      remoteId: 'first-text-gap6',
      availability: FileAvailability.local,
    );
    final secondNode = fileNodeFixture(
      id: 13,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'second.txt',
      localPath: secondText.path,
      relativePath: 'second.txt',
      remoteId: 'second-text-gap6',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, imageNode, firstNode, secondNode],
    );
    final interaction = _RecordingPreviewInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interaction,
    );
    await pumpFileContextUntilFound(tester, find.text('broken.png'));

    await _selectNode(tester, 'broken.png');
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await _selectNode(tester, 'first.txt');
    await _pumpUntilEditableText(tester, 'first text');
    await _selectNode(tester, 'second.txt');
    await _pumpUntilEditableText(tester, 'second text');

    expect(interaction.previewedNodeIds, <int>[firstNode.id, secondNode.id]);
  });
}

Future<void> _openRoot(WidgetTester tester, String rootName) async {
  final text = find.text(rootName);
  await pumpFileContextUntilFound(tester, text, maxPumps: 20);
  final tile = find.ancestor(of: text.first, matching: find.byType(ListTile));
  expect(tile, findsOneWidget);
  await tester.tap(tile);
  await tester.pump();
}

Future<void> _selectNode(WidgetTester tester, String nodeName) async {
  final tile = _treeTileFor(nodeName, Icons.check_circle_outline);
  await pumpFileContextUntilFound(tester, tile, maxPumps: 20);
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

Finder _treeTileFor(String text, IconData actionIcon) {
  return find.byElementPredicate(
    (element) {
      if (element.widget is! ListTile) {
        return false;
      }
      var hasText = false;
      var hasAction = false;
      void visit(Element child) {
        final widget = child.widget;
        if (widget is Text && widget.data == text) {
          hasText = true;
        }
        if (widget is Icon && widget.icon == actionIcon) {
          hasAction = true;
        }
        child.visitChildElements(visit);
      }

      element.visitChildElements(visit);
      return hasText && hasAction;
    },
    description: 'tree tile "$text"',
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
  int maxPumps = 20,
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

class _RecordingPreviewInteractionService extends FileContextInteractionService {
  _RecordingPreviewInteractionService(this.repository)
      : super(repository: repository);

  final FakeFileContextRepository repository;
  final previewedNodeIds = <int>[];

  @override
  Future<FilePreviewResult> previewTextNode(FileNode node) async {
    previewedNodeIds.add(node.id);
    return FilePreviewResult(
      canPreview: true,
      displayName: node.displayName,
      content: File(node.localPath).readAsStringSync(),
      message: null,
    );
  }
}
