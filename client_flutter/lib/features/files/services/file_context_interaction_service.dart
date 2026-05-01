import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/platform/desktop_shell_service.dart';
import '../../../core/server_api/file_context_api.dart';
import '../data/file_context_repository.dart';
import 'local_file_identity_service.dart';

class FilePreviewResult {
  const FilePreviewResult({
    required this.canPreview,
    required this.displayName,
    required this.content,
    required this.message,
  });

  final bool canPreview;
  final String displayName;
  final String? content;
  final String? message;
}

class FileNodeOpenResult {
  const FileNodeOpenResult({
    required this.opened,
    required this.action,
    required this.localIdentity,
    this.openPlan,
    this.localPath,
    this.message,
  });

  final bool opened;
  final String action;
  final Map<String, Object?> localIdentity;
  final Map<String, dynamic>? openPlan;
  final String? localPath;
  final String? message;

  bool get needsDownload =>
      action == 'download_then_open' ||
      action == 'conflict_or_download_required';
}

class FileContextInteractionService {
  FileContextInteractionService({
    required FileContextRepository repository,
    Future<FileContextApi> Function()? apiLoader,
    DesktopShellService shellService = const DesktopShellService(),
    LocalFileIdentityService identityService =
        const LocalFileIdentityService(),
  })  : _repository = repository,
        _apiLoader = apiLoader,
        _shellService = shellService,
        _identityService = identityService;

  final FileContextRepository _repository;
  final Future<FileContextApi> Function()? _apiLoader;
  final DesktopShellService _shellService;
  final LocalFileIdentityService _identityService;

  Future<bool> openFolder(
    FileFolder folder, {
    String? entityType,
    String? entityId,
  }) async {
    final path = folder.localPath;
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    await _repository.recordFolderUsage(
      folderId: folder.id,
      action: 'open',
      entityType: entityType,
      entityId: entityId,
      metadata: <String, Object?>{'path': path},
    );
    return _shellService.openPath(path);
  }

  Future<bool> revealFolder(
    FileFolder folder, {
    String? entityType,
    String? entityId,
  }) async {
    final path = folder.localPath;
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    await _repository.recordFolderUsage(
      folderId: folder.id,
      action: 'reveal',
      entityType: entityType,
      entityId: entityId,
      metadata: <String, Object?>{'path': path},
    );
    return _shellService.revealPath(path);
  }

  Future<FilePreviewResult> previewTextFile(FileItem file) async {
    final path = file.localPath;
    if (path == null || path.trim().isEmpty) {
      return FilePreviewResult(
        canPreview: false,
        displayName: file.displayName,
        content: null,
        message: '文件没有可用的本地路径。',
      );
    }
    final previewable = _isTextPreviewable(path, file.mimeType);
    if (!previewable) {
      return FilePreviewResult(
        canPreview: false,
        displayName: file.displayName,
        content: null,
        message: '当前文件类型暂不支持内置预览。',
      );
    }
    final localFile = File(path);
    if (!localFile.existsSync()) {
      return FilePreviewResult(
        canPreview: false,
        displayName: file.displayName,
        content: null,
        message: '文件不在本地，后续 P9 会提供下载确认流程。',
      );
    }
    final bytes = await localFile.openRead(0, 128 * 1024).fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return FilePreviewResult(
      canPreview: true,
      displayName: file.displayName,
      content: utf8.decode(bytes, allowMalformed: true),
      message: null,
    );
  }

  Future<FilePreviewResult> previewTextNode(FileNode node) async {
    if (!node.isFile) {
      return FilePreviewResult(
        canPreview: false,
        displayName: node.displayName,
        content: null,
        message: '请选择文件进行预览。',
      );
    }
    await _repository.recordFileNodeOperation(
      node: node,
      action: 'preview_file_node',
    );
    final path = node.localPath;
    final previewable = _isTextPreviewable(path, node.mimeType);
    if (!previewable) {
      return FilePreviewResult(
        canPreview: false,
        displayName: node.displayName,
        content: null,
        message: '当前文件类型暂不支持文本预览。',
      );
    }
    final localFile = File(path);
    if (!localFile.existsSync()) {
      return FilePreviewResult(
        canPreview: false,
        displayName: node.displayName,
        content: null,
        message: '文件路径失效，请重新定位资料库后再试。',
      );
    }
    final bytes = await localFile.openRead(0, 128 * 1024).fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return FilePreviewResult(
      canPreview: true,
      displayName: node.displayName,
      content: utf8.decode(bytes, allowMalformed: true),
      message: null,
    );
  }

