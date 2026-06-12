import 'dart:async';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_context_panel.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets('file page shows root loading and empty first-run states', (
    tester,
  ) async {
    final repository = FakeFileContextRepository()
      ..listFoldersCompleter = Completer<List<FileFolder>>();

    await pumpFileContextPageHarness(tester, repository: repository);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.listFoldersCompleter!.complete(const <FileFolder>[]);
    await tester.pump();
    await tester.pump();

    expect(
      find.widgetWithIcon(FilledButton, Icons.create_new_folder_outlined),
      findsOneWidget,
    );
  });

  testWidgets(
    'file page adds server roots, scans, searches, and navigates local and server trees',
    (tester) async {
      final localDirectory = Directory.systemTemp.createTempSync(
        'flowplanv2-file-context-local-',
      );
      addTearDown(() {
        if (localDirectory.existsSync()) {
          localDirectory.deleteSync(recursive: true);
        }
      });
      final serverRoot = fileFolderFixture(
        id: 1,
        folderUid: 'server-root',
        displayName: 'Server Drive Alpha',
        remoteId: 'drive-alpha',
      );
      final localRoot = fileFolderFixture(
        id: 2,
        folderUid: 'local-root',
        provider: FileProviderKind.local,
        displayName: 'Local Notes',
        localPath: localDirectory.path,
        remoteId: null,
        availability: FileAvailability.local,
      );
      final serverRootNode = fileNodeFixture(
        id: 10,
        rootFolderId: serverRoot.id,
        itemType: FileNodeType.folder,
        displayName: serverRoot.displayName,
        relativePath: '',
        localPath: '',
        remoteId: 'drive-alpha-root',
        availability: FileAvailability.remoteOnly,
        depth: 0,
      );
      final designFolder = fileNodeFixture(
        id: 11,
        rootFolderId: serverRoot.id,
        parentNodeId: serverRootNode.id,
        itemType: FileNodeType.folder,
        displayName: 'Design',
        relativePath: 'Design',
        remoteId: 'drive-alpha-design',
      );
      final sprintBrief = fileNodeFixture(
        id: 12,
        rootFolderId: serverRoot.id,
        parentNodeId: designFolder.id,
        displayName: 'Sprint brief.txt',
        relativePath: 'Design/Sprint brief.txt',
        remoteId: 'drive-alpha-brief',
      );
      final localRootNode = fileNodeFixture(
        id: 20,
        rootFolderId: localRoot.id,
        itemType: FileNodeType.folder,
        displayName: localRoot.displayName,
        localPath: localDirectory.path,
        relativePath: '',
        availability: FileAvailability.local,
        depth: 0,
      );
      final localNote = fileNodeFixture(
        id: 21,
        rootFolderId: localRoot.id,
        parentNodeId: localRootNode.id,
        displayName: 'local-plan.md',
        localPath:
            '${localDirectory.path}${Platform.pathSeparator}local-plan.md',
        relativePath: 'local-plan.md',
        remoteId: null,
        availability: FileAvailability.missing,
      );
      final repository = FakeFileContextRepository(
        rootsAfterSync: [serverRoot, localRoot],
        nodes: [localRootNode, localNote],
      )..onRequestServerRootScan = (repo, rootFolderId) {
          repo
            ..upsertNode(serverRootNode)
            ..upsertNode(designFolder)
            ..upsertNode(sprintBrief);
        };

      await pumpFileContextPageHarness(tester, repository: repository);
      await tester.pump();

      expect(find.text('Server Drive Alpha'), findsNothing);

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined).last);
      await tester.pump();
      await tester.pump();

      expect(repository.syncDriveRootsCalls, 1);
      expect(find.text('Server Drive Alpha'), findsWidgets);
      expect(find.text('Local Notes'), findsOneWidget);

      final snapshotButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.history_toggle_off).first,
      );
      expect(snapshotButton.onPressed, isNotNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh).first);
      await tester.pump();
      await pumpFileContextUntilFound(tester, find.text('Design'));

      expect(repository.scanRequests, [serverRoot.id]);
      expect(find.text('Design'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'brief');
      await tester.pump();
      await pumpFileContextUntilFound(tester, find.text('Sprint brief.txt'));

      expect(repository.searchRequests.last['query'], 'brief');
      expect(find.text('Sprint brief.txt'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await pumpFileContextUntilFound(tester, find.text('Design'));

      await tester.tap(find.text('Design'));
      await tester.pump();
      await pumpFileContextUntilFound(tester, find.text('Sprint brief.txt'));

      expect(find.text('Sprint brief.txt'), findsOneWidget);

      await tester
          .tap(find.widgetWithIcon(IconButton, Icons.arrow_upward).first);
      await tester.pump();
      await tester.pump();

      final upButtonAtRoot = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_upward).first,
      );
      expect(upButtonAtRoot.onPressed, isNull);

      await tester.tap(find.text('Local Notes'));
      await tester.pump();
      await pumpFileContextUntilFound(tester, find.text('local-plan.md'));

      expect(find.text('local-plan.md'), findsOneWidget);
    },
  );

  testWidgets('file page relocates roots and requires delete confirmation', (
    tester,
  ) async {
    final selectedDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-relocated-',
    );
    addTearDown(() {
      if (selectedDirectory.existsSync()) {
        selectedDirectory.deleteSync(recursive: true);
      }
    });
    final serverRoot = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Beta',
      remoteId: 'drive-beta',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: serverRoot.id,
      itemType: FileNodeType.folder,
      displayName: serverRoot.displayName,
      relativePath: '',
      remoteId: 'drive-beta-root',
      depth: 0,
    );
    final repository = FakeFileContextRepository(
      roots: [serverRoot],
      nodes: [rootNode],
    );
    final picker = FakeFilePicker(directoryPath: selectedDirectory.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      filePicker: picker,
    );
    await tester.pump();

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.folder_special_outlined).first,
    );
    await tester.pump();
    await tester.pump();

    expect(repository.boundRootPaths.single['folderId'], serverRoot.id);
    expect(
        repository.boundRootPaths.single['localPath'], selectedDirectory.path);
    expect(picker.directoryRequests.single['initialDirectory'], isNull);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.deletedRootIds, isEmpty);
    expect(find.text('Server Drive Beta'), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    await tester.pump();

    expect(repository.deletedRootIds, [serverRoot.id]);
    expect(find.text('Server Drive Beta'), findsNothing);
  });

  testWidgets('file page disables scan while pending and re-enables afterwards',
      (
    tester,
  ) async {
    final scanCompleter = Completer<void>();
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Scan',
      remoteId: 'drive-scan',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'drive-scan-root',
      depth: 0,
    );
    final scannedFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'scanned-result.txt',
      remoteId: 'drive-scan-file',
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode],
    )
      ..scanCompleter = scanCompleter
      ..onRequestServerRootScan = (repo, _) => repo.upsertNode(scannedFile);

    await pumpFileContextPageHarness(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh).first);
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final disabledRefresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh).first,
    );
    expect(disabledRefresh.onPressed, isNull);

    scanCompleter.complete();
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('scanned-result.txt'));

    expect(repository.scanRequests, [root.id]);
    expect(find.text('scanned-result.txt'), findsOneWidget);
    final enabledRefresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh).first,
    );
    expect(enabledRefresh.onPressed, isNotNull);
  });

  testWidgets('file page surfaces scan failures without clearing the tree', (
    tester,
  ) async {
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Error',
      remoteId: 'drive-error',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'drive-error-root',
      depth: 0,
    );
    final existingFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'already-here.txt',
      remoteId: 'drive-error-existing',
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, existingFile],
    )..scanError = StateError('scanner offline');

    await pumpFileContextPageHarness(tester, repository: repository);
    await pumpFileContextUntilFound(tester, find.text('already-here.txt'));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh).first);
    await tester.pump();
    await pumpFileContextUntilFound(
        tester, find.textContaining('scanner offline'));
    await pumpFileContextUntilFound(tester, find.text('already-here.txt'));

    expect(repository.scanRequests, [root.id]);
    expect(find.text('already-here.txt'), findsOneWidget);
    expect(find.textContaining('scanner offline'), findsOneWidget);
  });

  testWidgets('file page shows read errors, empty trees, and disabled actions',
      (
    tester,
  ) async {
    final errorRepository = FakeFileContextRepository()
      ..listFoldersError = StateError('roots offline');

    await pumpFileContextPageHarness(tester, repository: errorRepository);
    await tester.pump();

    expect(find.textContaining('roots offline'), findsOneWidget);

    final root = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Empty',
      remoteId: 'drive-empty',
    );
    final emptyRepository = FakeFileContextRepository(roots: [root]);

    await pumpFileContextPageHarness(tester, repository: emptyRepository);
    await tester.pump();

    expect(
      find.widgetWithIcon(FilledButton, Icons.refresh),
      findsOneWidget,
    );

    final snapshotButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.history_toggle_off).first,
    );
    expect(snapshotButton.onPressed, isNotNull);

    final upButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward).first,
    );
    expect(upButton.onPressed, isNull);

    emptyRepository.listChildNodesError = StateError('tree offline');
    emptyRepository.upsertNode(
      fileNodeFixture(
        id: 10,
        rootFolderId: root.id,
        itemType: FileNodeType.folder,
        displayName: root.displayName,
        relativePath: '',
        depth: 0,
      ),
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh).first);
    await tester.pump();
    await pumpFileContextUntilFound(
        tester, find.textContaining('tree offline'));

    expect(find.textContaining('tree offline'), findsOneWidget);
  });

  testWidgets('file page refreshes selected drive root from the app bar', (
    tester,
  ) async {
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Refresh',
      remoteId: 'drive-refresh',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'drive-refresh-root',
      depth: 0,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode],
    );

    await pumpFileContextPageHarness(tester, repository: repository);
    await tester.pump();
    final requestsBefore = repository.refreshDriveNodeRequests.length;

    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pump();
    await tester.pump();

    expect(repository.syncDriveRootsCalls, 1);
    expect(repository.refreshDriveNodeRequests.length, requestsBefore + 2);
    expect(repository.refreshDriveNodeRequests.last['rootFolderId'], root.id);
    expect(
      repository.refreshDriveNodeRequests
          .skip(requestsBefore)
          .any((request) => request['parentNodeId'] == null),
      isTrue,
    );
  });

  testWidgets('file page previews and saves a selected local text node', (
    tester,
  ) async {
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-preview-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, localDirectory));
    final noteFile = File(
      '${localDirectory.path}${Platform.pathSeparator}meeting-notes.md',
    )..writeAsStringSync('original notes');
    final root = fileFolderFixture(
      id: 1,
      provider: FileProviderKind.local,
      displayName: 'Local Preview Root',
      localPath: localDirectory.path,
      remoteId: null,
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      availability: FileAvailability.local,
      depth: 0,
    );
    final noteNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'meeting-notes.md',
      localPath: noteFile.path,
      relativePath: 'meeting-notes.md',
      mimeType: 'text/markdown',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, noteNode],
    );
    final interactionService = RecordingPreviewInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interactionService,
    );
    await pumpFileContextUntilFound(tester, find.text('meeting-notes.md'));

    await _tapNodeTile(tester, 'meeting-notes.md');
    await pumpFileContextUntilFound(tester, find.text(noteFile.path));
    await tester.drag(find.byType(ListView).last, const Offset(0, -520));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => repository.recordedNodeActions.contains('preview_file_node'),
      maxPumps: 20,
    );
    await _pumpUntilEditableText(tester, 'original notes');

    expect(_editableTexts(tester), contains('original notes'));

    final editor = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && widget.controller.text == 'original notes',
    );
    await tester.enterText(editor, 'updated notes');
    await _pumpUntilEditableText(tester, 'updated notes');
    final saveButton = find.byKey(AppKeys.fileContextSavePreviewButton);
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tapAt(tester.getCenter(saveButton));
    expect(repository.recordedNodeActions, contains('preview_file_node'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _pumpUntil(
      tester,
      () =>
          interactionService.savedTextByNodeId[noteNode.id] == 'updated notes',
      maxPumps: 20,
    );
    expect(interactionService.savedTextByNodeId[noteNode.id], 'updated notes');
    expect(repository.recordedNodeActions, contains('save_file_node_text'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'file page queues a confirmed remote download and routes to transfers', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final transferService = RecordingFileTransferService(db);
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-download-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, localDirectory));
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Download',
      localPath: localDirectory.path,
      remoteId: 'drive-download',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      remoteId: 'drive-download-root',
      availability: FileAvailability.local,
      depth: 0,
    );
    final remoteFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Remote proposal.txt',
      localPath: '',
      relativePath: 'Remote proposal.txt',
      remoteId: 'remote-proposal',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-proposal',
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, remoteFile],
    );
    final contextApi = FakeFileContextApi(
      openPlanAction: 'download_then_open',
    );
    final interactionService = ForcedDownloadInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      contextApi: contextApi,
      transferService: transferService,
      interactionService: interactionService,
      withRouter: true,
    );
    await pumpFileContextUntilFound(tester, find.text('Remote proposal.txt'));

    await tester.tap(find.text('Remote proposal.txt').first);
    await pumpFileContextUntilFound(tester, find.text('Download'));

    await _tapNodeOpenButton(tester, 'Remote proposal.txt');
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('取消'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    expect(contextApi.downloadRequests, isEmpty);
    expect(transferService.preparedDownloads, isEmpty);

    await _tapNodeOpenButton(tester, 'Remote proposal.txt');
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    expect(find.byType(AlertDialog), findsOneWidget);
    await _tapDialogDownloadConfirm(tester);
    await _pumpUntil(
      tester,
      () =>
          (contextApi.downloadRequests.isNotEmpty &&
              transferService.preparedDownloads.isNotEmpty) ||
          find.textContaining('文件打开/下载失败').evaluate().isNotEmpty,
      maxPumps: 20,
    );

    final expectedTarget =
        '${localDirectory.path}${Platform.pathSeparator}Remote proposal.txt';
    expect(contextApi.downloadRequests.single['nodeId'], 'remote-proposal');
    expect(contextApi.downloadRequests.single['targetPath'], expectedTarget);
    expect(
        transferService.preparedDownloads.single['targetPath'], expectedTarget);
    await pumpFileContextUntilFound(
      tester,
      find.text('Transfer center route'),
      maxPumps: 20,
    );
    expect(find.text('Transfer center route'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('file page reports remote download request failures', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final transferService = RecordingFileTransferService(db);
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-download-fail-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, localDirectory));
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Server Drive Download Fail',
      localPath: localDirectory.path,
      remoteId: 'drive-download-fail',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      remoteId: 'drive-download-fail-root',
      availability: FileAvailability.local,
      depth: 0,
    );
    final remoteFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Blocked remote.txt',
      localPath: '',
      relativePath: 'Blocked remote.txt',
      remoteId: 'blocked-remote',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-blocked',
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, remoteFile],
    );
    final contextApi = FakeFileContextApi(
      openPlanAction: 'download_then_open',
      downloadRequestOk: false,
    );
    final interactionService = ForcedDownloadInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      contextApi: contextApi,
      transferService: transferService,
      interactionService: interactionService,
    );
    await pumpFileContextUntilFound(tester, find.text('Blocked remote.txt'));

    await tester.tap(find.text('Blocked remote.txt').first);
    await pumpFileContextUntilFound(tester, find.text('Download'));
    await _tapNodeOpenButton(tester, 'Blocked remote.txt');
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    expect(find.byType(AlertDialog), findsOneWidget);
    await _tapDialogDownloadConfirm(tester);
    await _pumpUntil(
      tester,
      () =>
          contextApi.downloadRequests.isNotEmpty ||
          find.textContaining('download denied').evaluate().isNotEmpty,
      maxPumps: 20,
    );

    expect(contextApi.downloadRequests.single['nodeId'], 'blocked-remote');
    expect(transferService.preparedDownloads, isEmpty);
    expect(find.textContaining('download denied'), findsOneWidget);
  });

  testWidgets('file page creates Kopia snapshots and reports snapshot failures',
      (
    tester,
  ) async {
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-snapshot-',
    );
    addTearDown(() {
      if (localDirectory.existsSync()) {
        localDirectory.deleteSync(recursive: true);
      }
    });
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Snapshot Root',
      localPath: localDirectory.path,
      remoteId: 'snapshot-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      remoteId: 'snapshot-root-node',
      availability: FileAvailability.local,
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
    await tester.pump();

    await _tapFirstEnabledSnapshotButton(tester);
    await _pumpUntil(
      tester,
      () => cloudApi.createdSnapshots.isNotEmpty,
    );

    expect(cloudApi.createdSnapshots.single['rootPath'], localDirectory.path);
    expect(cloudApi.createdSnapshots.single['rootId'], root.id.toString());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final failingCloudApi = FakeFileCloudApi(snapshotOk: false);
    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: failingCloudApi,
    );
    await tester.pump();

    await _tapFirstEnabledSnapshotButton(tester);
    await _pumpUntil(
      tester,
      () => failingCloudApi.createdSnapshots.isNotEmpty,
      maxPumps: 20,
    );
    await pumpFileContextUntilFound(
        tester, find.textContaining('snapshot denied'));

    expect(failingCloudApi.createdSnapshots.single['rootPath'],
        localDirectory.path);
    expect(find.textContaining('snapshot denied'), findsOneWidget);
  });

  testWidgets(
      'file page runs server storage and version actions from file details', (
    tester,
  ) async {
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-versions-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, localDirectory));
    final versionCopy = File(
      '${localDirectory.path}${Platform.pathSeparator}version-copy.txt',
    );
    final proposalFile = File(
      '${localDirectory.path}${Platform.pathSeparator}Proposal.txt',
    )..writeAsStringSync('proposal draft');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Versioned Root',
      localPath: localDirectory.path,
      remoteId: 'versioned-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      remoteId: 'versioned-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final proposalNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Proposal.txt',
      localPath: proposalFile.path,
      relativePath: 'Proposal.txt',
      remoteId: 'proposal-node',
      mimeType: 'text/plain',
      sizeBytes: 4096,
      storageObjectId: 'storage-proposal',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, proposalNode],
    );
    final cloudApi = FakeFileCloudApi(
      storageObjectsFixture: const [
        <String, Object?>{
          'displayName': 'Stored proposal.txt',
          'storageObjectId': 'object-7',
          'status': 'current',
        },
      ],
      versionsFixture: const [
        <String, Object?>{
          'id': 'version-9',
          'displayName': 'Proposal Kopia snapshot',
          'modifiedAt': '2026-06-09T08:00:00Z',
          'sizeBytes': 4096,
          'versionRef': 'kopia:snapshot-9',
        },
      ],
    );
    final picker = FakeFilePicker(savePath: versionCopy.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      cloudApi: cloudApi,
      filePicker: picker,
    );
    await pumpFileContextUntilFound(tester, find.text('Proposal.txt'));

    await _tapNodeTile(tester, 'Proposal.txt');
    await pumpFileContextUntilFound(
      tester,
      find.text('Stored proposal.txt'),
      maxPumps: 20,
    );
    await pumpFileContextUntilFound(
      tester,
      find.text('Proposal Kopia snapshot'),
      maxPumps: 20,
    );

    expect(
        cloudApi.storageObjectRequests.single['localPath'], proposalFile.path);
    expect(cloudApi.storageObjectRequests.single['nodeId'], 'proposal-node');
    expect(cloudApi.versionRequests, [proposalNode.id.toString()]);

    await _tapFirstIcon(tester, Icons.cloud_upload_outlined);
    await _pumpUntil(
      tester,
      () => cloudApi.registeredStorageObjects.isNotEmpty,
      maxPumps: 20,
    );

    expect(cloudApi.registeredStorageObjects.single['localPath'],
        proposalFile.path);
    expect(
        cloudApi.registeredStorageObjects.single['fileName'], 'Proposal.txt');
    expect(cloudApi.registeredStorageObjects.single['fileNodeId'],
        'proposal-node');
    expect(
      (cloudApi.registeredStorageObjects.single['metadata']
          as Map<String, Object?>)['rootFolderId'],
      root.id,
    );

    await _tapFirstIcon(tester, Icons.history);
    await _pumpUntil(
      tester,
      () => cloudApi.refreshedVersions.isNotEmpty,
      maxPumps: 20,
    );

    expect(cloudApi.refreshedVersions.single['fileId'],
        proposalNode.id.toString());
    expect(cloudApi.refreshedVersions.single['filePath'], proposalFile.path);
    expect(cloudApi.refreshedVersions.single['displayName'], 'Proposal.txt');

    await _tapFirstIcon(tester, Icons.download_outlined);
    await _pumpUntil(
      tester,
      () => cloudApi.downloadedVersionCopies.isNotEmpty,
      maxPumps: 20,
    );

    expect(picker.saveRequests.single['fileName'], 'Proposal.kopia-copy.txt');
    expect(cloudApi.downloadedVersionCopies.single['versionId'], 'version-9');
    expect(cloudApi.downloadedVersionCopies.single['targetPath'],
        versionCopy.path);
    expect(
      cloudApi.downloadedVersionCopies.single['auditNote'],
      isA<String>(),
    );

    await _tapFirstIcon(tester, Icons.rule_folder_outlined);
    await _pumpUntil(
      tester,
      () => cloudApi.preparedRestores.isNotEmpty,
      maxPumps: 20,
    );
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));

    expect(cloudApi.preparedRestores.single['versionId'], 'version-9');
    expect(cloudApi.preparedRestores.single['targetPath'], proposalFile.path);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
      maxPumps: 20,
    );
  });

  testWidgets('file page cancels remote downloads at the save picker', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final transferService = RecordingFileTransferService(db);
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Unbound Server Drive',
      localPath: null,
      remoteId: 'unbound-drive',
      availability: FileAvailability.remoteOnly,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'unbound-root-node',
      depth: 0,
    );
    final remoteFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Cloud-only brief.txt',
      localPath: '',
      relativePath: 'Cloud-only brief.txt',
      remoteId: 'cloud-only-brief',
      availability: FileAvailability.remoteOnly,
      sizeBytes: 0,
      storageObjectId: 'storage-cloud-only',
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, remoteFile],
    );
    final contextApi = FakeFileContextApi();
    final picker = FakeFilePicker(savePath: '');

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      contextApi: contextApi,
      filePicker: picker,
      transferService: transferService,
      interactionService: ForcedDownloadInteractionService(repository),
    );
    await pumpFileContextUntilFound(tester, find.text('Cloud-only brief.txt'));

    await _tapNodeOpenButton(tester, 'Cloud-only brief.txt');
    await pumpFileContextUntilFound(tester, find.byType(AlertDialog));
    await _tapDialogDownloadConfirm(tester);
    await _pumpUntil(
      tester,
      () => picker.saveRequests.isNotEmpty,
      maxPumps: 20,
    );

    expect(picker.saveRequests.single['fileName'], 'Cloud-only brief.txt');
    expect(contextApi.downloadRequests, isEmpty);
    expect(transferService.preparedDownloads, isEmpty);
  });

  testWidgets(
      'file page surfaces non-download open outcomes and missing remote IDs', (
    tester,
  ) async {
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-open-edge-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, localDirectory));
    final blockedFile = File(
      '${localDirectory.path}${Platform.pathSeparator}blocked.txt',
    )..writeAsStringSync('blocked');
    final missingRemoteFile = File(
      '${localDirectory.path}${Platform.pathSeparator}missing-remote.txt',
    )..writeAsStringSync('missing remote');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Open Edge Root',
      localPath: localDirectory.path,
      remoteId: 'open-edge-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      remoteId: 'open-edge-root-node',
      availability: FileAvailability.local,
      depth: 0,
    );
    final blockedNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'blocked.txt',
      localPath: blockedFile.path,
      relativePath: 'blocked.txt',
      remoteId: 'blocked-node',
      availability: FileAvailability.local,
    );
    final missingRemoteNode = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'missing-remote.txt',
      localPath: missingRemoteFile.path,
      relativePath: 'missing-remote.txt',
      remoteId: null,
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, blockedNode, missingRemoteNode],
    );
    final interactionService = ScriptedOpenInteractionService(
      repository,
      resultForNode: (node) => node.id == blockedNode.id
          ? FileNodeOpenResult(
              opened: false,
              action: 'needs_upload_or_relink',
              localIdentity: const <String, Object?>{},
              message: 'Local copy needs relinking',
            )
          : FileNodeOpenResult(
              opened: false,
              action: 'download_then_open',
              localIdentity: const <String, Object?>{},
              message: 'Download required but metadata is incomplete',
            ),
    );
    final contextApi = FakeFileContextApi();

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      contextApi: contextApi,
      interactionService: interactionService,
    );
    await pumpFileContextUntilFound(tester, find.text('blocked.txt'));

    await _tapNodeOpenButton(tester, 'blocked.txt');
    await pumpFileContextUntilFound(
      tester,
      find.textContaining('Local copy needs relinking'),
      maxPumps: 20,
    );

    expect(interactionService.openPlanNodes, [blockedNode.id]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(contextApi.downloadRequests, isEmpty);

    await _tapNodeOpenButton(tester, 'missing-remote.txt');
    await pumpFileContextUntilFound(
      tester,
      find.textContaining('ID'),
      maxPumps: 20,
    );

    expect(interactionService.openPlanNodes,
        [blockedNode.id, missingRemoteNode.id]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(contextApi.downloadRequests, isEmpty);
  });

  testWidgets(
      'file page disables snapshot for missing roots and relocates from warning',
      (
    tester,
  ) async {
    final selectedDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-warning-relocate-',
    );
    addTearDown(() {
      if (selectedDirectory.existsSync()) {
        selectedDirectory.deleteSync(recursive: true);
      }
    });
    final missingPath =
        '${selectedDirectory.path}${Platform.pathSeparator}missing-root';
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Missing Root',
      localPath: missingPath,
      remoteId: 'missing-root',
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: missingPath,
      relativePath: '',
      remoteId: 'missing-root-node',
      availability: FileAvailability.missing,
      depth: 0,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode],
    );
    final picker = FakeFilePicker(directoryPath: selectedDirectory.path);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      filePicker: picker,
    );
    await tester.pump();

    final snapshotButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.history_toggle_off).first,
    );
    expect(snapshotButton.onPressed, isNull);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);

    final warning = find.ancestor(
      of: find.byIcon(Icons.warning_amber_outlined),
      matching: find.byType(Container),
    );
    await tester.tap(
      find.descendant(of: warning, matching: find.byType(TextButton)).first,
    );
    await tester.pump();
    await tester.pump();

    expect(picker.directoryRequests.single['initialDirectory'], missingPath);
    expect(repository.boundRootPaths.single['folderId'], root.id);
    expect(
        repository.boundRootPaths.single['localPath'], selectedDirectory.path);
  });

  testWidgets('file page keeps roots visible when delete fails', (
    tester,
  ) async {
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Protected Root',
      remoteId: 'protected-root',
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      relativePath: '',
      remoteId: 'protected-root-node',
      depth: 0,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode],
    )..deleteError = StateError('delete locked');

    await pumpFileContextPageHarness(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(FilledButton).last);
    await pumpFileContextUntilFound(
      tester,
      find.textContaining('delete locked'),
      maxPumps: 20,
    );

    expect(repository.deletedRootIds, isEmpty);
    expect(find.text('Protected Root'), findsWidgets);
  });

  testWidgets('file page reports preview save failures', (
    tester,
  ) async {
    final localDirectory = Directory.systemTemp.createTempSync(
      'flowplanv2-file-context-save-fail-',
    );
    addTearDown(() => _disposeWidgetAndDeleteTemp(tester, localDirectory));
    final noteFile = File(
      '${localDirectory.path}${Platform.pathSeparator}locked-note.txt',
    )..writeAsStringSync('locked draft');
    final root = fileFolderFixture(
      id: 1,
      provider: FileProviderKind.local,
      displayName: 'Save Failure Root',
      localPath: localDirectory.path,
      remoteId: null,
      availability: FileAvailability.local,
    );
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: localDirectory.path,
      relativePath: '',
      availability: FileAvailability.local,
      depth: 0,
    );
    final noteNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'locked-note.txt',
      localPath: noteFile.path,
      relativePath: 'locked-note.txt',
      mimeType: 'text/plain',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, noteNode],
    );
    final interactionService = FailingSavePreviewInteractionService(repository);

    await pumpFileContextPageHarness(
      tester,
      repository: repository,
      interactionService: interactionService,
    );
    await pumpFileContextUntilFound(tester, find.text('locked-note.txt'));

    await _tapNodeTile(tester, 'locked-note.txt');
    await _pumpUntilEditableText(tester, 'locked draft');

    final editor = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && widget.controller.text == 'locked draft',
    );
    await tester.enterText(editor, 'new locked draft');
    await _pumpUntilEditableText(tester, 'new locked draft');

    final saveButton = find.byKey(AppKeys.fileContextSavePreviewButton);
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tapAt(tester.getCenter(saveButton));
    await pumpFileContextUntilFound(
      tester,
      find.textContaining('disk read only'),
      maxPumps: 20,
    );

    expect(interactionService.saveAttempts, ['new locked draft']);
    expect(repository.recordedNodeActions, contains('preview_file_node'));
  });

  testWidgets(
    'entity file context panel confirms and rejects recommendations and binds nodes',
    (tester) async {
      final alphaRoot = fileFolderFixture(
        id: 1,
        displayName: 'Alpha Launch Assets',
        localPath: r'C:\FlowPlanV2\Alpha',
        remoteId: 'alpha-root',
      );
      final archiveRoot = fileFolderFixture(
        id: 2,
        displayName: 'Archive Drafts',
        localPath: r'C:\FlowPlanV2\Archive',
        remoteId: 'archive-root',
      );
      final rootNode = fileNodeFixture(
        id: 10,
        rootFolderId: alphaRoot.id,
        itemType: FileNodeType.folder,
        displayName: alphaRoot.displayName,
        localPath: r'C:\FlowPlanV2\Alpha',
        relativePath: '',
        remoteId: 'alpha-root-node',
        availability: FileAvailability.local,
        depth: 0,
      );
      final briefNode = fileNodeFixture(
        id: 11,
        rootFolderId: alphaRoot.id,
        parentNodeId: rootNode.id,
        displayName: 'Alpha sprint brief.md',
        localPath: r'C:\FlowPlanV2\Alpha\Alpha sprint brief.md',
        relativePath: 'Alpha sprint brief.md',
        remoteId: 'alpha-brief-node',
        availability: FileAvailability.local,
      );
      final repository = FakeFileContextRepository(
        roots: [alphaRoot, archiveRoot],
        nodes: [rootNode, briefNode],
        links: [
          fileContextLinkFixture(
            id: 1,
            entityType: FileContextEntityType.task,
            entityId: 'task-42',
            targetType: FileContextTargetType.folder,
            targetId: alphaRoot.id,
          ),
          fileContextLinkFixture(
            id: 2,
            entityType: FileContextEntityType.task,
            entityId: 'task-42',
            targetType: FileContextTargetType.folder,
            targetId: archiveRoot.id,
            reason: 'Weak historical match',
          ),
        ],
      );

      await _pumpRecommendationDecisionSeam(tester, repository: repository);
      await tester.pump();

      expect(find.text('Alpha Launch Assets'), findsOneWidget);
      expect(find.text('Archive Drafts'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_circle_outline).first);
      await tester.pump();
      await tester.pump();

      expect(repository.confirmedLinkIds, [1]);
      expect(
        repository.links.singleWhere((link) => link.id == 1).status,
        FileContextStatus.confirmed,
      );

      await tester.tap(find.byKey(const Key('reject-archive-recommendation')));
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh).first);
      await tester.pump();
      await tester.pump();

      expect(repository.rejectedLinkIds, [2]);
      expect(find.text('Archive Drafts'), findsNothing);

      await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
      await tester.pump();
      await pumpFileContextUntilFound(
        tester,
        find.text('Alpha sprint brief.md'),
      );

      final briefTile = find.ancestor(
        of: find.text('Alpha sprint brief.md'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: briefTile, matching: find.byType(TextButton)).first,
      );
      await tester.pump();
      await tester.pump();

      expect(repository.boundNodeIds, [briefNode.id]);
      expect(repository.recordedNodeActions, contains('bind_file_node'));
      expect(find.text('Alpha sprint brief.md'), findsOneWidget);
    },
  );
}

