import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../models/activity_log_archive_day.dart';
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

  DateTime? _selectedDate;
  String _searchQuery = '';
  TrackedInputEventKind? _selectedKind;
  bool _includeIgnored = true;

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

  Future<void> _openFolder(BuildContext context, String folderPath) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folderPath]);
      }

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已打开输入日志目录：$folderPath'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开输入日志目录失败：$error'),
        ),
      );
    }
  }

  Future<void> _pickArchiveDay(
    BuildContext context,
    List<ActivityLogArchiveDay> days,
  ) async {
    if (days.isEmpty) {
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _resolveSelectedDate(days) ?? days.first.date,
      firstDate: days.last.date,
      lastDate: days.first.date,
    );
    if (picked == null || !mounted) {
      return;
    }

    final matchedDay = _findArchiveDay(days, picked);
    if (matchedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('没有找到 ${_formatDate(picked)} 的输入历史文件'),
        ),
      );
      return;
    }

    setState(() {
      _selectedDate = matchedDay.date;
    });
  }

  Future<void> _exportFilteredEvents(
    BuildContext context, {
    required ActivityLogArchiveDay selectedDay,
    required List<TrackedInputEvent> filteredEvents,
  }) async {
    if (filteredEvents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有可导出的输入事件'),
        ),
      );
      return;
    }

    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出当前筛选后的输入历史',
        fileName: '${_formatDate(selectedDay.date)}.input-events.filtered.jsonl',
        type: FileType.custom,
        allowedExtensions: const ['jsonl'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        return;
      }

      final file = File(outputPath);
      await file.parent.create(recursive: true);
      final contents = filteredEvents
          .map((event) => jsonEncode(event.toJson()))
          .join('\n');
      await file.writeAsString('$contents\n', flush: true);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${filteredEvents.length} 条输入事件到：$outputPath',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出输入历史失败：$error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final archivePathAsync = ref.watch(inputEventArchiveDirectoryPathProvider);
    final archiveDaysAsync = ref.watch(inputEventArchiveDaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('完整输入历史'),
      ),
      body: archiveDaysAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('读取输入历史失败：$error'),
          ),
        ),
        data: (days) {
          final selectedDate = _resolveSelectedDate(days);
          final selectedDay = selectedDate == null
              ? null
              : _findArchiveDay(days, selectedDate);
          final eventsAsync = selectedDate == null
              ? const AsyncData<List<TrackedInputEvent>>(<TrackedInputEvent>[])
              : ref.watch(inputEventArchiveEntriesForDateProvider(selectedDate));

          return LayoutBuilder(
            builder: (context, constraints) {
              final wideLayout = constraints.maxWidth >= 1024;
              if (wideLayout) {
                return Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: _buildDayPanel(
                        context,
                        days: days,
                        selectedDate: selectedDate,
                        archivePathAsync: archivePathAsync,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _buildDetailPanel(
                        context,
                        selectedDay: selectedDay,
                        eventsAsync: eventsAsync,
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  SizedBox(
                    height: 280,
                    child: _buildDayPanel(
                      context,
                      days: days,
                      selectedDate: selectedDate,
                      archivePathAsync: archivePathAsync,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildDetailPanel(
                      context,
                      selectedDay: selectedDay,
                      eventsAsync: eventsAsync,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDayPanel(
    BuildContext context, {
    required List<ActivityLogArchiveDay> days,
    required DateTime? selectedDate,
    required AsyncValue<String> archivePathAsync,
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
                Expanded(
                  child: Text(
                    '按天分割的输入日志',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (days.isNotEmpty)
                  IconButton(
                    tooltip: '跳转日期',
                    onPressed: () => _pickArchiveDay(context, days),
                    icon: const Icon(Icons.event_outlined),
                  ),
                archivePathAsync.maybeWhen(
                  data: (path) => IconButton(
                    tooltip: '打开日志目录',
                    onPressed: () => _openFolder(context, path),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              days.isEmpty
                  ? '还没有可浏览的输入历史文件。'
                  : '共 ${days.length} 天，完整保留键盘与鼠标事件的原始顺序。',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: archivePathAsync.when(
              loading: () => const Text(
                '正在定位输入日志目录…',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              error: (error, _) => Text(
                '输入日志目录读取失败：$error',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
              data: (path) => Text(
                '目录：$path',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (days.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '追踪开始写入后，这里会按天出现输入历史文件，可用于回看完整输入顺序。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final selected = _isSameDay(selectedDate, day.date);
                  return Card(
                    elevation: 0,
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).cardColor,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () {
                        setState(() {
                          _selectedDate = day.date;
                        });
                      },
                      leading: Icon(
                        selected
                            ? Icons.keyboard_alt
                            : Icons.keyboard_alt_outlined,
                        color: selected ? AppColors.primary : null,
                      ),
                      title: Text(
                        _formatDate(day.date),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '文件大小：${_formatFileSize(day.fileSizeBytes)}',
                      ),
                      trailing:
                          selected ? const Icon(Icons.chevron_right) : null,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(
    BuildContext context, {
    required ActivityLogArchiveDay? selectedDay,
    required AsyncValue<List<TrackedInputEvent>> eventsAsync,
  }) {
    if (selectedDay == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '请选择一天的输入历史文件开始查看。',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('读取输入历史失败：$error'),
        ),
      ),
      data: (events) {
        final filteredEvents = events
            .where(
              (event) => _matchesEvent(
                event,
                searchQuery: _searchQuery,
                selectedKind: _selectedKind,
                includeIgnored: _includeIgnored,
              ),
            )
            .toList(growable: false);
        final hasActiveFilters =
            _searchQuery.trim().isNotEmpty ||
            _selectedKind != null ||
            !_includeIgnored;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatDate(selectedDay.date)} 输入历史',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '文件：${selectedDay.filePath}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasActiveFilters
                        ? '当前命中 ${filteredEvents.length}/${events.length} 条输入事件。'
                        : '当前文件共有 ${events.length} 条输入事件，列表保持原始顺序。',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: filteredEvents.isEmpty
                            ? null
                            : () => _exportFilteredEvents(
                                  context,
                                  selectedDay: selectedDay,
                                  filteredEvents: filteredEvents,
                                ),
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('导出当前结果'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: '搜索按键、字符、应用、窗口、分类、序号',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('全部类型'),
                    selected: _selectedKind == null,
                    onSelected: (_) {
                      setState(() {
                        _selectedKind = null;
                      });
                    },
                  ),
                  ...TrackedInputEventKind.values.map(
                    (kind) => ChoiceChip(
                      label: Text(_kindLabel(kind)),
                      selected: _selectedKind == kind,
                      onSelected: (_) {
                        setState(() {
                          _selectedKind = kind;
                        });
                      },
                    ),
                  ),
                  FilterChip(
                    label: const Text('包含自排除记录'),
                    selected: _includeIgnored,
                    onSelected: (value) {
                      setState(() {
                        _includeIgnored = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredEvents.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          hasActiveFilters
                              ? '没有找到匹配的输入事件，请尝试放宽搜索或恢复筛选。'
                              : '这一天的输入历史文件里还没有内容。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        return _TrackedInputEventTile(
                          event: filteredEvents[index],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  DateTime? _resolveSelectedDate(List<ActivityLogArchiveDay> days) {
    if (days.isEmpty) {
      return null;
    }

    if (_selectedDate == null) {
      return days.first.date;
    }

    for (final day in days) {
      if (_isSameDay(day.date, _selectedDate)) {
        return day.date;
      }
    }

    return days.first.date;
  }

  ActivityLogArchiveDay? _findArchiveDay(
    List<ActivityLogArchiveDay> days,
    DateTime date,
  ) {
    for (final day in days) {
      if (_isSameDay(day.date, date)) {
        return day;
      }
    }
    return null;
  }

  bool _isSameDay(DateTime? left, DateTime? right) {
    if (left == null || right == null) {
      return false;
    }

    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _TrackedInputEventTile extends StatelessWidget {
  const _TrackedInputEventTile({
    required this.event,
  });

  final TrackedInputEvent event;

  @override
  Widget build(BuildContext context) {
    final title = _eventTitle(event);
    final subtitleParts = <String>[
      if (event.activityLabel != null && event.activityLabel!.trim().isNotEmpty)
        event.activityLabel!.trim(),
      if (event.category != null && event.category!.trim().isNotEmpty)
        event.category!.trim(),
      if (event.processName != null && event.processName!.trim().isNotEmpty)
        event.processName!.trim(),
      if (event.isIgnored) '自排除',
    ];
    final detailLines = <String>[
      if (event.windowTitle != null && event.windowTitle!.trim().isNotEmpty)
        '窗口标题：${event.windowTitle!.trim()}',
      if (event.className != null && event.className!.trim().isNotEmpty)
        '窗口类名：${event.className!.trim()}',
      if (event.recordId != null) '关联记录：#${event.recordId}',
      if (event.keyCode != null) '键值代码：${event.keyCode}',
      if (event.keyLabel != null && event.keyLabel!.trim().isNotEmpty)
        '按键名称：${event.keyLabel!.trim()}',
      if (event.mouseButton != null && event.mouseButton!.trim().isNotEmpty)
        '鼠标按钮：${inputMouseButtonLabel(event.mouseButton!.trim())}',
      if (event.wheelDelta != 0) '滚轮增量：${event.wheelDelta}',
      if (event.deltaX != 0 || event.deltaY != 0)
        '位移向量：(${event.deltaX}, ${event.deltaY})',
      if (event.moveDistance > 0) '移动距离：${event.moveDistance}px',
      if (event.tokenText != null && event.tokenText!.isNotEmpty)
        '输入字符：${describeInputToken(event.tokenText)}',
      '事件标识：${event.eventUid}',
    ];

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTime(event.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${event.sequenceId}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _InputKindBadge(
                label: _kindLabel(event.kind),
                color: _kindColor(event),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (subtitleParts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitleParts.join(' · '),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (event.windowTitle != null && event.windowTitle!.trim().isNotEmpty)
                _buildTag('窗口已记录'),
              if (event.tokenText != null && event.tokenText!.isNotEmpty)
                _buildTag('字符输入'),
              if (event.recordId != null) _buildTag('已关联活动记录'),
              if (event.moveDistance > 0) _buildTag('${event.moveDistance}px'),
            ],
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text(
                '查看事件详情',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              children: [
                for (final line in detailLines)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(
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
      ),
    );
  }
}

class _InputKindBadge extends StatelessWidget {
  const _InputKindBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

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

Color _kindColor(TrackedInputEvent event) {
  if (event.isIgnored) {
    return const Color(0xFFF5935A);
  }
  switch (event.kind) {
    case TrackedInputEventKind.keyDown:
      return const Color(0xFF6B5EE4);
    case TrackedInputEventKind.mouseButton:
      return const Color(0xFF0EA8A0);
    case TrackedInputEventKind.mouseWheel:
      return const Color(0xFFE05A7A);
    case TrackedInputEventKind.mouseMove:
      return const Color(0xFF4C8BF5);
  }
}

String _kindLabel(TrackedInputEventKind kind) {
  switch (kind) {
    case TrackedInputEventKind.keyDown:
      return '按键';
    case TrackedInputEventKind.mouseButton:
      return '鼠标按钮';
    case TrackedInputEventKind.mouseWheel:
      return '滚轮';
    case TrackedInputEventKind.mouseMove:
      return '鼠标移动';
  }
}

String _eventTitle(TrackedInputEvent event) {
  switch (event.kind) {
    case TrackedInputEventKind.keyDown:
      final token = describeInputToken(event.tokenText);
      if (token.isNotEmpty) {
        return '按键 $token';
      }
      if (event.keyLabel != null && event.keyLabel!.trim().isNotEmpty) {
        return '按键 ${event.keyLabel!.trim()}';
      }
      if (event.keyCode != null) {
        return '按键 VK_${event.keyCode}';
      }
      return '按键事件';
    case TrackedInputEventKind.mouseButton:
      if (event.mouseButton != null && event.mouseButton!.trim().isNotEmpty) {
        return '鼠标${inputMouseButtonLabel(event.mouseButton!.trim())}';
      }
      return '鼠标按钮事件';
    case TrackedInputEventKind.mouseWheel:
      if (event.mouseButton != null && event.mouseButton!.trim().isNotEmpty) {
        return '滚轮 ${inputMouseButtonLabel(event.mouseButton!.trim())}';
      }
      return '滚轮 ${event.wheelDelta}';
    case TrackedInputEventKind.mouseMove:
      if (event.moveDistance > 0) {
        return '鼠标移动 ${event.moveDistance}px';
      }
      return '鼠标移动';
  }
}

bool _matchesEvent(
  TrackedInputEvent event, {
  required String searchQuery,
  required TrackedInputEventKind? selectedKind,
  required bool includeIgnored,
}) {
  if (!includeIgnored && event.isIgnored) {
    return false;
  }

  if (selectedKind != null && event.kind != selectedKind) {
    return false;
  }

  final target = <String>[
    event.sequenceId.toString(),
    _eventTitle(event),
    if (event.keyLabel != null) event.keyLabel!,
    if (event.tokenText != null) describeInputToken(event.tokenText),
    if (event.processName != null) event.processName!,
    if (event.windowTitle != null) event.windowTitle!,
    if (event.className != null) event.className!,
    if (event.category != null) event.category!,
    if (event.activityLabel != null) event.activityLabel!,
    if (event.mouseButton != null) inputMouseButtonLabel(event.mouseButton!),
  ].join(' ');

  return _matchesSearchText(target, searchQuery);
}

bool _matchesSearchText(String target, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }

  final normalizedTarget = target.toLowerCase();
  final tokens = normalizedQuery
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  if (tokens.isEmpty) {
    return true;
  }

  return tokens.every(normalizedTarget.contains);
}

Widget _buildTag(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
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

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
