import 'dart:async';
import 'dart:io';

import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_context_page.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';

void main() {
  testWidgets('file page reloads preview panes when the selected node changes',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap9-preview-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final brokenImage =
        File('${directory.path}${Platform.pathSeparator}broken.png')
          ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final firstText = File('${directory.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('alpha gap9 body');
    final secondText = File('${directory.path}${Platform.pathSeparator}b.txt')
      ..writeAsStringSync('beta gap9 body');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Gap9 Preview Root',
      localPath: directory.path,
      remoteId: 'gap9-preview-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'gap9-preview-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final imageNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'broken.png',
      localPath: brokenImage.path,
      relativePath: 'broken.png',
      remoteId: 'gap9-broken-image',
      mimeType: 'image/png',
      availability: FileAvailability.local,
    );
    final firstTextNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'a.txt',
      localPath: firstText.path,
      relativePath: 'a.txt',
      remoteId: 'gap9-a',
      availability: FileAvailability.local,
    );
    final secondTextNode = fileNodeFixture(
      id: 13,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'b.txt',
      localPath: secondText.path,
      relativePath: 'b.txt',
      remoteId: 'gap9-b',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, imageNode, firstTextNode, secondTextNode],
    );
    final secondPreviewGate = Completer<void>();
    final interaction = _PreviewRecordingInteractionService(
      repository,
      previewGates: {secondTextNode.id: secondPreviewGate.future},
    );

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interaction,
    );
    await pumpFileContextUntilFound(tester, find.text('broken.png'));

    await _selectNode(tester, 'broken.png');
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await _waitForAsyncCondition(
      tester,
      () => find.textContaining('图片预览失败').evaluate().isNotEmpty,
      maxPumps: 20,
    );

    await _selectNode(tester, 'a.txt');
    await _pumpUntilEditableText(tester, 'alpha gap9 body');

    await _selectNode(tester, 'b.txt');
    await _pumpUntil(
      tester,
      () => interaction.previewedNodeIds.contains(secondTextNode.id),
      maxPumps: 20,
    );
    expect(interaction.previewedNodeIds, [firstTextNode.id, secondTextNode.id]);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((widget) => widget.controller.text == 'beta gap9 body'),
      isFalse,
    );
    secondPreviewGate.complete();
    await _pumpUntilEditableText(tester, 'beta gap9 body');

    expect(interaction.previewedNodeIds, [firstTextNode.id, secondTextNode.id]);
    expect(find.text('alpha gap9 body'), findsNothing);
  });

  testWidgets(
      'server storage pane reloads on node change and reports successful version actions',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap9-versions-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final firstFile = File('${directory.path}${Platform.pathSeparator}first.md')
      ..writeAsStringSync('first');
    final secondFile =
        File('${directory.path}${Platform.pathSeparator}second.md')
          ..writeAsStringSync('second');
    final copyTarget =
        File('${directory.path}${Platform.pathSeparator}second-copy.md');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Gap9 Version Root',
      localPath: directory.path,
      remoteId: 'gap9-version-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'gap9-version-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final firstNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'first.md',
      localPath: firstFile.path,
      relativePath: 'first.md',
      remoteId: 'gap9-first-node',
      availability: FileAvailability.local,
    );
    final secondNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'second.md',
      localPath: secondFile.path,
      relativePath: 'second.md',
      remoteId: 'gap9-second-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, firstNode, secondNode],
    );
    final cloudApi = FakeFileCloudApi(
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-gap9',
          'displayName': 'Gap9 kopia version',
          'versionRef': 'kopia:gap9',
        },
      ],
    );
    final picker = FakeFilePicker(savePath: copyTarget.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: picker,
      onlinePrimaryPolicy: const OnlinePrimaryPolicy(
        serverReachable: true,
        authenticated: true,
        level: ServerConnectionLevel.online,
      ),
    );
    await pumpFileContextUntilFound(tester, find.text('first.md'));

    await _selectNode(tester, 'first.md');
    await pumpFileContextUntilFound(tester, find.text('Gap9 kopia version'));
    expect(cloudApi.storageObjectRequests.last['nodeId'], firstNode.remoteId);
    expect(cloudApi.versionRequests.last, firstNode.id.toString());

    await _selectNode(tester, 'second.md');
    await _pumpUntil(
      tester,
      () =>
          cloudApi.storageObjectRequests.isNotEmpty &&
          cloudApi.versionRequests.isNotEmpty &&
          cloudApi.storageObjectRequests.last['nodeId'] ==
              secondNode.remoteId &&
          cloudApi.versionRequests.last == secondNode.id.toString(),
      maxPumps: 20,
    );
    expect(cloudApi.storageObjectRequests.last['nodeId'], secondNode.remoteId);
    expect(cloudApi.versionRequests.last, secondNode.id.toString());

    await _tapIconAndWaitForReload(
      tester,
      cloudApi,
      Icons.cloud_upload_outlined,
    );
    expect(find.byType(SnackBar), findsOneWidget);
    expect(cloudApi.storageObjectRequests.last['nodeId'], secondNode.remoteId);
    expect(cloudApi.versionRequests.last, secondNode.id.toString());

    await _tapIconAndWaitForReload(tester, cloudApi, Icons.history);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(cloudApi.storageObjectRequests.last['nodeId'], secondNode.remoteId);
    expect(cloudApi.versionRequests.last, secondNode.id.toString());

    await _tapIconAndWaitForReload(tester, cloudApi, Icons.download_outlined);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(cloudApi.storageObjectRequests.last['nodeId'], secondNode.remoteId);
    expect(cloudApi.versionRequests.last, secondNode.id.toString());

    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        secondNode.remoteId);
    expect(
        cloudApi.refreshedVersions.single['fileId'], secondNode.id.toString());
    expect(
        cloudApi.downloadedVersionCopies.single['versionId'], 'version-gap9');
    expect(picker.saveRequests.single['fileName'], 'second.kopia-copy.md');
  });

  testWidgets('server storage register action requires online upload policy',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'flowplanv2-gap9-policy-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, directory));
    final file = File('${directory.path}${Platform.pathSeparator}policy.md')
      ..writeAsStringSync('policy');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Gap9 Policy Root',
      localPath: directory.path,
      remoteId: 'gap9-policy-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: directory.path,
      relativePath: '',
      remoteId: 'gap9-policy-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final node = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'policy.md',
      localPath: file.path,
      relativePath: 'policy.md',
      remoteId: 'gap9-policy-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, node],
    );
    final cloudApi = FakeFileCloudApi();

    await _pumpFileContextPageWithPolicy(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      policy: const OnlinePrimaryPolicy(
        serverReachable: false,
        authenticated: true,
        level: ServerConnectionLevel.offline,
      ),
    );
    await pumpFileContextUntilFound(tester, find.text('policy.md'));

    await _selectNode(tester, 'policy.md');
    await pumpFileContextUntilFound(tester, find.text('登记到服务端'));

    await _tapIcon(tester, Icons.cloud_upload_outlined);
    await _pumpUntil(
      tester,
      () => find
          .text(
              'Server connection is required before this write can be accepted.')
          .evaluate()
          .isNotEmpty,
      maxPumps: 20,
    );

    expect(cloudApi.registeredStorageObjects, isEmpty);
  });

  testWidgets('event panel binds a picked node after the root dropdown changes',
      (tester) async {
    final firstRoot = fileFolderFixture(
      id: 1,
      displayName: 'First Event Root',
      remoteId: 'first-event-root',
    );
    final secondRoot = fileFolderFixture(
      id: 2,
      displayName: 'Second Event Root',
      remoteId: 'second-event-root',
    );
    final firstRootNode = fileNodeFixture(
      id: 10,
      rootFolderId: firstRoot.id,
      itemType: FileNodeType.folder,
      displayName: firstRoot.displayName,
      relativePath: '',
      remoteId: 'first-event-root-node',
      depth: 0,
    );
    final secondRootNode = fileNodeFixture(
      id: 20,
      rootFolderId: secondRoot.id,
      itemType: FileNodeType.folder,
      displayName: secondRoot.displayName,
      relativePath: '',
      remoteId: 'second-event-root-node',
      depth: 0,
    );
    final agenda = fileNodeFixture(
      id: 21,
      rootFolderId: secondRoot.id,
      parentNodeId: secondRootNode.id,
      displayName: 'event-agenda.md',
      relativePath: 'event-agenda.md',
      remoteId: 'event-agenda-node',
    );
    final repository = FakeFileContextRepository(
      roots: [firstRoot, secondRoot],
      nodes: [firstRootNode, secondRootNode, agenda],
    );

    await pumpEntityFileContextPanelHarness(
      tester,
      repository: repository,
      entityType: FileContextEntityType.event,
      entityId: 'event-9',
      title: 'Planning calendar hold',
    );
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('First Event Root'));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Event Root').last);
    await tester.pumpAndSettle();
    await pumpFileContextUntilFound(tester, find.text('event-agenda.md'));

    await tester.tap(
      find.descendant(
        of: _tileForText('event-agenda.md'),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(repository.boundNodeIds, [agenda.id]);
    expect(repository.recordedNodeActions, contains('bind_file_node'));
    expect(repository.links.last.entityType, FileContextEntityType.event);
    expect(repository.links.last.entityId, 'event-9');
  });
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

Future<void> _pumpFileContextPageWithPolicy(
  WidgetTester tester, {
  required FakeFileContextRepository repository,
  required FakeFileCloudApi cloudApi,
  required OnlinePrimaryPolicy policy,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileContextRepositoryProvider.overrideWithValue(repository),
        fileContextApiProvider
            .overrideWith((ref) async => FakeFileContextApi()),
        fileCloudApiProvider.overrideWith((ref) async => cloudApi),
        onlinePrimaryPolicyProvider.overrideWith((ref) => policy),
      ],
      child: const MaterialApp(home: FileContextPage()),
    ),
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

Finder _tileForText(String text) {
  return find.ancestor(
    of: find.text(text).first,
    matching: find.byType(ListTile),
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

Future<void> _tapIconAndWaitForReload(
  WidgetTester tester,
  FakeFileCloudApi cloudApi,
  IconData icon,
) async {
  await _clearSnackBars(tester);
  final storageRequestCount = cloudApi.storageObjectRequests.length;
  final versionRequestCount = cloudApi.versionRequests.length;
  await _tapIcon(tester, icon);
  await _pumpUntil(
    tester,
    () =>
        cloudApi.storageObjectRequests.length > storageRequestCount &&
        cloudApi.versionRequests.length > versionRequestCount &&
        find.byType(SnackBar).evaluate().isNotEmpty,
    maxPumps: 20,
  );
  expect(find.byType(SnackBar), findsOneWidget);
}

Future<void> _clearSnackBars(WidgetTester tester) async {
  final messengerFinder = find.byType(ScaffoldMessenger);
  expect(messengerFinder, findsWidgets);
  tester.state<ScaffoldMessengerState>(messengerFinder.first).clearSnackBars();
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
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
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

class _PreviewRecordingInteractionService
    extends FileContextInteractionService {
  _PreviewRecordingInteractionService(
    this.repository, {
    this.previewGates = const {},
  }) : super(repository: repository);

  final FakeFileContextRepository repository;
  final Map<int, Future<void>> previewGates;
  final previewedNodeIds = <int>[];

  @override
  Future<FilePreviewResult> previewTextNode(FileNode node) async {
    previewedNodeIds.add(node.id);
    await (previewGates[node.id] ??
        Future<void>.delayed(const Duration(milliseconds: 10)));
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
