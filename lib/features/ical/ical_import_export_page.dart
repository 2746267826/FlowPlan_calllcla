import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_storage.dart';
import '../../../core/storage/database_restore_service.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/database_provider.dart';
import 'flowplan_archive_service.dart';
import 'ical_exporter.dart';
import 'ical_parser.dart';

enum _IcsImportMode {
  smartMerge,
  appendOnly,
  replaceCalendar,
}

extension _IcsImportModeX on _IcsImportMode {
  String get label {
    switch (this) {
      case _IcsImportMode.smartMerge:
        return '智能合并';
      case _IcsImportMode.appendOnly:
        return '仅追加';
      case _IcsImportMode.replaceCalendar:
        return '清空后导入';
    }
  }

  String get description {
    switch (this) {
      case _IcsImportMode.smartMerge:
        return '同 UID 的日程会覆盖更新；标题与起止时间完全一致的本地日程会自动跳过。适合日常重复导入。';
      case _IcsImportMode.appendOnly:
        return '不会改写已有日程；遇到重复项只跳过，其他内容直接追加到当前日历本。';
      case _IcsImportMode.replaceCalendar:
        return '会先清空当前本地日历本中的所有日程，再导入新文件。适合完整重建某个日历本。';
    }
  }
}

enum _IcsExportScope {
  selectedCalendar,
  allLocalCalendars,
}

extension _IcsExportScopeX on _IcsExportScope {
  String get label {
    switch (this) {
      case _IcsExportScope.selectedCalendar:
        return '当前日历本';
      case _IcsExportScope.allLocalCalendars:
        return '全部本地日历本';
    }
  }

  String get description {
    switch (this) {
      case _IcsExportScope.selectedCalendar:
        return '只导出当前选中的本地日历本。适合单个课程表、单个项目日历单独备份。';
      case _IcsExportScope.allLocalCalendars:
        return '会把全部本地日历本中的日程合并导出到一个 .ics 文件中，不保留日历本边界。';
    }
  }
}

class ICalImportExportPage extends ConsumerStatefulWidget {
  const ICalImportExportPage({super.key});

  @override
  ConsumerState<ICalImportExportPage> createState() => _ICalImportExportPageState();
}

class _ICalImportExportPageState extends ConsumerState<ICalImportExportPage> {
  bool _importing = false;
  bool _exporting = false;
  bool _exportingStructuredArchive = false;
  bool _importingStructuredArchive = false;
  bool _exportingDatabase = false;
  bool _restoringDatabase = false;
  bool _openingDatabaseFolder = false;
  String? _lastMessage;
  int? _selectedCalendarId;
  bool _structuredSelectionInitialized = false;
  Set<int> _selectedStructuredCalendarIds = <int>{};
  Set<int> _selectedStructuredTaskListIds = <int>{};
  PendingDatabaseRestore? _pendingRestore;
  _IcsImportMode _importMode = _IcsImportMode.smartMerge;
  _IcsExportScope _exportScope = _IcsExportScope.selectedCalendar;

  @override
  void initState() {
    super.initState();
    _loadPendingRestore();
    _loadRestoreNotice();
  }

  Future<void> _loadPendingRestore() async {
    final pendingRestore = await const DatabaseRestoreService().getPendingRestore();
    if (!mounted) {
      return;
    }
    setState(() => _pendingRestore = pendingRestore);
  }