  Future<bool> openFile(FileItem file) async {
    final path = file.localPath;
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    return _shellService.openPath(path);
  }

  Future<bool> openNode(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    final result = await openNodeWithPlan(
      node,
      entityType: entityType,
      entityId: entityId,
    );
    return result.opened;
  }

  Future<FileNodeOpenResult> openNodeWithPlan(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    final localIdentity = await _localIdentityForNode(node);
    final localPath = localIdentity['localPath']?.toString();
    final apiLoader = _apiLoader;
    Map<String, dynamic>? openPlan;
    if (apiLoader != null && node.remoteId != null) {
      try {
        final api = await apiLoader();
        final plan = await api.openPlan(
          nodeId: node.remoteId!,
          localIdentity: localIdentity,
        );
        openPlan = plan;
        if (plan['action'] != 'open_local') {
          final action = plan['action']?.toString() ?? 'unknown';
          await _repository.recordFileNodeOperation(
            node: node,
            action: 'open_file_node_requires_download',
            entityType: entityType,
            entityId: entityId,
            metadata: <String, Object?>{
              'openPlan': plan,
            },
          );
          return FileNodeOpenResult(
            opened: false,
            action: action,
            localIdentity: localIdentity,
            openPlan: plan,
            localPath: localPath,
            message: _messageForOpenAction(action, plan),
          );
        }
        if (localPath != null && localPath.trim().isNotEmpty) {
          await api.upsertDeviceLocation(
            nodeId: node.remoteId!,
            localPath: localPath,
            metadata: <String, Object?>{
              'source': 'open_node_hash_match',
              'identity': localIdentity,
            },
          );
        }
      } catch (_) {
        // Local open remains available when the server cannot prepare a plan.
      }
    }
    if (localPath == null || localPath.trim().isEmpty) {
      await _repository.recordFileNodeOperation(
        node: node,
        action: 'open_file_node_missing_local_copy',
        entityType: entityType,
        entityId: entityId,
        metadata: <String, Object?>{
          'availability': node.availability,
          'remoteId': node.remoteId,
          'storageObjectId': node.storageObjectId,
        },
      );
      return FileNodeOpenResult(
        opened: false,
        action: openPlan?['action']?.toString() ?? 'missing_local_copy',
        localIdentity: localIdentity,
        openPlan: openPlan,
        localPath: localPath,
        message: '文件没有可直接打开的本地副本。',
      );
    }
    await _repository.recordFileNodeOperation(
      node: node,
      action: 'open_file_node',
      entityType: entityType,
      entityId: entityId,
      metadata: <String, Object?>{
        'identity': localIdentity,
      },
    );
    final opened = await _shellService.openPath(localPath);
    return FileNodeOpenResult(
      opened: opened,
      action: opened ? 'open_local' : 'open_local_failed',
      localIdentity: localIdentity,
      openPlan: openPlan,
      localPath: localPath,
      message: opened ? null : '系统默认程序打开失败。',
    );
  }

  Future<bool> revealFile(FileItem file) async {
    final path = file.localPath;
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    return _shellService.revealPath(path);
  }

  Future<bool> revealNode(
    FileNode node, {
    String? entityType,
    String? entityId,
  }) async {
    final localIdentity = await _localIdentityForNode(node);
    final localPath = localIdentity['localPath']?.toString();
    if (localPath == null || localPath.trim().isEmpty) {
      await _repository.recordFileNodeOperation(
        node: node,
        action: 'reveal_file_node_missing_local_copy',
        entityType: entityType,
        entityId: entityId,
        metadata: <String, Object?>{
          'availability': node.availability,
          'remoteId': node.remoteId,
        },
      );
      return false;
    }
    await _repository.recordFileNodeOperation(
      node: node,
      action: 'reveal_file_node',
      entityType: entityType,
      entityId: entityId,
      metadata: <String, Object?>{
        'identity': localIdentity,
      },
    );
    return _shellService.revealPath(localPath);
  }

