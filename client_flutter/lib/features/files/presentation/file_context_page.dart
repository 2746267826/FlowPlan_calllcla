import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/router/app_router.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/file_context_repository.dart';
import '../services/file_context_interaction_service.dart';
import '../services/local_file_identity_service.dart';

final fileContextRefreshTickProvider = StateProvider<int>((ref) => 0);

final allFileFoldersProvider = FutureProvider<List<FileFolder>>((ref) {
  ref.watch(fileContextRefreshTickProvider);
  return ref.watch(fileContextRepositoryProvider).listFolders(limit: 200);
});

class FileContextPage extends ConsumerStatefulWidget {
  const FileContextPage({super.key});

  @override
  ConsumerState<FileContextPage> createState() => _FileContextPageState();
}

class _FileContextPageState extends ConsumerState<FileContextPage> {
  int? _selectedRootId;
  int? _currentFolderNodeId;
  int? _selectedNodeId;
  String _query = '';
  bool _scanning = false;
  int _scannedCount = 0;
  String _scanPath = '';

  @override
  Widget build(BuildContext context) {
    final rootsAsync = ref.watch(allFileFoldersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件中心'),
        actions: [
          IconButton(
            tooltip: '从服务端刷新云盘树',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _refreshDrive,
          ),
          IconButton(
            tooltip: '传输中心',
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () => context.go(AppRoutes.fileTransfers),
          ),
          IconButton(
            tooltip: '添加资料库 Root',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _addRoot,
          ),
        ],
      ),
      body: rootsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('资料库读取失败：$error')),
        data: (roots) {
          if (roots.isEmpty) {
            return _EmptyFirstRun(onAdd: _addRoot);
          }
          final selectedRoot = _selectRoot(roots);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final rootList = _RootList(
                roots: roots,
                selectedRootId: selectedRoot.id,
                onAdd: _addRoot,
                onSelect: (root) {
                  setState(() {
                    _selectedRootId = root.id;
                    _currentFolderNodeId = null;
                    _selectedNodeId = null;
                    _query = '';
                  });
                },
              );
              final browser = _NodeBrowserPane(
                root: selectedRoot,
                currentFolderNodeId: _currentFolderNodeId,
                selectedNodeId: _selectedNodeId,
                query: _query,
                scanning: _scanning,
                scannedCount: _scannedCount,
                scanPath: _scanPath,
                onQueryChanged: (value) => setState(() => _query = value),
                onEnterFolder: (node) {
                  setState(() {
                    _currentFolderNodeId = node.id;
                    _selectedNodeId = null;
                  });
                },
                onSelectNode: (node) => setState(() => _selectedNodeId = node.id),
                onGoUp: _goUp,
                onScan: () => _scanRoot(selectedRoot),
                onRelocate: () => _relocateRoot(selectedRoot),
                onCreateSnapshot: () => _createKopiaSnapshot(selectedRoot),
              );
              final preview = _NodePreviewHost(
                root: selectedRoot,
                selectedNodeId: _selectedNodeId,
                onRelocateRoot: () => _relocateRoot(selectedRoot),
              );

              if (!wide) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    rootList,
                    const SizedBox(height: 16),
                    SizedBox(height: 520, child: browser),
                    const Divider(height: 32),
                    SizedBox(height: 520, child: preview),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [rootList],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 440, child: browser),
                  const VerticalDivider(width: 1),
                  Expanded(child: preview),
                ],
              );
            },
          );
        },
      ),
    );
  }

  FileFolder _selectRoot(List<FileFolder> roots) {
    for (final root in roots) {
      if (root.id == _selectedRootId) {
        return root;
      }
    }
    _selectedRootId = roots.first.id;
    return roots.first;
  }

  Future<void> _addRoot() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择资料库 Root',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }
    if (!mounted) return;

    final noteController = TextEditingController();
    final sourceContext = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('资料库说明'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: '上下文备注',
            hintText: '项目、课程、会议或常用资料说明',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(noteController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    noteController.dispose();

    final repo = ref.read(fileContextRepositoryProvider);
    final folder = await repo.upsertLocalFolder(
      localPath: selectedPath,
      sourceContext:
          sourceContext == null || sourceContext.isEmpty ? null : sourceContext,
      pinned: true,
    );
    setState(() {
      _selectedRootId = folder.id;
      _currentFolderNodeId = null;
      _selectedNodeId = null;
      _query = '';
    });
    ref.read(fileContextRefreshTickProvider.notifier).state++;
    await _scanRoot(folder);
  }

  Future<void> _refreshDrive() async {
    final repo = ref.read(fileContextRepositoryProvider);
    await repo.syncDriveRootsFromServer();
    final selectedRootId = _selectedRootId;
    if (selectedRootId != null) {
      await repo.refreshDriveNodes(rootFolderId: selectedRootId);
    }
    if (!mounted) return;
    ref.read(fileContextRefreshTickProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('云盘树已从服务端刷新')),
    );
  }

  Future<void> _scanRoot(FileFolder root) async {
    setState(() {
      _scanning = true;
      _scannedCount = 0;
      _scanPath = root.localPath ?? '';
    });
    try {
      final result = await ref.read(fileContextRepositoryProvider).scanRoot(
            folderId: root.id,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _scannedCount = progress.scannedCount;
                _scanPath = progress.currentPath;
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _currentFolderNodeId = result.rootNode.id;
        _selectedNodeId = null;
      });
      final suffix = result.truncated ? '，已达到本次扫描上限' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描完成：${result.scannedCount} 个节点$suffix')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        ref.read(fileContextRefreshTickProvider.notifier).state++;
      }
    }
  }

  Future<void> _relocateRoot(FileFolder root) async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '重新定位资料库 Root',
      initialDirectory: root.localPath,
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }
    final updated = await ref.read(fileContextRepositoryProvider).relocateFolder(
          folderId: root.id,
          newLocalPath: selectedPath,
        );
    setState(() {
      _selectedRootId = updated.id;
      _currentFolderNodeId = null;
      _selectedNodeId = null;
    });
    ref.read(fileContextRefreshTickProvider.notifier).state++;
    await _scanRoot(updated);
  }

  Future<void> _createKopiaSnapshot(FileFolder root) async {
    final rootPath = root.localPath;
    if (rootPath == null || rootPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该资料库没有本地路径，不能创建 Kopia 快照')),
      );
      return;
    }
    try {
      final api = await ref.read(fileCloudApiProvider.future);
      final result = await api.createKopiaSnapshot(
        rootPath: rootPath,
        rootId: root.id.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['ok'] == true
              ? 'Kopia 快照已创建，可在文件详情中刷新历史版本'
              : 'Kopia 快照失败：${result['reason'] ?? 'unknown'}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kopia 快照失败：$error')),
      );
    }
  }

  Future<void> _goUp() async {
    final currentId = _currentFolderNodeId;
    if (currentId == null) return;
    final current =
        await ref.read(fileContextRepositoryProvider).getNodeById(currentId);
    if (!mounted || current == null) return;
    setState(() {
      _currentFolderNodeId = current.parentNodeId;
      _selectedNodeId = null;
    });
  }
}