  Future<void> _loadRestoreNotice() async {
    final notice = await const DatabaseRestoreService().consumeRestoreNotice();
    if (!mounted || notice == null) {
      return;
    }

    final formattedTime = _formatDateTime(notice.restoredAt);
    setState(() {
      _lastMessage = notice.previousDatabaseBackupPath == null
          ? '\u5df2\u5728 $formattedTime \u5e94\u7528\u6570\u636e\u5e93\u6062\u590d\u3002'
          : '\u5df2\u5728 $formattedTime \u5e94\u7528\u6570\u636e\u5e93\u6062\u590d\uff0c\u6062\u590d\u524d\u526f\u672c\u5df2\u4fdd\u7559\u5728\uff1a${notice.previousDatabaseBackupPath}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final calendarsAsync = ref.watch(allEventCalendarsProvider);
    final taskListsAsync = ref.watch(allTaskListsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u5bfc\u5165 / \u5bfc\u51fa\u4e0e\u5907\u4efd'),
      ),
      body: calendarsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('\u52a0\u8f7d\u65e5\u5386\u672c\u5931\u8d25\uff1a$error'),
          ),
        ),
        data: (allCalendars) {
          return taskListsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载任务本失败：$error'),
              ),
            ),
            data: (taskLists) {
          final localCalendars = allCalendars
              .where((calendar) => calendar.source == 'local')
              .toList(growable: false);
          _ensureSelectedCalendar(localCalendars);
          _ensureStructuredSelections(
            localCalendars: localCalendars,
            taskLists: taskLists,
          );

          final selectedCalendar = _findSelectedCalendar(localCalendars);
          final selectedCalendarName =
              selectedCalendar?.name ?? '\u672a\u9009\u62e9\u65e5\u5386\u672c';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u64cd\u4f5c\u5bf9\u8c61',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '\u5bfc\u5165\u548c\u5bfc\u51fa\u53ea\u4f1a\u9488\u5bf9\u672c\u5730\u65e5\u5386\u672c\u3002Outlook \u540c\u6b65\u65e5\u5386\u4e3a\u53ea\u8bfb\uff0c\u4e0d\u4f1a\u5728\u8fd9\u91cc\u88ab\u6539\u5199\u6216\u5bfc\u51fa\u56de\u5199\u3002',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      if (localCalendars.isEmpty)
                        const Text(
                          '\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c\u3002\u8bf7\u5148\u5728\u65e5\u5386\u672c\u7ba1\u7406\u4e2d\u521b\u5efa\u4e00\u4e2a\u672c\u5730\u65e5\u5386\u672c\u3002',
                          style: TextStyle(fontSize: 13),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: localCalendars.map((calendar) {
                            final selected = calendar.id == _selectedCalendarId;
                            return ChoiceChip(
                              label: Text(calendar.name),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _selectedCalendarId = calendar.id);
                              },
                              selectedColor: _parseColor(calendar.colorHex),
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : null,
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      if (localCalendars.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '导入策略',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _IcsImportMode.values.map((mode) {
                            return ChoiceChip(
                              label: Text(mode.label),
                              selected: _importMode == mode,
                              onSelected: (_) {
                                setState(() => _importMode = mode);
                              },
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _importMode.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '导出范围',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _IcsExportScope.values.map((scope) {
                            final disabled =
                                scope == _IcsExportScope.allLocalCalendars &&
                                    localCalendars.length <= 1;
                            return ChoiceChip(
                              label: Text(scope.label),
                              selected: _exportScope == scope,
                              onSelected: disabled
                                  ? null
                                  : (_) {
                                      setState(() => _exportScope = scope);
                                    },
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          localCalendars.length <= 1 &&
                                  _exportScope ==
                                      _IcsExportScope.allLocalCalendars
                              ? '当前只有一个本地日历本，“全部本地日历本”导出与“当前日历本”效果一致。'
                              : _exportScope.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.file_download_outlined,
                  title: '\u5bfc\u5165 .ics \u6587\u4ef6',
                  subtitle: localCalendars.isEmpty
                      ? '\u65e0\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c'
                      : '\u4ee5\u300c${_importMode.label}\u300d\u6a21\u5f0f\u5c06 iCalendar \u6587\u4ef6\u5bfc\u5165\u5230\u300c$selectedCalendarName\u300d',
                  actionLabel: _importing ? '\u5bfc\u5165\u4e2d...' : '\u9009\u62e9\u6587\u4ef6',
                  onAction: _importing || localCalendars.isEmpty
                      ? null
                      : () => _importIcs(selectedCalendar!),
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.file_upload_outlined,
                  title: '\u5bfc\u51fa .ics \u6587\u4ef6',
                  subtitle: localCalendars.isEmpty
                      ? '\u65e0\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c'
                      : _exportScope == _IcsExportScope.selectedCalendar
                          ? '\u53ea\u5bfc\u51fa\u300c$selectedCalendarName\u300d\u4e2d\u7684\u672c\u5730\u65e5\u7a0b'
                          : '\u5408\u5e76\u5bfc\u51fa ${localCalendars.length} \u4e2a\u672c\u5730\u65e5\u5386\u672c\u4e2d\u7684\u5168\u90e8\u65e5\u7a0b',
                  actionLabel: _exporting
                      ? '\u5bfc\u51fa\u4e2d...'
                      : _exportScope == _IcsExportScope.selectedCalendar
                          ? '\u5bfc\u51fa\u5f53\u524d\u65e5\u5386\u672c'
                          : '\u5408\u5e76\u5bfc\u51fa\u5168\u90e8\u672c\u5730\u65e5\u5386\u672c',
                  onAction: _exporting || localCalendars.isEmpty
                      ? null
                      : () => _exportIcs(
                            selectedCalendar: selectedCalendar!,
                            localCalendars: localCalendars,
                          ),
                  color: const Color(0xFF43A047),
                ),
                const SizedBox(height: 16),
                _buildStructuredArchiveSection(
                  localCalendars: localCalendars,
                  taskLists: taskLists,
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.backup_outlined,
                  title: '\u5bfc\u51fa\u5b8c\u6574\u6570\u636e\u5e93\u526f\u672c',
                  subtitle:
                      '\u4fdd\u7559\u6240\u6709\u65e5\u5386\u672c\u3001\u4efb\u52a1\u672c\u3001\u65e5\u7a0b\u3001\u4efb\u52a1\u3001\u8ffd\u8e2a\u6570\u636e\u3001\u540c\u6b65\u6620\u5c04\u4e0e\u5bb9\u5668\u9ed8\u8ba4\u89c4\u5219\u3002\u8fd9\u662f\u6700\u5b8c\u6574\u7684\u5907\u4efd\u65b9\u5f0f\u3002',
                  actionLabel: _exportingDatabase
                      ? '\u5bfc\u51fa\u4e2d...'
                      : '\u5bfc\u51fa\u6570\u636e\u5e93',
                  onAction: _exportingDatabase ? null : _exportDatabase,
                  color: const Color(0xFF5C6BC0),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.restore_page_outlined,
                  title: '\u6062\u590d\u5b8c\u6574\u6570\u636e\u5e93\u526f\u672c',
                  subtitle:
                      '\u5148\u9009\u62e9\u5df2\u5bfc\u51fa\u7684 FlowPlan \u6570\u636e\u5e93\u526f\u672c\uff0c\u7cfb\u7edf\u4f1a\u5148\u6682\u5b58\u5e76\u5728\u4f60\u4e0b\u6b21\u5b8c\u6574\u91cd\u542f FlowPlan \u65f6\u81ea\u52a8\u5e94\u7528\u3002',
                  actionLabel: _restoringDatabase
                      ? '\u51c6\u5907\u4e2d...'
                      : '\u9009\u62e9\u526f\u672c',
                  onAction:
                      _restoringDatabase ? null : _prepareDatabaseRestore,
                  color: const Color(0xFFD81B60),
                ),
                if (_pendingRestore != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD81B60).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFD81B60).withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.pending_actions_outlined,
                              color: Color(0xFFD81B60),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '\u5df2\u6682\u5b58\u5f85\u6062\u590d\u526f\u672c',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _restoringDatabase
                                  ? null
                                  : _clearPendingDatabaseRestore,
                              child: const Text('\u53d6\u6d88\u6062\u590d'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '\u539f\u59cb\u526f\u672c\uff1a${_pendingRestore!.sourcePath}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\u51c6\u5907\u65f6\u95f4\uff1a${_formatDateTime(_pendingRestore!.stagedAt)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '\u4e0b\u6b21\u5b8c\u5168\u5173\u95ed\u5e76\u91cd\u65b0\u6253\u5f00 FlowPlan \u65f6\uff0c\u7cfb\u7edf\u4f1a\u5148\u5e94\u7528\u8fd9\u4e2a\u526f\u672c\uff0c\u540c\u65f6\u4fdd\u7559\u4e00\u4efd\u6062\u590d\u524d\u7684\u6570\u636e\u5e93\u5907\u4efd\u3002',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.folder_open_outlined,
                  title: Platform.isWindows
                      ? '\u6253\u5f00\u6570\u636e\u5e93\u76ee\u5f55'
                      : '\u67e5\u770b\u6570\u636e\u5e93\u4f4d\u7f6e',
                  subtitle: Platform.isWindows
                      ? '\u6253\u5f00 FlowPlan \u5f53\u524d\u8fd0\u884c\u73af\u5883\u7684\u6570\u636e\u5e93\u6587\u4ef6\u5939\uff0c\u53ef\u7528\u7b2c\u4e09\u65b9 SQLite \u5de5\u5177\u76f4\u63a5\u67e5\u770b\u6216\u7ef4\u62a4\u3002'
                      : '\u67e5\u770b FlowPlan \u5f53\u524d\u6570\u636e\u5e93\u7684\u5b58\u50a8\u4f4d\u7f6e\uff0c\u4fbf\u4e8e\u540e\u7eed\u624b\u52a8\u5907\u4efd\u6216\u66ff\u6362\u3002',
                  actionLabel: _openingDatabaseFolder
                      ? (Platform.isWindows
                          ? '\u6253\u5f00\u4e2d...'
                          : '\u8bfb\u53d6\u4e2d...')
                      : (Platform.isWindows
                          ? '\u6253\u5f00\u76ee\u5f55'
                          : '\u663e\u793a\u8def\u5f84'),
                  onAction:
                      _openingDatabaseFolder ? null : _openDatabaseFolder,
                  color: const Color(0xFF8E24AA),
                ),
                const SizedBox(height: 24),
                if (_lastMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastMessage!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\u89c4\u5219\u8bf4\u660e',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.description_outlined,
                        text: 'iCalendar (.ics) \u00b7 RFC 5545 \u6807\u51c6',
                      ),
                      _InfoRow(
                        icon: Icons.calendar_month_outlined,
                        text: '\u652f\u6301 Outlook\u3001Google Calendar\u3001Apple Calendar \u5bfc\u51fa\u7684 .ics \u6587\u4ef6',
                      ),
                      _InfoRow(
                        icon: Icons.shield_outlined,
                        text: '\u53ea\u5904\u7406\u672c\u5730\u65e5\u5386\u672c\uff0c\u4e0d\u4f1a\u6539\u5199 Outlook \u53ea\u8bfb\u540c\u6b65\u65e5\u5386',
                      ),
                      _InfoRow(
                        icon: Icons.account_tree_outlined,
                        text: '.ics \u53ea\u4fdd\u7559\u65e5\u7a0b\u9879\u76ee\uff0c\u4e0d\u4fdd\u7559\u4efb\u52a1\u672c\u3001\u4efb\u52a1\u3001\u8ffd\u8e2a\u8bb0\u5f55\u3001\u540c\u6b65\u6620\u5c04\u6216\u5bb9\u5668\u9ed8\u8ba4\u89c4\u5219',
                      ),
                      _InfoRow(
                        icon: Icons.rule_folder_outlined,
                        text: '\u5bfc\u5165 .ics \u65f6\uff0c\u53ef\u9009\u62e9\u201c\u667a\u80fd\u5408\u5e76\u3001\u4ec5\u8ffd\u52a0\u3001\u6e05\u7a7a\u540e\u5bfc\u5165\u201d\u4e09\u79cd\u6a21\u5f0f\uff1b\u667a\u80fd\u5408\u5e76\u4f1a\u66f4\u65b0\u540c UID \u65e5\u7a0b\uff0c\u5e76\u81ea\u52a8\u8df3\u8fc7\u6807\u9898\u4e0e\u65f6\u95f4\u5b8c\u5168\u4e00\u81f4\u7684\u91cd\u590d\u9879',
                      ),
                      _InfoRow(
                        icon: Icons.layers_outlined,
                        text: '\u9009\u62e9\u201c\u5168\u90e8\u672c\u5730\u65e5\u5386\u672c\u201d\u5bfc\u51fa\u65f6\uff0c\u6240\u6709\u672c\u5730\u65e5\u7a0b\u4f1a\u5408\u5e76\u5230\u4e00\u4e2a .ics \u6587\u4ef6\u4e2d\uff0c\u4e0d\u4fdd\u7559\u65e5\u5386\u672c\u8fb9\u754c',
                      ),
                      _InfoRow(
                        icon: Icons.storage_outlined,
                        text: '如需要保留日历本 / 任务本边界、容器默认规则和项目归属关系，请优先使用“FlowPlan 结构化容器归档”。',
                      ),
                      _InfoRow(
                        icon: Icons.fact_check_outlined,
                        text: '结构化归档导入会先展示差异预览，并在写入前自动生成数据库回滚备份。',
                      ),
                      _InfoRow(
                        icon: Icons.restore_outlined,
                        text: '\u5982\u9700\u8981\u6062\u590d\u5b8c\u6574\u6570\u636e\uff0c\u53ef\u4ee5\u5728\u5173\u95ed FlowPlan \u540e\u624b\u52a8\u66ff\u6362\u6570\u636e\u5e93\u6587\u4ef6\uff0c\u4e5f\u53ef\u4ee5\u5728\u672c\u9875\u5148\u6682\u5b58\u6062\u590d\u526f\u672c\u3002',
                      ),
                      _InfoRow(
                        icon: Icons.restart_alt_outlined,
                        text: '\u73b0\u5728\u4e5f\u53ef\u4ee5\u5728\u672c\u9875\u76f4\u63a5\u9009\u62e9\u6570\u636e\u5e93\u526f\u672c\uff0c\u5e76\u5728\u4e0b\u6b21\u5b8c\u6574\u91cd\u542f FlowPlan \u65f6\u81ea\u52a8\u5e94\u7528\u6062\u590d',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
            },
          );
        },
      ),
    );
  }

  void _ensureSelectedCalendar(List<EventCalendar> localCalendars) {
    if (localCalendars.isEmpty) {
      if (_selectedCalendarId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedCalendarId = null);
          }
        });
      }
      return;
    }

