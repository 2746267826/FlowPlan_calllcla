import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_keys.dart';
import '../../../shared/providers/app_providers.dart';
import '../models/tracked_input_event.dart';

class TrackerInputHistoryPage extends ConsumerStatefulWidget {
  const TrackerInputHistoryPage({super.key});

  @override
  ConsumerState<TrackerInputHistoryPage> createState() =>
      _TrackerInputHistoryPageState();
}

class _TrackerInputHistoryPageState
    extends ConsumerState<TrackerInputHistoryPage> {
  late final TextEditingController _searchController;

  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  String? _selectedEventKind;
  int _currentOffset = 0;
  static const int _pageSize = 80;

  static const _eventKindOptions = <_EventKindOption>[
    _EventKindOption(value: null, label: '全部类型'),
    _EventKindOption(value: 'key_down', label: '按键按下'),
    _EventKindOption(value: 'key_up', label: '按键抬起'),
    _EventKindOption(value: 'mouse_button', label: '鼠标按键'),
    _EventKindOption(value: 'mouse_wheel', label: '滚轮'),
    _EventKindOption(value: 'mouse_move', label: '鼠标移动'),
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _currentOffset = 0;
    });
  }

  void _goToNextDay() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
      _currentOffset = 0;
    });
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _currentOffset = 0;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    setState(() {
      _selectedDate = picked;
      _currentOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final query = ServerInputEventQuery(
      start: dayStart,
      end: dayEnd,
      eventKind: _selectedEventKind,
      limit: _pageSize,
      offset: _currentOffset,
    );
    final eventsAsync = ref.watch(serverInputEventsPageProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('完整输入历史'),
        actions: [
          IconButton(
            tooltip: '跳转到今天',
            onPressed: _goToToday,
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wideLayout = constraints.maxWidth >= 1024;
          if (wideLayout) {
            return Row(
              children: [
                SizedBox(
                  width: 320,
                  child: _buildFilterPanel(context),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _buildDetailPanel(
                    context,
                    eventsAsync: eventsAsync,
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              SizedBox(
                height: 260,
                child: _buildFilterPanel(context),
              ),
              const Divider(height: 1),
              Expanded(
                child: _buildDetailPanel(
                  context,
                  eventsAsync: eventsAsync,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '前一天',
                    onPressed: _goToPreviousDay,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Text(
                        _formatDate(_selectedDate),
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '后一天',
                    onPressed: _goToNextDay,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '从服务端查询指定日期的输入事件，数据来源于客户端定期上传的追踪缓冲。',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '事件类型',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            ..._eventKindOptions.map(
              (option) => _FilterChipTile(
                label: option.label,
                selected: _selectedEventKind == option.value,
                onTap: () {
                  setState(() {
                    _selectedEventKind = option.value;
                    _currentOffset = 0;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel(
    BuildContext context, {
    required AsyncValue<Map<String, dynamic>> eventsAsync,
  }) {
    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                '读取服务端输入事件失败',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(serverInputEventsPageProvider),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (response) {
        final items = _serverItems(response);
        final totalEstimate = _intValue(response['total']);

        final events = items
            .map(_eventFromServerItem)
            .whereType<_ServerInputEvent>()
            .toList(growable: false)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        final hasMore = events.length >= _pageSize;
        final hasPrevious = _currentOffset > 0;

        final filteredEvents = _searchQuery.trim().isEmpty
            ? events
            : events.where((e) => _matchesEvent(e, _searchQuery)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatDate(_selectedDate)} 输入事件',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    totalEstimate > 0
                        ? '服务端共 $totalEstimate 条事件，当前显示第 ${_currentOffset + 1}-${_currentOffset + events.length} 条'
                        : events.isNotEmpty
                            ? '当前显示 ${events.length} 条事件'
                            : '该日期暂无输入事件',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: '搜索进程名、窗口标题、按键标签',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredEvents.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchQuery.trim().isNotEmpty
                              ? '没有找到匹配的输入事件，请尝试放宽搜索条件。'
                              : '这一天暂无来自服务端的输入事件。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        return _InputEventTile(event: filteredEvents[index]);
                      },
                    ),
            ),
            if (hasPrevious || hasMore)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: AppKeys.trackerInputHistoryPreviousPageButton,
                      onPressed: hasPrevious
                          ? () {
                              setState(() {
                                _currentOffset = (_currentOffset - _pageSize)
                                    .clamp(0, 1 << 31);
                              });
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left, size: 16),
                      label: const Text('上一页'),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '第 ${(_currentOffset / _pageSize).floor() + 1} 页',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      key: AppKeys.trackerInputHistoryNextPageButton,
                      onPressed: hasMore
                          ? () {
                              setState(() {
                                _currentOffset += _pageSize;
                              });
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right, size: 16),
                      label: const Text('下一页'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  bool _matchesEvent(_ServerInputEvent event, String searchQuery) {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;

    final target = <String>[
      if (event.processName != null) event.processName!,
      if (event.windowTitle != null) event.windowTitle!,
      if (event.category != null) event.category!,
      if (event.keyLabel != null) event.keyLabel!,
      if (event.activityLabel != null) event.activityLabel!,
      event.kind.value,
    ].join(' ').toLowerCase();

    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    return tokens.every(target.contains);
  }
}

class _EventKindOption {
  final String? value;
  final String label;

  const _EventKindOption({required this.value, required this.label});
}

class _FilterChipTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          selected ? Icons.filter_alt : Icons.filter_alt_outlined,
          color: selected ? AppColors.primary : null,
          size: 20,
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ServerInputEvent {
  final String uid;
  final int sequenceId;
  final DateTime timestamp;
  final TrackedInputEventKind kind;
  final int eventCount;
  final bool isIgnored;
  final String? processName;
  final String? className;
  final String? windowTitle;
  final String? category;
  final String? activityLabel;
  final int? keyCode;
  final String? keyLabel;
  final String? mouseButton;
  final int wheelDelta;
  final int deltaX;
  final int deltaY;
  final int moveDistance;
  final String? tokenText;

  const _ServerInputEvent({
    required this.uid,
    required this.sequenceId,
    required this.timestamp,
    required this.kind,
    required this.eventCount,
    required this.isIgnored,
    this.processName,
    this.className,
    this.windowTitle,
    this.category,
    this.activityLabel,
    this.keyCode,
    this.keyLabel,
    this.mouseButton,
    required this.wheelDelta,
    required this.deltaX,
    required this.deltaY,
    required this.moveDistance,
    this.tokenText,
  });
}

class _InputEventTile extends StatelessWidget {
  final _ServerInputEvent event;

  const _InputEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final title = event.activityLabel?.trim().isNotEmpty == true
        ? event.activityLabel!.trim()
        : (event.windowTitle?.trim().isNotEmpty == true
            ? event.windowTitle!.trim()
            : (event.processName?.trim().isNotEmpty == true
                ? event.processName!.trim()
                : '未命名事件'));

    final subtitle = <String>[
      if (event.category != null && event.category!.trim().isNotEmpty)
        event.category!.trim(),
      if (event.processName != null && event.processName!.trim().isNotEmpty)
        event.processName!.trim(),
      if (event.isIgnored) '自排除',
    ].join(' · ');

    final details = <String>[
      if (event.keyCode != null) '键码：${event.keyCode}',
      if (event.keyLabel != null && event.keyLabel!.trim().isNotEmpty)
        '按键：${event.keyLabel!.trim()}',
      if (event.mouseButton != null && event.mouseButton!.trim().isNotEmpty)
        '鼠标按钮：${event.mouseButton!.trim()}',
      if (event.wheelDelta != 0) '滚轮增量：${event.wheelDelta}',
      if (event.deltaX != 0 || event.deltaY != 0)
        '位移：(${event.deltaX}, ${event.deltaY})',
      if (event.moveDistance > 0) '移动距离：${event.moveDistance}px',
      if (event.tokenText != null && event.tokenText!.trim().isNotEmpty)
        '输入字符：${event.tokenText!.trim()}',
      '序号：${event.sequenceId}',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  _formatTime(event.timestamp),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _KindBadge(kind: event.kind),
              const SizedBox(width: 6),
              if (event.eventCount > 1) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '×${event.eventCount}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: details
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final TrackedInputEventKind kind;

  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _kindLabel(kind),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }

  Color get _color {
    switch (kind) {
      case TrackedInputEventKind.keyDown:
      case TrackedInputEventKind.keyUp:
        return const Color(0xFF6B5EE4);
      case TrackedInputEventKind.mouseButtonDown:
      case TrackedInputEventKind.mouseButtonUp:
      case TrackedInputEventKind.mouseButton:
        return const Color(0xFF0EA8A0);
      case TrackedInputEventKind.mouseWheel:
        return const Color(0xFFF5935A);
      case TrackedInputEventKind.mouseMove:
        return const Color(0xFFE05A7A);
    }
  }
}

_ServerInputEvent? _eventFromServerItem(Map<String, Object?> item) {
  final payload = _asMap(item['payload']);
  final timestamp = _dateValue(
    payload['timestamp'] ?? payload['occurredAt'] ?? item['occurredAt'],
  );
  if (timestamp == null) return null;

  final uid = _stringValue(
        payload['eventUid'] ?? payload['event_uid'] ?? item['serverId'],
      ) ??
      timestamp.toIso8601String();

  final kindStr =
      _stringValue(payload['eventKind'] ?? payload['kind']) ?? 'key_down';

  return _ServerInputEvent(
    uid: uid,
    sequenceId: _intValue(payload['sequenceId'] ?? payload['sequence_id'],
        fallback: _stablePositiveId(uid)),
    timestamp: timestamp,
    kind: _parseKind(kindStr),
    eventCount:
        _intValue(payload['eventCount'] ?? item['metricCount'], fallback: 1),
    isIgnored:
        payload['isIgnored'] is bool ? payload['isIgnored'] as bool : false,
    processName:
        _stringValue(payload['processName'] ?? payload['process_name']),
    className: _stringValue(payload['className']),
    windowTitle:
        _stringValue(payload['windowTitle'] ?? payload['window_title']),
    category: _stringValue(payload['category']),
    activityLabel: _stringValue(payload['activityLabel']),
    keyCode: _intOrNull(payload['keyCode']),
    keyLabel: _stringValue(payload['keyLabel']),
    mouseButton: _stringValue(payload['mouseButton']),
    wheelDelta: _intValue(payload['wheelDelta']),
    deltaX: _intValue(payload['deltaX']),
    deltaY: _intValue(payload['deltaY']),
    moveDistance:
        _intValue(payload['moveDistance'] ?? payload['move_distance']),
    tokenText: _stringValue(payload['tokenText']),
  );
}

TrackedInputEventKind _parseKind(String value) {
  switch (value) {
    case 'key_down':
      return TrackedInputEventKind.keyDown;
    case 'key_up':
      return TrackedInputEventKind.keyUp;
    case 'mouse_button_down':
      return TrackedInputEventKind.mouseButtonDown;
    case 'mouse_button_up':
      return TrackedInputEventKind.mouseButtonUp;
    case 'mouse_button':
      return TrackedInputEventKind.mouseButton;
    case 'mouse_wheel':
      return TrackedInputEventKind.mouseWheel;
    case 'mouse_move':
      return TrackedInputEventKind.mouseMove;
    default:
      return TrackedInputEventKind.keyDown;
  }
}

String _kindLabel(TrackedInputEventKind kind) {
  switch (kind) {
    case TrackedInputEventKind.keyDown:
      return '按键按下';
    case TrackedInputEventKind.keyUp:
      return '按键抬起';
    case TrackedInputEventKind.mouseButtonDown:
      return '鼠标按下';
    case TrackedInputEventKind.mouseButtonUp:
      return '鼠标抬起';
    case TrackedInputEventKind.mouseButton:
      return '鼠标按键';
    case TrackedInputEventKind.mouseWheel:
      return '滚轮';
    case TrackedInputEventKind.mouseMove:
      return '鼠标移动';
  }
}

List<Map<String, Object?>> _serverItems(Map<String, dynamic> response) {
  final items = response['items'];
  if (items is! List) return const <Map<String, Object?>>[];
  return items
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return Map<String, Object?>.from(value);
  if (value is Map) return Map<String, Object?>.from(value);
  return const <String, Object?>{};
}

DateTime? _dateValue(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) return parsed.round();
  }
  return fallback;
}

int? _intOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return num.tryParse(value)?.round();
  return null;
}

int _stablePositiveId(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