Future<void> _pumpRecommendationDecisionSeam(
  WidgetTester tester, {
  required FakeFileContextRepository repository,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  tester.view.physicalSize = const Size(900, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileContextRepositoryProvider.overrideWithValue(repository),
        fileContextApiProvider
            .overrideWith((ref) async => FakeFileContextApi()),
        fileCloudApiProvider.overrideWith((ref) async => FakeFileCloudApi()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: _RecommendationDecisionSeam(),
          ),
        ),
      ),
    ),
  );
}

class _RecommendationDecisionSeam extends ConsumerWidget {
  const _RecommendationDecisionSeam();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const EntityFileContextPanel(
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          title: 'Alpha launch brief',
          description: 'Prepare sprint launch assets',
        ),
        TextButton(
          key: const Key('reject-archive-recommendation'),
          onPressed: () async {
            await ref.read(fileContextRepositoryProvider).rejectLink(2);
          },
          child: const Text('Reject Archive Drafts'),
        ),
      ],
    );
  }
}

List<String> _editableTexts(WidgetTester tester) {
  return tester
      .widgetList<EditableText>(find.byType(EditableText))
      .map((widget) => widget.controller.text)
      .toList(growable: false);
}

Future<void> _pumpUntilEditableText(
  WidgetTester tester,
  String text, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (_editableTexts(tester).contains(text)) {
      return;
    }
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.last, const Offset(0, -160));
      await tester.pump();
    }
  }
  fail('Timed out waiting for editable text "$text".');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for widget condition.');
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

