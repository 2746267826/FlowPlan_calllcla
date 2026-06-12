import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/file_context_page_harness.dart';

void main() {
  testWidgets('entity file context panel renders empty state actions', (
    tester,
  ) async {
    final repository = FakeFileContextRepository();

    await pumpEntityFileContextPanelHarness(tester, repository: repository);
    await tester.pump();

    expect(find.byIcon(Icons.account_tree_outlined), findsNWidgets(2));
    expect(find.widgetWithIcon(IconButton, Icons.refresh), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.listFoldersCalls, 1);
  });

  testWidgets(
      'entity file context panel refreshes recommendations and confirms one', (
    tester,
  ) async {
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Alpha Launch Assets',
      localPath: r'C:\FlowPlanV2\Alpha',
      remoteId: 'alpha-root',
    );
    final repository = FakeFileContextRepository(roots: [root]);

    await pumpEntityFileContextPanelHarness(tester, repository: repository);
    await tester.pump();

    expect(find.text('Alpha Launch Assets'), findsNothing);

    repository.recommendationFolderIds.add(root.id);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
    await tester.pump();
    await pumpFileContextUntilFound(
      tester,
      find.text('Alpha Launch Assets'),
    );

    expect(find.text('Alpha Launch Assets'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline).first);
    await tester.pump();
    await tester.pump();

    expect(repository.confirmedLinkIds, [1]);
    expect(repository.links.single.status, FileContextStatus.confirmed);
  });

  testWidgets(
      'entity file context panel selects a root, searches, and binds a node', (
    tester,
  ) async {
    final archiveRoot = fileFolderFixture(
      id: 1,
      displayName: 'Archive Root',
      remoteId: 'archive-root',
    );
    final alphaRoot = fileFolderFixture(
      id: 2,
      displayName: 'Alpha Root',
      localPath: r'C:\FlowPlanV2\Alpha',
      remoteId: 'alpha-root',
    );
    final archiveRootNode = fileNodeFixture(
      id: 10,
      rootFolderId: archiveRoot.id,
      itemType: FileNodeType.folder,
      displayName: archiveRoot.displayName,
      relativePath: '',
      remoteId: 'archive-root-node',
      depth: 0,
    );
    final alphaRootNode = fileNodeFixture(
      id: 20,
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
      id: 21,
      rootFolderId: alphaRoot.id,
      parentNodeId: alphaRootNode.id,
      displayName: 'Alpha sprint brief.md',
      localPath: r'C:\FlowPlanV2\Alpha\Alpha sprint brief.md',
      relativePath: 'Alpha sprint brief.md',
      remoteId: 'alpha-brief-node',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(
      roots: [archiveRoot, alphaRoot],
      nodes: [archiveRootNode, alphaRootNode, briefNode],
    );

    await pumpEntityFileContextPanelHarness(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pump();
    await tester.tap(find.text('Alpha Root').last);
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'brief');
    await tester.pump();
    await pumpFileContextUntilFound(
      tester,
      find.text('Alpha sprint brief.md'),
    );

    expect(repository.searchRequests.last, containsPair('rootFolderId', 2));
    expect(repository.searchRequests.last, containsPair('query', 'brief'));

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
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Alpha sprint brief.md'), findsOneWidget);
  });
}
