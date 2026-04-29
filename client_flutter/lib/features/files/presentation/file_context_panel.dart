import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/app_providers.dart';
import '../data/file_context_repository.dart';

class EntityFileContextPanel extends ConsumerStatefulWidget {
  const EntityFileContextPanel({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.title,
    this.description,
    this.location,
  });

  final String entityType;
  final String entityId;
  final String title;
  final String? description;
  final String? location;

  @override
  ConsumerState<EntityFileContextPanel> createState() =>
      _EntityFileContextPanelState();
}

class _EntityFileContextPanelState extends ConsumerState<EntityFileContextPanel> {
  late Future<_FileContextPanelData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant EntityFileContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityType != widget.entityType ||
        oldWidget.entityId != widget.entityId ||
        oldWidget.title != widget.title ||
        oldWidget.description != widget.description ||
        oldWidget.location != widget.location) {
      _future = _load();
    }
  }

  Future<_FileContextPanelData> _load() async {
    final repo = ref.read(fileContextRepositoryProvider);
    await repo.ensureFolderRecommendations(
      entityType: widget.entityType,
      entityId: widget.entityId,
      title: widget.title,
      description: widget.description,
      location: widget.location,
    );
    final links = await repo.listLinksForEntity(
      entityType: widget.entityType,
      entityId: widget.entityId,
    );
    final folders = <int, FileFolder>{};
    final nodes = <int, FileNode>{};
    for (final link in links) {
      if (link.targetType == FileContextTargetType.folder) {
        final folder = await repo.getFolderById(link.targetId);
        if (folder != null) folders[link.targetId] = folder;
      } else if (link.targetType == FileContextTargetType.fileNode ||
          link.targetType == FileContextTargetType.folderNode) {
        final node = await repo.getNodeById(link.targetId);
        if (node != null) nodes[link.targetId] = node;
      }
    }
    return _FileContextPanelData(
      links: links,
      folders: folders,
      nodes: nodes,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FileContextPanelData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '文件上下文',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: '绑定文件树节点',
                  icon: const Icon(Icons.account_tree_outlined),
                  onPressed: _bindNode,
                ),
                IconButton(
                  tooltip: '添加本地文件夹',
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: _addFolder,
                ),
                IconButton(
                  tooltip: '刷新推荐',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              Text('文件上下文读取失败：${snapshot.error}')
            else if (data == null || data.links.isEmpty)
              const Text(
                '暂时没有关联文件。可绑定文件中心中的文件/文件夹节点，或先在文件中心添加资料库 Root。',
                style: TextStyle(fontSize: 13),
              )
            else
              ...data.links.map((link) {
                if (link.targetType == FileContextTargetType.folder) {
                  final folder = data.folders[link.targetId];
                  if (folder == null) {
                    return _MissingLinkTile(link: link);
                  }
                  return _FolderLinkTile(
                    link: link,
                    folder: folder,
                    entityType: widget.entityType,
                    entityId: widget.entityId,
                    onChanged: _refresh,
                  );
                }
                if (link.targetType == FileContextTargetType.fileNode ||
                    link.targetType == FileContextTargetType.folderNode) {
                  final node = data.nodes[link.targetId];
                  if (node == null) {
                    return _MissingLinkTile(link: link);
                  }
                  return _NodeLinkTile(
                    link: link,
                    node: node,
                    entityType: widget.entityType,
                    entityId: widget.entityId,
                    onChanged: _refresh,
                  );
                }
                return _MissingLinkTile(link: link);
              }),
          ],
        );
      },
    );
  }

  Future<void> _bindNode() async {
    final repo = ref.read(fileContextRepositoryProvider);
    final node = await showDialog<FileNode>(
      context: context,
      builder: (dialogContext) => _FileNodePickerDialog(repo: repo),
    );
    if (node == null || !mounted) {
      return;
    }
    await repo.bindNodeToEntity(
      entityType: widget.entityType,
      entityId: widget.entityId,
      node: node,
      reason: '${_entityLabel(widget.entityType)}详情手动绑定',
    );
    await repo.recordFileNodeOperation(
      node: node,
      action: 'bind_file_node',
      entityType: widget.entityType,
      entityId: widget.entityId,
    );
    _refresh();
  }

  Future<void> _addFolder() async {
    final controller = TextEditingController();
    final sourceController = TextEditingController(text: widget.title);
    final result = await showDialog<_FolderInput>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('添加本地文件夹'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '文件夹路径',
                  hintText: r'C:\Users\...\Documents\Project',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sourceController,
                decoration: const InputDecoration(labelText: '上下文备注'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final path = controller.text.trim();
                if (path.isEmpty) return;
                Navigator.of(dialogContext).pop(
                  _FolderInput(
                    path: path,
                    sourceContext: sourceController.text.trim(),
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    sourceController.dispose();
    if (result == null || !mounted) {
      return;
    }
    final repo = ref.read(fileContextRepositoryProvider);
    final folder = await repo.upsertLocalFolder(
      localPath: result.path,
      sourceContext: result.sourceContext.isEmpty ? null : result.sourceContext,
      pinned: true,
    );
    if (widget.entityType == FileContextEntityType.task) {
      await repo.bindFolderToTask(
        taskId: int.parse(widget.entityId),
        folderId: folder.id,
        reason: '任务详情手动绑定',
      );
    } else if (widget.entityType == FileContextEntityType.event) {
      await repo.bindFolderToEvent(
        eventId: int.parse(widget.entityId),
        folderId: folder.id,
        reason: '日程详情手动绑定',
      );
    } else {
      await repo.createRecommendationLink(
        entityType: widget.entityType,
        entityId: widget.entityId,
        folderId: folder.id,
        confidence: 1,
        reason: '手动添加',
      );
    }
    _refresh();
  }

  String _entityLabel(String entityType) {
    switch (entityType) {
      case FileContextEntityType.task:
        return '任务';
      case FileContextEntityType.event:
        return '日程';
      default:
        return '对象';
    }
  }
}

class _FolderLinkTile extends ConsumerWidget {
  const _FolderLinkTile({
    required this.link,
    required this.folder,
    required this.entityType,
    required this.entityId,
    required this.onChanged,
  });

  final FileContextLink link;
  final FileFolder folder;
  final String entityType;
  final String entityId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCandidate = link.status == FileContextStatus.candidate;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isCandidate ? Icons.lightbulb_outline : Icons.folder_outlined,
        ),
        title: Text(folder.displayName),
        subtitle: Text(
          [
            folder.localPath ?? folder.remoteId ?? folder.provider,
            if (link.reason != null) link.reason!,
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: link.reason != null,
        trailing: Wrap(
          spacing: 4,
          children: [
            if (isCandidate)
              IconButton(
                tooltip: '确认关联',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () async {
                  await ref.read(fileContextRepositoryProvider).confirmLink(link.id);
                  onChanged();
                },
              ),
            IconButton(
              tooltip: '打开',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => ref
                  .read(fileContextInteractionServiceProvider)
                  .openFolder(
                    folder,
                    entityType: entityType,
                    entityId: entityId,
                  ),
            ),
            IconButton(
              tooltip: '在资源管理器中定位',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () => ref
                  .read(fileContextInteractionServiceProvider)
                  .revealFolder(
                    folder,
                    entityType: entityType,
                    entityId: entityId,
                  ),
            ),
          ],
        ),
        onLongPress: () => ref
            .read(fileContextInteractionServiceProvider)
            .revealFolder(
              folder,
              entityType: entityType,
              entityId: entityId,
            ),
      ),
    );
  }
}

class _NodeLinkTile extends ConsumerWidget {
  const _NodeLinkTile({
    required this.link,
    required this.node,
    required this.entityType,
    required this.entityId,
    required this.onChanged,
  });

  final FileContextLink link;
  final FileNode node;
  final String entityType;
  final String entityId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCandidate = link.status == FileContextStatus.candidate;
    final exists = FileSystemEntity.typeSync(node.localPath) !=
        FileSystemEntityType.notFound;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          !exists
              ? Icons.report_problem_outlined
              : node.isFolder
                  ? Icons.folder_outlined
                  : Icons.insert_drive_file_outlined,
        ),
        title: Text(node.displayName),
        subtitle: Text(
          [
            exists ? node.relativePath : '路径失效：${node.localPath}',
            if (link.reason != null) link.reason!,
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: link.reason != null,
        trailing: Wrap(
          spacing: 4,
          children: [
            if (isCandidate)
              IconButton(
                tooltip: '确认关联',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () async {
                  await ref.read(fileContextRepositoryProvider).confirmLink(link.id);
                  onChanged();
                },
              ),
            IconButton(
              tooltip: '打开',
              icon: const Icon(Icons.open_in_new),
              onPressed: exists
                  ? () => ref
                      .read(fileContextInteractionServiceProvider)
                      .openNode(
                        node,
                        entityType: entityType,
                        entityId: entityId,
                      )
                  : null,
            ),
            IconButton(
              tooltip: '在资源管理器中定位',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: exists
                  ? () => ref
                      .read(fileContextInteractionServiceProvider)
                      .revealNode(
                        node,
                        entityType: entityType,
                        entityId: entityId,
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FileNodePickerDialog extends StatefulWidget {
  const _FileNodePickerDialog({required this.repo});

  final FileContextRepository repo;

  @override
  State<_FileNodePickerDialog> createState() => _FileNodePickerDialogState();
}

class _FileNodePickerDialogState extends State<_FileNodePickerDialog> {
  late Future<List<FileFolder>> _rootsFuture;
  int? _selectedRootId;
  int? _currentFolderNodeId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _rootsFuture = widget.repo.listFolders(limit: 200);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('绑定文件树节点'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: FutureBuilder<List<FileFolder>>(
          future: _rootsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final roots = snapshot.data ?? const <FileFolder>[];
            if (roots.isEmpty) {
              return const Center(child: Text('还没有资料库 Root。请先到文件中心添加并扫描。'));
            }
            _selectedRootId ??= roots.first.id;
            final selectedRoot = roots.firstWhere(
              (root) => root.id == _selectedRootId,
              orElse: () => roots.first,
            );
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedRoot.id,
                        decoration: const InputDecoration(
                          labelText: '资料库 Root',
                          border: OutlineInputBorder(),
                        ),
                        items: roots
                            .map(
                              (root) => DropdownMenuItem<int>(
                                value: root.id,
                                child: Text(
                                  root.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRootId = value;
                            _currentFolderNodeId = null;
                            _query = '';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '返回上级',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: _currentFolderNodeId == null ? null : _goUp,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: '搜索文件名',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<_PickerData>(
                    future: _loadNodes(selectedRoot),
                    builder: (context, nodeSnapshot) {
                      if (nodeSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (nodeSnapshot.hasError) {
                        return Center(
                          child: Text('文件树读取失败：${nodeSnapshot.error}'),
                        );
                      }
                      final data = nodeSnapshot.data;
                      if (data == null || data.rootNode == null) {
                        return const Center(
                          child: Text('该 Root 尚未扫描。请先到文件中心扫描生成文件树。'),
                        );
                      }
                      if (data.nodes.isEmpty) {
                        return const Center(child: Text('没有可绑定的节点。'));
                      }
                      return ListView.builder(
                        itemCount: data.nodes.length,
                        itemBuilder: (context, index) {
                          final node = data.nodes[index];
                          return ListTile(
                            leading: Icon(node.isFolder
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined),
                            title: Text(node.displayName),
                            subtitle: Text(
                              node.relativePath.isEmpty
                                  ? node.localPath
                                  : node.relativePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              if (node.isFolder && _query.trim().isEmpty) {
                                setState(() => _currentFolderNodeId = node.id);
                              }
                            },
                            trailing: TextButton(
                              onPressed: () => Navigator.of(context).pop(node),
                              child: const Text('绑定'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Future<_PickerData> _loadNodes(FileFolder root) async {
    final rootNode = await widget.repo.getRootNode(root.id);
    if (rootNode == null) {
      return const _PickerData(rootNode: null, nodes: []);
    }
    final trimmedQuery = _query.trim();
    if (trimmedQuery.isNotEmpty) {
      final nodes = await widget.repo.searchNodes(
        rootFolderId: root.id,
        query: trimmedQuery,
      );
      return _PickerData(rootNode: rootNode, nodes: nodes);
    }
    final current = _currentFolderNodeId == null
        ? rootNode
        : await widget.repo.getNodeById(_currentFolderNodeId!);
    final nodes = await widget.repo.listChildNodes(
      rootFolderId: root.id,
      parentNodeId: current?.id ?? rootNode.id,
    );
    return _PickerData(rootNode: rootNode, nodes: nodes);
  }

  Future<void> _goUp() async {
    final currentId = _currentFolderNodeId;
    if (currentId == null) return;
    final current = await widget.repo.getNodeById(currentId);
    if (!mounted || current == null) return;
    setState(() => _currentFolderNodeId = current.parentNodeId);
  }
}

class _PickerData {
  const _PickerData({
    required this.rootNode,
    required this.nodes,
  });

  final FileNode? rootNode;
  final List<FileNode> nodes;
}

class _MissingLinkTile extends StatelessWidget {
  const _MissingLinkTile({required this.link});

  final FileContextLink link;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.report_problem_outlined),
        title: const Text('关联目标不存在'),
        subtitle: Text('${link.targetType} #${link.targetId}'),
      ),
    );
  }
}

class _FileContextPanelData {
  const _FileContextPanelData({
    required this.links,
    required this.folders,
    required this.nodes,
  });

  final List<FileContextLink> links;
  final Map<int, FileFolder> folders;
  final Map<int, FileNode> nodes;
}

class _FolderInput {
  const _FolderInput({
    required this.path,
    required this.sourceContext,
  });

  final String path;
  final String sourceContext;
}
