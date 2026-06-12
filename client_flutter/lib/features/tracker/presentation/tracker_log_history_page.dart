import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_keys.dart';
import '../../../shared/providers/app_providers.dart';

class TrackerLogHistoryPage extends ConsumerStatefulWidget {
  const TrackerLogHistoryPage({super.key});

  @override
  ConsumerState<TrackerLogHistoryPage> createState() =>
      _TrackerLogHistoryPageState();
}

class _TrackerLogHistoryPageState extends ConsumerState<TrackerLogHistoryPage> {
  late final TextEditingController _searchController;

  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  String? _selectedProcess;
  String? _selectedCategory;
  int _currentOffset = 0;
  static const int _pageSize = 50;

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
    final filterOptions = ref.watch(trackerHistoryFilterOptionsProvider);
    final processOptions = filterOptions.processOptions;
    final categoryOptions = filterOptions.categoryOptions;

    final selectedProcess =
        processOptions.contains(_selectedProcess) ? _selectedProcess : null;
    final selectedCategory =
        categoryOptions.contains(_selectedCategory) ? _selectedCategory : null;

    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final query = ServerRecordQuery(
      start: dayStart,
      end: dayEnd,
      processName: selectedProcess,
      category: selectedCategory,
      limit: _pageSize,
      offset: _currentOffset,
    );
    final recordsAsync = ref.watch(serverActivityRecordsPageProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史活动记录'),
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
          final wideLayout = constraints.maxWidth >= 980;
          if (wideLayout) {
            return Row(
              children: [
                SizedBox(
                  width: 300,
                  child: _buildDatePanel(
                    context,
                    processOptions: processOptions,
                    categoryOptions: categoryOptions,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _buildDetailPanel(
                    context,
                    recordsAsync: recordsAsync,
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              SizedBox(
                height: 220,
                child: _buildDatePanel(
                  context,
                  processOptions: processOptions,
                  categoryOptions: categoryOptions,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _buildDetailPanel(
                  context,
                  recordsAsync: recordsAsync,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDatePanel(
    BuildContext context, {
    required List<String> processOptions,
    required List<String> categoryOptions,
  }) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
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
                    key: const Key('tracker-log-history-date-picker'),
                    onTap: _pickDate,
                    child: Text(
                      _formatDate(_selectedDate),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '从服务端查询指定日期的活动记录，数据来源于客户端定期上传的追踪缓冲。',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          if (processOptions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '应用筛选',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: processOptions.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _FilterChipTile(
                      label: '全部应用',
                      selected: _selectedProcess == null,
                      onTap: () {
                        setState(() {
                          _selectedProcess = null;
                          _currentOffset = 0;
                        });
                      },
                    );
                  }
                  final process = processOptions[index - 1];
                  return _FilterChipTile(
                    label: process,
                    selected: _selectedProcess == process,
                    onTap: () {
                      setState(() {
                        _selectedProcess =
                            _selectedProcess == process ? null : process;
                        _currentOffset = 0;
                      });
                    },
                  );
                },
              ),
            ),
          ] else
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '加载筛选选项中...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(
    BuildContext context, {
    required AsyncValue<Map<String, dynamic>> recordsAsync,
  }) {
    return recordsAsync.when(
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
                '读取服务端活动记录失败',
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
                onPressed: () =>
                    ref.invalidate(serverActivityRecordsPageProvider),
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

        final records = items.map(_recordFromServerItem).toList(growable: false)
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

        final hasMore = records.length >= _pageSize;
        final hasPrevious = _currentOffset > 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatDate(_selectedDate)} 活动记录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    totalEstimate > 0
                        ? '服务端共 $totalEstimate 条记录，当前显示第 ${_currentOffset + 1}-${_currentOffset + records.length} 条'
                        : records.isNotEmpty
                            ? '当前显示 ${records.length} 条记录'
                            : '该日期暂无活动记录',
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
                  hintText: '搜索进程名、窗口标题、分类',
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
              child: records.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchQuery.trim().isNotEmpty
                              ? '没有找到匹配的活动记录，请尝试放宽搜索条件。'
                              : '这一天暂无来自服务端的活动记录。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        if (!_matchesRecord(record, _searchQuery)) {
                          return const SizedBox.shrink();
                        }
                        return _ServerRecordTile(record: record);
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
                      key: AppKeys.trackerLogHistoryPreviousPageButton,
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
                      key: AppKeys.trackerLogHistoryNextPageButton,
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

  bool _matchesRecord(_ServerRecord record, String searchQuery) {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final target = <String>[
      if (record.processName != null) record.processName!,
      if (record.windowTitle != null) record.windowTitle!,
      if (record.category != null) record.category!,
      if (record.manualLabel != null) record.manualLabel!,
    ].join(' ').toLowerCase();

    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);

    return tokens.every(target.contains);
  }
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

class _ServerRecordTile extends StatelessWidget {
  final _ServerRecord record;

  const _ServerRecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final title = record.manualLabel?.trim().isNotEmpty == true
        ? record.manualLabel!.trim()
        : (record.windowTitle?.trim().isNotEmpty == true
            ? record.windowTitle!.trim()
            : (record.processName?.trim().isNotEmpty == true
                ? record.processName!.trim()
                : '未命名记录'));

    final subtitle = <String>[
      if (record.category != null && record.category!.trim().isNotEmpty)
        record.category!.trim(),
      if (record.processName != null && record.processName!.trim().isNotEmpty)
        record.processName!.trim(),
    ].join(' · ');

    final metrics = <String>[
      if (record.keyCount > 0) '${record.keyCount} 次按键',
      if (record.mouseClicks > 0) '${record.mouseClicks} 次点击',
      if (record.mouseMovePx > 0) '${record.mouseMovePx}px 移动',
      if (record.scrollPx > 0) '${record.scrollPx}px 滚动',
      if (record.durationMinutes > 0) '${record.durationMinutes} 分钟',
    ];

    final detailLines = <String>[
      if (record.windowTitle != null &&
          record.windowTitle!.trim().isNotEmpty &&
          record.windowTitle!.trim() != title)
        '窗口标题：${record.windowTitle!.trim()}',
      if (record.processName != null && record.processName!.trim().isNotEmpty)
        '进程名：${record.processName!.trim()}',
      if (record.linkedTaskId != null) '关联任务：#${record.linkedTaskId}',
      if (record.source != null && record.source!.trim().isNotEmpty)
        '来源：${record.source!.trim()}',
    ];

    final hasDetails = detailLines.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
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
                width: 92,
                child: Text(
                  _formatDateTimeShort(record.startTime),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(
                label: record.isAuto ? '自动' : '手动',
                color: record.isAuto
                    ? const Color(0xFF0EA8A0)
                    : const Color(0xFF6B5EE4),
              ),
              const SizedBox(width: 8),
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
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (hasDetails) ...[
            const SizedBox(height: 8),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: const Text(
                  '查看详情',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                children: [
                  for (final line in detailLines)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ServerRecord {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationMinutes;
  final String? processName;
  final String? windowTitle;
  final String? category;
  final String? manualLabel;
  final int? linkedTaskId;
  final int keyCount;
  final int mouseClicks;
  final int mouseMovePx;
  final int scrollPx;
  final bool isAuto;
  final String? source;

  const _ServerRecord({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.durationMinutes,
    this.processName,
    this.windowTitle,
    this.category,
    this.manualLabel,
    this.linkedTaskId,
    required this.keyCount,
    required this.mouseClicks,
    required this.mouseMovePx,
    required this.scrollPx,
    required this.isAuto,
    this.source,
  });
}

_ServerRecord _recordFromServerItem(Map<String, Object?> item) {
  final payload = _asMap(item['payload']);
  final start = _dateValue(
        payload['startTime'] ??
            payload['start_time'] ??
            payload['startedAt'] ??
            item['occurredAt'],
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final durationMinutes = _intValue(
    payload['durationMinutes'] ??
        payload['duration_minutes'] ??
        item['metricMinutes'],
    fallback: 1,
  );
  final end = _dateValue(
        payload['endTime'] ?? payload['end_time'] ?? payload['endedAt'],
      ) ??
      start.add(Duration(minutes: durationMinutes));
  return _ServerRecord(
    id: _stablePositiveId(
        _stringValue(item['serverId']) ?? start.toIso8601String()),
    startTime: start,
    endTime: end,
    durationMinutes: durationMinutes,
    processName: _stringValue(payload['processName'] ??
        payload['process_name'] ??
        payload['packageName']),
    windowTitle: _stringValue(
        payload['windowTitle'] ?? payload['window_title'] ?? payload['title']),
    category: _stringValue(payload['category']),
    manualLabel: _stringValue(
        payload['manualLabel'] ?? payload['manual_label'] ?? payload['label']),
    linkedTaskId:
        _intOrNull(payload['linkedTaskId'] ?? payload['linked_task_id']),
    keyCount: _intValue(payload['keyCount'] ?? payload['key_count']),
    mouseClicks: _intValue(payload['mouseClicks'] ?? payload['mouse_clicks']),
    mouseMovePx: _intValue(payload['mouseMovePx'] ?? payload['mouse_move_px']),
    scrollPx: _intValue(payload['scrollPx'] ?? payload['scroll_px']),
    isAuto: payload['isAuto'] is bool ? payload['isAuto'] as bool : true,
    source: _stringValue(item['objectType']),
  );
}

List<Map<String, Object?>> _serverItems(Map<String, dynamic> response) {
  final items = response['items'];
  if (items is! List) {
    return const <Map<String, Object?>>[];
  }
  return items
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
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
  return '$hour:$minute';
}

String _formatDateTimeShort(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return '$month-$day ${_formatTime(dateTime)}';
}
