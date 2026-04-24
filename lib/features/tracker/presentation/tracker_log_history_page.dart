import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../models/activity_log_archive_day.dart';
import '../models/activity_log_entry.dart';

class TrackerLogHistoryPage extends ConsumerStatefulWidget {
  const TrackerLogHistoryPage({super.key});

  @override
  ConsumerState<TrackerLogHistoryPage> createState() =>
      _TrackerLogHistoryPageState();
}

class _TrackerLogHistoryPageState extends ConsumerState<TrackerLogHistoryPage> {
  late final TextEditingController _searchController;

  DateTime? _selectedDate;
  String _searchQuery = '';
  ActivityLogEntryType? _selectedType;

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
    if (picked == null || !context.mounted) {
      return;
    }

    final matchedDay = _findArchiveDay(days, picked);
    if (matchedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('没有找到 ${_formatDate(picked)} 的历史日志文件'),
        ),
      );
      return;
    }

    setState(() {
      _selectedDate = matchedDay.date;
    });
  }

  Future<void> _exportFilteredEntries(
    BuildContext context, {
    required ActivityLogArchiveDay selectedDay,
    required List<ActivityLogEntry> filteredEntries,
  }) async {
    if (filteredEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有可导出的历史日志'),
        ),
      );
      return;
    }

    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出当前筛选后的历史日志',
        fileName: '${_formatDate(selectedDay.date)}.activity.filtered.jsonl',
        type: FileType.custom,
        allowedExtensions: const ['jsonl'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        return;
      }

      final file = File(outputPath);
      await file.parent.create(recursive: true);
      final contents =
          filteredEntries.map((entry) => jsonEncode(entry.toJson())).join('\n');
      await file.writeAsString('$contents\n', flush: true);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${filteredEntries.length} 条历史日志到：$outputPath',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出历史日志失败：$error'),
        ),
      );
    }
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
          content: Text('\u5df2\u6253\u5f00\u65e5\u5fd7\u76ee\u5f55\uff1a$folderPath'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u6253\u5f00\u65e5\u5fd7\u76ee\u5f55\u5931\u8d25\uff1a$error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final archivePathAsync = ref.watch(activityLogArchiveDirectoryPathProvider);
    final archiveDaysAsync = ref.watch(activityLogArchiveDaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u5386\u53f2\u65e5\u5fd7\u6587\u4ef6'),
        actions: [
          archivePathAsync.maybeWhen(
            data: (path) => IconButton(
              tooltip: '\u6253\u5f00\u65e5\u5fd7\u76ee\u5f55',
              onPressed: () => _openFolder(context, path),
              icon: const Icon(Icons.folder_open_outlined),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: archiveDaysAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '\u8bfb\u53d6\u5386\u53f2\u65e5\u5fd7\u6587\u4ef6\u5931\u8d25\uff1a$error',
            ),
          ),
        ),
        data: (days) {
          final selectedDate = _resolveSelectedDate(days);
          final selectedDay = selectedDate == null
              ? null
              : _findArchiveDay(days, selectedDate);
          final entriesAsync = selectedDate == null
              ? const AsyncData<List<ActivityLogEntry>>(<ActivityLogEntry>[])
              : ref.watch(activityLogArchiveEntriesForDateProvider(selectedDate));

          return LayoutBuilder(
            builder: (context, constraints) {
              final wideLayout = constraints.maxWidth >= 980;
              if (wideLayout) {
                return Row(
                  children: [
                    SizedBox(
                      width: 300,
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
                        entriesAsync: entriesAsync,
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  SizedBox(
                    height: 260,
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
                      entriesAsync: entriesAsync,
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
                    '\u6309\u5929\u5f52\u6863',
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              days.isEmpty
                  ? '\u8fd8\u6ca1\u6709\u53ef\u6d4f\u89c8\u7684\u5386\u53f2\u65e5\u5fd7\u6587\u4ef6\u3002'
                  : '\u5171 ${days.length} \u5929\u65e5\u5fd7\u6587\u4ef6\uff0c\u6309\u65e5\u671f\u5012\u5e8f\u6392\u5217\u3002',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: archivePathAsync.when(
              loading: () => const Text(
                '\u6b63\u5728\u5b9a\u4f4d\u65e5\u5fd7\u76ee\u5f55\u2026',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              error: (error, _) => Text(
                '\u65e5\u5fd7\u76ee\u5f55\u8bfb\u53d6\u5931\u8d25\uff1a$error',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
              data: (path) => Text(
                '\u76ee\u5f55\uff1a$path',
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
                    '\u8ffd\u8e2a\u5f00\u59cb\u5199\u5165\u540e\uff0c\u8fd9\u91cc\u4f1a\u6309\u5929\u51fa\u73b0\u5386\u53f2\u65e5\u5fd7\u6587\u4ef6\u3002',
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
                            ? Icons.description
                            : Icons.description_outlined,
                        color: selected ? AppColors.primary : null,
                      ),
                      title: Text(
                        _formatDate(day.date),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '\u6587\u4ef6\u5927\u5c0f\uff1a${_formatFileSize(day.fileSizeBytes)}',
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
    required AsyncValue<List<ActivityLogEntry>> entriesAsync,
  }) {
    if (selectedDay == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '\u8bf7\u9009\u62e9\u4e00\u5929\u7684\u65e5\u5fd7\u6587\u4ef6\u5f00\u59cb\u67e5\u770b\u3002',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('\u8bfb\u53d6\u65e5\u5fd7\u6587\u4ef6\u5931\u8d25\uff1a$error'),
        ),
      ),
      data: (entries) {
        final availableTypes = ActivityLogEntryType.values
            .where((type) => entries.any((entry) => entry.type == type))
            .toList(growable: false);
        final selectedType = availableTypes.contains(_selectedType)
            ? _selectedType
            : null;
        final filteredEntries = entries
            .where(
              (entry) => _matchesEntry(
                entry,
                searchQuery: _searchQuery,
                selectedType: selectedType,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
        final typeSummary = _buildTypeSummary(filteredEntries);
        final hasActiveFilters =
            _searchQuery.trim().isNotEmpty || selectedType != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatDate(selectedDay.date)} \u5386\u53f2\u65e5\u5fd7',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\u6587\u4ef6\uff1a${selectedDay.filePath}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasActiveFilters
                        ? '\u5f53\u524d\u547d\u4e2d ${filteredEntries.length}/${entries.length} \u6761\u65e5\u5fd7\u3002'
                        : '\u5f53\u524d\u6587\u4ef6\u5171\u6709 ${entries.length} \u6761\u65e5\u5fd7\u3002',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: filteredEntries.isEmpty
                            ? null
                            : () => _exportFilteredEntries(
                                  context,
                                  selectedDay: selectedDay,
                                  filteredEntries: filteredEntries,
                                ),
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('\u5bfc\u51fa\u5f53\u524d\u7ed3\u679c'),
                      ),
                    ],
                  ),
                  if (typeSummary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '\u65e5\u5fd7\u7c7b\u578b\uff1a$typeSummary',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
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
                  hintText:
                      '\u641c\u7d22\u6807\u9898\u3001\u7a97\u53e3\u3001\u5907\u6ce8\u3001\u5e94\u7528\u3001\u7c7b\u578b',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '\u6e05\u7a7a\u641c\u7d22',
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
            if (availableTypes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('\u5168\u90e8\u7c7b\u578b'),
                      selected: selectedType == null,
                      onSelected: (_) {
                        setState(() {
                          _selectedType = null;
                        });
                      },
                    ),
                    ...availableTypes.map(
                      (type) => ChoiceChip(
                        label: Text(_entryTypeLabel(type)),
                        selected: selectedType == type,
                        onSelected: (_) {
                          setState(() {
                            _selectedType = type;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: filteredEntries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          hasActiveFilters
                              ? '\u6ca1\u6709\u627e\u5230\u5339\u914d\u7684\u5386\u53f2\u65e5\u5fd7\uff0c\u8bf7\u5c1d\u8bd5\u653e\u5bbd\u641c\u7d22\u6216\u5207\u6362\u7c7b\u578b\u3002'
                              : '\u8fd9\u4e00\u5929\u7684\u5386\u53f2\u65e5\u5fd7\u6587\u4ef6\u91cc\u8fd8\u6ca1\u6709\u5185\u5bb9\u3002',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: filteredEntries.length,
                      itemBuilder: (context, index) {
                        return _ArchiveLogEntryTile(entry: filteredEntries[index]);
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

class _ArchiveLogEntryTile extends StatelessWidget {
  final ActivityLogEntry entry;

  const _ArchiveLogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final title = entry.label?.trim().isNotEmpty == true
        ? entry.label!.trim()
        : (entry.windowTitle?.trim().isNotEmpty == true
            ? entry.windowTitle!.trim()
            : (entry.processName?.trim().isNotEmpty == true
                ? entry.processName!.trim()
                : '\u672a\u547d\u540d\u65e5\u5fd7\u9879'));

    final subtitle = <String>[
      if (entry.category != null && entry.category!.trim().isNotEmpty)
        entry.category!.trim(),
      if (entry.processName != null && entry.processName!.trim().isNotEmpty)
        entry.processName!.trim(),
      if (entry.isIgnored) '\u81ea\u6392\u9664',
    ].join(' \u00b7 ');

    final metrics = <String>[
      if (entry.keyCount > 0) '${entry.keyCount} \u6b21\u6309\u952e',
      if (entry.mouseClicks > 0) '${entry.mouseClicks} \u6b21\u70b9\u51fb',
      if (entry.mouseMovePx > 0) '${entry.mouseMovePx}px \u79fb\u52a8',
      if (entry.scrollPx > 0) '${entry.scrollPx}px \u6eda\u52a8',
      if (entry.durationMinutes != null)
        '${entry.durationMinutes} \u5206\u949f',
    ];

    final detailLines = <String>[
      if (entry.windowTitle != null &&
          entry.windowTitle!.trim().isNotEmpty &&
          entry.windowTitle!.trim() != title)
        '\u7a97\u53e3\u6807\u9898\uff1a${entry.windowTitle!.trim()}',
      if (entry.className != null && entry.className!.trim().isNotEmpty)
        '\u7a97\u53e3\u7c7b\u540d\uff1a${entry.className!.trim()}',
      if (entry.recordId != null) '\u5173\u8054\u8bb0\u5f55\uff1a#${entry.recordId}',
      if (entry.isFullscreen) '\u7a97\u53e3\u72b6\u6001\uff1a\u5168\u5c4f',
      if (entry.note != null && entry.note!.trim().isNotEmpty)
        '\u5907\u6ce8\uff1a${entry.note!.trim()}',
    ];

    final keySequence = entry.keySequence?.trim();
    final hasDetails =
        detailLines.isNotEmpty || (keySequence != null && keySequence.isNotEmpty);

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
                  _formatDateTimeShort(entry.timestamp),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ArchiveStatusBadge(
                label: _entryTypeLabel(entry.type),
                color: entry.isIgnored
                    ? const Color(0xFFF5935A)
                    : const Color(0xFF0EA8A0),
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
              children: metrics.map(_buildTag).toList(),
            ),
          ],
          if (hasDetails) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: const Text(
                  '\u67e5\u770b\u65e5\u5fd7\u8be6\u60c5',
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
                  if (keySequence != null && keySequence.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '\u6309\u952e\u5e8f\u5217\uff1a${keySequence.replaceAll('\n', ' <\u56de\u8f66> ')}',
                        style: const TextStyle(fontSize: 12),
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

class _ArchiveStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ArchiveStatusBadge({
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

bool _matchesEntry(
  ActivityLogEntry entry, {
  required String searchQuery,
  required ActivityLogEntryType? selectedType,
}) {
  if (selectedType != null && entry.type != selectedType) {
    return false;
  }

  final target = <String>[
    if (entry.label != null) entry.label!,
    if (entry.processName != null) entry.processName!,
    if (entry.windowTitle != null) entry.windowTitle!,
    if (entry.category != null) entry.category!,
    if (entry.className != null) entry.className!,
    if (entry.note != null) entry.note!,
    _entryTypeLabel(entry.type),
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

String _buildTypeSummary(List<ActivityLogEntry> entries) {
  if (entries.isEmpty) {
    return '';
  }

  final counts = <ActivityLogEntryType, int>{};
  for (final entry in entries) {
    counts.update(entry.type, (value) => value + 1, ifAbsent: () => 1);
  }

  return ActivityLogEntryType.values
      .where(counts.containsKey)
      .map((type) => '${_entryTypeLabel(type)} ${counts[type]}')
      .join(' \u00b7 ');
}

String _entryTypeLabel(ActivityLogEntryType type) {
  switch (type) {
    case ActivityLogEntryType.sample:
      return '\u91c7\u6837';
    case ActivityLogEntryType.sessionOpen:
      return '\u4f1a\u8bdd\u5f00\u59cb';
    case ActivityLogEntryType.sessionUpdate:
      return '\u4f1a\u8bdd\u66f4\u65b0';
    case ActivityLogEntryType.sessionClose:
      return '\u4f1a\u8bdd\u7ed3\u675f';
    case ActivityLogEntryType.snapshot:
      return '\u5feb\u7167';
  }
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

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
