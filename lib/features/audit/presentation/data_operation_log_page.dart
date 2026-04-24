import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/app_providers.dart';
import '../data_operation_log_repository.dart';

final recentDataOperationLogsProvider =
    FutureProvider.autoDispose.family<List<DataOperationLogEntry>, int>(
  (ref, limit) {
    final repository = ref.watch(dataOperationLogRepositoryProvider);
    return repository.listRecent(limit: limit);
  },
);

class DataOperationLogPage extends ConsumerStatefulWidget {
  const DataOperationLogPage({super.key});

  @override
  ConsumerState<DataOperationLogPage> createState() =>
      _DataOperationLogPageState();
}

class _DataOperationLogPageState extends ConsumerState<DataOperationLogPage> {
  int _limit = 100;

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(recentDataOperationLogsProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据操作审计'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(recentDataOperationLogsProvider(_limit)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '这里只记录任务、日程、任务本、日历本、导入导出、数据库恢复、排程确认和 Outlook 同步等关键数据操作。追踪采样和键鼠采样不会写入这里。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _limit,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 50, child: Text('最近 50 条')),
                    DropdownMenuItem(value: 100, child: Text('最近 100 条')),
                    DropdownMenuItem(value: 200, child: Text('最近 200 条')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _limit = value);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: logsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('加载审计记录失败：$error'),
                ),
              ),
              data: (logs) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('当前还没有可显示的数据操作审计记录。'),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = logs[index];
                    return _AuditLogCard(entry: entry);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({
    required this.entry,
  });

  final DataOperationLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          entry.summary,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: _formatDateTime(entry.occurredAt)),
              _MetaChip(label: '操作者：${entry.actor}'),
              _MetaChip(label: '动作：${entry.action}'),
              _MetaChip(label: '类型：${entry.entityType}'),
              if (entry.entityId != null && entry.entityId!.trim().isNotEmpty)
                _MetaChip(label: 'ID：${entry.entityId}'),
            ],
          ),
        ),
        children: [
          if (entry.beforeJson != null && entry.beforeJson!.trim().isNotEmpty)
            _JsonBlock(
              title: '变更前',
              content: _prettyJson(entry.beforeJson!),
            ),
          if (entry.afterJson != null && entry.afterJson!.trim().isNotEmpty)
            _JsonBlock(
              title: '变更后',
              content: _prettyJson(entry.afterJson!),
            ),
          if (entry.metadataJson != null && entry.metadataJson!.trim().isNotEmpty)
            _JsonBlock(
              title: '附加信息',
              content: _prettyJson(entry.metadataJson!),
            ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  static String _prettyJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