Future<void> _tapNodeTile(
  WidgetTester tester,
  String nodeName,
) async {
  final tile = find
      .ancestor(
        of: find.text(nodeName).first,
        matching: find.byType(ListTile),
      )
      .first;
  final rect = tester.getRect(tile);
  await tester.tapAt(Offset(rect.left + 96, rect.center.dy));
  await tester.pump();
}

Future<void> _tapNodeOpenButton(
  WidgetTester tester,
  String nodeName,
) async {
  final tile = find.ancestor(
    of: find.text(nodeName).first,
    matching: find.byType(ListTile),
  );
  await tester.tap(
    find.descendant(
      of: tile,
      matching: find.widgetWithIcon(IconButton, Icons.open_in_new),
    ),
  );
}

Future<void> _tapDialogDownloadConfirm(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
}

Future<void> _tapFirstEnabledSnapshotButton(WidgetTester tester) async {
  final buttons = find.widgetWithIcon(IconButton, Icons.history_toggle_off);
  for (final element in buttons.evaluate()) {
    final widget = element.widget as IconButton;
    if (widget.onPressed == null) {
      continue;
    }
    await tester.tap(find.byWidget(widget));
    return;
  }
  throw StateError('No enabled snapshot button found.');
}

Future<void> _tapFirstIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump();
}

