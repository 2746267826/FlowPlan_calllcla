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
    unawaited(widget.onConnectionRefresh());
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
                left: _ItemSection2(
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
                right: _ItemSection2(
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
              _ItemSection2(
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
          return _ItemSection2(
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
  State<_EventsPage> createState() => _EventsPageState2();
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
          return _ItemSection2(
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

class _EventsPageState2 extends State<_EventsPage> {
  late Future<List<Map<String, dynamic>>> future = _load();
  String query = '';
  _EventViewMode viewMode = _EventViewMode.timeline;
  DateTime selectedDay = DateTime.now();

  Future<List<Map<String, dynamic>>> _load() async {
    final range = _eventRangeFor(viewMode, selectedDay);
    final result = await widget.api.getJson('/web/events', query: {
      'q': query,
      'from': range.start.toIso8601String(),
      'to': range.end.toIso8601String(),
      'view': viewMode.name,
      'limit': '500',
    });
    final items = _mapList(result['items']);
    items.sort((a, b) => (_eventStart(a) ?? DateTime(0)).compareTo(_eventStart(b) ?? DateTime(0)));
    return items;
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
        'notes': ['备注', _eventNotes(item)],
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
    final range = _eventRangeFor(viewMode, selectedDay);
    return _PageBody(
      title: '日程',
      subtitle: '浏览和编辑服务端日程。Web 端提供时间轴、本周、月视图和密集列表。',
      actions: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索日程标题或地点',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (value) {
              setState(() {
                query = value.trim();
                future = _load();
              });
            },
          ),
        ),
        FilledButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('新建日程'),
        ),
        IconButton.filledTonal(
          tooltip: '刷新',
          onPressed: () {
            setState(() {
              future = _load();
            });
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventToolbar(
                mode: viewMode,
                selectedDay: selectedDay,
                range: range,
                onModeChanged: (mode) {
                  setState(() {
                    viewMode = mode;
                    future = _load();
                  });
                },
                onMove: (delta) {
                  setState(() {
                    selectedDay = switch (viewMode) {
                      _EventViewMode.timeline => DateTime(selectedDay.year, selectedDay.month, selectedDay.day + delta),
                      _EventViewMode.week => DateTime(selectedDay.year, selectedDay.month, selectedDay.day + delta * 7),
                      _EventViewMode.month => DateTime(selectedDay.year, selectedDay.month + delta, selectedDay.day),
                      _EventViewMode.list => DateTime(selectedDay.year, selectedDay.month, selectedDay.day + delta),
                    };
                    future = _load();
                  });
                },
                onToday: () {
                  setState(() {
                    selectedDay = DateTime.now();
                    future = _load();
                  });
                },
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState != ConnectionState.done)
                const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '日程加载失败',
                  message: '${snapshot.error}',
                  action: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        future = _load();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                )
              else
                switch (viewMode) {
                  _EventViewMode.timeline => _EventTimelineView(
                      day: selectedDay,
                      items: items.where((item) => _isSameDay(_eventStart(item), selectedDay)).toList(),
                      onEdit: _edit,
                    ),
                  _EventViewMode.week => _EventWeekView(
                      selectedDay: selectedDay,
                      items: items,
                      onDaySelected: (day) {
                        setState(() {
                          selectedDay = day;
                          viewMode = _EventViewMode.timeline;
                          future = _load();
                        });
                      },
                    ),
                  _EventViewMode.month => _EventMonthView(
                      selectedDay: selectedDay,
                      items: items,
                      onDaySelected: (day) {
                        setState(() {
                          selectedDay = day;
                          viewMode = _EventViewMode.timeline;
                          future = _load();
                        });
                      },
                    ),
                  _EventViewMode.list => _ItemSection2(
                      title: '日程列表',
                      emptyText: '没有日程。',
                      items: items,
                      columns: const ['标题', '开始', '结束', '地点', '备注', '操作'],
                      row: (item) => [
                        item['title'],
                        item['startAt'],
                        item['endAt'],
                        item['location'],
                        _eventNotes(item),
                        TextButton(onPressed: () => _edit(item), child: const Text('编辑')),
                      ],
                    ),
                },
            ],
          );
        },
      ),
    );
  }
}

enum _EventViewMode { timeline, week, month, list }

class _EventRange {
  const _EventRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class _EventToolbar extends StatelessWidget {
  const _EventToolbar({
    required this.mode,
    required this.selectedDay,
    required this.range,
    required this.onModeChanged,
    required this.onMove,
    required this.onToday,
  });

  final _EventViewMode mode;
  final DateTime selectedDay;
  final _EventRange range;
  final ValueChanged<_EventViewMode> onModeChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      _EventViewMode.timeline => _formatDate(selectedDay),
      _EventViewMode.week => '${_formatDate(range.start)} - ${_formatDate(range.end.subtract(const Duration(days: 1)))}',
      _EventViewMode.month => '${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}',
      _EventViewMode.list => '列表',
    };
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<_EventViewMode>(
          segments: const [
            ButtonSegment(value: _EventViewMode.timeline, label: Text('时间轴'), icon: Icon(Icons.view_timeline_outlined)),
            ButtonSegment(value: _EventViewMode.week, label: Text('本周'), icon: Icon(Icons.view_week_outlined)),
            ButtonSegment(value: _EventViewMode.month, label: Text('月视图'), icon: Icon(Icons.calendar_view_month_outlined)),
            ButtonSegment(value: _EventViewMode.list, label: Text('列表'), icon: Icon(Icons.table_rows_outlined)),
          ],
          selected: {mode},
          onSelectionChanged: (value) => onModeChanged(value.first),
        ),
        IconButton.filledTonal(onPressed: () => onMove(-1), icon: const Icon(Icons.chevron_left)),
        SizedBox(
          width: 220,
          child: Center(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ),
        IconButton.filledTonal(onPressed: () => onMove(1), icon: const Icon(Icons.chevron_right)),
        OutlinedButton.icon(onPressed: onToday, icon: const Icon(Icons.today), label: const Text('今天')),
      ],
    );
  }
}

