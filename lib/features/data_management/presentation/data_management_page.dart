import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';

enum _ManagementTypeFilter { all, events, tasks }

enum _ManagementSourceFilter { all, local, outlook }

enum _ManagementTimeFilter { all, today, next7Days, overdue, noTime }

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  final _searchController = TextEditingController();
  final Set<String> _selectedKeys = <String>{};

  _ManagementTypeFilter _typeFilter = _ManagementTypeFilter.all;
  _ManagementSourceFilter _sourceFilter = _ManagementSourceFilter.all;
  _ManagementTimeFilter _timeFilter = _ManagementTimeFilter.all;
  String _statusFilter = 'all';
  String _query = '';
  bool _working = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(managementEventsProvider);
    final tasksAsync = ref.watch(managementTasksProvider);
    final calendarsAsync = ref.watch(allEventCalendarsProvider);
    final taskListsAsync = ref.watch(allTaskListsProvider);

    final loading = eventsAsync.isLoading ||
        tasksAsync.isLoading ||
        calendarsAsync.isLoading ||
        taskListsAsync.isLoading;
    final error = eventsAsync.error ??
        tasksAsync.error ??
        calendarsAsync.error ??
        taskListsAsync.error;

    final events = eventsAsync.asData?.value ?? const <CalendarEvent>[];
    final tasks = tasksAsync.asData?.value ?? const <TaskItem>[];
    final calendars = calendarsAsync.asData?.value ?? const <EventCalendar>[];
    final taskLists = taskListsAsync.asData?.value ?? const <TaskList>[];

    final calendarNames = <int, String>{
      for (final calendar in calendars) calendar.id: calendar.name,
    };
    final taskListNames = <int, String>{
      for (final taskList in taskLists) taskList.id: taskList.name,
    };
    final allItems = _buildItems(
      events: events,
      tasks: tasks,
      calendarNames: calendarNames,
      taskListNames: taskListNames,
    );
    final visibleItems = allItems.where(_matchesFilters).toList(growable: false);
    final visibleKeys = visibleItems.map((item) => item.key).toSet();
    _selectedKeys.removeWhere((key) => !allItems.any((item) => item.key == key));
    final selectedVisibleCount =
        _selectedKeys.where(visibleKeys.contains).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('全部任务与日程'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(managementEventsProvider);
              ref.invalidate(managementTasksProvider);
              ref.invalidate(allEventCalendarsProvider);
              ref.invalidate(allTaskListsProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _ErrorState(error: error)
              : Column(
                  children: [
                    _buildToolbar(
                      totalCount: allItems.length,
                      visibleCount: visibleItems.length,
                      selectedCount: _selectedKeys.length,
                      selectedVisibleCount: selectedVisibleCount,
                      visibleKeys: visibleKeys,
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: visibleItems.isEmpty
                          ? const _EmptyState()
                          : ListView.separated(
                              itemCount: visibleItems.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                return _ManagementItemTile(
                                  item: item,
                                  selected: _selectedKeys.contains(item.key),
                                  onSelected: _working
                                      ? null
                                      : (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedKeys.add(item.key);
                                            } else {
                                              _selectedKeys.remove(item.key);
                                            }
                                          });
                                        },
                                  onOpen: () => _openItem(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildToolbar({
    required int totalCount,
    required int visibleCount,
    required int selectedCount,
    required int selectedVisibleCount,
    required Set<String> visibleKeys,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '搜索标题、备注、地点或所属本',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FilterDropdown<_ManagementTypeFilter>(
                label: '类型',
                value: _typeFilter,
                values: _ManagementTypeFilter.values,
                labelOf: _typeLabel,
                onChanged: (value) => setState(() => _typeFilter = value),
              ),
              _FilterDropdown<_ManagementSourceFilter>(
                label: '来源',
                value: _sourceFilter,
                values: _ManagementSourceFilter.values,
                labelOf: _sourceLabel,
                onChanged: (value) => setState(() => _sourceFilter = value),
              ),
              _FilterDropdown<_ManagementTimeFilter>(
                label: '时间',
                value: _timeFilter,
                values: _ManagementTimeFilter.values,
                labelOf: _timeLabel,
                onChanged: (value) => setState(() => _timeFilter = value),
              ),
              DropdownButton<String>(
                value: _statusFilter,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部状态')),
                  DropdownMenuItem(value: 'NEEDS-ACTION', child: Text('待处理')),
                  DropdownMenuItem(value: 'IN-PROCESS', child: Text('进行中')),
                  DropdownMenuItem(value: 'COMPLETED', child: Text('已完成')),
                  DropdownMenuItem(value: 'CONFIRMED', child: Text('已确认')),
                  DropdownMenuItem(value: 'TENTATIVE', child: Text('暂定')),
                  DropdownMenuItem(value: 'CANCELLED', child: Text('已取消')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _statusFilter = value);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '共 $totalCount 条，当前显示 $visibleCount 条，已选 $selectedCount 条',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              OutlinedButton.icon(
                onPressed: _working || visibleItemsAreAllSelected(visibleKeys)
                    ? null
                    : () => setState(() => _selectedKeys.addAll(visibleKeys)),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('选择当前筛选结果'),
              ),
              OutlinedButton.icon(
                onPressed: _working || selectedVisibleCount == 0
                    ? null
                    : () => setState(() => _selectedKeys.removeAll(visibleKeys)),
                icon: const Icon(Icons.remove_done_outlined, size: 18),
                label: const Text('取消当前选择'),
              ),
              FilledButton.icon(
                onPressed:
                    _working || !_selectedKeys.any((key) => key.startsWith('task:'))
                        ? null
                        : _completeSelectedTasks,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('完成所选任务'),
              ),
              FilledButton.icon(
                onPressed: _working || selectedCount == 0 ? null : _deleteSelected,
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除所选'),
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool visibleItemsAreAllSelected(Set<String> visibleKeys) {
    return visibleKeys.isNotEmpty && visibleKeys.every(_selectedKeys.contains);
  }

  List<_ManagementItem> _buildItems({
    required List<CalendarEvent> events,
    required List<TaskItem> tasks,
    required Map<int, String> calendarNames,
    required Map<int, String> taskListNames,
  }) {
    return [
      for (final event in events)
        _ManagementItem.event(
          event,
          containerName: calendarNames[event.eventCalendarId] ?? '日历本',
        ),
      for (final task in tasks)
        _ManagementItem.task(
          task,
          containerName: taskListNames[task.taskListId] ?? '任务本',
        ),
    ]..sort((left, right) {
        final leftTime = left.primaryTime;
        final rightTime = right.primaryTime;
        if (leftTime == null && rightTime == null) {
          return left.title.compareTo(right.title);
        }
        if (leftTime == null) {
          return 1;
        }
        if (rightTime == null) {
          return -1;
        }
        return leftTime.compareTo(rightTime);
      });
  }

  bool _matchesFilters(_ManagementItem item) {
    if (_typeFilter == _ManagementTypeFilter.events && !item.isEvent) {
      return false;
    }
    if (_typeFilter == _ManagementTypeFilter.tasks && !item.isTask) {
      return false;
    }
    if (_sourceFilter == _ManagementSourceFilter.local && item.source != 'local') {
      return false;
    }
    if (_sourceFilter == _ManagementSourceFilter.outlook &&
        item.source != 'outlook') {
      return false;
    }
    if (_statusFilter != 'all' && item.status != _statusFilter) {
      return false;
    }
    if (!_matchesTimeFilter(item)) {
      return false;
    }
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      item.title,
      item.containerName,
      item.description ?? '',
      item.location ?? '',
      item.status,
      item.sourceLabel,
    ].join(' ').toLowerCase();
    return haystack.contains(_query.toLowerCase());
  }

  bool _matchesTimeFilter(_ManagementItem item) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final primaryTime = item.primaryTime;
    switch (_timeFilter) {
      case _ManagementTimeFilter.all:
        return true;
      case _ManagementTimeFilter.today:
        return primaryTime != null &&
            !primaryTime.isBefore(todayStart) &&
            primaryTime.isBefore(todayEnd);
      case _ManagementTimeFilter.next7Days:
        return primaryTime != null &&
            !primaryTime.isBefore(todayStart) &&
            primaryTime.isBefore(todayStart.add(const Duration(days: 7)));
      case _ManagementTimeFilter.overdue:
        return item.isTask &&
            item.status != 'COMPLETED' &&
            primaryTime != null &&
            primaryTime.isBefore(now);
      case _ManagementTimeFilter.noTime:
        return primaryTime == null;
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedKeys.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除所选数据'),
        content: Text('确认删除已选的 ${selected.length} 条任务或日程吗？此操作会写入审计日志。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _working = true);
    try {
      for (final key in selected) {
        final parsed = _parseKey(key);
        if (parsed == null) {
          continue;
        }
        if (parsed.type == 'event') {
          await ref.read(eventRepositoryProvider).delete(
                parsed.id,
                action: 'management_delete',
                summary: '在全部数据管理中删除日程 #${parsed.id}',
              );
        } else {
          await ref.read(taskRepositoryProvider).delete(
                parsed.id,
                action: 'management_delete',
                summary: '在全部数据管理中删除任务 #${parsed.id}',
              );
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedKeys.clear();
        _working = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${selected.length} 条数据。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  Future<void> _completeSelectedTasks() async {
    final taskIds = _selectedKeys
        .map(_parseKey)
        .whereType<_ParsedManagementKey>()
        .where((item) => item.type == 'task')
        .map((item) => item.id)
        .toList(growable: false);
    if (taskIds.isEmpty) {
      return;
    }

    setState(() => _working = true);
    try {
      for (final id in taskIds) {
        await ref.read(taskRepositoryProvider).markCompleted(
              id,
              action: 'management_mark_completed',
              summary: '在全部数据管理中完成任务 #$id',
            );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedKeys.removeWhere((key) => key.startsWith('task:'));
        _working = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已完成 ${taskIds.length} 个任务。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('完成任务失败：$error')),
      );
    }
  }

  void _openItem(_ManagementItem item) {
    if (item.isEvent) {
      context.push('/event/${item.id}');
    } else {
      context.push('/task/${item.id}');
    }
  }

  static _ParsedManagementKey? _parseKey(String key) {
    final parts = key.split(':');
    if (parts.length != 2) {
      return null;
    }
    final id = int.tryParse(parts[1]);
    if (id == null) {
      return null;
    }
    return _ParsedManagementKey(type: parts[0], id: id);
  }

  static String _typeLabel(_ManagementTypeFilter value) {
    switch (value) {
      case _ManagementTypeFilter.all:
        return '全部类型';
      case _ManagementTypeFilter.events:
        return '只看日程';
      case _ManagementTypeFilter.tasks:
        return '只看任务';
    }
  }

  static String _sourceLabel(_ManagementSourceFilter value) {
    switch (value) {
      case _ManagementSourceFilter.all:
        return '全部来源';
      case _ManagementSourceFilter.local:
        return '本地';
      case _ManagementSourceFilter.outlook:
        return 'Outlook';
    }
  }

  static String _timeLabel(_ManagementTimeFilter value) {
    switch (value) {
      case _ManagementTimeFilter.all:
        return '全部时间';
      case _ManagementTimeFilter.today:
        return '今天';
      case _ManagementTimeFilter.next7Days:
        return '未来 7 天';
      case _ManagementTimeFilter.overdue:
        return '已过期';
      case _ManagementTimeFilter.noTime:
        return '无时间';
    }
  }
}

class _ManagementItemTile extends StatelessWidget {
  const _ManagementItemTile({
    required this.item,
    required this.selected,
    required this.onSelected,
    required this.onOpen,
  });

  final _ManagementItem item;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = item.isEvent ? AppColors.primary : const Color(0xFF0EA8A0);
    return ListTile(
      leading: Checkbox(
        value: selected,
        onChanged: onSelected == null
            ? null
            : (value) => onSelected!.call(value ?? false),
      ),
      title: Row(
        children: [
          Icon(
            item.isEvent ? Icons.event_outlined : Icons.checklist_outlined,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title.isEmpty ? '未命名' : item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.typeLabel} · ${item.containerName} · ${item.sourceLabel} · ${_statusLabel(item.status)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              item.timeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
            if ((item.description ?? '').isNotEmpty ||
                (item.location ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [
                  if ((item.location ?? '').isNotEmpty) '地点：${item.location}',
                  if ((item.description ?? '').isNotEmpty) '备注：${item.description}',
                ].join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      trailing: IconButton(
        tooltip: '打开详情',
        icon: const Icon(Icons.chevron_right),
        onPressed: onOpen,
      ),
      onTap: onOpen,
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'NEEDS-ACTION':
        return '待处理';
      case 'IN-PROCESS':
        return '进行中';
      case 'COMPLETED':
        return '已完成';
      case 'CONFIRMED':
        return '已确认';
      case 'TENTATIVE':
        return '暂定';
      case 'CANCELLED':
        return '已取消';
      default:
        return status;
    }
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      underline: const SizedBox(),
      hint: Text(label),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(labelOf(item)),
            ),
          )
          .toList(growable: false),
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('当前筛选条件下没有任务或日程。'),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('读取数据失败：$error'),
      ),
    );
  }
}

class _ManagementItem {
  const _ManagementItem({
    required this.key,
    required this.id,
    required this.typeLabel,
    required this.title,
    required this.containerName,
    required this.source,
    required this.status,
    required this.primaryTime,
    required this.timeLabel,
    required this.description,
    required this.location,
    required this.isEvent,
  });

  factory _ManagementItem.event(
    CalendarEvent event, {
    required String containerName,
  }) {
    final end = event.dtend;
    return _ManagementItem(
      key: 'event:${event.id}',
      id: event.id,
      typeLabel: '日程',
      title: event.summary,
      containerName: containerName,
      source: event.source,
      status: event.status,
      primaryTime: event.dtstart,
      timeLabel: end == null
          ? _formatDateTime(event.dtstart)
          : '${_formatDateTime(event.dtstart)} - ${_formatDateTime(end)}',
      description: event.description,
      location: event.location,
      isEvent: true,
    );
  }

  factory _ManagementItem.task(
    TaskItem task, {
    required String containerName,
  }) {
    final primaryTime = task.dtstart ?? task.due;
    return _ManagementItem(
      key: 'task:${task.id}',
      id: task.id,
      typeLabel: '任务',
      title: task.summary,
      containerName: containerName,
      source: 'local',
      status: task.status,
      primaryTime: primaryTime,
      timeLabel: _taskTimeLabel(task),
      description: task.description,
      location: null,
      isEvent: false,
    );
  }

  final String key;
  final int id;
  final String typeLabel;
  final String title;
  final String containerName;
  final String source;
  final String status;
  final DateTime? primaryTime;
  final String timeLabel;
  final String? description;
  final String? location;
  final bool isEvent;

  bool get isTask => !isEvent;

  String get sourceLabel {
    switch (source) {
      case 'outlook':
        return 'Outlook';
      case 'local':
        return '本地';
      default:
        return source;
    }
  }

  static String _taskTimeLabel(TaskItem task) {
    final parts = <String>[];
    if (task.dtstart != null) {
      parts.add('计划：${_formatDateTime(task.dtstart!)}');
    }
    if (task.due != null) {
      parts.add('截止：${_formatDateTime(task.due!)}');
    }
    if (parts.isEmpty) {
      return '未设置时间';
    }
    return parts.join('  ');
  }

  static String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class _ParsedManagementKey {
  const _ParsedManagementKey({
    required this.type,
    required this.id,
  });

  final String type;
  final int id;
}