    final exists = localCalendars.any((calendar) => calendar.id == _selectedCalendarId);
    if (_selectedCalendarId == null || !exists) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedCalendarId = localCalendars.first.id);
        }
      });
    }
  }

  EventCalendar? _findSelectedCalendar(List<EventCalendar> localCalendars) {
    for (final calendar in localCalendars) {
      if (calendar.id == _selectedCalendarId) {
        return calendar;
      }
    }
    return localCalendars.isEmpty ? null : localCalendars.first;
  }

  void _ensureStructuredSelections({
    required List<EventCalendar> localCalendars,
    required List<TaskList> taskLists,
  }) {
    final calendarIds = localCalendars.map((calendar) => calendar.id).toSet();
    final taskListIds = taskLists.map((taskList) => taskList.id).toSet();
    final nextCalendarIds = _structuredSelectionInitialized
        ? _selectedStructuredCalendarIds.intersection(calendarIds)
        : calendarIds;
    final nextTaskListIds = _structuredSelectionInitialized
        ? _selectedStructuredTaskListIds.intersection(taskListIds)
        : taskListIds;

    if (_structuredSelectionInitialized &&
        _setEquals(_selectedStructuredCalendarIds, nextCalendarIds) &&
        _setEquals(_selectedStructuredTaskListIds, nextTaskListIds)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _structuredSelectionInitialized = true;
        _selectedStructuredCalendarIds = nextCalendarIds;
        _selectedStructuredTaskListIds = nextTaskListIds;
      });
    });
  }

  bool _setEquals(Set<int> left, Set<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final value in left) {
      if (!right.contains(value)) {
        return false;
      }
    }
    return true;
  }

  Widget _buildStructuredArchiveSection({
    required List<EventCalendar> localCalendars,
    required List<TaskList> taskLists,
  }) {
    final selectedCalendarCount = _selectedStructuredCalendarIds.length;
    final selectedTaskListCount = _selectedStructuredTaskListIds.length;
    final selectedContainerCount = selectedCalendarCount + selectedTaskListCount;
    final hasSelection = selectedContainerCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00897B).withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_tree_outlined,
                  color: Color(0xFF00897B),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FlowPlan 结构化容器归档',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '保留日历本 / 任务本边界、容器默认规则、日程和任务归属关系，适合跨设备迁移或选择性备份。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStructuredCalendarSelector(localCalendars),
          const SizedBox(height: 14),
          _buildStructuredTaskListSelector(taskLists),
          const SizedBox(height: 16),
          Text(
            hasSelection
                ? '已选择 $selectedCalendarCount 个日历本、$selectedTaskListCount 个任务本。'
                : '请至少选择一个日历本或任务本。',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _exportingStructuredArchive || !hasSelection
                    ? null
                    : _exportStructuredArchive,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(
                  _exportingStructuredArchive
                      ? '导出中...'
                      : '导出结构化归档',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _importingStructuredArchive
                    ? null
                    : _importStructuredArchive,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(
                  _importingStructuredArchive
                      ? '导入中...'
                      : '导入结构化归档',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredCalendarSelector(List<EventCalendar> localCalendars) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '选择日历本',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: localCalendars.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedStructuredCalendarIds =
                            localCalendars.map((calendar) => calendar.id).toSet();
                      });
                    },
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: _selectedStructuredCalendarIds.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedStructuredCalendarIds = <int>{};
                      });
                    },
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (localCalendars.isEmpty)
          const Text(
            '暂无本地日历本可导出。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: localCalendars.map((calendar) {
              final selected = _selectedStructuredCalendarIds.contains(calendar.id);
              return FilterChip(
                label: Text(calendar.name),
                selected: selected,
                selectedColor: _parseColor(calendar.colorHex)
                    .withValues(alpha: 0.18),
                onSelected: (value) {
                  setState(() {
                    final next = Set<int>.from(_selectedStructuredCalendarIds);
                    if (value) {
                      next.add(calendar.id);
                    } else {
                      next.remove(calendar.id);
                    }
                    _selectedStructuredCalendarIds = next;
                  });
                },
              );
            }).toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildStructuredTaskListSelector(List<TaskList> taskLists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '选择任务本',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: taskLists.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedStructuredTaskListIds =
                            taskLists.map((taskList) => taskList.id).toSet();
                      });
                    },
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: _selectedStructuredTaskListIds.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedStructuredTaskListIds = <int>{};
                      });
                    },
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (taskLists.isEmpty)
          const Text(
            '暂无任务本可导出。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: taskLists.map((taskList) {
              final selected = _selectedStructuredTaskListIds.contains(taskList.id);
              return FilterChip(
                avatar: taskList.emoji == null || taskList.emoji!.trim().isEmpty
                    ? null
                    : Text(taskList.emoji!),
                label: Text(taskList.name),
                selected: selected,
                selectedColor: _parseColor(taskList.colorHex)
                    .withValues(alpha: 0.18),
                onSelected: (value) {
                  setState(() {
                    final next = Set<int>.from(_selectedStructuredTaskListIds);
                    if (value) {
                      next.add(taskList.id);
                    } else {
                      next.remove(taskList.id);
                    }
                    _selectedStructuredTaskListIds = next;
                  });
                },
              );
            }).toList(growable: false),
          ),
      ],
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  String _safeFileNameSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'flowplan_export' : sanitized;
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year\u5e74$month\u6708$day\u65e5 $hour:$minute';
  }

  String _buildImportSignature({
    required String summary,
    required DateTime dtstart,
    DateTime? dtend,
  }) {
    final normalizedSummary = summary.trim().toLowerCase();
    final endPart = dtend?.toIso8601String() ?? 'null';
    return '$normalizedSummary|${dtstart.toIso8601String()}|$endPart';
  }

  Future<List<CalendarEventsCompanion>> _applyCalendarImportDefaults({
    required EventCalendar calendar,
    required List<CalendarEventsCompanion> companions,
  }) async {
    final defaults = await ref
        .read(calendarBooksRepositoryProvider)
        .getEventCalendarDefaults(calendar.id);
    return companions
        .map(
          (companion) => companion.copyWith(
            eventCalendarId: Value(calendar.id),
            colorHex: Value(calendar.colorHex),
            isBlock: Value(defaults.defaultIsBlock),
          ),
        )
        .toList(growable: false);
  }

  FlowPlanArchiveService _archiveService() {
    return FlowPlanArchiveService(
      database: ref.read(databaseProvider),
      calendarBooksRepository: ref.read(calendarBooksRepositoryProvider),
      eventRepository: ref.read(eventRepositoryProvider),
      taskRepository: ref.read(taskRepositoryProvider),
    );
  }

  Future<void> _exportStructuredArchive() async {
    setState(() => _exportingStructuredArchive = true);

    try {
      final archive = await _archiveService().buildArchive(
        calendarIds: _selectedStructuredCalendarIds,
        taskListIds: _selectedStructuredTaskListIds,
      );

      if (archive.calendars.isEmpty && archive.taskLists.isEmpty) {
        setState(() {
          _exportingStructuredArchive = false;
          _lastMessage = '没有可导出的日历本或任务本。';
        });
        return;
      }

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出 FlowPlan 结构化容器归档',
        fileName: 'flowplan-containers-${_formatDate(DateTime.now())}.flowplan.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        setState(() {
          _exportingStructuredArchive = false;
          _lastMessage = '已取消导出结构化归档。';
        });
        return;
      }

      await File(outputPath).writeAsString(archive.toPrettyJson());
      setState(() {
        _exportingStructuredArchive = false;
        _lastMessage =
            '已导出结构化归档到 $outputPath：${archive.calendars.length} 个日历本、${archive.taskLists.length} 个任务本。';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _exportingStructuredArchive = false;
        _lastMessage = '导出结构化归档失败：$error';
      });
    }
  }

  Future<void> _importStructuredArchive() async {
    setState(() => _importingStructuredArchive = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _importingStructuredArchive = false;
          _lastMessage = '未选择结构化归档文件。';
        });
        return;
      }

      final file = result.files.single;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() {
          _importingStructuredArchive = false;
          _lastMessage = '无法读取结构化归档文件内容。';
        });
        return;
      }

      final archive = FlowPlanArchiveData.fromJsonString(content);
      if (!mounted) {
        return;
      }

      final mode = await _chooseStructuredImportMode();
      if (mode == null) {
        setState(() {
          _importingStructuredArchive = false;
          _lastMessage = '已取消结构化归档导入。';
        });
        return;
      }

      final preview = await _archiveService().previewImport(
        archive: archive,
        mode: mode,
      );
      if (!mounted) {
        return;
      }

      final confirmed = await _confirmStructuredImportPreview(preview);
      if (confirmed != true) {
        setState(() {
          _importingStructuredArchive = false;
          _lastMessage = '已取消结构化归档导入。';
        });
        return;
      }

      final importResult = await _archiveService().importArchive(
        archive: archive,
        mode: mode,
      );
      ref.invalidate(allEventCalendarsProvider);
      ref.invalidate(allTaskListsProvider);

      if (!mounted) {
        return;
      }
      setState(() {
        _importingStructuredArchive = false;
        _lastMessage = _buildStructuredImportResultMessage(importResult);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _importingStructuredArchive = false;
        _lastMessage = '导入结构化归档失败：$error';
      });
    }
  }

  Future<FlowPlanArchiveImportMode?> _chooseStructuredImportMode() {
    var selectedMode = FlowPlanArchiveImportMode.smartMerge;
    return showDialog<FlowPlanArchiveImportMode>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('选择结构化导入策略'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: FlowPlanArchiveImportMode.values.map((mode) {
                  return RadioListTile<FlowPlanArchiveImportMode>(
                    value: mode,
                    groupValue: selectedMode,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() => selectedMode = value);
                    },
                    title: Text(mode.label),
                    subtitle: Text(mode.description),
                  );
                }).toList(growable: false),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selectedMode),
                  child: const Text('查看导入预览'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool?> _confirmStructuredImportPreview(
    FlowPlanArchivePreview preview,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认结构化导入预览'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入策略：${preview.mode.label}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '将新建 ${preview.createdContainers} 个容器，合并 ${preview.mergedContainers} 个同名容器；新增 ${preview.createdItems} 项，更新 ${preview.updatedItems} 项，跳过 ${preview.skippedItems} 项。',
                ),
                if (preview.removedBeforeImportItems > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '替换导入会先移除 ${preview.removedBeforeImportItems} 个同名容器内的旧项目。导入前会自动生成数据库回滚备份。',
                    style: const TextStyle(color: Colors.red),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    '导入前会自动生成数据库回滚备份，可在需要时通过完整数据库恢复功能回退。',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      children: preview.containers.map((container) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            container.kindLabel == '日历本'
                                ? Icons.calendar_month_outlined
                                : Icons.checklist_outlined,
                          ),
                          title: Text('${container.kindLabel}：${container.name}'),
                          subtitle: Text(
                            '${container.actionLabel}，新增 ${container.createCount}，更新 ${container.updateCount}，跳过 ${container.skipCount}，移除 ${container.removeBeforeImportCount}',
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('生成备份并导入'),
            ),
          ],
        );
      },
    );
  }

  String _buildStructuredImportResultMessage(
    FlowPlanArchiveImportResult result,
  ) {
    return '结构化归档导入完成：新建日历本 ${result.createdCalendars} 个，合并日历本 ${result.mergedCalendars} 个，新建任务本 ${result.createdTaskLists} 个，合并任务本 ${result.mergedTaskLists} 个；'
        '日程新增 ${result.createdEvents} 条、更新 ${result.updatedEvents} 条、跳过 ${result.skippedEvents} 条、移除 ${result.removedEvents} 条；'
        '任务新增 ${result.createdTasks} 条、更新 ${result.updatedTasks} 条、跳过 ${result.skippedTasks} 条、移除 ${result.removedTasks} 条。'
        '\n\n导入前数据库回滚备份：${result.backupPath}';
  }

  Future<void> _importIcs(EventCalendar calendar) async {
    setState(() => _importing = true);

    try {
      final importMode = _importMode;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _importing = false;
          _lastMessage = '\u672a\u9009\u62e9\u6587\u4ef6';
        });
        return;
      }

      final file = result.files.single;
      String content;
      if (file.bytes != null) {
        try {
          content = utf8.decode(file.bytes!);
        } catch (_) {
          content = String.fromCharCodes(file.bytes!);
        }
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() {
          _importing = false;
          _lastMessage = '\u65e0\u6cd5\u8bfb\u53d6\u6587\u4ef6\u5185\u5bb9';
        });
        return;
      }

      final companions = const ICalParser().parse(content);
      if (companions.isEmpty) {
        setState(() {
          _importing = false;
          _lastMessage = '\u6587\u4ef6\u4e2d\u672a\u627e\u5230\u6709\u6548\u65e5\u7a0b (VEVENT)';
        });
        return;
      }

      final importCompanions = await _applyCalendarImportDefaults(
        calendar: calendar,
        companions: companions,
      );
      final repo = ref.read(eventRepositoryProvider);
      if (importMode == _IcsImportMode.replaceCalendar) {
        final existingCount = (await repo.getByCalendarId(calendar.id)).length;
        if (!mounted) {
          return;
        }

        final confirmed = await _confirmReplaceImport(
          calendar: calendar,
          existingCount: existingCount,
        );
        if (confirmed != true) {
          setState(() {
            _importing = false;
            _lastMessage =
                '\u5df2\u53d6\u6d88\u5bf9\u300c${calendar.name}\u300d\u7684\u6e05\u7a7a\u540e\u5bfc\u5165';
          });
          return;
        }

        final deletedCount = existingCount;
        await repo.replaceCalendarEvents(
          calendarId: calendar.id,
          companions: importCompanions,
        );
        final createdCount = importCompanions.length;

        if (!mounted) {
          return;
        }
        setState(() {
          _importing = false;
          _lastMessage =
              '\u5df2\u5148\u6e05\u7a7a\u300c${calendar.name}\u300d\u4e2d\u7684 $deletedCount \u6761\u539f\u6709\u65e5\u7a0b\uff0c\u518d\u5bfc\u5165 $createdCount \u6761\u65b0\u65e5\u7a0b\u3002';
        });
        return;
      }

      final existingEvents = await repo.getByCalendarId(calendar.id);
      final existingIdsByUid = <String, int>{};
      final existingSignatures = <String>{};
      for (final event in existingEvents) {
        final uid = event.uid.trim();
        if (uid.isNotEmpty) {
          existingIdsByUid.putIfAbsent(uid, () => event.id);
        }
        existingSignatures.add(
          _buildImportSignature(
            summary: event.summary,
            dtstart: event.dtstart,
            dtend: event.dtend,
          ),
        );
      }

      var createdCount = 0;
      var updatedCount = 0;
      var skippedCount = 0;
      for (final targetCompanion in importCompanions) {
        final uid = targetCompanion.uid.value.trim();
        final summary = targetCompanion.summary.value.trim();
        final dtstart = targetCompanion.dtstart.value;
        final dtend =
            targetCompanion.dtend.present ? targetCompanion.dtend.value : null;
        final signature = _buildImportSignature(
          summary: summary,
          dtstart: dtstart,
          dtend: dtend,
        );

        final existingId = uid.isNotEmpty ? existingIdsByUid[uid] : null;
        if (existingId != null) {
          if (importMode == _IcsImportMode.smartMerge) {
            await repo.update(
              targetCompanion.copyWith(id: Value(existingId)),
            );
            existingSignatures.add(signature);
            updatedCount++;
          } else {
            skippedCount++;
          }
          continue;
        }

        if (existingSignatures.contains(signature)) {
          skippedCount++;
          continue;
        }

        final createdId = await repo.create(targetCompanion);
        if (uid.isNotEmpty) {
          existingIdsByUid[uid] = createdId;
        }
        existingSignatures.add(signature);
        createdCount++;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _importing = false;
        _lastMessage = _buildImportResultMessage(
          calendarName: calendar.name,
          importMode: importMode,
          createdCount: createdCount,
          updatedCount: updatedCount,
          skippedCount: skippedCount,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _importing = false;
        _lastMessage = '\u5bfc\u5165\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _exportIcs({
    required EventCalendar selectedCalendar,
    required List<EventCalendar> localCalendars,
  }) async {
    setState(() => _exporting = true);

    try {
      final repo = ref.read(eventRepositoryProvider);
      final exportScope = _exportScope;
      final exportable = exportScope == _IcsExportScope.selectedCalendar
          ? await repo.getByCalendarId(selectedCalendar.id)
          : await repo.getByCalendarIds(
              localCalendars.map((calendar) => calendar.id),
            );

      if (exportable.isEmpty) {
        setState(() {
          _exporting = false;
          _lastMessage = exportScope == _IcsExportScope.selectedCalendar
              ? '\u300c${selectedCalendar.name}\u300d\u4e2d\u6ca1\u6709\u53ef\u5bfc\u51fa\u7684\u65e5\u7a0b'
              : '\u5f53\u524d\u5168\u90e8\u672c\u5730\u65e5\u5386\u672c\u4e2d\u6ca1\u6709\u53ef\u5bfc\u51fa\u7684\u65e5\u7a0b';
        });
        return;
      }

      final fileName = exportScope == _IcsExportScope.selectedCalendar
          ? '${_safeFileNameSegment(selectedCalendar.name)}_flowplan_export.ics'
          : 'flowplan_all_local_calendars_${_formatDate(DateTime.now())}.ics';
      final calendarName = exportScope == _IcsExportScope.selectedCalendar
          ? 'FlowPlan - ${selectedCalendar.name}'
          : 'FlowPlan - 全部本地日历本';

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '\u4fdd\u5b58 .ics \u6587\u4ef6',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );

      if (outputPath == null) {
        setState(() {
          _exporting = false;
          _lastMessage = '\u672a\u9009\u62e9\u4fdd\u5b58\u4f4d\u7f6e';
        });
        return;
      }

      final file = File(outputPath);
      await file.writeAsString(
        const ICalExporter().export(
          exportable,
          calendarName: calendarName,
        ),
      );

      setState(() {
        _exporting = false;
        _lastMessage = exportScope == _IcsExportScope.selectedCalendar
            ? '\u6210\u529f\u4ece\u300c${selectedCalendar.name}\u300d\u5bfc\u51fa ${exportable.length} \u6761\u65e5\u7a0b\u5230 ${file.path}'
            : '\u6210\u529f\u5408\u5e76\u5bfc\u51fa ${localCalendars.length} \u4e2a\u672c\u5730\u65e5\u5386\u672c\u4e2d\u7684 ${exportable.length} \u6761\u65e5\u7a0b\u5230 ${file.path}';
      });
    } catch (error) {
      setState(() {
        _exporting = false;
        _lastMessage = '\u5bfc\u51fa\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _exportDatabase() async {
    setState(() => _exportingDatabase = true);

    try {
      final database = ref.read(databaseProvider);
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '\u5bfc\u51fa\u5b8c\u6574\u6570\u636e\u5e93\u526f\u672c',
        fileName:
            'flowplan-$appStorageFlavorLabel-backup-${_formatDate(DateTime.now())}.db',
        type: FileType.custom,
        allowedExtensions: const ['db', 'sqlite', 'sqlite3'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        setState(() {
          _exportingDatabase = false;
          _lastMessage = '\u5df2\u53d6\u6d88\u5bfc\u51fa\u6570\u636e\u5e93';
        });
        return;
      }

      await database.exportToFile(outputPath);
      setState(() {
        _exportingDatabase = false;
        _lastMessage = '\u5b8c\u6574\u6570\u636e\u5e93\u5df2\u5bfc\u51fa\u5230 $outputPath';
      });
    } catch (error) {
      setState(() {
        _exportingDatabase = false;
        _lastMessage = '\u5bfc\u51fa\u5b8c\u6574\u6570\u636e\u5e93\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _prepareDatabaseRestore() async {
    setState(() => _restoringDatabase = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db', 'sqlite', 'sqlite3'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _restoringDatabase = false;
          _lastMessage = '\u5df2\u53d6\u6d88\u9009\u62e9\u6062\u590d\u526f\u672c';
        });
        return;
      }

      final selectedFile = result.files.single;
      final sourcePath = selectedFile.path;
      if (sourcePath == null || sourcePath.trim().isEmpty) {
        setState(() {
          _restoringDatabase = false;
          _lastMessage = '\u65e0\u6cd5\u8bfb\u53d6\u6240\u9009\u6062\u590d\u526f\u672c\u8def\u5f84';
        });
        return;
      }

      final preparation =
          await const DatabaseRestoreService().stageRestore(sourcePath);
      final pendingRestore = await const DatabaseRestoreService().getPendingRestore();
      if (!mounted) {
        return;
      }
      setState(() {
        _restoringDatabase = false;
        _pendingRestore = pendingRestore;
        _lastMessage =
            '\u5df2\u51c6\u5907\u597d\u6062\u590d\u526f\u672c\uff1a${preparation.sourcePath}\n\n\u8bf7\u5b8c\u5168\u5173\u95ed\u5e76\u91cd\u65b0\u6253\u5f00 FlowPlan\uff0c\u4e0b\u6b21\u542f\u52a8\u65f6\u4f1a\u81ea\u52a8\u5e94\u7528\u6062\u590d\u3002';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _restoringDatabase = false;
        _lastMessage = '\u51c6\u5907\u6062\u590d\u526f\u672c\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _clearPendingDatabaseRestore() async {
    setState(() => _restoringDatabase = true);

    try {
      await const DatabaseRestoreService().clearPendingRestore();
      if (!mounted) {
        return;
      }
      setState(() {
        _restoringDatabase = false;
        _pendingRestore = null;
        _lastMessage = '\u5df2\u53d6\u6d88\u5f85\u5e94\u7528\u7684\u6570\u636e\u5e93\u6062\u590d\u526f\u672c\u3002';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _restoringDatabase = false;
        _lastMessage = '\u53d6\u6d88\u5f85\u6062\u590d\u526f\u672c\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _openDatabaseFolder() async {
    setState(() => _openingDatabaseFolder = true);

    try {
      final database = ref.read(databaseProvider);
      final databasePath = await database.getDatabasePath();
      final folderPath = File(databasePath).parent.path;

      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folderPath]);
        setState(() {
          _openingDatabaseFolder = false;
          _lastMessage = '\u5df2\u6253\u5f00\u6570\u636e\u5e93\u76ee\u5f55\uff1a$folderPath';
        });
        return;
      }

      setState(() {
        _openingDatabaseFolder = false;
        _lastMessage = '\u5f53\u524d\u6570\u636e\u5e93\u76ee\u5f55\uff1a$folderPath';
      });
    } catch (error) {
      setState(() {
        _openingDatabaseFolder = false;
        _lastMessage = '\u8bfb\u53d6\u6570\u636e\u5e93\u4f4d\u7f6e\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<bool?> _confirmReplaceImport({
    required EventCalendar calendar,
    required int existingCount,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u786e\u8ba4\u6e05\u7a7a\u540e\u5bfc\u5165'),
        content: Text(
          existingCount > 0
              ? '\u300c${calendar.name}\u300d\u5f53\u524d\u5df2\u6709 $existingCount \u6761\u65e5\u7a0b\u3002\n\n\u9009\u62e9\u201c\u6e05\u7a7a\u540e\u5bfc\u5165\u201d\u540e\uff0c\u8fd9\u4e9b\u65e5\u7a0b\u4f1a\u5148\u88ab\u79fb\u9664\uff0c\u7136\u540e\u518d\u5bfc\u5165\u65b0\u7684 .ics \u5185\u5bb9\u3002\u8fd9\u4e2a\u64cd\u4f5c\u4e0d\u4f1a\u5f71\u54cd\u5176\u4ed6\u65e5\u5386\u672c\u3002'
              : '\u300c${calendar.name}\u300d\u5f53\u524d\u662f\u7a7a\u65e5\u5386\u672c\u3002\u7cfb\u7edf\u4f1a\u76f4\u63a5\u5bfc\u5165\u65b0\u7684 .ics \u5185\u5bb9\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '\u7ee7\u7eed',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _buildImportResultMessage({
    required String calendarName,
    required _IcsImportMode importMode,
    required int createdCount,
    required int updatedCount,
    required int skippedCount,
  }) {
    switch (importMode) {
      case _IcsImportMode.smartMerge:
        return skippedCount > 0 || updatedCount > 0
            ? '\u5df2\u4ee5\u300c${importMode.label}\u300d\u6a21\u5f0f\u5b8c\u6210\u5bfc\u5165\u300c$calendarName\u300d\uff1a\u65b0\u5efa $createdCount \u6761\uff0c\u66f4\u65b0 $updatedCount \u6761\uff0c\u8df3\u8fc7 $skippedCount \u6761\u91cd\u590d\u65e5\u7a0b\u3002'
            : '\u5df2\u4ee5\u300c${importMode.label}\u300d\u6a21\u5f0f\u6210\u529f\u5bfc\u5165 $createdCount \u6761\u65e5\u7a0b\u5230\u300c$calendarName\u300d';
      case _IcsImportMode.appendOnly:
        return skippedCount > 0
            ? '\u5df2\u4ee5\u300c${importMode.label}\u300d\u6a21\u5f0f\u5b8c\u6210\u5bfc\u5165\u300c$calendarName\u300d\uff1a\u65b0\u589e $createdCount \u6761\uff0c\u8df3\u8fc7 $skippedCount \u6761\u5df2\u5b58\u5728\u7684\u65e5\u7a0b\u3002'
            : '\u5df2\u4ee5\u300c${importMode.label}\u300d\u6a21\u5f0f\u6210\u529f\u65b0\u589e $createdCount \u6761\u65e5\u7a0b\u5230\u300c$calendarName\u300d';
      case _IcsImportMode.replaceCalendar:
        return '\u5df2\u5b8c\u6210\u300c$calendarName\u300d\u7684\u6e05\u7a7a\u540e\u5bfc\u5165\uff1a\u65b0\u5efa $createdCount \u6761\u65e5\u7a0b\u3002';
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