class _EventTimelineView extends StatelessWidget {
  const _EventTimelineView({
    required this.day,
    required this.items,
    required this.onEdit,
  });

  final DateTime day;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.event_available_outlined,
        title: '当天没有日程',
        message: '可以切换周视图、月视图，或新建一个日程。',
      );
    }
    return _Panel(
      title: '${_formatDate(day)} 时间轴',
      child: Column(
        children: [
          for (var hour = 0; hour < 24; hour++)
            _HourLane(
              hour: hour,
              items: items.where((item) => (_eventStart(item)?.hour ?? -1) == hour).toList(),
              onEdit: onEdit,
            ),
        ],
      ),
    );
  }
}

class _HourLane extends StatelessWidget {
  const _HourLane({
    required this.hour,
    required this.items,
    required this.onEdit,
  });

  final int hour;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${hour.toString().padLeft(2, '0')}:00', style: const TextStyle(color: Colors.black54)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
                      child: _EventCard(item: item, compact: false, onTap: () => onEdit(item)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventWeekView extends StatelessWidget {
  const _EventWeekView({
    required this.selectedDay,
    required this.items,
    required this.onDaySelected,
  });

  final DateTime selectedDay;
  final List<Map<String, dynamic>> items;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final start = _startOfWeek(selectedDay);
    final days = [for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 820;
        final children = [
          for (final day in days)
            _WeekDayColumn(
              day: day,
              items: items.where((item) => _isSameDay(_eventStart(item), day)).toList(),
              onTap: () => onDaySelected(day),
            ),
        ];
        if (narrow) {
          return Column(children: [for (final child in children) Padding(padding: const EdgeInsets.only(bottom: 8), child: child)]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final child in children) Expanded(child: child)]);
      },
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.day,
    required this.items,
    required this.onTap,
  });

  final DateTime day;
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_formatDate(day), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text('无日程', style: TextStyle(color: Colors.black45))
              else
                for (final item in items.take(6)) ...[
                  _EventCard(item: item, compact: true),
                  const SizedBox(height: 6),
                ],
              if (items.length > 6) Text('+${items.length - 6} 条', style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventMonthView extends StatelessWidget {
  const _EventMonthView({
    required this.selectedDay,
    required this.items,
    required this.onDaySelected,
  });

  final DateTime selectedDay;
  final List<Map<String, dynamic>> items;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(selectedDay.year, selectedDay.month);
    final leading = first.weekday - 1;
    final daysInMonth = DateTime(selectedDay.year, selectedDay.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var day = 1; day <= daysInMonth; day++) DateTime(selectedDay.year, selectedDay.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760 ? 1 : 7;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: columns == 1 ? 4.2 : 1.15,
          ),
          itemCount: cells.length,
          itemBuilder: (context, index) {
            final day = cells[index];
            if (day == null) return const SizedBox.shrink();
            final dayItems = items.where((item) => _isSameDay(_eventStart(item), day)).toList();
            return Card(
              child: InkWell(
                onTap: () => onDaySelected(day),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('${dayItems.length} 条日程', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 6),
                      for (final item in dayItems.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${_timeLabel(_eventStart(item))} ${item['title'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.item,
    this.compact = false,
    this.onTap,
  });

  final Map<String, dynamic> item;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final blocking = _isBlockingEvent(item);
    final notes = _eventNotes(item);
    return Material(
      color: blocking ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: blocking ? const Color(0xFFF97316) : const Color(0xFF93C5FD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item['title'] ?? '未命名日程'}',
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${_timeLabel(_eventStart(item))} - ${_timeLabel(_eventEnd(item))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              if ('${item['location'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '地点：${item['location']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (!compact && notes.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
              if (blocking) ...[
                const SizedBox(height: 6),
                const _StatusChip(label: '阻挡', tone: _ChipTone.warning),
              ],
            ],
          ),
        ),
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
            child: _ItemSection2(
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
  State<_TrackingPage> createState() => _TrackingPageServerFirstState();
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
                left: _ItemSection2(
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
                right: _ItemSection2(
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

enum _WebTrackingTab { overview, activity, input, details, understanding }

class _TrackingPageServerFirstState extends State<_TrackingPage> {
  _WebTrackingTab tab = _WebTrackingTab.overview;
  DateTime selectedDay = DateTime.now();
  int refreshSeed = 0;

  _EventRange get range {
    final start = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    return _EventRange(start, start.add(const Duration(days: 1)));
  }

  void _refresh() => setState(() => refreshSeed++);

  void _moveDay(int days) {
    setState(() {
      selectedDay = selectedDay.add(Duration(days: days));
      refreshSeed++;
    });
  }

  void _selectHeatmapBucket(DateTime day) {
    setState(() {
      selectedDay = DateTime(day.year, day.month, day.day);
      tab = _WebTrackingTab.activity;
      refreshSeed++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentRange = range;
    return _PageBody(
      title: '追踪',
      subtitle: 'Web 端只展示服务端追踪结果，不采集本机活动；热力图、分析和明细均由服务端处理后返回。',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _moveDay(-1),
          icon: const Icon(Icons.chevron_left),
          label: const Text('前一天'),
        ),
        _StatusChip(label: _formatDate(selectedDay), tone: _ChipTone.success),
        OutlinedButton.icon(
          onPressed: () => _moveDay(1),
          icon: const Icon(Icons.chevron_right),
          label: const Text('后一天'),
        ),
        IconButton.filledTonal(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoStrip(
            text:
                '追踪数据由原生客户端采集后上传服务端。浏览器只读取服务端聚合结果、分页明细和活动理解候选，不读取本地追踪缓冲。',
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_WebTrackingTab>(
              segments: const [
                ButtonSegment(value: _WebTrackingTab.overview, icon: Icon(Icons.dashboard_outlined), label: Text('总览')),
                ButtonSegment(value: _WebTrackingTab.activity, icon: Icon(Icons.timeline_outlined), label: Text('活动分析')),
                ButtonSegment(value: _WebTrackingTab.input, icon: Icon(Icons.keyboard_outlined), label: Text('输入行为')),
                ButtonSegment(value: _WebTrackingTab.details, icon: Icon(Icons.subject_outlined), label: Text('详细数据')),
                ButtonSegment(value: _WebTrackingTab.understanding, icon: Icon(Icons.psychology_alt_outlined), label: Text('活动理解')),
              ],
              selected: {tab},
              onSelectionChanged: (value) => setState(() => tab = value.first),
            ),
          ),
          const SizedBox(height: 12),
          switch (tab) {
            _WebTrackingTab.overview => _TrackingOverviewTab(
                api: widget.api,
                range: currentRange,
                selectedDay: selectedDay,
                refreshSeed: refreshSeed,
                onBucketSelected: _selectHeatmapBucket,
              ),
            _WebTrackingTab.activity => _TrackingActivityTab(
                api: widget.api,
                range: currentRange,
                selectedDay: selectedDay,
                refreshSeed: refreshSeed,
                onBucketSelected: _selectHeatmapBucket,
              ),
            _WebTrackingTab.input => _TrackingInputTab(
                api: widget.api,
                range: currentRange,
                refreshSeed: refreshSeed,
              ),
            _WebTrackingTab.details => _TrackingDetailsTab(
                api: widget.api,
                range: currentRange,
                refreshSeed: refreshSeed,
              ),
            _WebTrackingTab.understanding => _TrackingUnderstandingTab(
                api: widget.api,
                range: currentRange,
                refreshSeed: refreshSeed,
                onChanged: _refresh,
              ),
          },
        ],
      ),
    );
  }
}

class _TrackingOverviewTab extends StatelessWidget {
  const _TrackingOverviewTab({
    required this.api,
    required this.range,
    required this.selectedDay,
    required this.refreshSeed,
    required this.onBucketSelected,
  });

  final WebApiClient api;
  final _EventRange range;
  final DateTime selectedDay;
  final int refreshSeed;
  final ValueChanged<DateTime> onBucketSelected;

  @override
  Widget build(BuildContext context) {
    return _TrackingFuturePanel(
      key: ValueKey('tracking-home-${_formatDate(selectedDay)}-$refreshSeed'),
      reloadKey: 'tracking-home-${_formatDate(selectedDay)}-$refreshSeed',
      loader: () => api.getJson('/analytics/tracker-home', query: {
        'date': selectedDay.toIso8601String(),
      }),
      builder: (context, data) {
        final daySummary = _asMap(data['daySummary']);
        final insights = _asMap(daySummary['insights']);
        final topApps = _mapList(_asMap(data['topApps'])['items']);
        final topCategories = _mapList(_asMap(data['topCategories'])['items']);
        final preview = _mapList(daySummary['previewRecords']);
        return Column(
          children: [
            _TrackingMetricGrid(
              metrics: {
                '记录': _readInt(insights['recordCount']),
                '分钟': _readInt(insights['totalMinutes']),
                '按键': _readInt(insights['totalKeys']),
                '点击': _readInt(insights['totalClicks']),
              },
            ),
            const SizedBox(height: 12),
            _TrackingHeatmapPanel(
              title: '活动热力图',
              data: _asMap(data['activityHeatmap']),
              valueLabel: '分钟',
              valueReader: (bucket) => _numberValue(bucket['totalMinutes']),
              onBucketSelected: onBucketSelected,
            ),
            const SizedBox(height: 12),
            _TwoColumn(
              left: _TrackingMetricList(
                title: 'Top Apps',
                emptyText: '服务端暂未返回应用统计。',
                items: topApps,
                nameReader: (item) => '${item['name'] ?? item['processName'] ?? 'unknown'}',
                valueReader: (item) => '${_readInt(item['totalMinutes'])} 分钟 / ${_readInt(item['recordCount'])} 条',
              ),
              right: _TrackingMetricList(
                title: 'Top Categories',
                emptyText: '服务端暂未返回分类统计。',
                items: topCategories,
                nameReader: (item) => '${item['name'] ?? item['category'] ?? 'uncategorized'}',
                valueReader: (item) => '${_readInt(item['totalMinutes'])} 分钟 / ${_readInt(item['recordCount'])} 条',
              ),
            ),
            const SizedBox(height: 12),
            _TwoColumn(
              left: _TrackingWorkSummaryPanel(api: api, range: range, refreshSeed: refreshSeed),
              right: _TrackingRecordPreviewPanel(title: '最近活动预览', items: preview),
            ),
          ],
        );
      },
    );
  }
}

class _TrackingActivityTab extends StatelessWidget {
  const _TrackingActivityTab({
    required this.api,
    required this.range,
    required this.selectedDay,
    required this.refreshSeed,
    required this.onBucketSelected,
  });

  final WebApiClient api;
  final _EventRange range;
  final DateTime selectedDay;
  final int refreshSeed;
  final ValueChanged<DateTime> onBucketSelected;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(selectedDay.year, selectedDay.month);
    final monthEnd = DateTime(selectedDay.year, selectedDay.month + 1);
    return Column(
      children: [
        _TrackingFuturePanel(
          key: ValueKey('activity-heatmap-${selectedDay.year}-${selectedDay.month}-$refreshSeed'),
          reloadKey: 'activity-heatmap-${selectedDay.year}-${selectedDay.month}-$refreshSeed',
          loader: () => api.getJson('/analytics/activity-heatmap', query: {
            'start': monthStart.toIso8601String(),
            'end': monthEnd.toIso8601String(),
            'bucket': 'day',
          }),
          builder: (context, data) => _TrackingHeatmapPanel(
            title: '月活动热力图',
            data: data,
            valueLabel: '分钟',
            valueReader: (bucket) => _numberValue(bucket['totalMinutes']),
            onBucketSelected: onBucketSelected,
          ),
        ),
        const SizedBox(height: 12),
        _TrackingFuturePanel(
          key: ValueKey('range-analysis-${range.start.toIso8601String()}-$refreshSeed'),
          reloadKey: 'range-analysis-${range.start.toIso8601String()}-$refreshSeed',
          loader: () => api.getJson('/analytics/range-analysis', query: {
            'start': range.start.toIso8601String(),
            'end': range.end.toIso8601String(),
            'bucket': 'hour',
          }),
          builder: (context, data) {
            final insights = _asMap(data['insights']);
            final sessions = _mapList(data['sessions']);
            final preview = _mapList(data['previewRecords']);
            return Column(
              children: [
                _TrackingMetricGrid(
                  metrics: {
                    '区间记录': _readInt(insights['recordCount']),
                    '区间分钟': _readInt(insights['totalMinutes']),
                    '专注分钟': _readInt(insights['focusMinutes']),
                    '生产记录': _readInt(insights['productiveRecordCount']),
                  },
                ),
                const SizedBox(height: 12),
                _TwoColumn(
                  left: _TrackingSessionsPanel(items: sessions),
                  right: _TrackingRecordPreviewPanel(title: '区间活动预览', items: preview),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TrackingInputTab extends StatelessWidget {
  const _TrackingInputTab({
    required this.api,
    required this.range,
    required this.refreshSeed,
  });

  final WebApiClient api;
  final _EventRange range;
  final int refreshSeed;

  @override
  Widget build(BuildContext context) {
    return _TrackingFuturePanel(
      key: ValueKey('input-heatmap-${range.start.toIso8601String()}-$refreshSeed'),
      reloadKey: 'input-heatmap-${range.start.toIso8601String()}-$refreshSeed',
      loader: () => api.getJson('/analytics/input-heatmap', query: {
        'start': range.start.toIso8601String(),
        'end': range.end.toIso8601String(),
        'bucket': 'hour',
      }),
      builder: (context, data) {
        final buckets = _mapList(data['buckets']);
        final topKeys = _mapList(data['topKeys']);
        final processIntensities = _mapList(data['processIntensities']);
        final mouseCounts = _asMap(data['mouseCounts']);
        return Column(
          children: [
            _TrackingHeatmapPanel(
              title: '输入行为热力图',
              data: data,
              valueLabel: '事件',
              valueReader: (bucket) => _numberValue(bucket['eventCount']),
            ),
            const SizedBox(height: 12),
            _TrackingMetricGrid(
              metrics: {
                '输入桶': buckets.length,
                '键盘事件': buckets.fold<int>(0, (sum, item) => sum + _readInt(item['keyboardEventCount'])),
                '鼠标点击': buckets.fold<int>(0, (sum, item) => sum + _readInt(item['mouseButtonEventCount'])),
                '滚轮事件': buckets.fold<int>(0, (sum, item) => sum + _readInt(item['wheelEventCount'])),
              },
            ),
            const SizedBox(height: 12),
            _TwoColumn(
              left: _TrackingMetricList(
                title: '键盘按键分布',
                emptyText: '服务端尚无按键分布数据。',
                items: topKeys,
                nameReader: (item) => '${item['label'] ?? item['keyCode'] ?? ''}',
                valueReader: (item) => '${_readInt(item['count'])} 次',
              ),
              right: _TrackingMetricList(
                title: '鼠标行为分布',
                emptyText: '服务端尚无鼠标行为数据。',
                items: [
                  for (final entry in mouseCounts.entries) {'name': entry.key, 'count': entry.value},
                ],
                nameReader: (item) => _mouseLabel('${item['name']}'),
                valueReader: (item) => '${_readInt(item['count'])} 次',
              ),
            ),
            const SizedBox(height: 12),
            _ItemSection2(
              title: '进程级输入强度',
              emptyText: '服务端尚无进程输入强度数据。',
              items: processIntensities,
              columns: const ['进程', '强度', '键盘', '鼠标', '活跃分钟'],
              row: (item) => [
                item['processName'],
                item['intensityScore'],
                item['keyEvents'],
                _readInt(item['mouseButtonEvents']) + _readInt(item['wheelEvents']) + _readInt(item['mouseMoveEvents']),
                item['activeMinutes'],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TrackingDetailsTab extends StatefulWidget {
  const _TrackingDetailsTab({
    required this.api,
    required this.range,
    required this.refreshSeed,
  });

  final WebApiClient api;
  final _EventRange range;
  final int refreshSeed;

  @override
  State<_TrackingDetailsTab> createState() => _TrackingDetailsTabState();
}

class _TrackingDetailsTabState extends State<_TrackingDetailsTab> {
  int activityOffset = 0;
  int inputOffset = 0;
  String processFilter = '';
  String categoryFilter = '';
  String eventKindFilter = '';
  static const limit = 50;

  @override
  void didUpdateWidget(covariant _TrackingDetailsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range.start != widget.range.start ||
        oldWidget.range.end != widget.range.end ||
        oldWidget.refreshSeed != widget.refreshSeed) {
      activityOffset = 0;
      inputOffset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _InfoStrip(text: '详细数据是服务端分页明细预览，默认每页 50 条，不用于浏览器端统计计算。'),
        const SizedBox(height: 12),
        _TrackingDetailFilterBar(
          processFilter: processFilter,
          categoryFilter: categoryFilter,
          eventKindFilter: eventKindFilter,
          onApply: (process, category, eventKind) {
            setState(() {
              processFilter = process;
              categoryFilter = category;
              eventKindFilter = eventKind;
              activityOffset = 0;
              inputOffset = 0;
            });
          },
        ),
        const SizedBox(height: 12),
        _TrackingPagedDetailsPanel(
          key: ValueKey('activity-detail-${widget.range.start.toIso8601String()}-$activityOffset-${widget.refreshSeed}'),
          title: '活动记录明细',
          emptyText: '服务端没有返回活动记录。',
          api: widget.api,
          endpoint: '/analytics/activity-records',
          range: widget.range,
          offset: activityOffset,
          limit: limit,
          query: {
            'processName': processFilter,
            'category': categoryFilter,
          },
          columns: const ['时间', '应用', '分类', '分钟', '窗口/标题'],
          row: (item) {
            final payload = _asMap(item['payload']);
            return [
              _formatDateTime(_parseDate(item['occurredAt'])),
              _payloadText(payload, const ['processName', 'process_name', 'packageName', 'appName']),
              _payloadText(payload, const ['category']),
              item['metricMinutes'],
              _payloadText(payload, const ['windowTitle', 'window_title', 'title', 'summary']),
            ];
          },
          onPrevious: activityOffset == 0
              ? null
              : () => setState(() => activityOffset = activityOffset - limit < 0 ? 0 : activityOffset - limit),
          onNext: () => setState(() => activityOffset += limit),
        ),
        const SizedBox(height: 12),
        _TrackingPagedDetailsPanel(
          key: ValueKey('input-detail-${widget.range.start.toIso8601String()}-$inputOffset-${widget.refreshSeed}'),
          title: '输入事件明细',
          emptyText: '服务端没有返回输入事件。',
          api: widget.api,
          endpoint: '/analytics/input-events',
          range: widget.range,
          offset: inputOffset,
          limit: limit,
          query: {
            'processName': processFilter,
            'category': categoryFilter,
            'eventKind': eventKindFilter,
          },
          columns: const ['时间', '进程', '类型', '次数', '摘要'],
          row: (item) {
            final payload = _asMap(item['payload']);
            return [
              _formatDateTime(_parseDate(item['occurredAt'])),
              _payloadText(payload, const ['processName', 'process_name']),
              _payloadText(payload, const ['eventKind', 'event_kind', 'kind']),
              item['metricCount'],
              _trackingPayloadSummary(payload),
            ];
          },
          onPrevious: inputOffset == 0
              ? null
              : () => setState(() => inputOffset = inputOffset - limit < 0 ? 0 : inputOffset - limit),
          onNext: () => setState(() => inputOffset += limit),
        ),
      ],
    );
  }
}

class _TrackingUnderstandingTab extends StatelessWidget {
  const _TrackingUnderstandingTab({
    required this.api,
    required this.range,
    required this.refreshSeed,
    required this.onChanged,
  });

  final WebApiClient api;
  final _EventRange range;
  final int refreshSeed;
  final VoidCallback onChanged;

  Future<void> _buildSegments(BuildContext context) async {
    await api.postJson('/activity-understanding/build', body: {
      'start': range.start.toIso8601String(),
      'end': range.end.toIso8601String(),
    });
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已请求服务端重新生成活动片段。')));
    }
  }

  Future<void> _confirm(BuildContext context, Map<String, dynamic> item) async {
    await api.postJson('/activity-understanding/segments/${item['id']}/confirm', body: {
      'title': item['title'] ?? item['summary'] ?? '已确认活动',
      if ('${item['matchedTaskId'] ?? ''}'.isNotEmpty) 'taskId': '${item['matchedTaskId']}',
    });
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('活动片段已确认，服务端会写入实际记录和任务投入。')));
    }
  }

  Future<void> _reject(BuildContext context, Map<String, dynamic> item) async {
    await api.postJson('/activity-understanding/segments/${item['id']}/reject', body: {
      'reason': 'web_user_rejected',
    });
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('活动片段已拒绝。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _buildSegments(context),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('服务端整理当天活动'),
          ),
        ),
        const SizedBox(height: 12),
        _TrackingFuturePanel(
          key: ValueKey('segments-${range.start.toIso8601String()}-$refreshSeed'),
          reloadKey: 'segments-${range.start.toIso8601String()}-$refreshSeed',
          loader: () => api.getJson('/activity-understanding/segments', query: {
            'start': range.start.toIso8601String(),
            'end': range.end.toIso8601String(),
            'limit': '100',
          }),
          builder: (context, data) {
            final items = _mapList(data['items']);
            return _ItemSection2(
              title: '服务端活动片段',
              emptyText: '服务端暂未生成活动片段。',
              items: items,
              columns: const ['时间', '标题', '应用/窗口', '置信度', '操作'],
              row: (item) => [
                '${_timeLabel(_parseDate(item['startAt']))}-${_timeLabel(_parseDate(item['endAt']))}',
                item['title'] ?? item['summary'],
                '${item['primaryApp'] ?? item['primaryProcessName'] ?? ''}\n${item['primaryWindowTitle'] ?? ''}',
                '${((_numberValue(item['confidence']) * 100).clamp(0, 100)).toStringAsFixed(0)}%',
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(onPressed: () => _showSegmentDetail(context, item), child: const Text('详情')),
                    TextButton(onPressed: () => _confirm(context, item), child: const Text('确认')),
                    TextButton(onPressed: () => _reject(context, item), child: const Text('拒绝')),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showSegmentDetail(BuildContext context, Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item['title'] ?? '活动片段详情'}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: _KeyValueList({
              '时间': '${item['startAt']} - ${item['endAt']}',
              '主要应用': item['primaryApp'] ?? item['primaryProcessName'],
              '主要窗口': item['primaryWindowTitle'],
              '文件路径': item['primaryFilePath'],
              '分类': item['category'],
              '状态': item['status'],
              '任务候选': item['matchedTaskId'],
              '证据': item['evidence'],
              '原因': item['reason'],
            }),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }
}

class _TrackingDetailFilterBar extends StatefulWidget {
  const _TrackingDetailFilterBar({
    required this.processFilter,
    required this.categoryFilter,
    required this.eventKindFilter,
    required this.onApply,
  });

  final String processFilter;
  final String categoryFilter;
  final String eventKindFilter;
  final void Function(String process, String category, String eventKind) onApply;

  @override
  State<_TrackingDetailFilterBar> createState() => _TrackingDetailFilterBarState();
}

class _TrackingDetailFilterBarState extends State<_TrackingDetailFilterBar> {
  late final process = TextEditingController(text: widget.processFilter);
  late final category = TextEditingController(text: widget.categoryFilter);
  late final eventKind = TextEditingController(text: widget.eventKindFilter);

  @override
  void dispose() {
    process.dispose();
    category.dispose();
    eventKind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '服务端明细筛选',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: process,
              decoration: const InputDecoration(labelText: '进程 / 应用'),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: category,
              decoration: const InputDecoration(labelText: '分类'),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: eventKind,
              decoration: const InputDecoration(labelText: '输入类型'),
            ),
          ),
          FilledButton.icon(
            onPressed: () => widget.onApply(
              process.text.trim(),
              category.text.trim(),
              eventKind.text.trim(),
            ),
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('应用筛选'),
          ),
          TextButton(
            onPressed: () {
              process.clear();
              category.clear();
              eventKind.clear();
              widget.onApply('', '', '');
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}

class _TrackingFuturePanel extends StatefulWidget {
  const _TrackingFuturePanel({
    super.key,
    required this.reloadKey,
    required this.loader,
    required this.builder,
  });

  final Object reloadKey;
  final Future<Map<String, dynamic>> Function() loader;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;

  @override
  State<_TrackingFuturePanel> createState() => _TrackingFuturePanelState();
}

class _TrackingFuturePanelState extends State<_TrackingFuturePanel> {
  late Future<Map<String, dynamic>> future = widget.loader();

  @override
  void didUpdateWidget(covariant _TrackingFuturePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) {
      future = widget.loader();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Panel(
            title: '加载中',
            child: SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return _Panel(
            title: '服务端追踪数据不可用',
            child: _EmptyState(
              icon: Icons.cloud_off_outlined,
              title: '服务端不可用',
              message: '${snapshot.error}',
            ),
          );
        }
        return widget.builder(context, snapshot.data ?? <String, dynamic>{});
      },
    );
  }
}

class _TrackingMetricGrid extends StatelessWidget {
  const _TrackingMetricGrid({required this.metrics});

  final Map<String, int> metrics;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '服务端摘要',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 2.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: metrics.length,
        itemBuilder: (context, index) {
          final entry = metrics.entries.elementAt(index);
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: const TextStyle(color: Colors.black54)),
                const Spacer(),
                Text('${entry.value}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrackingHeatmapPanel extends StatelessWidget {
  const _TrackingHeatmapPanel({
    required this.title,
    required this.data,
    required this.valueLabel,
    required this.valueReader,
    this.onBucketSelected,
  });

  final String title;
  final Map<String, dynamic> data;
  final String valueLabel;
  final double Function(Map<String, dynamic>) valueReader;
  final ValueChanged<DateTime>? onBucketSelected;

  @override
  Widget build(BuildContext context) {
    final buckets = _mapList(data['buckets']);
    final maxValue = buckets.fold<double>(0, (max, item) {
      final value = valueReader(item);
      return value > max ? value : max;
    });
    return _Panel(
      title: title,
      child: buckets.isEmpty
          ? const _EmptyState(
              icon: Icons.grid_view_outlined,
              title: '暂无热力图数据',
              message: '服务端还没有返回该范围内的聚合桶。',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 900 ? 14 : 7;
                final cellSize = ((constraints.maxWidth - (columns - 1) * 6) / columns).clamp(32.0, 72.0);
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final bucket in buckets)
                      _HeatmapCell(
                        bucket: bucket,
                        size: cellSize,
                        value: valueReader(bucket),
                        maxValue: maxValue,
                        valueLabel: valueLabel,
                        onTap: onBucketSelected == null
                            ? null
                            : () {
                                final parsed = _parseDate(bucket['bucketStart']);
                                if (parsed != null) onBucketSelected!(parsed);
                              },
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.bucket,
    required this.size,
    required this.value,
    required this.maxValue,
    required this.valueLabel,
    this.onTap,
  });

  final Map<String, dynamic> bucket;
  final double size;
  final double value;
  final double maxValue;
  final String valueLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    final color = Color.lerp(const Color(0xFFEFF6FF), const Color(0xFF2563EB), ratio)!;
    final date = _parseDate(bucket['bucketStart']);
    return Tooltip(
      message: '${_formatDateTime(date)}\n${value.toStringAsFixed(0)} $valueLabel',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.12)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(date == null ? '--' : '${date.month}/${date.day}', style: TextStyle(color: ratio > 0.55 ? Colors.white : Colors.black87)),
                Text(value.toStringAsFixed(0), style: TextStyle(fontWeight: FontWeight.w800, color: ratio > 0.55 ? Colors.white : Colors.black87)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingMetricList extends StatelessWidget {
  const _TrackingMetricList({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.nameReader,
    required this.valueReader,
  });

  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) nameReader;
  final String Function(Map<String, dynamic>) valueReader;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: items.isEmpty
          ? _EmptyState(icon: Icons.insights_outlined, title: emptyText, message: '等待客户端上传追踪数据后会显示。')
          : Column(
              children: [
                for (final item in items.take(12))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(nameReader(item), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        _StatusChip(label: valueReader(item)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TrackingWorkSummaryPanel extends StatelessWidget {
  const _TrackingWorkSummaryPanel({
    required this.api,
    required this.range,
    required this.refreshSeed,
  });

  final WebApiClient api;
  final _EventRange range;
  final int refreshSeed;

  @override
  Widget build(BuildContext context) {
    return _TrackingFuturePanel(
      key: ValueKey('task-work-${range.start.toIso8601String()}-$refreshSeed'),
      reloadKey: 'task-work-${range.start.toIso8601String()}-$refreshSeed',
      loader: () => api.getJson('/analytics/task-work-summary', query: {
        'start': range.start.toIso8601String(),
        'end': range.end.toIso8601String(),
        'limit': '20',
      }),
      builder: (context, data) => _TrackingMetricList(
        title: '任务实际投入',
        emptyText: '服务端暂无任务投入统计。',
        items: _mapList(data['items']),
        nameReader: (item) => '${item['taskTitle'] ?? item['title'] ?? item['name'] ?? 'unlinked'}',
        valueReader: (item) => '${_readInt(item['totalMinutes'])} 分钟',
      ),
    );
  }
}

class _TrackingRecordPreviewPanel extends StatelessWidget {
  const _TrackingRecordPreviewPanel({
    required this.title,
    required this.items,
  });

  final String title;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return _ItemSection2(
      title: title,
      emptyText: '服务端暂无活动预览。',
      items: items,
      columns: const ['时间', '应用', '分类', '分钟'],
      row: (item) {
        final payload = _asMap(item['payload']);
        return [
          _formatDateTime(_parseDate(item['occurredAt'])),
          _payloadText(payload, const ['processName', 'process_name', 'packageName', 'appName']),
          _payloadText(payload, const ['category']),
          item['metricMinutes'],
        ];
      },
    );
  }
}

class _TrackingSessionsPanel extends StatelessWidget {
  const _TrackingSessionsPanel({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return _ItemSection2(
      title: '服务端工作会话',
      emptyText: '服务端暂无会话分析。',
      items: items,
      columns: const ['时间', '标签', '分钟', '应用'],
      row: (item) => [
        '${_timeLabel(_parseDate(item['startTime']))}-${_timeLabel(_parseDate(item['endTime']))}',
        item['label'] ?? item['category'],
        item['durationMinutes'],
        item['processName'] ?? _csvText(item['processNames']),
      ],
    );
  }
}

class _TrackingPagedDetailsPanel extends StatelessWidget {
  const _TrackingPagedDetailsPanel({
    super.key,
    required this.title,
    required this.emptyText,
    required this.api,
    required this.endpoint,
    required this.range,
    required this.offset,
    required this.limit,
    required this.query,
    required this.columns,
    required this.row,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final String emptyText;
  final WebApiClient api;
  final String endpoint;
  final _EventRange range;
  final int offset;
  final int limit;
  final Map<String, String> query;
  final List<String> columns;
  final List<Object?> Function(Map<String, dynamic>) row;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _TrackingFuturePanel(
      reloadKey: [
        endpoint,
        range.start.toIso8601String(),
        range.end.toIso8601String(),
        offset,
        limit,
        ...query.entries.map((entry) => '${entry.key}:${entry.value}'),
      ].join('|'),
      loader: () => api.getJson(endpoint, query: {
        'start': range.start.toIso8601String(),
        'end': range.end.toIso8601String(),
        'limit': '$limit',
        'offset': '$offset',
        ...query,
      }),
      builder: (context, data) {
        final items = _mapList(data['items']);
        final hasMore = data['hasMore'] == true;
        return Column(
          children: [
            _ItemSection2(
              title: '$title（第 ${(offset ~/ limit) + 1} 页）',
              emptyText: emptyText,
              items: items,
              columns: columns,
              row: row,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(onPressed: onPrevious, child: const Text('上一页')),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: hasMore ? onNext : null, child: const Text('下一页')),
              ],
            ),
          ],
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
                left: _ItemSection2(
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
                right: _ItemSection2(
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
                left: _ItemSection2(
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
                right: _ItemSection2(
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
                child: _ItemSection2(
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

class _ItemSection2 extends StatelessWidget {
  const _ItemSection2({
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 680) {
                      return Column(
                        children: [
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ItemCard(columns: columns, cells: row(item)),
                            ),
                        ],
                      );
                    }
                    final tableMinWidth = columns.length * 150.0 + 80;
                    return Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: tableMinWidth > constraints.maxWidth ? tableMinWidth : constraints.maxWidth,
                          ),
                          child: DataTable(
                            columnSpacing: 18,
                            headingRowHeight: 40,
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 72,
                            columns: [
                              for (var i = 0; i < columns.length; i++)
                                DataColumn(
                                  label: SizedBox(
                                    width: i == columns.length - 1 ? 112 : 150,
                                    child: Text(columns[i], overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                            ],
                            rows: [
                              for (final item in items)
                                DataRow(
                                  cells: [
                                    for (final entry in row(item).asMap().entries)
                                      DataCell(
                                        SizedBox(
                                          width: entry.key == row(item).length - 1 ? 112 : 150,
                                          child: entry.value is Widget
                                              ? Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment: Alignment.centerLeft,
                                                    child: entry.value as Widget,
                                                  ),
                                                )
                                              : Text(
                                                  _cellText(entry.value),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.columns, required this.cells});

  final List<String> columns;
  final List<Object?> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: cells[i] is Widget
                  ? Align(alignment: Alignment.centerLeft, child: cells[i] as Widget)
                  : Text(
                      '${i < columns.length ? '${columns[i]}：' : ''}${_cellText(cells[i])}',
                      maxLines: i == 0 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
        ],
      ),
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

DateTime? _parseDate(Object? value) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toLocal();
}

DateTime? _eventStart(Map<String, dynamic> item) {
  final payload = _asMap(item['payload']);
  return _parseDate(
    item['startAt'] ??
        item['dtstart'] ??
        payload['startAt'] ??
        payload['start_at'] ??
        payload['startTime'] ??
        payload['dtstart'],
  );
}

DateTime? _eventEnd(Map<String, dynamic> item) {
  final payload = _asMap(item['payload']);
  return _parseDate(
    item['endAt'] ??
        item['dtend'] ??
        payload['endAt'] ??
        payload['end_at'] ??
        payload['endTime'] ??
        payload['dtend'],
  );
}

String _eventNotes(Map<String, dynamic>? item) {
  if (item == null) return '';
  final payload = _asMap(item['payload']);
  return '${item['notes'] ?? item['description'] ?? payload['notes'] ?? payload['note'] ?? payload['description'] ?? ''}'.trim();
}

bool _isBlockingEvent(Map<String, dynamic> item) {
  final payload = _asMap(item['payload']);
  final value = item['isBlock'] ?? payload['isBlock'] ?? payload['blocking'] ?? payload['isBlocking'] ?? false;
  return value == true || '$value'.toLowerCase() == 'true';
}

bool _isSameDay(DateTime? value, DateTime day) {
  if (value == null) return false;
  return value.year == day.year && value.month == day.month && value.day == day.day;
}

DateTime _startOfWeek(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  return date.subtract(Duration(days: date.weekday - 1));
}

_EventRange _eventRangeFor(_EventViewMode mode, DateTime selectedDay) {
  switch (mode) {
    case _EventViewMode.timeline:
      final start = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      return _EventRange(start, start.add(const Duration(days: 1)));
    case _EventViewMode.list:
      final start = DateTime(selectedDay.year, selectedDay.month);
      final end = DateTime(selectedDay.year, selectedDay.month + 1);
      return _EventRange(start, end);
    case _EventViewMode.week:
      final start = _startOfWeek(selectedDay);
      return _EventRange(start, start.add(const Duration(days: 7)));
    case _EventViewMode.month:
      final start = DateTime(selectedDay.year, selectedDay.month);
      final end = DateTime(selectedDay.year, selectedDay.month + 1);
      return _EventRange(start, end);
  }
}

String _formatDate(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '';
  return '${_formatDate(value)} ${_timeLabel(value)}';
}

String _timeLabel(DateTime? value) {
  if (value == null) return '--:--';
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _payloadText(Map<String, dynamic> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    final text = '$value'.trim();
    if (value != null && text.isNotEmpty && text != 'null') {
      return text;
    }
  }
  final metadata = _asMap(payload['metadata']);
  for (final key in keys) {
    final value = metadata[key];
    final text = '$value'.trim();
    if (value != null && text.isNotEmpty && text != 'null') {
      return text;
    }
  }
  return '';
}

String _trackingPayloadSummary(Map<String, dynamic> payload) {
  final metadata = _asMap(payload['metadata']);
  final parts = <String>[
    _payloadText(payload, const ['keyLabel', 'key_label', 'tokenText']),
    _payloadText(payload, const ['mouseButton', 'mouse_button']),
    _payloadText(payload, const ['windowTitle', 'window_title', 'title']),
    _payloadText(payload, const ['filePath', 'file_path']),
  ].where((item) => item.isNotEmpty).toList();
  if (parts.isEmpty) {
    final eventCount = metadata['eventCount'] ?? metadata['event_count'];
    return eventCount == null ? '' : '事件数 $eventCount';
  }
  return parts.take(3).join(' / ');
}

String _mouseLabel(String value) {
  return switch (value) {
    'left' => '左键',
    'right' => '右键',
    'middle' => '中键',
    'wheel_up' => '滚轮上',
    'wheel_down' => '滚轮下',
    'wheel' => '滚轮',
    'move' => '移动',
    'button' => '按钮',
    _ => value,
  };
}

String _csvText(Object? value) {
  if (value is Iterable) {
    return value.map((item) => '$item').where((item) => item.trim().isNotEmpty).join(', ');
  }
  return _cellText(value);
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