  Future<Map<String, Object?>> _localIdentityForNode(FileNode node) async {
    for (final candidate in await _localCandidatePaths(node)) {
      final identity = await _identityService.identify(candidate);
      if (identity == null) {
        continue;
      }
      return identity.toJson(storageObjectId: node.storageObjectId);
    }
    return <String, Object?>{
      if (node.storageObjectId != null) 'storageObjectId': node.storageObjectId,
    };
  }

  Future<List<String>> _localCandidatePaths(FileNode node) async {
    final paths = <String>[];
    final localPath = node.localPath.trim();
    if (localPath.isNotEmpty) {
      paths.add(localPath);
    }
    final root = await _repository.getFolderById(node.rootFolderId);
    final rootPath = root?.localPath?.trim();
    final relativePath = node.relativePath.trim();
    if (rootPath != null && rootPath.isNotEmpty && relativePath.isNotEmpty) {
      paths.add(p.joinAll(<String>[
        rootPath,
        ...relativePath.split('/').where((part) => part.trim().isNotEmpty),
      ]));
    }
    return paths.toSet().toList(growable: false);
  }

  String _messageForOpenAction(String action, Map<String, dynamic> plan) {
    switch (action) {
      case 'conflict_or_download_required':
        return '本地候选文件无法与服务端对象确认同一性，不能直接打开。可下载服务端副本，或重新定位正确文件。';
      case 'download_then_open':
        return '本设备没有可确认同一性的本地副本，需要下载后打开。';
      case 'needs_upload_or_relink':
        return '服务端没有可下载对象，或本地文件需要重新定位/上传后才能打开。';
      default:
        return plan['reason']?.toString() ?? '文件暂时不能直接打开。';
    }
  }

  Future<FilePreviewResult> saveTextFile(
    FileItem file,
    String content,
  ) async {
    final path = file.localPath;
    if (path == null || path.trim().isEmpty) {
      return FilePreviewResult(
        canPreview: false,
        displayName: file.displayName,
        content: null,
        message: '文件没有可用的本地路径。',
      );
    }
    if (!_isTextPreviewable(path, file.mimeType)) {
      return FilePreviewResult(
        canPreview: false,
        displayName: file.displayName,
        content: null,
        message: '当前文件类型不允许内置修改。',
      );
    }
    await File(path).writeAsString(content, encoding: utf8);
    return FilePreviewResult(
      canPreview: true,
      displayName: file.displayName,
      content: content,
      message: null,
    );
  }

  Future<FilePreviewResult> saveTextNode(
    FileNode node,
    String content,
  ) async {
    if (!node.isFile) {
      return FilePreviewResult(
        canPreview: false,
        displayName: node.displayName,
        content: null,
        message: '文件夹不能作为文本保存。',
      );
    }
    if (!_isTextPreviewable(node.localPath, node.mimeType)) {
      return FilePreviewResult(
        canPreview: false,
        displayName: node.displayName,
        content: null,
        message: '当前文件类型不允许内置修改。',
      );
    }
    await File(node.localPath).writeAsString(content, encoding: utf8);
    await _repository.recordFileNodeOperation(
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

  Future<FileVersionRecord> registerKopiaVersion({
    required FileItem file,
    required String snapshotId,
    required String objectPath,
    int? sizeBytes,
    DateTime? modifiedAt,
    String? checksum,
    String? note,
  }) {
    return _repository.addVersionRecord(
      fileId: file.id,
      provider: 'kopia',
      versionRef: snapshotId,
      displayName: objectPath,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      checksum: checksum,
      sourceBackend: 'kopia',
      note: note,
      metadata: <String, Object?>{
        'snapshotId': snapshotId,
        'objectPath': objectPath,
      },
    );
  }

  bool _isTextPreviewable(String path, String? mimeType) {
    if (mimeType?.startsWith('text/') == true) {
      return true;
    }
    final lower = path.toLowerCase();
    return lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.log');
  }
}
