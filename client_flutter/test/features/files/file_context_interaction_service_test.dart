import 'dart:io';

import 'package:flowplanv2/core/platform/desktop_shell_service.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/files/services/file_context_interaction_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/file_context_page_harness.dart';

void main() {
  test(
      'openNodeWithPlan opens a verified local copy and records device location',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-open-node-local-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final docsDir = Directory('${tempDir.path}${Platform.pathSeparator}docs')
      ..createSync();
    final file = File('${docsDir.path}${Platform.pathSeparator}brief.md')
      ..writeAsStringSync('open me');
    final root = fileFolderFixture(
      id: 1,
      displayName: 'Alpha Root',
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      remoteId: 'remote-node-10',
      displayName: 'brief.md',
      localPath: '',
      relativePath: 'docs/brief.md',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-10',
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final api = FakeFileContextApi(openPlanAction: 'open_local');
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isTrue);
    expect(result.action, 'open_local');
    expect(result.localPath, file.path);
    expect(shell.openedPaths, [file.path]);
    expect(api.openPlanNodeIds, ['remote-node-10']);
    expect(
      api.openPlanRequests.single['localIdentity'],
      containsPair('storageObjectId', 'storage-10'),
    );
    expect(api.deviceLocations.single['nodeId'], 'remote-node-10');
    expect(api.deviceLocations.single['localPath'], file.path);
    expect(repository.recordedNodeActions, ['open_file_node']);
  });

  test('openNodeWithPlan returns a download-required result without opening',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-open-node-conflict-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}brief.md')
      ..writeAsStringSync('local but stale');
    final root = fileFolderFixture(
      id: 1,
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      remoteId: 'remote-node-10',
      displayName: 'brief.md',
      localPath: file.path,
      relativePath: 'brief.md',
      availability: FileAvailability.conflict,
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final api = FakeFileContextApi(
      openPlanAction: 'conflict_or_download_required',
    );
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isFalse);
    expect(result.needsDownload, isTrue);
    expect(result.action, 'conflict_or_download_required');
    expect(result.message, isNotNull);
    expect(shell.openedPaths, isEmpty);
    expect(repository.recordedNodeActions, [
      'open_file_node_requires_download',
    ]);
    expect(
      repository.recordedNodeOperations.single['metadata'],
      containsPair('openPlan', containsPair('action', result.action)),
    );
  });

  test('openNodeWithPlan falls back to local open when open-plan API fails',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-open-node-api-fallback-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}brief.md')
      ..writeAsStringSync('local copy still opens');
    final root = fileFolderFixture(
      id: 1,
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      remoteId: 'remote-node-10',
      displayName: 'brief.md',
      localPath: file.path,
      relativePath: 'brief.md',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final api = FakeFileContextApi(throwOpenPlan: true);
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isTrue);
    expect(result.action, 'open_local');
    expect(shell.openedPaths, [file.path]);
    expect(api.deviceLocations, isEmpty);
    expect(repository.recordedNodeActions, ['open_file_node']);
  });

  test(
      'openNodeWithPlan reports shell open failures after recording the attempt',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-open-node-shell-fail-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}brief.md')
      ..writeAsStringSync('cannot open shell');
    final root = fileFolderFixture(
      id: 1,
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      displayName: 'brief.md',
      localPath: file.path,
      relativePath: 'brief.md',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final shell = RecordingDesktopShellService(openResult: false);
    final service = FileContextInteractionService(
      repository: repository,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isFalse);
    expect(result.action, 'open_local_failed');
    expect(result.message, isNotNull);
    expect(shell.openedPaths, [file.path]);
    expect(repository.recordedNodeActions, ['open_file_node']);
  });

  test('openNodeWithPlan records missing local copies with storage metadata',
      () async {
    final root = fileFolderFixture(id: 1, localPath: null);
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      remoteId: null,
      displayName: 'server-only.txt',
      localPath: '',
      relativePath: 'server-only.txt',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-only',
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isFalse);
    expect(result.action, 'missing_local_copy');
    expect(result.localIdentity, {'storageObjectId': 'storage-only'});
    expect(shell.openedPaths, isEmpty);
    expect(repository.recordedNodeActions, [
      'open_file_node_missing_local_copy',
    ]);
  });

  test('openNodeWithPlan keeps open-plan action when local copy is missing',
      () async {
    final root = fileFolderFixture(id: 1, localPath: null);
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      remoteId: 'remote-node-10',
      displayName: 'server-only.txt',
      localPath: '',
      relativePath: 'server-only.txt',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-only',
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final api = FakeFileContextApi(openPlanAction: 'open_local');
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isFalse);
    expect(result.action, 'open_local');
    expect(result.openPlan, containsPair('action', 'open_local'));
    expect(api.openPlanNodeIds, ['remote-node-10']);
    expect(shell.openedPaths, isEmpty);
    expect(repository.recordedNodeActions, [
      'open_file_node_missing_local_copy',
    ]);
  });

  test('openNodeWithPlan uses reason for unknown open-plan actions', () async {
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: 1,
      remoteId: 'remote-node-10',
      displayName: 'review-needed.txt',
      localPath: '',
      relativePath: 'review-needed.txt',
      availability: FileAvailability.remoteOnly,
    );
    final repository = FakeFileContextRepository(nodes: [node]);
    final api = FakeFileContextApi(
      openPlanFixture: <String, dynamic>{
        'action': 'wait_for_review',
        'reason': 'Manual approval is required before opening.',
      },
    );
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
      shellService: shell,
    );

    final result = await service.openNodeWithPlan(node);

    expect(result.opened, isFalse);
    expect(result.action, 'wait_for_review');
    expect(result.message, 'Manual approval is required before opening.');
    expect(shell.openedPaths, isEmpty);
    expect(repository.recordedNodeActions, [
      'open_file_node_requires_download',
    ]);
  });

  test(
      'previewTextNode reads a bounded text preview and saveTextNode writes it',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-preview-save-node-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}large.log');
    file.writeAsStringSync(
      '${List.filled(128 * 1024, 'a').join()}tail that is not previewed',
    );
    final root = fileFolderFixture(
      id: 1,
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      displayName: 'large.log',
      localPath: file.path,
      relativePath: 'large.log',
      mimeType: 'text/plain',
      availability: FileAvailability.local,
    );
    final repository = FakeFileContextRepository(roots: [root], nodes: [node]);
    final service = FileContextInteractionService(repository: repository);

    final preview = await service.previewTextNode(node);
    final saved = await service.saveTextNode(node, 'updated text');

    expect(preview.canPreview, isTrue);
    expect(preview.content, hasLength(128 * 1024));
    expect(preview.content, isNot(contains('tail that is not previewed')));
    expect(saved.canPreview, isTrue);
    expect(file.readAsStringSync(), 'updated text');
    expect(repository.recordedNodeActions, [
      'preview_file_node',
      'save_file_node_text',
    ]);
  });

  test('preview and save reject folders, binary files, and missing local paths',
      () async {
    final repository = FakeFileContextRepository();
    final service = FileContextInteractionService(repository: repository);
    final folder = fileNodeFixture(
      id: 1,
      rootFolderId: 1,
      itemType: FileNodeType.folder,
      displayName: 'Folder',
      relativePath: '',
    );
    final binary = fileNodeFixture(
      id: 2,
      rootFolderId: 1,
      displayName: 'archive.bin',
      localPath: 'archive.bin',
      relativePath: 'archive.bin',
      mimeType: 'application/octet-stream',
    );
    final missingText = fileNodeFixture(
      id: 3,
      rootFolderId: 1,
      displayName: 'missing.txt',
      localPath: 'missing.txt',
      relativePath: 'missing.txt',
      mimeType: 'text/plain',
    );

    final folderPreview = await service.previewTextNode(folder);
    final binaryPreview = await service.previewTextNode(binary);
    final missingPreview = await service.previewTextNode(missingText);
    final folderSave = await service.saveTextNode(folder, 'ignored');
    final binarySave = await service.saveTextNode(binary, 'ignored');

    expect(folderPreview.canPreview, isFalse);
    expect(binaryPreview.canPreview, isFalse);
    expect(missingPreview.canPreview, isFalse);
    expect(folderSave.canPreview, isFalse);
    expect(binarySave.canPreview, isFalse);
    expect(repository.recordedNodeActions, [
      'preview_file_node',
      'preview_file_node',
    ]);
  });

  test('folder open and reveal record usage before shell interaction',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-folder-interaction-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final folder = fileFolderFixture(
      id: 1,
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final missingPathFolder = fileFolderFixture(id: 2, localPath: ' ');
    final repository = FakeFileContextRepository(roots: [folder]);
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      shellService: shell,
    );

    final opened = await service.openFolder(
      folder,
      entityType: FileContextEntityType.task,
      entityId: 'task-folder',
    );
    final revealed = await service.revealFolder(
      folder,
      entityType: FileContextEntityType.report,
      entityId: 'report-folder',
    );
    final missingOpen = await service.openFolder(missingPathFolder);
    final missingReveal = await service.revealFolder(missingPathFolder);

    expect(opened, isTrue);
    expect(revealed, isTrue);
    expect(missingOpen, isFalse);
    expect(missingReveal, isFalse);
    expect(shell.openedPaths, [tempDir.path]);
    expect(shell.revealedPaths, [tempDir.path]);
    expect(repository.recordedFolderActions, ['open', 'reveal']);
    expect(
      repository.recordedFolderUsages.first,
      containsPair('entityId', 'task-folder'),
    );
    expect(
      repository.recordedFolderUsages.last['metadata'],
      containsPair('path', tempDir.path),
    );
  });

  test('file preview save open and reveal handle text and unsupported paths',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-file-interaction-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final markdown = File('${tempDir.path}${Platform.pathSeparator}brief.md')
      ..writeAsStringSync('# Brief');
    final binary = File('${tempDir.path}${Platform.pathSeparator}archive.bin')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final textItem = fileItemFixture(
      id: 1,
      displayName: 'brief.md',
      localPath: markdown.path,
      mimeType: 'text/markdown',
    );
    final binaryItem = fileItemFixture(
      id: 2,
      displayName: 'archive.bin',
      localPath: binary.path,
      mimeType: 'application/octet-stream',
    );
    final missingTextItem = fileItemFixture(
      id: 3,
      displayName: 'missing.txt',
      localPath: '${tempDir.path}${Platform.pathSeparator}missing.txt',
      mimeType: 'text/plain',
    );
    final noPathItem = fileItemFixture(
      id: 4,
      displayName: 'no-path.md',
      localPath: null,
      mimeType: 'text/markdown',
    );
    final repository = FakeFileContextRepository();
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      shellService: shell,
    );

    final preview = await service.previewTextFile(textItem);
    final saved = await service.saveTextFile(textItem, 'updated text');
    final opened = await service.openFile(textItem);
    final revealed = await service.revealFile(textItem);
    final binaryPreview = await service.previewTextFile(binaryItem);
    final missingPreview = await service.previewTextFile(missingTextItem);
    final noPathPreview = await service.previewTextFile(noPathItem);
    final binarySave = await service.saveTextFile(binaryItem, 'ignored');
    final noPathSave = await service.saveTextFile(noPathItem, 'ignored');
    final noPathOpen = await service.openFile(noPathItem);
    final noPathReveal = await service.revealFile(noPathItem);

    expect(preview.canPreview, isTrue);
    expect(preview.content, '# Brief');
    expect(saved.canPreview, isTrue);
    expect(markdown.readAsStringSync(), 'updated text');
    expect(opened, isTrue);
    expect(revealed, isTrue);
    expect(binaryPreview.canPreview, isFalse);
    expect(missingPreview.canPreview, isFalse);
    expect(noPathPreview.canPreview, isFalse);
    expect(binarySave.canPreview, isFalse);
    expect(noPathSave.canPreview, isFalse);
    expect(noPathOpen, isFalse);
    expect(noPathReveal, isFalse);
    expect(shell.openedPaths, [markdown.path]);
    expect(shell.revealedPaths, [markdown.path]);
  });

  test(
      'revealNode resolves root-relative candidates and records missing copies',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'flowplanv2-reveal-node-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final docsDir = Directory('${tempDir.path}${Platform.pathSeparator}docs')
      ..createSync();
    final file = File('${docsDir.path}${Platform.pathSeparator}brief.txt')
      ..writeAsStringSync('reveal me');
    final root = fileFolderFixture(
      id: 1,
      localPath: tempDir.path,
      availability: FileAvailability.local,
    );
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: root.id,
      remoteId: 'remote-node-10',
      displayName: 'brief.txt',
      localPath: '',
      relativePath: 'docs/brief.txt',
      availability: FileAvailability.remoteOnly,
    );
    final missingNode = fileNodeFixture(
      id: 11,
      rootFolderId: root.id,
      remoteId: 'remote-node-11',
      displayName: 'server-only.txt',
      localPath: '',
      relativePath: 'server-only.txt',
      availability: FileAvailability.remoteOnly,
      storageObjectId: 'storage-11',
    );
    final repository = FakeFileContextRepository(roots: [root]);
    final shell = RecordingDesktopShellService();
    final service = FileContextInteractionService(
      repository: repository,
      shellService: shell,
    );

    final revealed = await service.revealNode(
      node,
      entityType: FileContextEntityType.task,
      entityId: 'task-reveal',
    );
    final missingReveal = await service.revealNode(missingNode);

    expect(revealed, isTrue);
    expect(missingReveal, isFalse);
    expect(shell.revealedPaths, [file.path]);
    expect(repository.recordedNodeActions, [
      'reveal_file_node',
      'reveal_file_node_missing_local_copy',
    ]);
    expect(
      repository.recordedNodeOperations.first['metadata'],
      containsPair('identity', containsPair('localPath', file.path)),
    );
    expect(
      repository.recordedNodeOperations.last['metadata'],
      containsPair('remoteId', 'remote-node-11'),
    );
  });

  test('openNode forwards the open-plan opened flag and download message',
      () async {
    final node = fileNodeFixture(
      id: 10,
      rootFolderId: 1,
      remoteId: 'remote-node-10',
      displayName: 'download-me.txt',
      localPath: '',
      relativePath: 'download-me.txt',
      availability: FileAvailability.remoteOnly,
    );
    final repository = FakeFileContextRepository();
    final api = FakeFileContextApi(openPlanAction: 'download_then_open');
    final service = FileContextInteractionService(
      repository: repository,
      apiLoader: () async => api,
    );

    final opened = await service.openNode(node);
    final planned = await service.openNodeWithPlan(
      node,
      entityType: FileContextEntityType.task,
      entityId: 'task-download',
    );

    expect(opened, isFalse);
    expect(planned.needsDownload, isTrue);
    expect(planned.action, 'download_then_open');
    expect(planned.message, isNotNull);
    expect(api.openPlanNodeIds, ['remote-node-10', 'remote-node-10']);
    expect(repository.recordedNodeActions, [
      'open_file_node_requires_download',
      'open_file_node_requires_download',
    ]);
  });

  test('registerKopiaVersion delegates provider metadata to repository',
      () async {
    final file = fileItemFixture(
      id: 7,
      displayName: 'brief.md',
      localPath: r'C:\FlowPlanV2\brief.md',
    );
    final repository = FakeFileContextRepository();
    final service = FileContextInteractionService(repository: repository);
    final modifiedAt = DateTime.utc(2026, 6, 10, 9);

    final version = await service.registerKopiaVersion(
      file: file,
      snapshotId: 'snapshot-123',
      objectPath: 'kopia/brief.md',
      sizeBytes: 321,
      modifiedAt: modifiedAt,
      checksum: 'checksum-123',
      note: 'manual snapshot',
    );

    expect(version.fileId, file.id);
    expect(version.provider, 'kopia');
    expect(version.sourceBackend, 'kopia');
    expect(repository.addedVersionRecords.single, {
      'fileId': 7,
      'versionRef': 'snapshot-123',
      'displayName': 'kopia/brief.md',
      'provider': 'kopia',
      'sizeBytes': 321,
      'modifiedAt': modifiedAt,
      'checksum': 'checksum-123',
      'sourceDevice': null,
      'sourceBackend': 'kopia',
      'note': 'manual snapshot',
      'metadata': <String, Object?>{
        'snapshotId': 'snapshot-123',
        'objectPath': 'kopia/brief.md',
      },
    });
  });
}

