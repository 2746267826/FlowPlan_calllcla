import 'dart:io';

import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';

void main() {
  testWidgets('snapshot action reports a missing local root path', (
    tester,
  ) async {
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Remote Snapshot Root',
      localPath: null,
      remoteId: 'remote-snapshot-root',
      availability: FileAvailability.remoteOnly,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'remote-snapshot-root-node',
      depth: 0,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode],
    );
    final cloudApi = FakeFileCloudApi();

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
    );
    await pumpFileContextUntilFound(tester, find.text('Remote Snapshot Root'));

    final button = find.widgetWithIcon(
      IconButton,
      Icons.history_toggle_off,
    );
    expect(button, findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.byType(SnackBar));

    expect(cloudApi.createdSnapshots, isEmpty);
  });

  testWidgets(
      'node changes reload server and text panes before version success actions',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-lcov-gap-b-page-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final firstFile = File(
      '${directory.path}${Platform.pathSeparator}first.txt',
    )..writeAsStringSync('first body');
    final secondFile = File(
      '${directory.path}${Platform.pathSeparator}second.txt',
    )..writeAsStringSync('second body');
    final copyTarget = File(
      '${directory.path}${Platform.pathSeparator}second.copy.txt',
    );
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Version Reload Root',
      localPath: directory.path,
      remoteId: 'version-reload-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'version-reload-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final firstNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'first.txt',
      localPath: firstFile.path,
      relativePath: 'first.txt',
      remoteId: 'first-version-node',
      availability: FileAvailability.local,
    );
    final secondNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'second.txt',
      localPath: secondFile.path,
      relativePath: 'second.txt',
      remoteId: 'second-version-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, firstNode, secondNode],
    );
    final cloudApi = FakeFileCloudApi(
      versionsFixture: const [
        <String, Object?>{
          'id': 'focused-version',
          'displayName': 'Focused version',
          'versionRef': 'kopia:focused-version',
        },
      ],
    );
    final interaction = _RecordingPreviewInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: FakeFilePicker(savePath: copyTarget.path),
      interactionService: interaction,
    );
    await pumpFileContextUntilFound(tester, find.text('first.txt'));

    await _selectNode(tester, 'first.txt');
    await _pumpUntilEditableText(tester, 'first body');
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.versionRequests.contains(firstNode.id.toString()),
    );

    await _selectNode(tester, 'second.txt');
    await _pumpUntilEditableText(tester, 'second body');
    await _waitForAsyncCondition(
      tester,
      () => cloudApi.versionRequests.contains(secondNode.id.toString()),
    );

    expect(interaction.previewedNodeIds, <int>[firstNode.id, secondNode.id]);

    await _tapServerActionButton(tester, Icons.cloud_upload_outlined);
    await _waitForAsyncCondition(
      tester,
      () =>
          cloudApi.registeredStorageObjects.isNotEmpty &&
          _snackTextContains(tester, '服务端存储对象'),
      reason: 'register action',
    );
    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        'second-version-node');
    await _clearSnackBars(tester);

    await _tapServerActionButton(tester, Icons.history);
    await _waitForAsyncCondition(
      tester,
      () =>
          cloudApi.refreshedVersions.isNotEmpty &&
          _snackTextContains(tester, '历史版本已刷新'),
      reason: 'refresh action',
    );
    expect(
        cloudApi.refreshedVersions.single['fileId'], secondNode.id.toString());
    await _clearSnackBars(tester);

    await _tapVersionActionIcon(
      tester,
      versionName: 'Focused version',
      icon: Icons.download_outlined,
    );
    await _waitForAsyncCondition(
      tester,
      () =>
          cloudApi.downloadedVersionCopies.isNotEmpty &&
          _snackTextContains(tester, '历史版本已下载'),
      reason: 'download action',
    );

    expect(cloudApi.downloadedVersionCopies.single['versionId'],
        'focused-version');
    expect(
        cloudApi.downloadedVersionCopies.single['targetPath'], copyTarget.path);
  });

  testWidgets('panel picker falls back when the selected root disappears', (
    tester,
  ) async {
    final alphaRoot = fileFolderFixture(
      id: 1,
      displayName: 'Alpha Root',
    );
    final betaRoot = fileFolderFixture(
      id: 2,
      displayName: 'Beta Root',
      folderUid: 'folder-2',
      remoteId: 'root-b',
    );
    final alphaRootNode = fileNodeFixture(
      id: 10,
      rootFolderId: alphaRoot.id,
      itemType: FileNodeType.folder,
      displayName: alphaRoot.displayName,
      relativePath: '',
      depth: 0,
    );
    final betaRootNode = fileNodeFixture(
      id: 20,
      rootFolderId: betaRoot.id,
      itemType: FileNodeType.folder,
      displayName: betaRoot.displayName,
      relativePath: '',
      depth: 0,
    );
    final alphaFile = fileNodeFixture(
      id: 11,
      rootFolderId: alphaRoot.id,
      parentNodeId: alphaRootNode.id,
      displayName: 'Alpha brief.md',
      relativePath: 'Alpha brief.md',
    );
    final betaFile = fileNodeFixture(
      id: 21,
      rootFolderId: betaRoot.id,
      parentNodeId: betaRootNode.id,
      displayName: 'Beta brief.md',
      relativePath: 'Beta brief.md',
    );
    final repository = _LiveRootsPanelRepository(
      roots: [alphaRoot, betaRoot],
      nodes: [alphaRootNode, betaRootNode, alphaFile, betaFile],
    );

    await pumpEntityFileContextPanelHarness(
      tester,
      repository: repository,
    );
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Alpha brief.md'));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta Root').last);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Beta brief.md'));

    repository.roots.removeWhere((root) => root.id == betaRoot.id);
    await tester.enterText(find.byType(TextField).first, 'Alpha');
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Alpha brief.md'));

    expect(repository.searchRequests.last['rootFolderId'], alphaRoot.id);
    expect(repository.searchRequests.last['query'], 'Alpha');
  });
}

bool _snackTextContains(WidgetTester tester, String text) {
  return find
      .descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(text),
      )
      .evaluate()
      .isNotEmpty;
}

Future<void> _selectNode(WidgetTester tester, String nodeName) async {
  final tile = find.ancestor(
    of: find.text(nodeName).first,
    matching: find.byType(ListTile),
  );
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
  int maxPumps = 24,
  String? reason,
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
  fail(
    'Timed out waiting for async condition.'
    '${reason == null ? '' : ' $reason'} '
    'SnackBars: ${_visibleSnackTexts(tester)}',
  );
}

List<String> _visibleSnackTexts(WidgetTester tester) {
  final bars = find.byType(SnackBar);
  return tester
      .widgetList<Text>(
        find.descendant(
          of: bars,
          matching: find.byType(Text),
        ),
      )
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
}

Future<void> _clearSnackBars(WidgetTester tester) async {
  final messenger = find.byType(ScaffoldMessenger);
  expect(messenger, findsWidgets);
  tester.state<ScaffoldMessengerState>(messenger.first).clearSnackBars();
  await tester.pump();
  await _waitForAsyncCondition(
    tester,
    () => find.byType(SnackBar).evaluate().isEmpty,
  );
}

Future<void> _disposeWidgetAndDeleteTemp(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
}

class _RecordingPreviewInteractionService
    extends FileContextInteractionService {
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

class _LiveRootsPanelRepository extends FakeFileContextRepository {
  _LiveRootsPanelRepository({
    required super.roots,
    required super.nodes,
  });

  @override
  Future<List<FileFolder>> listFolders({int limit = 200}) async {
    listFoldersCalls++;
    return roots;
  }
}
