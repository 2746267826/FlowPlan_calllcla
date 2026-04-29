// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'web_api_client.dart';
import 'web_local_store.dart';

class FlowPlanWebApp extends StatelessWidget {
  const FlowPlanWebApp({super.key, required this.store});

  final WebLocalStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FlowPlan',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
      home: _UserShell(store: store),
    );
  }
}

class _UserShell extends StatefulWidget {
  const _UserShell({required this.store});

  final WebLocalStore store;

  @override
  State<_UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<_UserShell> {
  late final api = WebApiClient(widget.store);
  int index = 0;
  _ConnectionState connection = const _ConnectionState();
  Timer? heartbeatTimer;

  final pages = const [
    _NavItem('今日', Icons.today_outlined),
    _NavItem('日程', Icons.calendar_month_outlined),
    _NavItem('任务', Icons.checklist_outlined),
    _NavItem('文件', Icons.folder_outlined),
    _NavItem('追踪', Icons.query_stats_outlined),
    _NavItem('报告', Icons.article_outlined),
    _NavItem('设置', Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshConnection());
  }

  @override
  void dispose() {
    heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshConnection() async {
    try {
      final bootstrap = await api.getJson('/client/bootstrap');
      await _sendHeartbeat(source: 'bootstrap');
      await widget.store.setLastBootstrap(bootstrap);
      if (!mounted) return;
      setState(() {
        connection = _ConnectionState(
          online: true,
          serverTime: '${bootstrap['serverTime'] ?? ''}',
          deviceId: '${_asMap(bootstrap['device'])['clientDeviceId'] ?? widget.store.deviceId ?? ''}',
          lastHeartbeatAt: DateTime.now(),
          error: '',
        );
      });
      _scheduleHeartbeat();
    } catch (error) {
      final cached = widget.store.readLastBootstrap();
      if (!mounted) return;
      setState(() {
        connection = _ConnectionState(
          online: false,
          serverTime: '${cached?['serverTime'] ?? ''}',
          deviceId: widget.store.deviceId ?? '',
          error: '$error',
        );
      });
      _scheduleHeartbeat(seconds: 60);
    }
  }

  Future<void> _sendHeartbeat({String source = 'timer'}) {
    final deviceId = widget.store.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return Future<void>.value();
    }
    return api.postJson(
      '/devices/${Uri.encodeComponent(deviceId)}/heartbeat',
      body: {
        'clientTime': DateTime.now().toIso8601String(),
        'appVersion': 'web',
        'platform': 'web',
        'networkType': 'browser',
        'networkSummary': {'source': source},
        'syncSummary': {
          'pendingCount': 0,
          'failedCount': 0,
          'conflictCount': 0,
        },
      },
    ).then((response) {
      if (!mounted) return;
      setState(() {
        connection = _ConnectionState(
          online: true,
          serverTime: '${response['serverTime'] ?? connection.serverTime}',
          deviceId: deviceId,
          lastHeartbeatAt: DateTime.now(),
          error: '',
        );
      });
    });
  }

  void _scheduleHeartbeat({int seconds = 30}) {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer(Duration(seconds: seconds), () {
      unawaited(_sendHeartbeat().then((_) => _scheduleHeartbeat()).catchError((error) {
        if (mounted) {
          setState(() {
            connection = _ConnectionState(
              online: false,
              serverTime: connection.serverTime,
              deviceId: widget.store.deviceId ?? connection.deviceId,
              error: '$error',
            );
          });
        }
        _scheduleHeartbeat(seconds: 60);
      }));
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (index) {
      0 => _TodayPage(api: api, onConnectionRefresh: _refreshConnection),
      1 => _EventsPage(api: api),
      2 => _TasksPage(api: api),
      3 => _DrivePage(api: api),
      4 => _TrackingPage(api: api),
      5 => _ReportsPage(api: api),
      _ => _SettingsPage(
          api: api,
          store: widget.store,
          connection: connection,
          onConnectionRefresh: _refreshConnection,
        ),
    };
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            minWidth: 82,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: [
              for (final page in pages)
                NavigationRailDestination(
                  icon: Icon(page.icon),
                  selectedIcon: Icon(page.icon),
                  label: Text(page.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _AppHeader(
                  title: pages[index].label,
                  connection: connection,
                  onRefresh: _refreshConnection,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayPage extends StatefulWidget {
  const _TodayPage({
    required this.api,
    required this.onConnectionRefresh,
  });

  final WebApiClient api;
  final Future<void> Function() onConnectionRefresh;

  @override
  State<_TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<_TodayPage> {
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    await widget.onConnectionRefresh();
    return widget.api.getJson('/web/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncPage(
      future: future,
      onRefresh: () {
        setState(() {
          future = _load();
        });
      },
      builder: (context, data) {
        final today = _asMap(data['today']);
        final lists = _asMap(data['lists']);
        final sync = _asMap(data['sync']);
        final current = _asMap(today['current']);
        final next = _asMap(today['next']);
        return _PageBody(
          title: '今日工作台',
          subtitle: '打开浏览器也能继续查看日程、任务和实际记录。',
          actions: [
            _StatusChip(
              label: '待同步 ${sync['pendingMutations'] ?? 0}',
              tone: ((sync['pendingMutations'] as num?) ?? 0) > 0
                  ? _ChipTone.warning
                  : _ChipTone.normal,
            ),
            _StatusChip(
              label: '冲突 ${sync['openConflicts'] ?? 0}',
              tone: ((sync['openConflicts'] as num?) ?? 0) > 0
                  ? _ChipTone.danger
                  : _ChipTone.normal,
            ),
          ],
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _FocusPanel(
                      current: current.isEmpty ? null : current,
                      next: next.isEmpty ? null : next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 320,
                    child: _SummaryPanel(
                      tasks: _mapList(today['tasks']).length,
                      events: _mapList(today['events']).length,
                      actuals: _mapList(today['actualRecords']).length,
                      reminders: _mapList(lists['reminders']).length,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TwoColumn(
                left: _ItemSection(
                  title: '今日任务',
                  emptyText: '今天没有截止任务。',
                  items: _mapList(today['tasks']).isEmpty
                      ? _mapList(lists['openTasks']).take(8).toList()
                      : _mapList(today['tasks']),
                  columns: const ['标题', '状态', '截止', '地点'],
                  row: (item) => [
                    item['title'],
                    item['status'],
                    item['dueAt'],
                    item['location'],
                  ],
                ),
                right: _ItemSection(
                  title: '今日日程',
                  emptyText: '今天没有日程。',
                  items: _mapList(today['events']),
                  columns: const ['标题', '开始', '结束', '地点'],
                  row: (item) => [
                    item['title'],
                    item['startAt'],
                    item['endAt'],
                    item['location'],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ItemSection(
                title: '今日实际记录',
                emptyText: '还没有确认的实际记录。',
                items: _mapList(today['actualRecords']),
                columns: const ['标题', '开始', '结束', '状态'],
                row: (item) => [
                  item['title'],
                  item['startAt'],
                  item['endAt'],
                  item['status'],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TasksPage extends StatefulWidget {
  const _TasksPage({required this.api});

  final WebApiClient api;

  @override
  State<_TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<_TasksPage> {
  late Future<List<Map<String, dynamic>>> future = _load();
  String query = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final result = await widget.api.getJson('/web/tasks', query: {'q': query});
    return _mapList(result['items']);
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final result = await _editDialog(
      context,
      title: item == null ? '新建任务' : '编辑任务',
      fields: {
        'title': ['标题', '${item?['title'] ?? ''}'],
        'status': ['状态', '${item?['status'] ?? 'todo'}'],
        'dueAt': ['截止时间', '${item?['dueAt'] ?? ''}'],
        'location': ['地点', '${item?['location'] ?? ''}'],
        'notes': ['备注', '${_asMap(item?['payload'])['notes'] ?? ''}'],
      },
    );
    if (result == null) return;
    if (item == null) {
      await widget.api.postJson('/web/tasks', body: result);
    } else {
      await widget.api.patchJson('/web/tasks/${item['id']}', body: result);
    }
    setState(() {
      future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ListPage(
      title: '任务',
      subtitle: '查看和编辑服务端任务。Web 端不做离线事实写入。',
      searchHint: '搜索任务标题或地点',
      query: query,
      onQueryChanged: (value) => query = value,
      onRefresh: () {
        setState(() {
          future = _load();
        });
      },
      action: FilledButton.icon(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新建任务'),
      ),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          return _ItemSection(
            title: '任务列表',
            emptyText: '没有任务。',
            items: snapshot.data ?? const [],
            loading: snapshot.connectionState != ConnectionState.done,
            columns: const ['标题', '状态', '截止', '地点', '操作'],
            row: (item) => [
              item['title'],
              item['status'],
              item['dueAt'],
              item['location'],
              TextButton(onPressed: () => _edit(item), child: const Text('编辑')),
            ],
          );
        },
      ),
    );
  }
}

class _EventsPage extends StatefulWidget {
  const _EventsPage({required this.api});

  final WebApiClient api;

  @override
  State<_EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<_EventsPage> {
  late Future<List<Map<String, dynamic>>> future = _load();
  String query = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final result = await widget.api.getJson('/web/events', query: {'q': query});
    return _mapList(result['items']);
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final result = await _editDialog(
      context,
      title: item == null ? '新建日程' : '编辑日程',
      fields: {
        'title': ['标题', '${item?['title'] ?? ''}'],
        'startAt': ['开始时间', '${item?['startAt'] ?? ''}'],
        'endAt': ['结束时间', '${item?['endAt'] ?? ''}'],
        'location': ['地点', '${item?['location'] ?? ''}'],
        'status': ['状态', '${item?['status'] ?? 'confirmed'}'],
      },
    );
    if (result == null) return;
    if (item == null) {
      await widget.api.postJson('/web/events', body: result);
    } else {
      await widget.api.patchJson('/web/events/${item['id']}', body: result);
    }
    setState(() {
      future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ListPage(
      title: '日程',
      subtitle: '浏览和编辑服务端日程，地点会作为一等字段展示。',
      searchHint: '搜索日程标题或地点',
      query: query,
      onQueryChanged: (value) => query = value,
      onRefresh: () {
        setState(() {
          future = _load();
        });
      },
      action: FilledButton.icon(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新建日程'),
      ),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          return _ItemSection(
            title: '日程列表',
            emptyText: '没有日程。',
            items: snapshot.data ?? const [],
            loading: snapshot.connectionState != ConnectionState.done,
            columns: const ['标题', '开始', '结束', '地点', '操作'],
            row: (item) => [
              item['title'],
              item['startAt'],
              item['endAt'],
              item['location'],
              TextButton(onPressed: () => _edit(item), child: const Text('编辑')),
            ],
          );
        },
      ),
    );
  }
}

class _DrivePage extends StatefulWidget {
  const _DrivePage({required this.api});

  final WebApiClient api;

  @override
  State<_DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<_DrivePage> {
  List<Map<String, dynamic>> roots = [];
  List<Map<String, dynamic>> nodes = [];
  final path = <Map<String, dynamic>>[];
  String? rootId;
  String? parentId;
  String query = '';
  String status = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final rootResult = await widget.api.getJson('/files/drive/roots');
      roots = _mapList(rootResult['roots']);
      rootId ??= roots.isNotEmpty ? '${roots.first['id']}' : null;
      if (rootId == null) {
        nodes = [];
        status = '还没有云盘 Root，可以先创建一个服务端云盘。';
      } else {
        final nodeResult = await widget.api.getJson('/files/drive/nodes', query: {
          'rootId': rootId,
          'parentId': parentId,
          'q': query,
          'limit': '300',
        });
        nodes = _mapList(nodeResult['nodes']);
        status = '已读取 ${nodes.length} 个文件节点';
      }
    } catch (error) {
      status = '$error';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _createRoot() async {
    await widget.api.postJson('/files/roots', body: {
      'rootUid': 'web-root',
      'name': 'FlowPlan 云盘',
      'providerType': 'server_storage',
      'rootUri': 'flowplan://server-storage/web-root',
      'rootDisplayPath': '服务端云盘',
      'isManaged': true,
      'syncPolicy': 'server_primary',
      'metadata': {'createdBy': 'flutter_web'},
    });
    await _load();
  }

  Future<void> _upload() async {
    if (rootId == null) {
      await _createRoot();
    }
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    const chunkSize = 768 * 1024;
    setState(() => status = '正在上传 ${file.name}');
    final sessionResult = await widget.api.postJson('/files/upload-sessions', body: {
      'providerKey': 'server_storage',
      'fileName': file.name,
      'totalBytes': bytes.length,
      'chunkSize': chunkSize,
      'metadata': {
        'rootId': rootId,
        'parentId': parentId,
        'nodeName': file.name,
        'source': 'flutter_web_upload',
      },
    });
    final session = _asMap(sessionResult['uploadSession']);
    final sessionId = '${session['sessionId']}';
    final expected = (session['expectedChunks'] as num?)?.toInt() ??
        ((bytes.length + chunkSize - 1) ~/ chunkSize);
    for (var index = 0; index < expected; index += 1) {
      final start = index * chunkSize;
      final end = (start + chunkSize > bytes.length) ? bytes.length : start + chunkSize;
      await widget.api.putJson('/files/upload-sessions/$sessionId/chunks/$index', body: {
        'payloadBase64': encodeBytes(Uint8List.sublistView(bytes, start, end)),
        'startByte': start,
        'endByte': end - 1,
      });
      setState(() => status = '上传中 ${index + 1}/$expected');
    }
    await widget.api.postJson('/files/upload-sessions/$sessionId/complete');
    setState(() => status = '上传完成：${file.name}');
    await _load();
  }

  Future<void> _download(Map<String, dynamic> node) async {
    final bytes = await _downloadNodeBytes(node, previewOnly: false);
    final blob = html.Blob(
      [bytes],
      '${node['mimeType'] ?? 'application/octet-stream'}',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = '${node['name'] ?? 'download'}'
      ..click();
    html.Url.revokeObjectUrl(url);
    setState(() => status = '已开始下载：${node['name']}');
  }

  Future<Uint8List> _downloadNodeBytes(
    Map<String, dynamic> node, {
    required bool previewOnly,
  }) async {
    final request = await widget.api.postJson(
      '/files/drive/nodes/${node['id']}/download-request',
      body: {'targetMode': previewOnly ? 'browser_preview' : 'browser_download'},
    );
    final session = _asMap(request['downloadSession']);
    final sessionId = '${session['sessionId']}';
    final total = (session['totalBytes'] as num?)?.toInt() ??
        (node['sizeBytes'] as num?)?.toInt() ??
        0;
    final chunkSize = (session['chunkSize'] as num?)?.toInt() ?? 768 * 1024;
    final targetBytes = previewOnly && total > 512 * 1024 ? 512 * 1024 : total;
    final chunks = <int>[];
    for (var start = 0; start < targetBytes || (targetBytes == 0 && start == 0); start += chunkSize) {
      final end = targetBytes == 0 ? chunkSize - 1 : (start + chunkSize - 1).clamp(0, targetBytes - 1);
      final range = await widget.api.getJson(
        '/files/download-sessions/$sessionId/range',
        query: {'start': '$start', 'end': '$end'},
      );
      for (final chunk in (range['chunks'] as List? ?? const [])) {
        final payload = _asMap(chunk)['payloadBase64'];
        if (payload is String) chunks.addAll(decodeBytes(payload));
      }
      if (targetBytes == 0) break;
    }
    return Uint8List.fromList(chunks);
  }

  Future<void> _open(Map<String, dynamic> node) async {
    if (node['nodeType'] == 'folder') {
      path.add(node);
      parentId = '${node['id']}';
      query = '';
      await _load();
      return;
    }
    final mime = '${node['mimeType'] ?? ''}';
    if (!(mime.startsWith('text/') || mime.contains('markdown') || mime.startsWith('image/'))) {
      await _download(node);
      return;
    }
    final bytes = await _downloadNodeBytes(node, previewOnly: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${node['name']}'),
        content: SizedBox(
          width: 760,
          height: 540,
          child: mime.startsWith('image/')
              ? Image.memory(bytes, fit: BoxFit.contain)
              : SingleChildScrollView(
                  child: SelectableText(utf8.decode(bytes, allowMalformed: true)),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_download(node));
            },
            child: const Text('下载'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      title: '文件',
      subtitle: '浏览服务端云盘；浏览器端不扫描本地目录。',
      actions: [
        OutlinedButton.icon(
          onPressed: _createRoot,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('创建 Root'),
        ),
        FilledButton.icon(
          onPressed: _upload,
          icon: const Icon(Icons.upload_file),
          label: const Text('上传'),
        ),
        IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
      scrollable: false,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: rootId,
                  decoration: const InputDecoration(labelText: '云盘 Root'),
                  items: [
                    for (final root in roots)
                      DropdownMenuItem(
                        value: '${root['id']}',
                        child: Text('${root['name'] ?? root['rootUid']}'),
                      ),
                  ],
                  onChanged: (value) {
                    rootId = value;
                    parentId = null;
                    path.clear();
                    unawaited(_load());
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '搜索文件名',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (value) {
                    query = value.trim();
                    unawaited(_load());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.home_outlined),
                label: const Text('Root'),
                onPressed: () {
                  path.clear();
                  parentId = null;
                  unawaited(_load());
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < path.length; i += 1)
                      ActionChip(
                        label: Text('${path[i]['name']}'),
                        onPressed: () {
                          path.removeRange(i + 1, path.length);
                          parentId = '${path[i]['id']}';
                          unawaited(_load());
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(status, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _ItemSection(
              title: '云盘文件',
              emptyText: '没有文件。',
              loading: loading,
              items: nodes,
              columns: const ['名称', '类型', '状态', '大小', '操作'],
              row: (item) => [
                item['name'],
                item['nodeType'],
                _StatusChip(label: '${item['availability'] ?? ''}'),
                _formatBytes(item['sizeBytes']),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: item['nodeType'] == 'folder' ? '进入' : '预览',
                      icon: Icon(item['nodeType'] == 'folder'
                          ? Icons.folder_open
                          : Icons.visibility_outlined),
                      onPressed: () => _open(item),
                    ),
                    if (item['nodeType'] != 'folder')
                      IconButton(
                        tooltip: '下载',
                        icon: const Icon(Icons.download),
                        onPressed: () => _download(item),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingPage extends StatefulWidget {
  const _TrackingPage({required this.api});

  final WebApiClient api;

  @override
  State<_TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<_TrackingPage> {
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    return {
      'summary': await _safe(() => widget.api.getJson('/analytics/activity-range-summary')),
      'apps': await _safe(() => widget.api.getJson('/analytics/top-apps')),
      'categories': await _safe(() => widget.api.getJson('/analytics/top-categories')),
      'work': await _safe(() => widget.api.getJson('/analytics/task-work-summary')),
    };
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncPage(
      future: future,
      onRefresh: () {
        setState(() {
          future = _load();
        });
      },
      builder: (context, data) {
        final summary = _asMap(data['summary']);
        return _PageBody(
          title: '追踪',
          subtitle: '浏览器端只展示服务端综合统计，不采集本机活动。',
          actions: [
            _StatusChip(label: '只读云端统计'),
          ],
          child: Column(
            children: [
              _SummaryPanel(
                tasks: _readInt(summary['recordCount'] ?? summary['records']),
                events: _readInt(summary['totalMinutes']),
                actuals: _mapList(_asMap(data['apps'])['items'] ?? _asMap(data['apps'])['apps']).length,
                reminders: _mapList(_asMap(data['categories'])['items'] ?? _asMap(data['categories'])['categories']).length,
                labels: const ['记录', '分钟', '应用', '分类'],
              ),
              const SizedBox(height: 12),
              _TwoColumn(
                left: _ItemSection(
                  title: 'Top Apps',
                  emptyText: '暂无应用统计。',
                  items: _mapList(_asMap(data['apps'])['items'] ?? _asMap(data['apps'])['apps']),
                  columns: const ['应用', '分钟', '记录'],
                  row: (item) => [
                    item['processName'] ?? item['app'] ?? item['name'],
                    item['totalMinutes'] ?? item['minutes'],
                    item['recordCount'] ?? item['records'],
                  ],
                ),
                right: _ItemSection(
                  title: '任务投入',
                  emptyText: '暂无任务投入统计。',
                  items: _mapList(_asMap(data['work'])['items'] ?? _asMap(data['work'])['tasks']),
                  columns: const ['任务', '分钟', '记录'],
                  row: (item) => [
                    item['taskTitle'] ?? item['title'] ?? item['linkedTaskId'],
                    item['totalMinutes'] ?? item['minutes'],
                    item['recordCount'] ?? item['records'],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportsPage extends StatefulWidget {
  const _ReportsPage({required this.api});

  final WebApiClient api;

  @override
  State<_ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<_ReportsPage> {
  late Future<Map<String, dynamic>> future = _load();
  String status = '';

  Future<Map<String, dynamic>> _load() async {
    return {
      'reports': await _safe(() => widget.api.getJson('/reports')),
      'diary': await _safe(() => widget.api.getJson('/diary')),
      'weatherLocations': await _safe(() => widget.api.getJson('/weather/locations')),
      'weatherSummary': await _safe(() => widget.api.getJson('/weather/summary')),
      'channels': await _safe(() => widget.api.getJson('/push/channels')),
      'deliveries': await _safe(() => widget.api.getJson('/push/deliveries')),
    };
  }

  void _refresh() {
    setState(() {
      future = _load();
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    try {
      final message = await action();
      if (!mounted) return;
      setState(() {
        status = message;
        future = _load();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => status = '操作失败：$error');
    }
  }

  Future<void> _generateReport() async {
    await _run(() async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      await widget.api.postJson('/reports/generate', body: {
        'reportType': 'daily',
        'periodStart': day.toIso8601String(),
        'periodEnd': day.add(const Duration(days: 1)).toIso8601String(),
      });
      return '已生成今日日报草稿。';
    });
  }

  Future<void> _generateDiary() async {
    await _run(() async {
      await widget.api.postJson('/diary/generate', body: {
        'date': DateTime.now().toIso8601String(),
      });
      return '已生成今日日记草稿。';
    });
  }

  Future<void> _editReport(Map<String, dynamic> item) async {
    final result = await _editMarkdownDialogWeb(
      context,
      title: '编辑报告',
      initialTitle: '${item['title'] ?? ''}',
      initialMarkdown: '${item['contentMarkdown'] ?? item['summary'] ?? ''}',
    );
    if (result == null) return;
    await _run(() async {
        await widget.api.patchJson('/reports/${item['id']}', body: {
          'title': result['title'],
          'contentMarkdown': result['markdown'],
          if ((result['userNote'] ?? '').isNotEmpty)
            'userNote': result['userNote'],
        });
      return '报告已保存。';
    });
  }

  Future<void> _editDiary(Map<String, dynamic> item) async {
    final result = await _editMarkdownDialogWeb(
      context,
      title: '编辑日记',
      initialTitle: '${item['title'] ?? ''}',
      initialMarkdown: '${item['contentMarkdown'] ?? ''}',
    );
    if (result == null) return;
    await _run(() async {
      await widget.api.patchJson('/diary/${item['id']}', body: {
        'title': result['title'],
        'contentMarkdown': result['markdown'],
      });
      return '日记已保存。';
    });
  }

  Future<void> _openReport(Map<String, dynamic> item) async {
    final detail = await widget.api.getJson('/reports/${item['id']}');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_asMap(detail['report'])['title'] ?? '报告'}'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_asMap(detail['report'])['contentMarkdown'] ?? ''}'),
                const Divider(height: 28),
                Text('条目与证据', style: Theme.of(context).textTheme.titleMedium),
                for (final entry in _mapList(detail['entries']))
                  ListTile(
                    dense: true,
                    title: Text('[${entry['claimType'] ?? entry['entryType']}] ${entry['title'] ?? ''}'),
                    subtitle: Text('${entry['body'] ?? ''}'),
                  ),
                const Divider(height: 28),
                for (final evidence in _mapList(detail['evidence']))
                  Text('- ${evidence['evidenceType']}: ${evidence['sourceType']} ${evidence['summary'] ?? ''}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _configureWeather() async {
    final result = await _editDialog(
      context,
      title: '配置默认天气地点',
      fields: {
        'name': ['地点名称', '默认地点'],
        'latitude': ['纬度', ''],
        'longitude': ['经度', ''],
        'timezone': ['时区', 'auto'],
      },
    );
    if (result == null) return;
    await _run(() async {
      final created = await widget.api.postJson('/weather/locations', body: {
        'name': result['name'],
        'latitude': double.parse('${result['latitude']}'),
        'longitude': double.parse('${result['longitude']}'),
        'timezone': result['timezone'],
        'isDefault': true,
      });
      final location = _asMap(created['location']);
      await widget.api.postJson('/weather/locations/${location['id']}/refresh');
      return '天气地点已保存并刷新。';
    });
  }

  Future<void> _configurePush() async {
    final result = await _editDialog(
      context,
      title: '配置推送渠道',
      fields: {
        'channelType': ['类型：webhook 或 telegram', 'webhook'],
        'name': ['名称', '报告推送'],
        'url': ['Webhook URL', ''],
        'botToken': ['Telegram Bot Token', ''],
        'chatId': ['Telegram Chat ID', ''],
      },
    );
    if (result == null) return;
    await _run(() async {
      await widget.api.postJson('/push/channels', body: {
        'channelType': result['channelType'],
        'name': result['name'],
        'status': 'enabled',
        'config': {
          if ('${result['url']}'.trim().isNotEmpty) 'url': '${result['url']}'.trim(),
          if ('${result['botToken']}'.trim().isNotEmpty) 'botToken': '${result['botToken']}'.trim(),
          if ('${result['chatId']}'.trim().isNotEmpty) 'chatId': '${result['chatId']}'.trim(),
        },
      });
      return '推送渠道已保存。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncPage(
      future: future,
      onRefresh: () {
        setState(() {
          future = _load();
        });
      },
      builder: (context, data) {
        return _PageBody(
          title: '报告与日记',
          subtitle: '查看、生成和确认服务端报告草稿。',
          actions: [
            FilledButton.icon(
              onPressed: _generateReport,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('生成日报'),
            ),
            OutlinedButton.icon(
              onPressed: _generateDiary,
              icon: const Icon(Icons.edit_note),
              label: const Text('生成日记'),
            ),
            OutlinedButton.icon(
              onPressed: _configureWeather,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('天气地点'),
            ),
            OutlinedButton.icon(
              onPressed: _configurePush,
              icon: const Icon(Icons.send_outlined),
              label: const Text('推送渠道'),
            ),
          ],
          child: Column(
            children: [
              _InfoStrip(
                text:
                    '模板报告和模板日记不依赖 AI。AI 润色失败时会保留原草稿；位置和蓝牙当前不采集。',
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text(status)),
              ],
              const SizedBox(height: 12),
              _TwoColumn(
                left: _ItemSection(
                  title: '报告',
                  emptyText: '暂无报告。',
                  items: _mapList(_asMap(data['reports'])['reports'] ?? _asMap(data['reports'])['items']),
                  columns: const ['标题', '类型', '状态', '操作'],
                  row: (item) => [
                    item['title'],
                    item['reportType'] ?? item['type'],
                    item['status'],
                    Wrap(spacing: 4, children: [
                      TextButton(onPressed: () => _openReport(item), child: const Text('查看')),
                      TextButton(onPressed: () => _editReport(item), child: const Text('编辑')),
                      TextButton(
                        onPressed: () => _run(() async {
                          await widget.api.postJson('/reports/${item['id']}/confirm');
                          return '报告已确认。';
                        }),
                        child: const Text('确认'),
                      ),
                      TextButton(
                        onPressed: () => _run(() async {
                          final result = await widget.api.postJson('/reports/${item['id']}/polish');
                          return result['llmApplied'] == true ? 'AI 润色已加入报告。' : 'AI 不可用，已保留模板报告。';
                        }),
                        child: const Text('AI 润色'),
                      ),
                      TextButton(
                        onPressed: () => _run(() async {
                          await widget.api.postJson('/reports/${item['id']}/push');
                          return '已创建推送记录并尝试发送。';
                        }),
                        child: const Text('推送'),
                      ),
                    ]),
                  ],
                ),
                right: _ItemSection(
                  title: '日记',
                  emptyText: '暂无日记。',
                  items: _mapList(_asMap(data['diary'])['diary'] ?? _asMap(data['diary'])['items']),
                  columns: const ['标题', '日期', '状态', '操作'],
                  row: (item) => [
                    item['title'],
                    item['date'] ?? item['entryDate'],
                    item['status'],
                    Wrap(spacing: 4, children: [
                      TextButton(onPressed: () => _editDiary(item), child: const Text('编辑')),
                      TextButton(
                        onPressed: () => _run(() async {
                          await widget.api.postJson('/diary/${item['id']}/confirm');
                          return '日记已确认。';
                        }),
                        child: const Text('确认'),
                      ),
                      TextButton(
                        onPressed: () => _run(() async {
                          final result = await widget.api.postJson('/diary/${item['id']}/polish');
                          return result['llmApplied'] == true ? 'AI 润色已加入日记。' : 'AI 不可用，已保留模板日记。';
                        }),
                        child: const Text('AI 润色'),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _TwoColumn(
                left: _ItemSection(
                  title: '天气缓存',
                  emptyText: '暂无天气缓存。',
                  items: _mapList(_asMap(data['weatherSummary'])['items']),
                  columns: const ['地点', '摘要', '过期时间'],
                  row: (item) => [
                    item['locationName'],
                    item['summary'],
                    item['expiresAt'],
                  ],
                ),
                right: _ItemSection(
                  title: '推送记录',
                  emptyText: '暂无推送记录。',
                  items: _mapList(_asMap(data['deliveries'])['items']),
                  columns: const ['渠道', '状态', '错误', '操作'],
                  row: (item) => [
                    item['channel'],
                    item['status'],
                    item['lastError'],
                    item['status'] == 'failed'
                        ? TextButton(
                            onPressed: () => _run(() async {
                              final result = await widget.api.postJson('/push/deliveries/${item['id']}/retry');
                              return result['ok'] == true ? '重试成功。' : '重试失败，已记录原因。';
                            }),
                            child: const Text('重试'),
                          )
                        : '',
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.api,
    required this.store,
    required this.connection,
    required this.onConnectionRefresh,
  });

  final WebApiClient api;
  final WebLocalStore store;
  final _ConnectionState connection;
  final Future<void> Function() onConnectionRefresh;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final baseUrl = TextEditingController(text: widget.store.baseUrl);
  late final userId = TextEditingController(text: widget.store.userId);
  String status = '';
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    return {
      'settings': await _safe(() => widget.api.getJson('/client/settings')),
      'bootstrap': await _safe(() => widget.api.getJson('/client/bootstrap')),
    };
  }

  Future<void> _saveLocal() async {
    await widget.store.setBaseUrl(baseUrl.text);
    await widget.store.setUserId(userId.text);
    setState(() => status = '已保存本机浏览器设置，刷新页面后完全生效。');
  }

  Future<void> _login() async {
    final result = await widget.api.postJson('/auth/login', body: {
      'userId': userId.text.trim(),
      'displayName': 'FlowPlan Web',
    });
    await widget.store.setTokens(
      accessToken: '${result['accessToken'] ?? ''}',
      refreshToken: '${result['refreshToken'] ?? ''}',
    );
    final user = _asMap(result['user']);
    if (user['id'] is String) {
      await widget.store.setUserId('${user['id']}');
      userId.text = '${user['id']}';
    }
    await widget.onConnectionRefresh();
    setState(() {
      status = '已登录并保存 token。';
      future = _load();
    });
  }

  Future<void> _requestNotification() async {
    final permission = await html.Notification.requestPermission();
    setState(() => status = '浏览器通知权限：$permission');
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncPage(
      future: future,
      onRefresh: () {
        setState(() {
          future = _load();
        });
      },
      builder: (context, data) {
        return _PageBody(
          title: '设置',
          subtitle: '这里只保留用户端必要设置；全局数据管理请打开 Web Admin。',
          actions: [
            FilledButton.icon(
              onPressed: _saveLocal,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
            OutlinedButton.icon(
              onPressed: _login,
              icon: const Icon(Icons.login),
              label: const Text('登录'),
            ),
          ],
          child: Column(
            children: [
              _Panel(
                title: '连接',
                child: Column(
                  children: [
                    TextField(
                      controller: baseUrl,
                      decoration: const InputDecoration(labelText: '服务端 API 地址'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: userId,
                      decoration: const InputDecoration(labelText: '用户 ID'),
                    ),
                    const SizedBox(height: 12),
                    _KeyValueList({
                      '连接状态': widget.connection.online ? '在线' : '服务端不可用',
                      '设备 ID': widget.connection.deviceId,
                      'Token': widget.store.accessToken == null ? '未保存' : '已保存',
                      '服务端时间': widget.connection.serverTime,
                      '最后心跳': widget.connection.lastHeartbeatAt?.toIso8601String() ?? '尚无',
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _requestNotification,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('申请浏览器通知权限'),
                      ),
                    ),
                    if (status.isNotEmpty)
                      Align(alignment: Alignment.centerLeft, child: Text(status)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: '远程设置摘要',
                child: _ItemSection(
                  title: '用户可见设置',
                  emptyText: '暂无远程设置。',
                  items: _mapList(_asMap(data['settings'])['settings']),
                  columns: const ['键', '范围', '版本', '更新时间'],
                  row: (item) => [
                    item['key'] ?? item['configKey'],
                    item['scope'],
                    item['version'],
                    item['updatedAt'],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: '管理端',
                child: const Text('完整数据管理和系统维护请使用 web_admin。Flutter Web 只作为日常使用端。'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ListPage extends StatelessWidget {
  const _ListPage({
    required this.title,
    required this.subtitle,
    required this.searchHint,
    required this.query,
    required this.onQueryChanged,
    required this.onRefresh,
    required this.child,
    required this.action,
  });

  final String title;
  final String subtitle;
  final String searchHint;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRefresh;
  final Widget child;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: query);
    return _PageBody(
      title: title,
      subtitle: subtitle,
      actions: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: searchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: (value) {
              onQueryChanged(value.trim());
              onRefresh();
            },
          ),
        ),
        action,
        IconButton.filledTonal(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
      ],
      child: child,
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Text(text),
    );
  }
}

class _AsyncPage extends StatelessWidget {
  const _AsyncPage({
    required this.future,
    required this.builder,
    required this.onRefresh,
  });

  final Future<Map<String, dynamic>> future;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '服务端不可用',
            message: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          );
        }
        return builder(context, snapshot.data ?? <String, dynamic>{});
      },
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: scrollable ? SingleChildScrollView(child: child) : child,
          ),
        ],
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.title,
    required this.connection,
    required this.onRefresh,
  });

  final String title;
  final _ConnectionState connection;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Text(
            'FlowPlan',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 16),
          Text(title, style: const TextStyle(color: Colors.black54)),
          const Spacer(),
          _StatusChip(
            label: connection.online ? '服务端在线' : '本地缓存模式',
            tone: connection.online ? _ChipTone.success : _ChipTone.warning,
          ),
          const SizedBox(width: 8),
          _StatusDot(color: connection.online ? Colors.green : Colors.redAccent),
          const SizedBox(width: 6),
          Text(_shortDeviceLabel(connection.deviceId), style: Theme.of(context).textTheme.bodySmall),
          IconButton(
            tooltip: '刷新连接',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _FocusPanel extends StatelessWidget {
  const _FocusPanel({required this.current, required this.next});

  final Map<String, dynamic>? current;
  final Map<String, dynamic>? next;

  @override
  Widget build(BuildContext context) {
    final main = current ?? next;
    return _Panel(
      title: current == null ? '下一项' : '当前进行中',
      child: main == null
          ? const _EmptyState(
              icon: Icons.check_circle_outline,
              title: '暂时没有安排',
              message: '可以去任务或日程页添加新的事项。',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${main['title'] ?? '未命名'}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _KeyValueList({
                  '时间': main['startAt'] ?? main['dueAt'] ?? '',
                  '结束': main['endAt'] ?? '',
                  '地点': main['location'] ?? '',
                  '状态': main['status'] ?? '',
                }),
              ],
            ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.tasks,
    required this.events,
    required this.actuals,
    required this.reminders,
    this.labels = const ['任务', '日程', '实际', '提醒'],
  });

  final int tasks;
  final int events;
  final int actuals;
  final int reminders;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final values = [tasks, events, actuals, reminders];
    return _Panel(
      title: '摘要',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.55,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: labels.length,
        itemBuilder: (context, index) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labels[index], style: const TextStyle(color: Colors.black54)),
              const Spacer(),
              Text(
                '${values[index]}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(children: [left, const SizedBox(height: 12), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _ItemSection extends StatelessWidget {
  const _ItemSection({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.columns,
    required this.row,
    this.loading = false,
  });

  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> items;
  final List<String> columns;
  final List<Object?> Function(Map<String, dynamic>) row;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: loading
          ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
          : items.isEmpty
              ? _EmptyState(
                  icon: Icons.inbox_outlined,
                  title: emptyText,
                  message: '刷新或创建后会显示在这里。',
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 66,
                    columns: [for (final column in columns) DataColumn(label: Text(column))],
                    rows: [
                      for (final item in items)
                        DataRow(
                          cells: [
                            for (final cell in row(item))
                              DataCell(
                                cell is Widget
                                    ? cell
                                    : ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 240),
                                        child: Text(
                                          _cellText(cell),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

enum _ChipTone { normal, success, warning, danger }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.tone = _ChipTone.normal});

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _ChipTone.success => Colors.green,
      _ChipTone.warning => Colors.orange,
      _ChipTone.danger => Colors.red,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(color: color.shade700, fontSize: 12)),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  const _KeyValueList(this.entries);

  final Map<String, Object?> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in entries.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 82,
                  child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Expanded(child: Text(_cellText(entry.value))),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: Colors.black38),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _ConnectionState {
  const _ConnectionState({
    this.online = false,
    this.serverTime = '',
    this.deviceId = '',
    this.lastHeartbeatAt,
    this.error = '',
  });

  final bool online;
  final String serverTime;
  final String deviceId;
  final DateTime? lastHeartbeatAt;
  final String error;
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

Future<Map<String, dynamic>> _safe(
  Future<Map<String, dynamic>> Function() loader,
) async {
  try {
    return await loader();
  } catch (error) {
    return {'ok': false, 'error': '$error'};
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is Iterable) {
    return [for (final item in value) _asMap(item)];
  }
  return const [];
}

int _readInt(Object? value) {
  final parsed = _numberValue(value);
  return parsed.toInt();
}

double _numberValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _cellText(Object? value) {
  if (value == null) return '';
  if (value is Map || value is List) return jsonEncode(value);
  return '$value';
}

String _formatBytes(Object? value) {
  final bytes = _numberValue(value);
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${bytes.toInt()} B';
}

String _shortDeviceLabel(String deviceId) {
  if (deviceId.isEmpty) return '';
  return '设备 ${deviceId.length <= 8 ? deviceId : deviceId.substring(0, 8)}';
}

Future<Map<String, dynamic>?> _editDialog(
  BuildContext context, {
  required String title,
  required Map<String, List<String>> fields,
}) async {
  final controllers = {
    for (final entry in fields.entries) entry.key: TextEditingController(text: entry.value[1]),
  };
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controllers[entry.key],
                  decoration: InputDecoration(labelText: entry.value[0]),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
      ],
    ),
  );
  if (saved != true) return null;
  return {
    for (final entry in controllers.entries) entry.key: entry.value.text.trim(),
  };
}

Future<Map<String, String>?> _editMarkdownDialogWeb(
  BuildContext context, {
  required String title,
  required String initialTitle,
  required String initialMarkdown,
  }) async {
    final titleController = TextEditingController(text: initialTitle);
    final markdownController = TextEditingController(text: initialMarkdown);
    final userNoteController = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: markdownController,
              minLines: 12,
              maxLines: 18,
              decoration: const InputDecoration(
                labelText: 'Markdown 内容',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: userNoteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '用户补充，可留空',
                  alignLabelWithHint: true,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
      ],
    ),
  );
  if (saved != true) return null;
    return {
      'title': titleController.text.trim(),
      'markdown': markdownController.text.trim(),
      'userNote': userNoteController.text.trim(),
    };
  }
