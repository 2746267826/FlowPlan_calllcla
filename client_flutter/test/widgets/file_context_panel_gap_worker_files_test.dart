import 'dart:async';

import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/presentation/file_context_panel.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';

void main() {
  testWidgets('panel shows loading, empty, and repository error states', (
    tester,
  ) async {
    final repository = _ScriptedPanelRepository()
      ..ensureCompleter = Completer<List<FileContextLink>>();

    await _pumpPanel(tester, repository: repository);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(repository.ensureRequests.single['title'], 'Alpha launch brief');
    expect(repository.ensureRequests.single['description'],
        'Prepare sprint launch assets');

    repository.ensureCompleter!.complete(const <FileContextLink>[]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.account_tree_outlined), findsNWidgets(2));
    expect(find.widgetWithIcon(IconButton, Icons.refresh), findsOneWidget);

    repository.ensureCompleter = Completer<List<FileContextLink>>();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
    await tester.pump();
    repository.ensureCompleter!.completeError(StateError('panel offline'));
    await tester.pump();

    expect(find.textContaining('panel offline'), findsOneWidget);
  });

  testWidgets('panel renders missing folder, node, and unknown link targets', (
    tester,
  ) async {
    final repository = FakeFileContextRepository(
      links: [
        fileContextLinkFixture(
          id: 1,
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          targetType: FileContextTargetType.folder,
          targetId: 404,
        ),
        fileContextLinkFixture(
          id: 2,
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          targetType: FileContextTargetType.fileNode,
          targetId: 405,
        ),
        fileContextLinkFixture(
          id: 3,
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          targetType: 'unknown-target',
          targetId: 406,
        ),
      ],
    );

    await _pumpPanel(tester, repository: repository);
    await tester.pump();

    expect(find.byIcon(Icons.report_problem_outlined), findsNWidgets(3));
    expect(find.text('${FileContextTargetType.folder} #404'), findsOneWidget);
    expect(
      find.text('${FileContextTargetType.fileNode} #405'),
      findsOneWidget,
    );
    expect(find.text('unknown-target #406'), findsOneWidget);
  });

  testWidgets('folder links confirm, open, reveal, and long-press reveal', (
    tester,
  ) async {
    final folder = fileFolderFixture(
      id: 7,
      displayName: 'Alpha Launch Assets',
      localPath: r'C:\FlowPlanV2\Alpha',
      remoteId: 'alpha-root',
    );
    final repository = FakeFileContextRepository(
      roots: [folder],
      links: [
        fileContextLinkFixture(
          id: 1,
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          targetType: FileContextTargetType.folder,
          targetId: folder.id,
        ),
      ],
    );
    final interactionService = _RecordingInteractionService(repository);

    await _pumpPanel(
      tester,
      repository: repository,
      interactionService: interactionService,
    );
    await tester.pump();

    expect(find.text('Alpha Launch Assets'), findsOneWidget);
    expect(find.textContaining(r'C:\FlowPlanV2\Alpha'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline).first);
    await tester.pump();
    await tester.pump();

    expect(repository.confirmedLinkIds, [1]);
    expect(repository.links.single.status, FileContextStatus.confirmed);

    final folderTile = _tileForText('Alpha Launch Assets');
    await tester.tap(
      find.descendant(
        of: folderTile,
        matching: find.widgetWithIcon(IconButton, Icons.open_in_new),
      ),
    );
    await tester.tap(
      find.descendant(
        of: folderTile,
        matching: find.widgetWithIcon(
          IconButton,
          Icons.drive_file_move_outline,
        ),
      ),
    );
    await tester.longPress(folderTile);

    expect(interactionService.folderOpens, [folder.id]);
    expect(interactionService.folderReveals, [folder.id, folder.id]);
    expect(
      interactionService.lastFolderEntity,
      {'entityType': FileContextEntityType.task, 'entityId': 'task-42'},
    );
  });

  testWidgets(
      'node links confirm, invoke local actions, and disable remote-only actions',
      (
    tester,
  ) async {
    final root = fileFolderFixture(id: 1, displayName: 'Node Root');
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: 'Node Root',
      relativePath: '',
      depth: 0,
    );
    final localFile = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Alpha sprint brief.md',
      localPath: r'C:\FlowPlanV2\Alpha\Alpha sprint brief.md',
      relativePath: 'Alpha sprint brief.md',
      availability: FileAvailability.local,
    );
    final remoteOnlyFile = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      displayName: 'Server only brief.md',
      localPath: '',
      relativePath: 'Server only brief.md',
      remoteId: 'server-only-brief',
      availability: FileAvailability.remoteOnly,
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, localFile, remoteOnlyFile],
      links: [
        fileContextLinkFixture(
          id: 1,
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          targetType: FileContextTargetType.fileNode,
          targetId: localFile.id,
        ),
        fileContextLinkFixture(
          id: 2,
          entityType: FileContextEntityType.task,
          entityId: 'task-42',
          targetType: FileContextTargetType.fileNode,
          targetId: remoteOnlyFile.id,
          status: FileContextStatus.confirmed,
        ),
      ],
    );
    final interactionService = _RecordingInteractionService(repository);

    await _pumpPanel(
      tester,
      repository: repository,
      interactionService: interactionService,
    );
    await tester.pump();

    expect(find.text('Alpha sprint brief.md'), findsOneWidget);
    expect(find.text('Server only brief.md'), findsOneWidget);

    final remoteTile = _tileForText('Server only brief.md');
    final remoteOpen = tester.widget<IconButton>(
      find.descendant(
        of: remoteTile,
        matching: find.widgetWithIcon(IconButton, Icons.open_in_new),
      ),
    );
    final remoteReveal = tester.widget<IconButton>(
      find.descendant(
        of: remoteTile,
        matching: find.widgetWithIcon(
          IconButton,
          Icons.drive_file_move_outline,
        ),
      ),
    );
    expect(remoteOpen.onPressed, isNull);
    expect(remoteReveal.onPressed, isNull);

    final localTile = _tileForText('Alpha sprint brief.md');
    await tester.tap(
      find.descendant(
        of: localTile,
        matching: find.widgetWithIcon(IconButton, Icons.check_circle_outline),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(repository.confirmedLinkIds, [1]);

    await tester.tap(
      find.descendant(
        of: localTile,
        matching: find.widgetWithIcon(IconButton, Icons.open_in_new),
      ),
    );
    await tester.tap(
      find.descendant(
        of: localTile,
        matching: find.widgetWithIcon(
          IconButton,
          Icons.drive_file_move_outline,
        ),
      ),
    );

    expect(interactionService.nodeOpens, [localFile.id]);
    expect(interactionService.nodeReveals, [localFile.id]);
    expect(
      interactionService.lastNodeEntity,
      {'entityType': FileContextEntityType.task, 'entityId': 'task-42'},
    );
  });

  testWidgets(
      'picker handles empty roots, node load errors, navigation, search, and cancel',
      (
    tester,
  ) async {
    final emptyRepository = FakeFileContextRepository()
      ..listFoldersCompleter = Completer<List<FileFolder>>();

    await _pumpPanel(tester, repository: emptyRepository);
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    emptyRepository.listFoldersCompleter!.complete(const <FileFolder>[]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Center), findsWidgets);
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    final root = fileFolderFixture(id: 1, displayName: 'Alpha Root');
    final rootNode = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      itemType: FileNodeType.folder,
      displayName: 'Alpha Root',
      relativePath: '',
      depth: 0,
    );
    final designFolder = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      parentNodeId: rootNode.id,
      itemType: FileNodeType.folder,
      displayName: 'Design',
      relativePath: 'Design',
    );
    final brief = fileNodeFixture(
      id: 12,
      rootFolderId: root.id,
      parentNodeId: designFolder.id,
      displayName: 'Brief.md',
      relativePath: 'Design/Brief.md',
    );
    final repository = FakeFileContextRepository(
      roots: [root],
      nodes: [rootNode, designFolder, brief],
    );

    await _pumpPanel(tester, repository: repository);
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Design'));

    final disabledUp = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward),
    );
    expect(disabledUp.onPressed, isNull);

    await tester.tap(_tileForText('Design').last);
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Brief.md'));

    final enabledUp = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward),
    );
    expect(enabledUp.onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Design'));

    await tester.enterText(find.byType(TextField).first, 'Brief');
    await tester.pump();
    await pumpFileContextUntilFound(tester, find.text('Brief.md'));

    expect(repository.searchRequests.single['rootFolderId'], root.id);
    expect(repository.searchRequests.single['query'], 'Brief');

    repository.listChildNodesError = StateError('tree offline');
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await pumpFileContextUntilFound(
        tester, find.textContaining('tree offline'));

    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.boundNodeIds, isEmpty);
  });
}

