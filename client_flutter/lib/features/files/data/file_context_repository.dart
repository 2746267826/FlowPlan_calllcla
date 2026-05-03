import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/server_api/file_context_api.dart';
import '../../../core/sync/sync_object_registry.dart';
import '../../../core/sync/sync_write_recorder.dart';
import '../../audit/data_operation_log_repository.dart';

class FileProviderKind {
  const FileProviderKind._();

  static const local = 'local';
  static const serverStorage = 'server_storage';
  static const oneDrive = 'onedrive';
}

class FileAvailability {
  const FileAvailability._();

  static const local = 'local';
  static const remoteOnly = 'remote_only';
  static const missing = 'missing';
  static const conflict = 'conflict';
}

class FileContextEntityType {
  const FileContextEntityType._();

  static const task = 'task';
  static const event = 'event';
  static const project = 'project';
  static const report = 'report';
  static const diary = 'diary';
}

class FileContextTargetType {
  const FileContextTargetType._();

  static const folder = 'folder';
  static const file = 'file';
  static const folderNode = 'folder_node';
  static const fileNode = 'file_node';
}

class FileContextRelationType {
  const FileContextRelationType._();

  static const manual = 'manual';
  static const recommended = 'recommended';
  static const recent = 'recent';
  static const historical = 'historical';
}

class FileContextStatus {
  const FileContextStatus._();

  static const candidate = 'candidate';
  static const confirmed = 'confirmed';
  static const rejected = 'rejected';
}