FileItem fileItemFixture({
  required int id,
  String fileUid = 'file-1',
  String provider = FileProviderKind.local,
  String displayName = 'brief.md',
  int? folderId,
  String? localPath,
  String? remoteId,
  String? mimeType = 'text/markdown',
  int? sizeBytes = 128,
  DateTime? modifiedAt,
  String availability = FileAvailability.local,
  String previewMode = 'text',
  String metadataJson = '{}',
}) {
  return FileItem(
    id: id,
    fileUid: fileUid,
    provider: provider,
    displayName: displayName,
    folderId: folderId,
    localPath: localPath,
    remoteId: remoteId,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    modifiedAt: modifiedAt ?? fileContextHarnessNow,
    availability: availability,
    previewMode: previewMode,
    metadataJson: metadataJson,
    createdAt: fileContextHarnessNow,
    updatedAt: fileContextHarnessNow,
  );
}

class RecordingDesktopShellService extends DesktopShellService {
  RecordingDesktopShellService({
    this.openResult = true,
    this.revealResult = true,
  });

  final bool openResult;
  final bool revealResult;
  final openedPaths = <String>[];
  final revealedPaths = <String>[];

  @override
  Future<bool> openPath(String path) async {
    openedPaths.add(path);
    return openResult;
  }

  @override
  Future<bool> revealPath(String path) async {
    revealedPaths.add(path);
    return revealResult;
  }
}