Finder _tileForText(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byType(ListTile),
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required FakeFileContextRepository repository,
  FileContextInteractionService? interactionService,
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
        if (interactionService != null)
          fileContextInteractionServiceProvider
              .overrideWithValue(interactionService),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: EntityFileContextPanel(
              entityType: FileContextEntityType.task,
              entityId: 'task-42',
              title: 'Alpha launch brief',
              description: 'Prepare sprint launch assets',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _ScriptedPanelRepository extends FakeFileContextRepository {
  Object? ensureError;
  Completer<List<FileContextLink>>? ensureCompleter;
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
    final error = ensureError;
    if (error != null) {
      throw error;
    }
    final completer = ensureCompleter;
    if (completer != null && !completer.isCompleted) {
      return completer.future;
    }
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

class _RecordingInteractionService extends FileContextInteractionService {
  _RecordingInteractionService(FakeFileContextRepository repository)
      : super(repository: repository);

  final folderOpens = <int>[];
  final folderReveals = <int>[];
  final nodeOpens = <int>[];
  final nodeReveals = <int>[];
  Map<String, String?> lastFolderEntity = const <String, String?>{};
  Map<String, String?> lastNodeEntity = const <String, String?>{};

  @override
  Future<bool> openFolder(
    FileFolder folder, {
    String? entityType,
    String? entityId,
  }) async {
    folderOpens.add(folder.id);
    lastFolderEntity = {'entityType': entityType, 'entityId': entityId};
    return true;
  }

  @override
  Future<bool> revealFolder(
    FileFolder folder, {
    String? entityType,
    String? entityId,
  }) async {
    folderReveals.add(folder.id);
    lastFolderEntity = {'entityType': entityType, 'entityId': entityId};
    return true;
  }

  @override
  Future<bool> openNode(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    nodeOpens.add(node.id);
    lastNodeEntity = {'entityType': entityType, 'entityId': entityId};
    return true;
  }

  @override
  Future<bool> revealNode(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    nodeReveals.add(node.id);
    lastNodeEntity = {'entityType': entityType, 'entityId': entityId};
    return true;
  }
}