class _RootList extends ConsumerWidget {
  const _RootList({
    required this.roots,
    required this.selectedRootId,
    required this.onAdd,
    required this.onSelect,
  });

  final List<FileFolder> roots;
  final int selectedRootId;
  final VoidCallback onAdd;
  final ValueChanged<FileFolder> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '资料库 Root',
          action: IconButton(
            tooltip: '添加资料库 Root',
            icon: const Icon(Icons.add),
            onPressed: onAdd,
          ),
        ),
        ...roots.map(
          (root) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: root.id == selectedRootId
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.45)
                : null,
            child: ListTile(
              leading: Icon(
                root.availability == FileAvailability.local
                    ? Icons.folder_outlined
                    : Icons.report_problem_outlined,
              ),
              title: Row(
                children: [
                  Expanded(child: Text(root.displayName)),
                  if (root.pinned) const Icon(Icons.push_pin_outlined, size: 16),
                ],
              ),
              subtitle: Text(
                root.localPath ?? root.remoteId ?? root.provider,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              selected: root.id == selectedRootId,
              onTap: () => onSelect(root),
              onLongPress: () => ref
                  .read(fileContextInteractionServiceProvider)
                  .revealFolder(root),
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeBrowserPane extends ConsumerWidget {
  const _NodeBrowserPane({
    required this.root,
    required this.currentFolderNodeId,
    required this.selectedNodeId,
    required this.query,
    required this.scanning,
    required this.scannedCount,
    required this.scanPath,
    required this.onQueryChanged,
    required this.onEnterFolder,
    required this.onSelectNode,
    required this.onGoUp,
    required this.onScan,
    required this.onRelocate,
    required this.onCreateSnapshot,
  });

  final FileFolder root;
  final int? currentFolderNodeId;
  final int? selectedNodeId;
  final String query;
  final bool scanning;
  final int scannedCount;
  final String scanPath;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<FileNode> onEnterFolder;
  final ValueChanged<FileNode> onSelectNode;
  final VoidCallback onGoUp;
  final VoidCallback onScan;
  final VoidCallback onRelocate;
  final VoidCallback onCreateSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootMissing =
        root.localPath == null || !Directory(root.localPath!).existsSync();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<FileNode?>(
                future: _loadCurrentFolder(ref),
                builder: (context, snapshot) {
                  final current = snapshot.data;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          current?.displayName ?? root.displayName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      IconButton(
                        tooltip: '返回上级',
                        onPressed:
                            current?.parentNodeId == null ? null : onGoUp,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: '重新扫描',
                        onPressed: scanning ? null : onScan,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: '重新定位',
                        onPressed: onRelocate,
                        icon: const Icon(Icons.folder_special_outlined),
                      ),
                      IconButton(
                        tooltip: '创建 Kopia 快照',
                        onPressed: scanning || rootMissing ? null : onCreateSnapshot,
                        icon: const Icon(Icons.history_toggle_off),
                      ),
                    ],
                  );
                },
              ),
              Text(
                root.localPath ?? '未设置本地路径',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: '搜索文件名',
                  border: OutlineInputBorder(),
                ),
                onChanged: onQueryChanged,
              ),
              if (rootMissing) ...[
                const SizedBox(height: 12),
                _WarningBox(
                  message: '资料库路径不存在。请重新定位后再扫描或打开文件。',
                  actionLabel: '重新定位',
                  onAction: onRelocate,
                ),
              ],
              if (scanning) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(
                  '正在扫描 $scannedCount 个节点：$scanPath',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<_NodeBrowserData>(
            future: _loadData(ref),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('文件树读取失败：${snapshot.error}'));
              }
              final data = snapshot.data;
              if (data == null || data.rootNode == null) {
                return _EmptyTree(onScan: onScan);
              }
              if (data.nodes.isEmpty) {
                return Center(
                  child: Text(query.trim().isEmpty
                      ? '当前目录为空。'
                      : '没有匹配的文件名。'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: data.nodes.length,
                itemBuilder: (context, index) {
                  final node = data.nodes[index];
                  return _NodeTile(
                    node: node,
                    selected: selectedNodeId == node.id,
                    onTap: () => node.isFolder && query.trim().isEmpty
                        ? onEnterFolder(node)
                        : onSelectNode(node),
                    onSelect: () => onSelectNode(node),
                    onOpen: () => _openOrDownloadNode(context, ref, node),
                    onReveal: () => ref
                        .read(fileContextInteractionServiceProvider)
                        .revealNode(node),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<FileNode?> _loadCurrentFolder(WidgetRef ref) async {
    final repo = ref.read(fileContextRepositoryProvider);
    if (currentFolderNodeId != null) {
      return repo.getNodeById(currentFolderNodeId!);
    }
    return repo.getRootNode(root.id);
  }

  Future<_NodeBrowserData> _loadData(WidgetRef ref) async {
    final repo = ref.read(fileContextRepositoryProvider);
    final rootNode = await repo.getRootNode(root.id);
    if (rootNode == null) {
      return const _NodeBrowserData(rootNode: null, nodes: []);
    }
    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      final nodes = await repo.searchNodes(
        rootFolderId: root.id,
        query: trimmedQuery,
      );
      return _NodeBrowserData(rootNode: rootNode, nodes: nodes);
    }
    final current = currentFolderNodeId == null
        ? rootNode
        : await repo.getNodeById(currentFolderNodeId!);
    final nodes = await repo.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: current?.id ?? rootNode.id,
    );
    return _NodeBrowserData(rootNode: rootNode, nodes: nodes);
  }
}

class _NodeBrowserData {
  const _NodeBrowserData({
    required this.rootNode,
    required this.nodes,
  });

  final FileNode? rootNode;
  final List<FileNode> nodes;
}

Future<void> _openOrDownloadNode(
  BuildContext context,
  WidgetRef ref,
  FileNode node,
) async {
  try {
    final interaction = ref.read(fileContextInteractionServiceProvider);
    final result = await interaction.openNodeWithPlan(node);
    if (result.opened) {
      return;
    }

    if (!result.needsDownload) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ?? '文件未能直接打开：可能需要重新定位或处理 hash 不一致。',
          ),
        ),
      );
      return;
    }

    if (node.remoteId == null || node.remoteId!.trim().isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该文件缺少服务端节点 ID，不能创建下载请求。')),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载后打开文件'),
        content: SelectableText(
          '${result.message ?? '本设备没有可直接打开的本地副本。'}\n\n'
          '文件：${node.displayName}\n'
          '大小：${_formatBytes(node.sizeBytes)}\n\n'
          '确认后会创建服务端下载请求，并进入传输中心。下载完成后会校验 hash，'
          '再登记为本设备本地副本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.download),
            label: const Text('选择位置并下载'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '保存云盘文件副本',
      fileName: node.displayName,
    );
    if (targetPath == null || targetPath.trim().isEmpty) {
      return;
    }

    final api = await ref.read(fileContextApiProvider.future);
    final request = await api.createDownloadRequest(
      nodeId: node.remoteId!,
      targetPath: targetPath,
    );
    if (request['ok'] != true) {
      throw StateError(request['reason']?.toString() ?? '创建下载请求失败');
    }

    final transferService = ref.read(fileTransferServiceProvider);
    unawaited(
      transferService
          .downloadPreparedSession(
        Map<String, Object?>.from(request),
        targetPath,
      )
          .then((job) async {
        final identity = await const LocalFileIdentityService().identify(
          job.localPath,
        );
        if (identity == null) {
          return;
        }
        await api.upsertDeviceLocation(
          nodeId: node.remoteId!,
          localPath: job.localPath,
          metadata: <String, Object?>{
            'source': 'drive_download_completed',
            'transferJobId': job.id,
            'identity': identity.toJson(storageObjectId: job.storageObjectId),
          },
        );
      }).catchError((Object error) {
        // 传输中心会保留失败状态；这里避免后台 Future 变成未处理异常。
        debugPrint('云盘文件下载失败：$error');
      }),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已创建下载任务，正在进入传输中心。')),
    );
    context.go(AppRoutes.fileTransfers);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('文件打开/下载失败：$error')),
    );
  }
}