class ForcedDownloadInteractionService extends FileContextInteractionService {
  ForcedDownloadInteractionService(FakeFileContextRepository repository)
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
      openPlan: <String, dynamic>{
        'action': 'download_then_open',
        'message': 'Server copy requires a download',
      },
      message: 'Server copy requires a download',
    );
  }
}

class ScriptedOpenInteractionService extends FileContextInteractionService {
  ScriptedOpenInteractionService(
    FakeFileContextRepository repository, {
    required this.resultForNode,
  }) : super(repository: repository);

  final FileNodeOpenResult Function(FileNode node) resultForNode;
  final openPlanNodes = <int>[];

  @override
  Future<FileNodeOpenResult> openNodeWithPlan(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    openPlanNodes.add(node.id);
    return resultForNode(node);
  }
}

class RecordingPreviewInteractionService extends FileContextInteractionService {
  RecordingPreviewInteractionService(this.repository)
      : super(repository: repository);

  final FakeFileContextRepository repository;
  final savedTextByNodeId = <int, String>{};

  @override
  Future<FilePreviewResult> previewTextNode(FileNode node) async {
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

  @override
  Future<FilePreviewResult> saveTextNode(
    FileNode node,
    String content,
  ) async {
    savedTextByNodeId[node.id] = content;
    await repository.recordFileNodeOperation(
      node: node,
      action: 'save_file_node_text',
    );
    return FilePreviewResult(
      canPreview: true,
      displayName: node.displayName,
      content: content,
      message: null,
    );
  }
}

class FailingSavePreviewInteractionService
    extends RecordingPreviewInteractionService {
  FailingSavePreviewInteractionService(super.repository);

  final saveAttempts = <String>[];

  @override
  Future<FilePreviewResult> saveTextNode(
    FileNode node,
    String content,
  ) async {
    saveAttempts.add(content);
    throw StateError('disk read only');
  }
}

class RecordingFileTransferService extends FileTransferService {
  RecordingFileTransferService(AppDatabase db)
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
      id: 'recorded-download-${preparedDownloads.length}',
      direction: FileTransferDirection.download,
      fileName: 'downloaded remote copy',
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