class FileFolder {
  const FileFolder({
    required this.id,
    required this.folderUid,
    required this.provider,
    required this.displayName,
    required this.localPath,
    required this.remoteId,
    required this.parentPath,
    required this.sourceContext,
    required this.pinned,
    required this.availability,
    required this.useCount,
    required this.lastUsedAt,
    required this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String folderUid;
  final String provider;
  final String displayName;
  final String? localPath;
  final String? remoteId;
  final String? parentPath;
  final String? sourceContext;
  final bool pinned;
  final String availability;
  final int useCount;
  final DateTime? lastUsedAt;
  final String metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'folderUid': folderUid,
        'provider': provider,
        'displayName': displayName,
        'localPath': localPath,
        'remoteId': remoteId,
        'parentPath': parentPath,
        'sourceContext': sourceContext,
        'pinned': pinned,
        'availability': availability,
        'useCount': useCount,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'metadataJson': metadataJson,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FileFolder.fromRow(QueryRow row) {
    return FileFolder(
      id: row.read<int>('id'),
      folderUid: row.read<String>('folder_uid'),
      provider: row.read<String>('provider'),
      displayName: row.read<String>('display_name'),
      localPath: row.data['local_path'] as String?,
      remoteId: row.data['remote_id'] as String?,
      parentPath: row.data['parent_path'] as String?,
      sourceContext: row.data['source_context'] as String?,
      pinned: row.read<int>('pinned') == 1,
      availability: row.read<String>('availability'),
      useCount: row.read<int>('use_count'),
      lastUsedAt: _date(row.data['last_used_at']),
      metadataJson: row.read<String>('metadata_json'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class FileItem {
  const FileItem({
    required this.id,
    required this.fileUid,
    required this.provider,
    required this.displayName,
    required this.folderId,
    required this.localPath,
    required this.remoteId,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.availability,
    required this.previewMode,
    required this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String fileUid;
  final String provider;
  final String displayName;
  final int? folderId;
  final String? localPath;
  final String? remoteId;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String availability;
  final String previewMode;
  final String metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'fileUid': fileUid,
        'provider': provider,
        'displayName': displayName,
        'folderId': folderId,
        'localPath': localPath,
        'remoteId': remoteId,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt?.toIso8601String(),
        'availability': availability,
        'previewMode': previewMode,
        'metadataJson': metadataJson,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FileItem.fromRow(QueryRow row) {
    return FileItem(
      id: row.read<int>('id'),
      fileUid: row.read<String>('file_uid'),
      provider: row.read<String>('provider'),
      displayName: row.read<String>('display_name'),
      folderId: row.data['folder_id'] as int?,
      localPath: row.data['local_path'] as String?,
      remoteId: row.data['remote_id'] as String?,
      mimeType: row.data['mime_type'] as String?,
      sizeBytes: row.data['size_bytes'] as int?,
      modifiedAt: _date(row.data['modified_at']),
      availability: row.read<String>('availability'),
      previewMode: row.read<String>('preview_mode'),
      metadataJson: row.read<String>('metadata_json'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class FileNodeType {
  const FileNodeType._();

  static const folder = 'folder';
  static const file = 'file';
}

class FileNode {
  const FileNode({
    required this.id,
    required this.nodeUid,
    required this.remoteId,
    required this.rootFolderId,
    required this.parentNodeId,
    required this.itemType,
    required this.displayName,
    required this.localPath,
    required this.relativePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.availability,
    required this.scanBatchId,
    required this.depth,
    required this.hashSha256,
    required this.storageObjectId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String nodeUid;
  final String? remoteId;
  final int rootFolderId;
  final int? parentNodeId;
  final String itemType;
  final String displayName;
  final String localPath;
  final String relativePath;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String availability;
  final String scanBatchId;
  final int depth;
  final String? hashSha256;
  final String? storageObjectId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFolder => itemType == FileNodeType.folder;
  bool get isFile => itemType == FileNodeType.file;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'nodeUid': nodeUid,
        'remoteId': remoteId,
        'rootFolderId': rootFolderId,
        'parentNodeId': parentNodeId,
        'itemType': itemType,
        'displayName': displayName,
        'localPath': localPath,
        'relativePath': relativePath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt?.toIso8601String(),
        'availability': availability,
        'scanBatchId': scanBatchId,
        'depth': depth,
        'hashSha256': hashSha256,
        'storageObjectId': storageObjectId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FileNode.fromRow(QueryRow row) {
    return FileNode(
      id: row.read<int>('id'),
      nodeUid: row.read<String>('node_uid'),
      remoteId: row.data['remote_id'] as String?,
      rootFolderId: row.read<int>('root_folder_id'),
      parentNodeId: row.data['parent_node_id'] as int?,
      itemType: row.read<String>('item_type'),
      displayName: row.read<String>('display_name'),
      localPath: row.read<String>('local_path'),
      relativePath: row.read<String>('relative_path'),
      mimeType: row.data['mime_type'] as String?,
      sizeBytes: row.data['size_bytes'] as int?,
      modifiedAt: _date(row.data['modified_at']),
      availability: row.read<String>('availability'),
      scanBatchId: row.read<String>('scan_batch_id'),
      depth: row.read<int>('depth'),
      hashSha256: row.data['hash_sha256'] as String?,
      storageObjectId: row.data['storage_object_id'] as String?,
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class FileScanProgress {
  const FileScanProgress({
    required this.scannedCount,
    required this.currentPath,
    required this.done,
  });

  final int scannedCount;
  final String currentPath;
  final bool done;
}

class FileScanResult {
  const FileScanResult({
    required this.rootNode,
    required this.scannedCount,
    required this.truncated,
  });

  final FileNode rootNode;
  final int scannedCount;
  final bool truncated;
}

class FileContextLink {
  const FileContextLink({
    required this.id,
    required this.linkUid,
    required this.entityType,
    required this.entityId,
    required this.targetType,
    required this.targetId,
    required this.relationType,
    required this.confidence,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
  });

  final int id;
  final String linkUid;
  final String entityType;
  final String entityId;
  final String targetType;
  final int targetId;
  final String relationType;
  final double confidence;
  final String? reason;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'linkUid': linkUid,
        'entityType': entityType,
        'entityId': entityId,
        'targetType': targetType,
        'targetId': targetId,
        'relationType': relationType,
        'confidence': confidence,
        'reason': reason,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'confirmedAt': confirmedAt?.toIso8601String(),
      };

  factory FileContextLink.fromRow(QueryRow row) {
    return FileContextLink(
      id: row.read<int>('id'),
      linkUid: row.read<String>('link_uid'),
      entityType: row.read<String>('entity_type'),
      entityId: row.read<String>('entity_id'),
      targetType: row.read<String>('target_type'),
      targetId: row.read<int>('target_id'),
      relationType: row.read<String>('relation_type'),
      confidence: (row.data['confidence'] as num?)?.toDouble() ?? 0,
      reason: row.data['reason'] as String?,
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
      confirmedAt: _date(row.data['confirmed_at']),
    );
  }
}

class FileVersionRecord {
  const FileVersionRecord({
    required this.id,
    required this.versionUid,
    required this.fileId,
    required this.provider,
    required this.versionRef,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.checksum,
    required this.sourceDevice,
    required this.sourceBackend,
    required this.note,
    required this.metadataJson,
    required this.createdAt,
  });

  final int id;
  final String versionUid;
  final int fileId;
  final String provider;
  final String versionRef;
  final String displayName;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? checksum;
  final String? sourceDevice;
  final String? sourceBackend;
  final String? note;
  final String metadataJson;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'versionUid': versionUid,
        'fileId': fileId,
        'provider': provider,
        'versionRef': versionRef,
        'displayName': displayName,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt?.toIso8601String(),
        'checksum': checksum,
        'sourceDevice': sourceDevice,
        'sourceBackend': sourceBackend,
        'note': note,
        'metadataJson': metadataJson,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FileVersionRecord.fromRow(QueryRow row) {
    return FileVersionRecord(
      id: row.read<int>('id'),
      versionUid: row.read<String>('version_uid'),
      fileId: row.read<int>('file_id'),
      provider: row.read<String>('provider'),
      versionRef: row.read<String>('version_ref'),
      displayName: row.read<String>('display_name'),
      sizeBytes: row.data['size_bytes'] as int?,
      modifiedAt: _date(row.data['modified_at']),
      checksum: row.data['checksum'] as String?,
      sourceDevice: row.data['source_device'] as String?,
      sourceBackend: row.data['source_backend'] as String?,
      note: row.data['note'] as String?,
      metadataJson: row.read<String>('metadata_json'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
    );
  }
}

class FileFolderRecommendation {
  const FileFolderRecommendation({
    required this.folder,
    required this.score,
    required this.reason,
    required this.existingLink,
  });

  final FileFolder folder;
  final double score;
  final String reason;
  final FileContextLink? existingLink;
}

class FileContextRepository {
  FileContextRepository(
    this._db, [
    this._operationLogs,
    this._syncWriteRecorder,
    this._apiLoader,
  ]);

  final AppDatabase _db;
  final DataOperationLogRepository? _operationLogs;
  final SyncWriteRecorder? _syncWriteRecorder;
  final Future<FileContextApi> Function()? _apiLoader;
  final Uuid _uuid = const Uuid();

  Future<FileFolder> upsertLocalFolder({
    required String localPath,
    String? displayName,
    String? sourceContext,
    bool pinned = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final normalizedPath = _normalizePath(localPath);
    final existing = await getFolderByPath(normalizedPath);
    final now = DateTime.now();
    final parentPath = _parentPath(normalizedPath);
    final name = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : _displayNameFromPath(normalizedPath);
    final metadataJson = jsonEncode(metadata);

    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO file_folders (
          folder_uid,
          provider,
          display_name,
          local_path,
          parent_path,
          source_context,
          pinned,
          availability,
          metadata_json,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _uuid.v4(),
          FileProviderKind.local,
          name,
          normalizedPath,
          parentPath,
          sourceContext,
          pinned ? 1 : 0,
          Directory(normalizedPath).existsSync()
              ? FileAvailability.local
              : FileAvailability.missing,
          metadataJson,
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );
      final created = await _lastFolder();
      await _upsertRootToServer(created);
      await _recordFolderCreate(created);
      return (await getFolderById(created.id)) ?? created;
    }

    await _db.customStatement(
      '''
      UPDATE file_folders
      SET display_name = ?,
          parent_path = ?,
          source_context = COALESCE(?, source_context),
          pinned = CASE WHEN ? = 1 THEN 1 ELSE pinned END,
          availability = ?,
          metadata_json = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        name,
        parentPath,
        sourceContext,
        pinned ? 1 : 0,
        Directory(normalizedPath).existsSync()
            ? FileAvailability.local
            : FileAvailability.missing,
        metadataJson,
        now.toIso8601String(),
        existing.id,
      ],
    );
    final updated = await getFolderById(existing.id);
    if (updated == null) {
      throw StateError('Folder update failed.');
    }
    await _upsertRootToServer(updated);
    await _recordFolderUpdate(updated);
    return (await getFolderById(updated.id)) ?? updated;
  }

  Future<FileFolder?> getFolderById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM file_folders WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : FileFolder.fromRow(row);
  }

  Future<FileFolder?> getFolderByPath(String localPath) async {
    final row = await _db.customSelect(
      '''
      SELECT *
      FROM file_folders
      WHERE provider = ? AND local_path = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(FileProviderKind.local),
        Variable<String>(_normalizePath(localPath)),
      ],
    ).getSingleOrNull();
    return row == null ? null : FileFolder.fromRow(row);
  }

  Future<List<FileFolder>> listFolders({int limit = 200}) async {
    await syncDriveRootsFromServer();
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_folders
      ORDER BY
        CASE WHEN provider = ? THEN 0 ELSE 1 END,
        pinned DESC,
        last_used_at DESC,
        use_count DESC,
        display_name ASC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(FileProviderKind.serverStorage),
        Variable<int>(limit),
      ],
    ).get();
    return rows.map(FileFolder.fromRow).toList();
  }

  Future<void> syncDriveRootsFromServer() async {
    final apiLoader = _apiLoader;
    if (apiLoader == null) {
      return;
    }
    try {
      final api = await apiLoader();
      final response = await api.driveRoots();
      final roots = _mapList(response['roots']);
      for (final root in roots) {
        await _cacheDriveRoot(root);
      }
    } catch (_) {
      // The local cache remains usable when the server is unavailable.
    }
  }

  Future<FileFolder> bindRootLocalDirectory({
    required int folderId,
    required String localPath,
  }) async {
    final folder = await getFolderById(folderId);
    if (folder == null) {
      throw StateError('Folder not found.');
    }
    if (folder.remoteId == null || folder.remoteId!.trim().isEmpty) {
      throw StateError('Only server drive roots can be bound to a local directory.');
    }
    final normalizedPath = _normalizePath(localPath);
    final exists = Directory(normalizedPath).existsSync();
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE file_folders
      SET local_path = ?,
          parent_path = ?,
          availability = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        normalizedPath,
        _parentPath(normalizedPath),
        exists ? FileAvailability.local : FileAvailability.missing,
        now,
        folderId,
      ],
    );
    await _db.customStatement(
      '''
      UPDATE file_nodes
      SET local_path = ?,
          availability = ?,
          updated_at = ?
      WHERE root_folder_id = ? AND parent_node_id IS NULL
      ''',
      [
        normalizedPath,
        exists ? FileAvailability.local : FileAvailability.missing,
        now,
        folderId,
      ],
    );
    final updated = await getFolderById(folderId);
    if (updated == null) {
      throw StateError('Folder binding failed.');
    }
    await _operationLogs?.record(
      actor: 'user',
      action: 'bind_drive_root_local_directory',
      entityType: 'file_folder',
      entityId: folderId.toString(),
      summary: 'Bound server drive root ${folder.displayName} to local directory.',
      metadata: {
        'remoteId': folder.remoteId,
        'localPath': normalizedPath,
        'exists': exists,
      },
    );
    return updated;
  }

  Future<void> requestServerRootScan(int folderId) async {
    final apiLoader = _apiLoader;
    if (apiLoader == null) {
      return;
    }
    final folder = await getFolderById(folderId);
    final rootId = folder?.remoteId;
    if (folder == null || rootId == null || rootId.trim().isEmpty) {
      throw StateError('Only server drive roots can be scanned by the server.');
    }
    final api = await apiLoader();
    final response = await api.scanDriveRoot(rootId: rootId);
    if (response['ok'] != true) {
      throw StateError(response['reason']?.toString() ?? 'Server root scan failed.');
    }
    await syncDriveRootsFromServer();
    await refreshDriveNodes(rootFolderId: folderId);
  }

  Future<void> refreshDriveNodes({
    required int rootFolderId,
    int? parentNodeId,
    String? query,
    int limit = 300,
  }) async {
    final apiLoader = _apiLoader;
    if (apiLoader == null) {
      return;
    }
    final root = await getFolderById(rootFolderId);
    final rootRemoteId = root?.remoteId;
    if (root == null || rootRemoteId == null || rootRemoteId.trim().isEmpty) {
      return;
    }
    final parentRemoteId =
        parentNodeId == null ? null : (await getNodeById(parentNodeId))?.remoteId;
    try {
      final api = await apiLoader();
      final response = await api.driveNodes(
        rootId: rootRemoteId,
        parentId: parentRemoteId,
        query: query,
        limit: limit,
      );
      final nodes = _mapList(response['nodes']);
      final parentLocalId = parentNodeId ?? (await _ensureSyntheticRootNode(root)).id;
      for (final node in nodes) {
        await _cacheDriveNode(
          rootFolder: root,
          node: node,
          fallbackParentNodeId: query == null ? parentLocalId : null,
        );
      }
    } catch (_) {
      // Keep browsing cached data if remote refresh fails.
    }
  }

  Future<List<FileFolder>> listRecentFolders({int limit = 20}) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_folders
      WHERE pinned = 1 OR last_used_at IS NOT NULL
      ORDER BY pinned DESC, last_used_at DESC, use_count DESC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map(FileFolder.fromRow).toList();
  }

  Future<FileFolder> relocateFolder({
    required int folderId,
    required String newLocalPath,
  }) async {
    final folder = await getFolderById(folderId);
    if (folder == null) {
      throw StateError('Folder not found.');
    }
    final normalizedPath = _normalizePath(newLocalPath);
    final now = DateTime.now();
    await _db.customStatement(
      '''
      UPDATE file_folders
      SET local_path = ?,
          parent_path = ?,
          display_name = ?,
          availability = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        normalizedPath,
        _parentPath(normalizedPath),
        _displayNameFromPath(normalizedPath),
        Directory(normalizedPath).existsSync()
            ? FileAvailability.local
            : FileAvailability.missing,
        now.toIso8601String(),
        folderId,
      ],
    );
    final updated = await getFolderById(folderId);
    if (updated == null) {
      throw StateError('Folder relocate failed.');
    }
    await _operationLogs?.record(
      actor: 'user',
      action: 'relocate_file_root',
      entityType: 'file_folder',
      entityId: folderId.toString(),
      summary: '重新定位资料库「${updated.displayName}」',
      before: folder.toJson(),
      after: updated.toJson(),
    );
    await _recordFolderUpdate(updated);
    return updated;
  }

  Future<FileScanResult> scanRoot({
    required int folderId,
    int maxNodes = 5000,
    void Function(FileScanProgress progress)? onProgress,
  }) async {
    final folder = await getFolderById(folderId);
    final rootPath = folder?.localPath;
    if (folder == null || rootPath == null || rootPath.trim().isEmpty) {
      throw StateError('Root folder has no local path.');
    }
    final rootDirectory = Directory(rootPath);
    if (!rootDirectory.existsSync()) {
      await _setFolderAvailability(folderId, FileAvailability.missing);
      final existingRoot = await getRootNode(folderId);
      if (existingRoot != null) {
        return FileScanResult(
          rootNode: existingRoot,
          scannedCount: 0,
          truncated: false,
        );
      }
      throw StateError('Root folder is missing.');
    }

    await _setFolderAvailability(folderId, FileAvailability.local);
    final scanBatchId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      'DELETE FROM file_nodes WHERE root_folder_id = ?',
      [folderId],
    );
    final rootNode = await _insertFileNode(
      rootFolderId: folderId,
      parentNodeId: null,
      itemType: FileNodeType.folder,
      displayName: folder.displayName,
      localPath: rootDirectory.path,
      relativePath: '',
      mimeType: null,
      sizeBytes: null,
      modifiedAt: rootDirectory.statSync().modified,
      availability: FileAvailability.local,
      scanBatchId: scanBatchId,
      depth: 0,
      now: now,
    );

    final queue = <({Directory directory, int parentNodeId, int depth})>[
      (directory: rootDirectory, parentNodeId: rootNode.id, depth: 1),
    ];
    var scanned = 1;
    var truncated = false;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      List<FileSystemEntity> children;
      try {
        children = await current.directory.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      children.sort(
        (left, right) => left.path.toLowerCase().compareTo(right.path.toLowerCase()),
      );

      for (final entity in children) {
        if (scanned >= maxNodes) {
          truncated = true;
          queue.clear();
          break;
        }
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory) {
          continue;
        }
        FileStat stat;
        try {
          stat = await entity.stat();
        } catch (_) {
          continue;
        }
        final isFolder = type == FileSystemEntityType.directory;
        final node = await _insertFileNode(
          rootFolderId: folderId,
          parentNodeId: current.parentNodeId,
          itemType: isFolder ? FileNodeType.folder : FileNodeType.file,
          displayName: _displayNameFromPath(entity.path),
          localPath: entity.path,
          relativePath: _relativePath(rootDirectory.path, entity.path),
          mimeType: isFolder ? null : _guessMimeType(entity.path),
          sizeBytes: isFolder ? null : stat.size,
          modifiedAt: stat.modified,
          availability: FileAvailability.local,
          scanBatchId: scanBatchId,
          depth: current.depth,
          now: DateTime.now().toIso8601String(),
        );
        scanned++;
        if (!isFolder) {
          await _upsertLocalFileWithoutSync(
            localPath: entity.path,
            folderId: folderId,
            mimeType: _guessMimeType(entity.path),
            previewMode: _isImagePath(entity.path)
                ? 'image'
                : _isTextPath(entity.path)
                    ? 'text'
                    : 'none',
          );
        }
        if (isFolder) {
          queue.add((
            directory: Directory(entity.path),
            parentNodeId: node.id,
            depth: current.depth + 1,
          ));
        }
        if (scanned % 100 == 0) {
          onProgress?.call(
            FileScanProgress(
              scannedCount: scanned,
              currentPath: entity.path,
              done: false,
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    onProgress?.call(
      FileScanProgress(
        scannedCount: scanned,
        currentPath: rootDirectory.path,
        done: true,
      ),
    );
    await _operationLogs?.record(
      actor: 'user',
      action: 'scan_file_root',
      entityType: 'file_folder',
      entityId: folderId.toString(),
      summary: '扫描资料库「${folder.displayName}」：$scanned 个节点',
      metadata: {
        'scan_batch_id': scanBatchId,
        'scanned_count': scanned,
        'truncated': truncated,
      },
    );
    await _pushLocalSnapshotToDrive(folderId);
    return FileScanResult(
      rootNode: rootNode,
      scannedCount: scanned,
      truncated: truncated,
    );
  }

  Future<FileNode?> getRootNode(int rootFolderId) async {
    final row = await _db.customSelect(
      '''
      SELECT *
      FROM file_nodes
      WHERE root_folder_id = ? AND parent_node_id IS NULL
      LIMIT 1
      ''',
      variables: [Variable<int>(rootFolderId)],
    ).getSingleOrNull();
    return row == null ? null : FileNode.fromRow(row);
  }

  Future<FileNode?> getNodeById(int nodeId) async {
    final row = await _db.customSelect(
      'SELECT * FROM file_nodes WHERE id = ?',
      variables: [Variable<int>(nodeId)],
    ).getSingleOrNull();
    return row == null ? null : FileNode.fromRow(row);
  }

  Future<List<FileNode>> listChildNodes({
    required int rootFolderId,
    int? parentNodeId,
  }) async {
    await refreshDriveNodes(rootFolderId: rootFolderId, parentNodeId: parentNodeId);
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_nodes
      WHERE root_folder_id = ?
        AND ${parentNodeId == null ? 'parent_node_id IS NULL' : 'parent_node_id = ?'}
      ORDER BY CASE item_type WHEN 'folder' THEN 0 ELSE 1 END, display_name ASC
      ''',
      variables: [
        Variable<int>(rootFolderId),
        if (parentNodeId != null) Variable<int>(parentNodeId),
      ],
    ).get();
    return rows.map(FileNode.fromRow).toList(growable: false);
  }

  Future<List<FileNode>> searchNodes({
    required int rootFolderId,
    required String query,
    int limit = 120,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <FileNode>[];
    }
    await refreshDriveNodes(
      rootFolderId: rootFolderId,
      query: trimmed,
      limit: limit,
    );
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_nodes
      WHERE root_folder_id = ?
        AND display_name LIKE ?
      ORDER BY CASE item_type WHEN 'folder' THEN 0 ELSE 1 END, depth ASC, display_name ASC
      LIMIT ?
      ''',
      variables: [
        Variable<int>(rootFolderId),
        Variable<String>('%$trimmed%'),
        Variable<int>(limit),
      ],
    ).get();
    return rows.map(FileNode.fromRow).toList(growable: false);
  }

  Future<List<FileNode>> breadcrumbForNode(FileNode node) async {
    final nodes = <FileNode>[node];
    var parentId = node.parentNodeId;
    while (parentId != null) {
      final parent = await getNodeById(parentId);
      if (parent == null) {
        break;
      }
      nodes.add(parent);
      parentId = parent.parentNodeId;
    }
    return nodes.reversed.toList(growable: false);
  }

  Future<FileContextLink> bindNodeToEntity({
    required String entityType,
    required String entityId,
    required FileNode node,
    String relationType = FileContextRelationType.manual,
    String? reason,
  }) {
    return _upsertLink(
      entityType: entityType,
      entityId: entityId,
      targetType: node.isFolder
          ? FileContextTargetType.folderNode
          : FileContextTargetType.fileNode,
      targetId: node.id,
      relationType: relationType,
      status: FileContextStatus.confirmed,
      confidence: 1,
      reason: reason,
    );
  }

  Future<List<FileItem>> scanLocalFolder({
    required int folderId,
    int limit = 200,
  }) async {
    final folder = await getFolderById(folderId);
    final path = folder?.localPath;
    if (path == null || path.trim().isEmpty) {
      return const <FileItem>[];
    }
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return listFilesForFolder(folderId);
    }

    final files = <FileItem>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (files.length >= limit) {
        break;
      }
      if (entity is! File) {
        continue;
      }
      final item = await upsertLocalFile(
        localPath: entity.path,
        folderId: folderId,
        mimeType: _guessMimeType(entity.path),
        previewMode: _isTextPath(entity.path) ? 'text' : 'none',
      );
      files.add(item);
    }
    return listFilesForFolder(folderId);
  }

  Future<List<FileItem>> listFilesForFolder(int folderId) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_items
      WHERE folder_id = ?
      ORDER BY display_name ASC
      ''',
      variables: [Variable<int>(folderId)],
    ).get();
    return rows.map(FileItem.fromRow).toList();
  }

  Future<FileItem?> getFileById(int id) => _getFileById(id);

  Future<FileItem> upsertLocalFile({
    required String localPath,
    int? folderId,
    String? mimeType,
    String previewMode = 'none',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final normalizedPath = _normalizePath(localPath);
    final existing = await _getFileByPath(normalizedPath);
    final file = File(normalizedPath);
    final stat = file.existsSync() ? file.statSync() : null;
    final now = DateTime.now();
    final displayName = normalizedPath.split(RegExp(r'[\\/]')).last;

    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO file_items (
          file_uid,
          provider,
          display_name,
          folder_id,
          local_path,
          mime_type,
          size_bytes,
          modified_at,
          availability,
          preview_mode,
          metadata_json,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _uuid.v4(),
          FileProviderKind.local,
          displayName,
          folderId,
          normalizedPath,
          mimeType,
          stat?.size,
          stat?.modified.toIso8601String(),
          stat == null ? FileAvailability.missing : FileAvailability.local,
          previewMode,
          jsonEncode(metadata),
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );
      final created = await _lastFile();
      await _syncWriteRecorder?.recordCreate(
        objectType: SyncObjectType.fileItem.key,
        localId: created.id.toString(),
        uid: created.fileUid,
        payload: created.toJson(),
      );
      return created;
    }

    await _db.customStatement(
      '''
      UPDATE file_items
      SET display_name = ?,
          folder_id = ?,
          mime_type = COALESCE(?, mime_type),
          size_bytes = ?,
          modified_at = ?,
          availability = ?,
          preview_mode = ?,
          metadata_json = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        displayName,
        folderId ?? existing.folderId,
        mimeType,
        stat?.size,
        stat?.modified.toIso8601String(),
        stat == null ? FileAvailability.missing : FileAvailability.local,
        previewMode,
        jsonEncode(metadata),
        now.toIso8601String(),
        existing.id,
      ],
    );
    final updated = await _getFileById(existing.id);
    if (updated == null) {
      throw StateError('File update failed.');
    }
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.fileItem.key,
      localId: updated.id.toString(),
      uid: updated.fileUid,
      payload: updated.toJson(),
    );
    return updated;
  }

  Future<FileContextLink> bindFolderToTask({
    required int taskId,
    required int folderId,
    String relationType = FileContextRelationType.manual,
    String? reason,
  }) {
    return _upsertLink(
      entityType: FileContextEntityType.task,
      entityId: taskId.toString(),
      targetType: FileContextTargetType.folder,
      targetId: folderId,
      relationType: relationType,
      status: FileContextStatus.confirmed,
      confidence: 1,
      reason: reason,
    );
  }

  Future<FileContextLink> bindFolderToEvent({
    required int eventId,
    required int folderId,
    String relationType = FileContextRelationType.manual,
    String? reason,
  }) {
    return _upsertLink(
      entityType: FileContextEntityType.event,
      entityId: eventId.toString(),
      targetType: FileContextTargetType.folder,
      targetId: folderId,
      relationType: relationType,
      status: FileContextStatus.confirmed,
      confidence: 1,
      reason: reason,
    );
  }

  Future<FileContextLink> createRecommendationLink({
    required String entityType,
    required String entityId,
    required int folderId,
    required double confidence,
    required String reason,
  }) {
    return _upsertLink(
      entityType: entityType,
      entityId: entityId,
      targetType: FileContextTargetType.folder,
      targetId: folderId,
      relationType: FileContextRelationType.recommended,
      status: FileContextStatus.candidate,
      confidence: confidence,
      reason: reason,
    );
  }

  Future<FileContextLink> confirmLink(int linkId) async {
    final link = await _getLinkById(linkId);
    if (link == null) {
      throw StateError('Link not found.');
    }
    final now = DateTime.now();
    await _db.customStatement(
      '''
      UPDATE file_context_links
      SET status = ?,
          relation_type = ?,
          updated_at = ?,
          confirmed_at = ?
      WHERE id = ?
      ''',
      [
        FileContextStatus.confirmed,
        link.relationType == FileContextRelationType.recommended
            ? FileContextRelationType.manual
            : link.relationType,
        now.toIso8601String(),
        now.toIso8601String(),
        linkId,
      ],
    );
    final updated = await _getLinkById(linkId);
    if (updated == null) {
      throw StateError('Link confirmation failed.');
    }
    await _recordLinkUpdate(updated, action: 'confirm');
    return updated;
  }

  Future<void> rejectLink(int linkId) async {
    final link = await _getLinkById(linkId);
    if (link == null) {
      return;
    }
    final now = DateTime.now();
    await _db.customStatement(
      '''
      UPDATE file_context_links
      SET status = ?, updated_at = ?
      WHERE id = ?
      ''',
      [FileContextStatus.rejected, now.toIso8601String(), linkId],
    );
    final updated = await _getLinkById(linkId);
    if (updated != null) {
      await _recordLinkUpdate(updated, action: 'reject');
    }
  }

  Future<List<FileContextLink>> listLinksForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_context_links
      WHERE entity_type = ? AND entity_id = ? AND status <> ?
      ORDER BY status DESC, confidence DESC, updated_at DESC
      ''',
      variables: [
        Variable<String>(entityType),
        Variable<String>(entityId),
        Variable<String>(FileContextStatus.rejected),
      ],
    ).get();
    return rows.map(FileContextLink.fromRow).toList();
  }

  Future<List<FileFolder>> listConfirmedFoldersForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT f.*
      FROM file_context_links l
      INNER JOIN file_folders f ON f.id = l.target_id
      WHERE l.entity_type = ?
        AND l.entity_id = ?
        AND l.target_type = ?
        AND l.status = ?
      ORDER BY l.updated_at DESC
      ''',
      variables: [
        Variable<String>(entityType),
        Variable<String>(entityId),
        Variable<String>(FileContextTargetType.folder),
        Variable<String>(FileContextStatus.confirmed),
      ],
    ).get();
    return rows.map(FileFolder.fromRow).toList();
  }

  Future<List<FileFolderRecommendation>> recommendFolders({
    required String entityType,
    required String entityId,
    required String title,
    String? description,
    String? location,
    int limit = 8,
  }) async {
    final folders = await listFolders(limit: 500);
    final links = await listLinksForEntity(
      entityType: entityType,
      entityId: entityId,
    );
    final linkByFolderId = <int, FileContextLink>{
      for (final link in links)
        if (link.targetType == FileContextTargetType.folder) link.targetId: link
    };
    final tokens = _tokens('$title ${description ?? ''} ${location ?? ''}');
    final recommendations = <FileFolderRecommendation>[];

    for (final folder in folders) {
      final existing = linkByFolderId[folder.id];
      if (existing?.status == FileContextStatus.confirmed) {
        recommendations.add(
          FileFolderRecommendation(
            folder: folder,
            score: 1,
            reason: '已人工确认关联',
            existingLink: existing,
          ),
        );
        continue;
      }

      var score = 0.0;
      final haystack = _tokens(
        '${folder.displayName} ${folder.localPath ?? ''} '
        '${folder.parentPath ?? ''} ${folder.sourceContext ?? ''}',
      );
      for (final token in tokens) {
        if (token.length < 2) {
          continue;
        }
        if (haystack.contains(token)) {
          score += 0.22;
        }
      }
      if (folder.pinned) {
        score += 0.18;
      }
      if (folder.lastUsedAt != null) {
        final ageHours = DateTime.now().difference(folder.lastUsedAt!).inHours;
        if (ageHours <= 48) {
          score += 0.18;
        } else if (ageHours <= 24 * 14) {
          score += 0.08;
        }
      }
      if (folder.useCount > 0) {
        score += folder.useCount.clamp(0, 10).toDouble() * 0.015;
      }
      if (score <= 0.12) {
        continue;
      }
      recommendations.add(
        FileFolderRecommendation(
          folder: folder,
          score: score.clamp(0, 0.96).toDouble(),
          reason: _recommendationReason(folder, score),
          existingLink: existing,
        ),
      );
    }

    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(limit).toList(growable: false);
  }

  Future<List<FileContextLink>> ensureFolderRecommendations({
    required String entityType,
    required String entityId,
    required String title,
    String? description,
    String? location,
    int limit = 5,
  }) async {
    final recommendations = await recommendFolders(
      entityType: entityType,
      entityId: entityId,
      title: title,
      description: description,
      location: location,
      limit: limit,
    );
    final links = <FileContextLink>[];
    for (final recommendation in recommendations) {
      if (recommendation.existingLink != null) {
        links.add(recommendation.existingLink!);
        continue;
      }
      links.add(
        await createRecommendationLink(
          entityType: entityType,
          entityId: entityId,
          folderId: recommendation.folder.id,
          confidence: recommendation.score,
          reason: recommendation.reason,
        ),
      );
    }
    return links;
  }

  Future<void> recordFolderUsage({
    required int folderId,
    required String action,
    String? entityType,
    String? entityId,
    String source = 'user',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO file_folder_usages (
        usage_uid,
        folder_id,
        entity_type,
        entity_id,
        action,
        source,
        used_at,
        metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        folderId,
        entityType,
        entityId,
        action,
        source,
        now.toIso8601String(),
        jsonEncode(metadata),
      ],
    );
    final usageRow = await _db.customSelect(
      'SELECT * FROM file_folder_usages WHERE id = last_insert_rowid()',
    ).getSingle();
    await _db.customStatement(
      '''
      UPDATE file_folders
      SET use_count = use_count + 1,
          last_used_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [now.toIso8601String(), now.toIso8601String(), folderId],
    );
    final usage = <String, Object?>{
      'id': usageRow.read<int>('id'),
      'usageUid': usageRow.read<String>('usage_uid'),
      'folderId': folderId,
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'source': source,
      'usedAt': now.toIso8601String(),
      'metadataJson': jsonEncode(metadata),
    };
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.fileFolderUsage.key,
      localId: usage['id'].toString(),
      uid: usage['usageUid'] as String,
      payload: usage,
    );
  }

  Future<void> recordFileNodeOperation({
    required FileNode node,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    await _operationLogs?.record(
      actor: 'user',
      action: action,
      entityType: 'file_node',
      entityId: node.id.toString(),
      summary: '${_nodeActionLabel(action)}「${node.displayName}」',
      after: node.toJson(),
      metadata: {
        'entity_type': entityType,
        'entity_id': entityId,
        'local_path': node.localPath,
        ...metadata,
      },
    );
  }

  Future<FileVersionRecord> addVersionRecord({
    required int fileId,
    required String versionRef,
    required String displayName,
    String provider = 'kopia',
    int? sizeBytes,
    DateTime? modifiedAt,
    String? checksum,
    String? sourceDevice,
    String? sourceBackend,
    String? note,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO file_version_records (
        version_uid,
        file_id,
        provider,
        version_ref,
        display_name,
        size_bytes,
        modified_at,
        checksum,
        source_device,
        source_backend,
        note,
        metadata_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        fileId,
        provider,
        versionRef,
        displayName,
        sizeBytes,
        modifiedAt?.toIso8601String(),
        checksum,
        sourceDevice,
        sourceBackend,
        note,
        jsonEncode(metadata),
        now.toIso8601String(),
      ],
    );
    final version = await _lastVersion();
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.fileVersionRecord.key,
      localId: version.id.toString(),
      uid: version.versionUid,
      payload: version.toJson(),
    );
    return version;
  }

  Future<List<FileVersionRecord>> listFileVersions(int fileId) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM file_version_records
      WHERE file_id = ?
      ORDER BY COALESCE(modified_at, created_at) DESC
      ''',
      variables: [Variable<int>(fileId)],
    ).get();
    return rows.map(FileVersionRecord.fromRow).toList();
  }

  Future<void> _upsertRootToServer(FileFolder folder) async {
    // Client local folders are device-side copies only. They must never become
    // global cloud-drive roots; service roots are created/scanned on the server.
    return;
  }

  Future<FileFolder> _cacheDriveRoot(Map<String, dynamic> root) async {
    final remoteId = root['id']?.toString();
    final rootUid = root['rootUid']?.toString() ?? 'server-root:$remoteId';
    final name = root['name']?.toString() ?? root['rootDisplayPath']?.toString() ?? 'Drive Root';
    final now = DateTime.now().toIso8601String();
    final existing = await _db.customSelect(
      '''
      SELECT *
      FROM file_folders
      WHERE folder_uid = ? OR remote_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(rootUid),
        Variable<String>(remoteId ?? ''),
      ],
    ).getSingleOrNull();
    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO file_folders (
          folder_uid,
          provider,
          display_name,
          local_path,
          remote_id,
          parent_path,
          source_context,
          pinned,
          availability,
          metadata_json,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          rootUid,
          FileProviderKind.serverStorage,
          name,
          null,
          remoteId,
          null,
          'server_drive',
          0,
          FileAvailability.remoteOnly,
          jsonEncode(root),
          now,
          now,
        ],
      );
      final created = await _lastFolder();
      await _ensureSyntheticRootNode(created);
      return created;
    }
    final folder = FileFolder.fromRow(existing);
    await _db.customStatement(
      '''
      UPDATE file_folders
      SET provider = ?,
          display_name = ?,
          remote_id = ?,
          availability = ?,
          metadata_json = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        FileProviderKind.serverStorage,
        name,
        remoteId,
        folder.localPath == null || folder.localPath!.trim().isEmpty
            ? FileAvailability.remoteOnly
            : folder.availability,
        jsonEncode(root),
        now,
        folder.id,
      ],
    );
    final updated = (await getFolderById(folder.id)) ?? folder;
    await _ensureSyntheticRootNode(updated);
    return updated;
  }

  Future<FileNode> _ensureSyntheticRootNode(FileFolder root) async {
    final existing = await getRootNode(root.id);
    if (existing != null) {
      return existing;
    }
    return _insertFileNode(
      rootFolderId: root.id,
      parentNodeId: null,
      itemType: FileNodeType.folder,
      displayName: root.displayName,
      localPath: root.localPath ?? '',
      relativePath: '',
      mimeType: null,
      sizeBytes: null,
      modifiedAt: null,
      availability: root.availability,
      scanBatchId: 'server-drive',
      depth: 0,
      now: DateTime.now().toIso8601String(),
      remoteId: null,
    );
  }

  Future<FileNode> _cacheDriveNode({
    required FileFolder rootFolder,
    required Map<String, dynamic> node,
    int? fallbackParentNodeId,
  }) async {
    final remoteId = node['id']?.toString();
    final nodeUid = node['nodeUid']?.toString() ?? 'server-node:$remoteId';
    final parentRemoteId = node['parentId']?.toString();
    int? parentLocalId = fallbackParentNodeId;
    if (parentRemoteId != null && parentRemoteId.isNotEmpty) {
      final parent = await _getNodeByRemoteId(parentRemoteId);
      parentLocalId = parent?.id ?? fallbackParentNodeId;
    }
    final storage = node['storage'];
    final currentDevice = node['currentDevice'];
    final currentDevicePath = currentDevice is Map
        ? currentDevice['localPath']?.toString()
        : null;
    final currentDeviceAvailability = currentDevice is Map
        ? currentDevice['availability']?.toString()
        : null;
    final localPath = currentDevicePath?.trim().isNotEmpty == true
        ? currentDevicePath!
        : '';
    final availability = localPath.trim().isEmpty
        ? FileAvailability.remoteOnly
        : currentDeviceAvailability ?? FileAvailability.local;
    final now = DateTime.now().toIso8601String();
    final existing = await _db.customSelect(
      '''
      SELECT *
      FROM file_nodes
      WHERE node_uid = ? OR remote_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(nodeUid),
        Variable<String>(remoteId ?? ''),
      ],
    ).getSingleOrNull();
    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO file_nodes (
          node_uid,
          remote_id,
          root_folder_id,
          parent_node_id,
          item_type,
          display_name,
          local_path,
          relative_path,
          mime_type,
          size_bytes,
          modified_at,
          availability,
          scan_batch_id,
          depth,
          hash_sha256,
          storage_object_id,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          nodeUid,
          remoteId,
          rootFolder.id,
          parentLocalId,
          node['nodeType']?.toString() ?? FileNodeType.file,
          node['displayName']?.toString() ?? node['name']?.toString() ?? 'file',
          _normalizePath(localPath),
          node['relativePath']?.toString() ?? '',
          node['mimeType']?.toString(),
          _readInt(node['sizeBytes']),
          node['mtime']?.toString(),
          availability,
          'server-drive',
          _depthOfRelativePath(node['relativePath']?.toString() ?? ''),
          node['hashSha256']?.toString(),
          storage is Map ? storage['storageObjectId']?.toString() : null,
          now,
          now,
        ],
      );
      return FileNode.fromRow(
        await _db.customSelect(
          'SELECT * FROM file_nodes WHERE id = last_insert_rowid()',
        ).getSingle(),
      );
    }
    final existingNode = FileNode.fromRow(existing);
    await _db.customStatement(
      '''
      UPDATE file_nodes
      SET remote_id = ?,
          parent_node_id = COALESCE(?, parent_node_id),
          item_type = ?,
          display_name = ?,
          local_path = CASE WHEN ? = '' THEN local_path ELSE ? END,
          relative_path = ?,
          mime_type = ?,
          size_bytes = ?,
          modified_at = ?,
          availability = ?,
          scan_batch_id = 'server-drive',
          depth = ?,
          hash_sha256 = ?,
          storage_object_id = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        remoteId,
        parentLocalId,
        node['nodeType']?.toString() ?? existingNode.itemType,
        node['displayName']?.toString() ?? node['name']?.toString() ?? existingNode.displayName,
        _normalizePath(localPath),
        _normalizePath(localPath),
        node['relativePath']?.toString() ?? existingNode.relativePath,
        node['mimeType']?.toString(),
        _readInt(node['sizeBytes']),
        node['mtime']?.toString(),
        availability,
        _depthOfRelativePath(node['relativePath']?.toString() ?? existingNode.relativePath),
        node['hashSha256']?.toString(),
        storage is Map ? storage['storageObjectId']?.toString() : existingNode.storageObjectId,
        now,
        existingNode.id,
      ],
    );
    return (await getNodeById(existingNode.id)) ?? existingNode;
  }

  Future<FileNode?> _getNodeByRemoteId(String remoteId) async {
    final row = await _db.customSelect(
      'SELECT * FROM file_nodes WHERE remote_id = ? LIMIT 1',
      variables: [Variable<String>(remoteId)],
    ).getSingleOrNull();
    return row == null ? null : FileNode.fromRow(row);
  }

  Future<void> _pushLocalSnapshotToDrive(int folderId) async {
    final apiLoader = _apiLoader;
    if (apiLoader == null) {
      return;
    }
    final folder = await getFolderById(folderId);
    final rootId = folder?.remoteId;
    if (folder == null || rootId == null || rootId.trim().isEmpty) {
      return;
    }
    try {
      final rows = await _db.customSelect(
        '''
        SELECT child.*, parent.node_uid AS parent_node_uid
        FROM file_nodes child
        LEFT JOIN file_nodes parent ON parent.id = child.parent_node_id
        WHERE child.root_folder_id = ?
        ORDER BY child.depth ASC, child.item_type ASC, child.display_name ASC
        ''',
        variables: [Variable<int>(folderId)],
      ).get();
      final payload = rows.map((row) {
        final node = FileNode.fromRow(row);
        return <String, Object?>{
          'nodeUid': node.nodeUid,
          'parentNodeUid': row.data['parent_node_uid'] as String?,
          'nodeType': node.itemType,
          'name': node.displayName,
          'relativePath': node.relativePath,
          'displayPath': node.localPath,
          'localPath': node.localPath,
          'mimeType': node.mimeType,
          'extension': _extension(node.displayName),
          'sizeBytes': node.sizeBytes,
          'mtime': node.modifiedAt?.toIso8601String(),
          'hashSha256': node.hashSha256,
          'availability': node.availability,
          'metadata': <String, Object?>{
            'localNodeId': node.id,
            'rootFolderId': node.rootFolderId,
          },
        };
      }).toList(growable: false);
      final api = await apiLoader();
      await api.applyNodeSnapshot(rootId: rootId, nodes: payload);
      await refreshDriveNodes(rootFolderId: folderId);
    } catch (_) {
      // Snapshot upload is retryable via later scans/manual sync.
    }
  }

  Future<void> _setFolderAvailability(int folderId, String availability) {
    return _db.customStatement(
      '''
      UPDATE file_folders
      SET availability = ?, updated_at = ?
      WHERE id = ?
      ''',
      [availability, DateTime.now().toIso8601String(), folderId],
    );
  }

  Future<FileNode> _insertFileNode({
    required int rootFolderId,
    required int? parentNodeId,
    required String itemType,
    required String displayName,
    required String localPath,
    required String relativePath,
    required String? mimeType,
    required int? sizeBytes,
    required DateTime? modifiedAt,
    required String availability,
    required String scanBatchId,
    required int depth,
    required String now,
    String? remoteId,
    String? hashSha256,
    String? storageObjectId,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO file_nodes (
        node_uid,
        remote_id,
        root_folder_id,
        parent_node_id,
        item_type,
        display_name,
        local_path,
        relative_path,
        mime_type,
        size_bytes,
        modified_at,
        availability,
        scan_batch_id,
        depth,
        hash_sha256,
        storage_object_id,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        remoteId,
        rootFolderId,
        parentNodeId,
        itemType,
        displayName,
        _normalizePath(localPath),
        relativePath,
        mimeType,
        sizeBytes,
        modifiedAt?.toIso8601String(),
        availability,
        scanBatchId,
        depth,
        hashSha256,
        storageObjectId,
        now,
        now,
      ],
    );
    final row = await _db.customSelect(
      'SELECT * FROM file_nodes WHERE id = last_insert_rowid()',
    ).getSingle();
    return FileNode.fromRow(row);
  }

  Future<FileItem> _upsertLocalFileWithoutSync({
    required String localPath,
    int? folderId,
    String? mimeType,
    String previewMode = 'none',
  }) async {
    final normalizedPath = _normalizePath(localPath);
    final existing = await _getFileByPath(normalizedPath);
    final file = File(normalizedPath);
    final stat = file.existsSync() ? file.statSync() : null;
    final now = DateTime.now();
    final displayName = _displayNameFromPath(normalizedPath);
    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO file_items (
          file_uid,
          provider,
          display_name,
          folder_id,
          local_path,
          mime_type,
          size_bytes,
          modified_at,
          availability,
          preview_mode,
          metadata_json,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _uuid.v4(),
          FileProviderKind.local,
          displayName,
          folderId,
          normalizedPath,
          mimeType,
          stat?.size,
          stat?.modified.toIso8601String(),
          stat == null ? FileAvailability.missing : FileAvailability.local,
          previewMode,
          '{}',
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );
      return _lastFile();
    }
    await _db.customStatement(
      '''
      UPDATE file_items
      SET display_name = ?,
          folder_id = ?,
          mime_type = COALESCE(?, mime_type),
          size_bytes = ?,
          modified_at = ?,
          availability = ?,
          preview_mode = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        displayName,
        folderId ?? existing.folderId,
        mimeType,
        stat?.size,
        stat?.modified.toIso8601String(),
        stat == null ? FileAvailability.missing : FileAvailability.local,
        previewMode,
        now.toIso8601String(),
        existing.id,
      ],
    );
    return (await _getFileById(existing.id)) ?? existing;
  }

  Future<FileFolder> _lastFolder() async {
    final row = await _db.customSelect(
      'SELECT * FROM file_folders WHERE id = last_insert_rowid()',
    ).getSingle();
    return FileFolder.fromRow(row);
  }

  Future<FileItem> _lastFile() async {
    final row = await _db.customSelect(
      'SELECT * FROM file_items WHERE id = last_insert_rowid()',
    ).getSingle();
    return FileItem.fromRow(row);
  }

  Future<FileVersionRecord> _lastVersion() async {
    final row = await _db.customSelect(
      'SELECT * FROM file_version_records WHERE id = last_insert_rowid()',
    ).getSingle();
    return FileVersionRecord.fromRow(row);
  }

  Future<FileItem?> _getFileById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM file_items WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : FileItem.fromRow(row);
  }

  Future<FileItem?> _getFileByPath(String localPath) async {
    final row = await _db.customSelect(
      '''
      SELECT *
      FROM file_items
      WHERE provider = ? AND local_path = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(FileProviderKind.local),
        Variable<String>(_normalizePath(localPath)),
      ],
    ).getSingleOrNull();
    return row == null ? null : FileItem.fromRow(row);
  }

  Future<FileContextLink?> _getLinkById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM file_context_links WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : FileContextLink.fromRow(row);
  }

  Future<FileContextLink> _upsertLink({
    required String entityType,
    required String entityId,
    required String targetType,
    required int targetId,
    required String relationType,
    required String status,
    required double confidence,
    String? reason,
  }) async {
    final existingRow = await _db.customSelect(
      '''
      SELECT *
      FROM file_context_links
      WHERE entity_type = ?
        AND entity_id = ?
        AND target_type = ?
        AND target_id = ?
        AND status <> ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(entityType),
        Variable<String>(entityId),
        Variable<String>(targetType),
        Variable<int>(targetId),
        Variable<String>(FileContextStatus.rejected),
      ],
    ).getSingleOrNull();
    final now = DateTime.now();
    if (existingRow == null) {
      await _db.customStatement(
        '''
        INSERT INTO file_context_links (
          link_uid,
          entity_type,
          entity_id,
          target_type,
          target_id,
          relation_type,
          confidence,
          reason,
          status,
          created_at,
          updated_at,
          confirmed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _uuid.v4(),
          entityType,
          entityId,
          targetType,
          targetId,
          relationType,
          confidence,
          reason,
          status,
          now.toIso8601String(),
          now.toIso8601String(),
          status == FileContextStatus.confirmed ? now.toIso8601String() : null,
        ],
      );
      final link = FileContextLink.fromRow(
        await _db.customSelect(
          'SELECT * FROM file_context_links WHERE id = last_insert_rowid()',
        ).getSingle(),
      );
      await _recordLinkCreate(link);
      return link;
    }

    final existing = FileContextLink.fromRow(existingRow);
    await _db.customStatement(
      '''
      UPDATE file_context_links
      SET relation_type = ?,
          confidence = MAX(confidence, ?),
          reason = COALESCE(?, reason),
          status = CASE
            WHEN status = ? THEN status
            ELSE ?
          END,
          updated_at = ?,
          confirmed_at = CASE
            WHEN ? = ? THEN COALESCE(confirmed_at, ?)
            ELSE confirmed_at
          END
      WHERE id = ?
      ''',
      [
        existing.status == FileContextStatus.confirmed
            ? existing.relationType
            : relationType,
        confidence,
        reason,
        FileContextStatus.confirmed,
        status,
        now.toIso8601String(),
        status,
        FileContextStatus.confirmed,
        now.toIso8601String(),
        existing.id,
      ],
    );
    final updated = await _getLinkById(existing.id);
    if (updated == null) {
      throw StateError('Link update failed.');
    }
    await _recordLinkUpdate(updated);
    return updated;
  }

  Future<void> _recordFolderCreate(FileFolder folder) async {
    await _operationLogs?.record(
      actor: 'user',
      action: 'create_file_folder',
      entityType: 'file_folder',
      entityId: folder.id.toString(),
      summary: '添加文件夹「${folder.displayName}」',
      after: folder.toJson(),
    );
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.fileFolder.key,
      localId: folder.id.toString(),
      uid: folder.folderUid,
      payload: folder.toJson(),
    );
  }

  Future<void> _recordFolderUpdate(FileFolder folder) async {
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.fileFolder.key,
      localId: folder.id.toString(),
      uid: folder.folderUid,
      payload: folder.toJson(),
    );
  }

  Future<void> _recordLinkCreate(FileContextLink link) async {
    await _operationLogs?.record(
      actor: 'user',
      action: 'create_file_context_link',
      entityType: 'file_context_link',
      entityId: link.id.toString(),
      summary: '添加文件上下文关联',
      after: link.toJson(),
    );
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.fileContextLink.key,
      localId: link.id.toString(),
      uid: link.linkUid,
      payload: link.toJson(),
    );
  }

  Future<void> _recordLinkUpdate(
    FileContextLink link, {
    String action = 'update',
  }) async {
    await _operationLogs?.record(
      actor: 'user',
      action: '${action}_file_context_link',
      entityType: 'file_context_link',
      entityId: link.id.toString(),
      summary: '更新文件上下文关联',
      after: link.toJson(),
    );
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.fileContextLink.key,
      localId: link.id.toString(),
      uid: link.linkUid,
      payload: link.toJson(),
    );
  }

  String _normalizePath(String path) {
    return path.trim().replaceAll('/', Platform.pathSeparator);
  }

  String? _parentPath(String path) {
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    if (index <= 0) {
      return null;
    }
    return path.substring(0, index);
  }

  String _displayNameFromPath(String path) {
    final normalized = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    final parts = normalized.split(RegExp(r'[\\/]'));
    return parts.isEmpty || parts.last.trim().isEmpty ? normalized : parts.last;
  }

  String? _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'text/yaml';
    if (lower.endsWith('.log')) return 'text/plain';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return null;
  }

  bool _isTextPath(String path) {
    return _guessMimeType(path)?.startsWith('text/') == true ||
        _guessMimeType(path) == 'application/json';
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp');
  }

  String _relativePath(String rootPath, String childPath) {
    final root = _normalizePath(rootPath);
    final child = _normalizePath(childPath);
    if (child == root) {
      return '';
    }
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (child.startsWith(prefix)) {
      return child.substring(prefix.length);
    }
    return child;
  }

  Set<String> _tokens(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[\s\\/_\-.,;:()\[\]{}]+'))
        .where((token) => token.trim().isNotEmpty)
        .toSet();
  }

  String _recommendationReason(FileFolder folder, double score) {
    if (folder.pinned) {
      return '常驻文件夹与当前上下文匹配';
    }
    if (folder.lastUsedAt != null) {
      return '最近使用过，且名称或路径与当前上下文匹配';
    }
    if (score > 0.5) {
      return '文件夹名称、路径或来源上下文高度匹配';
    }
    return '文件夹名称、路径或来源上下文可能相关';
  }

  String _nodeActionLabel(String action) {
    switch (action) {
      case 'open_file_node':
        return '打开文件节点';
      case 'reveal_file_node':
        return '在资源管理器中显示文件节点';
      case 'preview_file_node':
        return '预览文件节点';
      case 'save_file_node_text':
        return '保存文本文件节点';
      case 'bind_file_node':
        return '绑定文件节点';
      default:
        return '操作文件节点';
    }
  }
}

DateTime? _date(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

int? _readInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

int _depthOfRelativePath(String path) {
  if (path.trim().isEmpty) {
    return 0;
  }
  return path
      .split(RegExp(r'[\\/]'))
      .where((part) => part.trim().isNotEmpty)
      .length;
}

String? _extension(String path) {
  final index = path.lastIndexOf('.');
  if (index <= 0 || index == path.length - 1) {
    return null;
  }
  return path.substring(index + 1).toLowerCase();
}