String _formatBytes(int? value) {
  final bytes = value ?? 0;
  if (bytes <= 0) return '未知';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.selected,
    required this.onTap,
    required this.onSelect,
    required this.onOpen,
    required this.onReveal,
  });

  final FileNode node;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final Future<void> Function() onOpen;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final exists = _localPathExists(node.localPath);
    final remoteOnly = !exists && node.availability == FileAvailability.remoteOnly;
    final canAskServerOpenPlan = node.isFile && node.remoteId != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selected
          ? Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: 0.55)
          : null,
      child: ListTile(
        leading: Icon(
          remoteOnly
              ? Icons.cloud_outlined
              : !exists
                  ? Icons.report_problem_outlined
                  : node.isFolder
                      ? Icons.folder_outlined
                      : _iconForNode(node),
        ),
        title: Text(node.displayName),
        subtitle: Text(
          !exists ? '路径失效：${node.localPath}' : node.relativePath,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        selected: selected,
        onTap: onTap,
        onLongPress: onReveal,
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: '选中',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: onSelect,
            ),
            IconButton(
              tooltip: node.isFolder ? '打开文件夹' : '系统默认打开',
              icon: const Icon(Icons.open_in_new),
              onPressed: exists || canAskServerOpenPlan ? onOpen : null,
            ),
            IconButton(
              tooltip: '在资源管理器中显示',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: exists ? onReveal : null,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForNode(FileNode node) {
    final mime = node.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('text/') || mime == 'application/json') {
      return Icons.description_outlined;
    }
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _NodePreviewHost extends ConsumerWidget {
  const _NodePreviewHost({
    required this.root,
    required this.selectedNodeId,
    required this.onRelocateRoot,
  });

  final FileFolder root;
  final int? selectedNodeId;
  final VoidCallback onRelocateRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeId = selectedNodeId;
    if (nodeId == null) {
      return const Center(child: Text('选择文件或文件夹查看详情。'));
    }
    return FutureBuilder<FileNode?>(
      future: ref.read(fileContextRepositoryProvider).getNodeById(nodeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final node = snapshot.data;
        if (node == null) {
          return const Center(child: Text('选中的文件节点不存在。'));
        }
        return _NodePreviewPane(
          root: root,
          node: node,
          onRelocateRoot: onRelocateRoot,
        );
      },
    );
  }
}

class _NodePreviewPane extends ConsumerWidget {
  const _NodePreviewPane({
    required this.root,
    required this.node,
    required this.onRelocateRoot,
  });

  final FileFolder root;
  final FileNode node;
  final VoidCallback onRelocateRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interaction = ref.read(fileContextInteractionServiceProvider);
    final exists = _localPathExists(node.localPath);
    final canAskServerOpenPlan = node.isFile && node.remoteId != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                node.displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            IconButton(
              tooltip: node.isFolder ? '打开文件夹' : '系统默认打开',
              icon: const Icon(Icons.open_in_new),
              onPressed: exists || canAskServerOpenPlan
                  ? () => _openOrDownloadNode(context, ref, node)
                  : null,
            ),
            IconButton(
              tooltip: '在资源管理器中显示',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: exists ? () => interaction.revealNode(node) : null,
            ),
          ],
        ),
        Text(node.localPath, style: Theme.of(context).textTheme.bodySmall),
        if (node.isFile) ...[
          const SizedBox(height: 12),
          _ServerStorageAndVersionPane(node: node),
        ],
        const SizedBox(height: 12),
        if (!exists)
          _WarningBox(
            message: '该节点路径失效。请重新定位 Root「${root.displayName}」后重新扫描。',
            actionLabel: '重新定位 Root',
            onAction: onRelocateRoot,
          )
        else if (node.isFolder)
          const _EmptyNotice(message: '这是文件夹。可在左侧进入子目录，或调用系统打开。')
        else if (_isImageNode(node))
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(node.localPath),
              fit: BoxFit.contain,
              errorBuilder: (_, error, __) => Text('图片预览失败：$error'),
            ),
          )
        else if (_isTextNode(node))
          _NodeTextPreviewEditor(node: node)
        else if (node.mimeType == 'application/pdf')
          _WarningBox(
            message: 'PDF 暂不内置预览，可调用系统默认程序打开。',
            actionLabel: '打开 PDF',
            onAction: () => interaction.openNode(node),
          )
        else
          const _EmptyNotice(
            message: '当前文件类型暂不支持内置预览，可调用系统默认程序打开。',
          ),
      ],
    );
  }

  bool _isImageNode(FileNode node) => node.mimeType?.startsWith('image/') == true;

  bool _isTextNode(FileNode node) {
    final mime = node.mimeType;
    return mime?.startsWith('text/') == true || mime == 'application/json';
  }
}

