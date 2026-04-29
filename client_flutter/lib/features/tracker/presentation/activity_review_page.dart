import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/activity_fusion_repository.dart';
import '../services/activity_fusion_service.dart';

class ActivityReviewPage extends ConsumerStatefulWidget {
  const ActivityReviewPage({super.key});

  @override
  ConsumerState<ActivityReviewPage> createState() => _ActivityReviewPageState();
}

class _ActivityReviewPageState extends ConsumerState<ActivityReviewPage> {
  var _loading = true;
  var _rebuilding = false;
  String? _error;
  ActivityFusionRunResult? _lastRun;
  List<_SegmentReviewItem> _items = const <_SegmentReviewItem>[];
  List<TaskItem> _tasks = const <TaskItem>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final date = ref.read(selectedDateProvider);
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fusion = ref.read(activityFusionRepositoryProvider);
      final segments = await fusion.listSegmentsInRange(start, end);
      final items = <_SegmentReviewItem>[];
      for (final segment in segments) {
        final interpretations =
            await fusion.listInterpretationsForSegment(segment.id);
        interpretations.sort(
          (left, right) => right.confidence.compareTo(left.confidence),
        );
        items.add(
          _SegmentReviewItem(
            segment: segment,
            interpretation:
                interpretations.isEmpty ? null : interpretations.first,
          ),
        );
      }
      final tasks = await ref.read(taskRepositoryProvider).listAllVisible();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _tasks = tasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _rebuild() async {
    final date = ref.read(selectedDateProvider);
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    setState(() {
      _rebuilding = true;
      _error = null;
    });
    try {
      final result = await ref.read(activityFusionServiceProvider).rebuildRange(
            start: start,
            end: end,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastRun = result;
      });
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已整理 ${result.segmentCount} 个活动片段，等待人工确认后写入实际记录。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _rebuilding = false;
        });
      }
    }
  }

  Future<void> _confirm(_SegmentReviewItem item) async {
    final selected = await showDialog<_SegmentConfirmationDraft>(
      context: context,
      builder: (dialogContext) {
        return _ConfirmSegmentDialog(
          item: item,
          tasks: _tasks,
        );
      },
    );
    if (selected == null) {
      return;
    }
    try {
      final result = await ref.read(activityFusionServiceProvider).confirmSegment(
            item.segment.id,
            title: selected.title,
            taskId: selected.taskId,
            note: selected.note,
          );
      await _load();
      if (!mounted) {
        return;
      }
      final suffix = result.taskWorkLog == null ? '未关联任务投入。' : '已写入任务实际投入。';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已确认实际记录，$suffix')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('确认失败：$error')),
      );
    }
  }

  Future<void> _reject(_SegmentReviewItem item) async {
    final fusion = ref.read(activityFusionRepositoryProvider);
    await fusion.updateSegmentStatus(
      item.segment.id,
      status: 'rejected',
    );
    await fusion.updateInterpretationsStatusForSegment(
      item.segment.id,
      status: 'rejected',
    );
    await fusion.rejectTaskWorkLogsForSegment(segmentId: item.segment.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('活动理解'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (GoRouter.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/tracker');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: '重新读取并整理当天追踪',
            onPressed: _rebuilding ? null : _rebuild,
            icon: _rebuilding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(
              date: selectedDate,
              itemCount: _items.length,
              lastRun: _lastRun,
              onRebuild: _rebuilding ? null : _rebuild,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _NoticeCard(
                icon: Icons.warning_amber_outlined,
                title: '活动理解读取失败',
                message: _error!,
                isError: true,
              ),
            ],
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              _NoticeCard(
                icon: Icons.manage_search_outlined,
                title: '还没有活动片段',
                message: '点击右上角整理按钮，系统会读取当天 raw_activity_logs、tracked_input_events 和 activity_records 生成候选片段。',
              )
            else
              ..._items.map(
                (item) => _SegmentCard(
                  item: item,
                  task: _taskById(item.interpretation?.inferredTaskId),
                  onConfirm: item.segment.status == 'confirmed'
                      ? null
                      : () => _confirm(item),
                  onReject: item.segment.status == 'rejected'
                      ? null
                      : () => _reject(item),
                ),
              ),
          ],
        ),
      ),
    );
  }

  TaskItem? _taskById(int? taskId) {
    if (taskId == null) {
      return null;
    }
    for (final task in _tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.date,
    required this.itemCount,
    required this.lastRun,
    required this.onRebuild,
  });

  final DateTime date;
  final int itemCount;
  final ActivityFusionRunResult? lastRun;
  final VoidCallback? onRebuild;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${date.year}年${date.month}月${date.day}日活动理解',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onRebuild,
                icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                label: const Text('整理'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '当前 $itemCount 个片段。确认前都只是候选，确认后才会写入实际记录和任务实际投入。',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (lastRun != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag('活动记录 ${lastRun!.sourceRecordCount}'),
                _Tag('原始日志 ${lastRun!.rawLogCount}'),
                _Tag('输入事件 ${lastRun!.inputEventCount}'),
                _Tag('任务投入候选 ${lastRun!.taskWorkLogCount}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({
    required this.item,
    required this.task,
    required this.onConfirm,
    required this.onReject,
  });

  final _SegmentReviewItem item;
  final TaskItem? task;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final segment = item.segment;
    final interpretation = item.interpretation;
    final evidence = _decodeEvidence(segment.evidenceJson);
    final statusColor = switch (segment.status) {
      'confirmed' => Colors.green,
      'rejected' => Colors.red,
      _ => AppColors.primary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    interpretation?.summary ??
                        segment.label ??
                        segment.category ??
                        segment.primaryProcessName ??
                        '未分类活动',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _StatusPill(
                  label: _statusLabel(segment.status),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatTime(segment.startAt)} - ${_formatTime(segment.endAt)} · ${segment.durationMinutes} 分钟',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag('置信度 ${(segment.confidence * 100).round()}%'),
                if (segment.primaryProcessName != null)
                  _Tag('应用 ${segment.primaryProcessName}'),
                if (task != null) _Tag('建议任务 ${task!.summary}'),
                if (segment.category != null) _Tag('分类 ${segment.category}'),
              ],
            ),
            if (segment.primaryWindowTitle != null) ...[
              const SizedBox(height: 10),
              Text(
                '主要窗口：${segment.primaryWindowTitle}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              _evidenceSummary(evidence),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('确认'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.block_outlined, size: 18),
                  label: const Text('拒绝'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _evidenceSummary(Map<String, Object?> evidence) {
    final parts = <String>[
      '活动记录 ${evidence['activityRecordCount'] ?? 0}',
      '原始日志 ${evidence['rawLogCount'] ?? 0}',
      '输入事件 ${evidence['inputEventCount'] ?? 0}',
    ];
    final processes = evidence['processes'];
    if (processes is List && processes.isNotEmpty) {
      parts.add('应用证据 ${processes.take(3).join('、')}');
    }
    return '证据摘要：${parts.join('，')}';
  }
}

class _ConfirmSegmentDialog extends StatefulWidget {
  const _ConfirmSegmentDialog({
    required this.item,
    required this.tasks,
  });

  final _SegmentReviewItem item;
  final List<TaskItem> tasks;

  @override
  State<_ConfirmSegmentDialog> createState() => _ConfirmSegmentDialogState();
}

class _ConfirmSegmentDialogState extends State<_ConfirmSegmentDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  int? _taskId;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(
      text: item.interpretation?.summary ??
          item.segment.label ??
          item.segment.category ??
          item.segment.primaryProcessName ??
          '未分类活动',
    );
    _noteController = TextEditingController();
    _taskId = item.interpretation?.inferredTaskId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认活动片段'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '实际记录标题'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _taskId,
              decoration: const InputDecoration(labelText: '关联任务'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('不关联任务'),
                ),
                for (final task in widget.tasks)
                  DropdownMenuItem<int?>(
                    value: task.id,
                    child: Text(
                      task.summary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _taskId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '备注（可选）'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _SegmentConfirmationDraft(
                title: _titleController.text,
                taskId: _taskId,
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
              ),
            );
          },
          child: const Text('确认写入'),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isError ? Colors.red : AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: child,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
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
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SegmentReviewItem {
  const _SegmentReviewItem({
    required this.segment,
    required this.interpretation,
  });

  final ActivitySegment segment;
  final ActivityInterpretation? interpretation;
}

class _SegmentConfirmationDraft {
  const _SegmentConfirmationDraft({
    required this.title,
    required this.taskId,
    required this.note,
  });

  final String title;
  final int? taskId;
  final String? note;
}

Map<String, Object?> _decodeEvidence(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
  } catch (_) {
    return const <String, Object?>{};
  }
  return const <String, Object?>{};
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _statusLabel(String status) {
  switch (status) {
    case 'confirmed':
      return '已确认';
    case 'rejected':
      return '已拒绝';
    default:
      return '候选';
  }
}