class _ServerStorageAndVersionPane extends ConsumerStatefulWidget {
  const _ServerStorageAndVersionPane({required this.node});

  final FileNode node;

  @override
  ConsumerState<_ServerStorageAndVersionPane> createState() =>
      _ServerStorageAndVersionPaneState();
}

class _ServerStorageAndVersionPaneState
    extends ConsumerState<_ServerStorageAndVersionPane> {
  late Future<_ServerFileState> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ServerStorageAndVersionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ServerFileState>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_done_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '服务端存储与历史版本',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    IconButton(
                      tooltip: '刷新状态',
                      onPressed: _busy ? null : _reload,
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data == null
                      ? '正在读取服务端状态'
                      : '存储目录：${data.storageRoot ?? '未返回'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (data?.storageObjects.isEmpty ?? true)
                  const Text('当前文件尚未登记为服务端存储对象。')
                else
                  ...data!.storageObjects.map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(item['displayName']?.toString() ?? 'server object'),
                      subtitle: Text(
                        '对象 ${item['storageObjectId']} · ${item['status'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _registerStorageObject,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('登记到服务端'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _refreshVersions,
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('刷新历史版本'),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (data?.versions.isEmpty ?? true)
                  const Text('尚未读取到 Kopia 历史版本。请先对资料库 Root 创建快照。')
                else
                  ...data!.versions.map(_versionTile),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _versionTile(Map<String, dynamic> version) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.restore_page_outlined),
      title: Text(version['displayName']?.toString() ?? 'Kopia version'),
      subtitle: Text(
        [
          version['modifiedAt']?.toString(),
          version['sizeBytes'] == null ? null : '${version['sizeBytes']} bytes',
          version['versionRef']?.toString(),
        ].whereType<String>().where((item) => item.isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: '下载为副本',
            onPressed: _busy ? null : () => _downloadVersionCopy(version),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '准备恢复（不执行覆盖）',
            onPressed: _busy ? null : () => _prepareRestore(version),
            icon: const Icon(Icons.rule_folder_outlined),
          ),
        ],
      ),
    );
  }

  Future<_ServerFileState> _load() async {
    final api = await ref.read(fileCloudApiProvider.future);
    final results = await Future.wait([
      api.storageStatus(),
      api.storageObjects(
        localPath: widget.node.localPath.trim().isEmpty ? null : widget.node.localPath,
        nodeId: widget.node.remoteId,
      ),
      api.versions(widget.node.id.toString()),
    ]);
    return _ServerFileState.fromApi(results[0], results[1], results[2]);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _registerStorageObject() async {
    await _runBusy(() async {
      final api = await ref.read(fileCloudApiProvider.future);
      final result = await api.registerStorageObject(
        localPath: widget.node.localPath,
        fileName: widget.node.displayName,
        fileNodeId: widget.node.remoteId,
        metadata: <String, Object?>{
          'fileNodeId': widget.node.id,
          'serverFileNodeId': widget.node.remoteId,
          'rootFolderId': widget.node.rootFolderId,
        },
      );
      if (result['ok'] != true) {
        throw StateError(result['reason']?.toString() ?? '登记失败');
      }
      _reload();
      _snack('已登记为服务端存储对象');
    });
  }

  Future<void> _refreshVersions() async {
    await _runBusy(() async {
      final api = await ref.read(fileCloudApiProvider.future);
      final result = await api.refreshKopiaVersions(
        fileId: widget.node.id.toString(),
        filePath: widget.node.localPath,
        displayName: widget.node.displayName,
      );
      if (result['ok'] != true) {
        throw StateError(result['reason']?.toString() ?? '刷新历史版本失败');
      }
      _reload();
      _snack('历史版本已刷新');
    });
  }

  Future<void> _downloadVersionCopy(Map<String, dynamic> version) async {
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '下载历史版本副本',
      fileName: '${p.basenameWithoutExtension(widget.node.displayName)}.kopia-copy${p.extension(widget.node.displayName)}',
    );
    if (targetPath == null || targetPath.trim().isEmpty) {
      return;
    }
    await _runBusy(() async {
      final api = await ref.read(fileCloudApiProvider.future);
      final result = await api.downloadVersionCopy(
        versionId: version['id'].toString(),
        targetPath: targetPath,
        auditNote: '用户从文件详情下载历史版本副本',
      );
      if (result['ok'] != true) {
        throw StateError(result['reason']?.toString() ?? '下载副本失败');
      }
      _reload();
      _snack('历史版本已下载为副本');
    });
  }

  Future<void> _prepareRestore(Map<String, dynamic> version) async {
    await _runBusy(() async {
      final api = await ref.read(fileCloudApiProvider.future);
      final result = await api.prepareVersionRestore(
        versionId: version['id'].toString(),
        targetPath: widget.node.localPath,
      );
      if (result['ok'] != true) {
        throw StateError(result['reason']?.toString() ?? '准备恢复失败');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复旧版本需要二次确认'),
          content: SelectableText(
            '本次只生成 prepare，不会覆盖当前文件。\n\n${result['prepare']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ServerFileState {
  const _ServerFileState({
    required this.storageRoot,
    required this.storageObjects,
    required this.versions,
  });

  final String? storageRoot;
  final List<Map<String, dynamic>> storageObjects;
  final List<Map<String, dynamic>> versions;

  factory _ServerFileState.fromApi(
    Map<String, dynamic> status,
    Map<String, dynamic> objects,
    Map<String, dynamic> versions,
  ) {
    return _ServerFileState(
      storageRoot: status['rootPath']?.toString(),
      storageObjects: _mapList(objects['storageObjects']),
      versions: _mapList(versions['versions']),
    );
  }
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

bool _localPathExists(String path) {
  if (path.trim().isEmpty) {
    return false;
  }
  return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
}

class _NodeTextPreviewEditor extends ConsumerStatefulWidget {
  const _NodeTextPreviewEditor({required this.node});

  final FileNode node;

  @override
  ConsumerState<_NodeTextPreviewEditor> createState() =>
      _NodeTextPreviewEditorState();
}

class _NodeTextPreviewEditorState extends ConsumerState<_NodeTextPreviewEditor> {
  late Future<FilePreviewResult> _future;
  final _controller = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future =
        ref.read(fileContextInteractionServiceProvider).previewTextNode(widget.node);
  }

  @override
  void didUpdateWidget(covariant _NodeTextPreviewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _loaded = false;
      _future = ref
          .read(fileContextInteractionServiceProvider)
          .previewTextNode(widget.node);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FilePreviewResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        final result = snapshot.data;
        if (result == null || !result.canPreview) {
          return _EmptyNotice(message: result?.message ?? '无法预览');
        }
        if (!_loaded) {
          _controller.text = result.content ?? '';
          _loaded = true;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('文本/Markdown 预览')),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存修改'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              minLines: 14,
              maxLines: 28,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              '为避免卡顿，仅轻量读取文件开头内容。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(fileContextInteractionServiceProvider)
          .saveTextNode(widget.node, _controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已保存并记录操作日志')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _EmptyTree extends StatelessWidget {
  const _EmptyTree({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onScan,
        icon: const Icon(Icons.refresh),
        label: const Text('扫描资料库生成文件树'),
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.action,
  });

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _EmptyFirstRun extends StatelessWidget {
  const _EmptyFirstRun({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('添加第一个资料库 Root'),
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(message),
    );
  }
}
