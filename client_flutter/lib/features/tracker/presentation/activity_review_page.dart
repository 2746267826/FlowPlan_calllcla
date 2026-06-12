import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_keys.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/activity_fusion_repository.dart';

@visibleForTesting
String debugActivityReviewEvidenceSummary(Map<String, Object?> rawEvidence) {
  return _SegmentCard.evidenceSummaryForTesting(rawEvidence);
}

class ActivityReviewPage extends ConsumerStatefulWidget {
  const ActivityReviewPage({super.key});

  @override
  ConsumerState<ActivityReviewPage> createState() => _ActivityReviewPageState();
}

class _ActivityReviewPageState extends ConsumerState<ActivityReviewPage> {
  var _loading = true;
  var _rebuilding = false;
  String? _error;
  _ServerActivityBuildResult? _lastRun;
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
      final store = await ref.read(trackingServerFirstStoreProvider.future);
      final tasks = await ref.read(allTasksProvider.future);
      final taskByUid = <String, TaskItem>{
        for (final task in tasks) task.uid: task,
      };
      final response = await store.segments(
        startAt: start,
        endAt: end,
        limit: 200,
      );
      final items = <_SegmentReviewItem>[];
      for (final item in _serverSegmentItems(response)) {
        items.add(_segmentReviewItemFromServer(item, taskByUid));
      }
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
    setState(() {
      _rebuilding = true;
      _error = null;
    });
    try {
      final store = await ref.read(trackingServerFirstStoreProvider.future);
      final response = await store.buildSegments(date: start);
      final result = _ServerActivityBuildResult.fromServer(response);
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
      final result =
          await (await ref.read(trackingServerFirstStoreProvider.future))
              .confirmSegment(
        segmentId: item.serverId,
        title: selected.title,
        taskId: selected.taskUid,
        note: selected.note,
      );
      await _load();
      if (!mounted) {
        return;
      }
      final suffix = result['taskId'] == null ? '未关联任务投入。' : '已写入任务实际投入。';
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
    try {
      await (await ref.read(trackingServerFirstStoreProvider.future))
          .rejectSegment(
        segmentId: item.serverId,
        reason: 'user_rejected',
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $error')),
      );
    }
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
                message:
                    '点击右上角整理按钮，系统会读取当天 raw_activity_logs、tracked_input_events 和 activity_records 生成候选片段。',
              )
            else
              ..._items.map(
                (item) => _SegmentCard(
                  item: item,
                  task: _taskByUid(item.inferredTaskUid),
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

  TaskItem? _taskByUid(String? taskUid) {
    if (taskUid == null) {
      return null;
    }
    for (final task in _tasks) {
      if (task.uid == taskUid) {
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
  final _ServerActivityBuildResult? lastRun;
  final VoidCallback? onRebuild;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined,
                  color: AppColors.primary),
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
                _Tag('服务端原始事实 ${lastRun!.rawCount}'),
                _Tag('新增片段 ${lastRun!.segmentsCreated}'),
                _Tag('更新片段 ${lastRun!.segmentsUpdated}'),
                _Tag('低置信度 ${lastRun!.lowConfidenceCount}'),
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

  @visibleForTesting
  static String evidenceSummaryForTesting(Map<String, Object?> rawEvidence) {
    return _evidenceSummary(rawEvidence);
  }

  static String _evidenceSummary(Map<String, Object?> rawEvidence) {
    final evidence = _unwrapEvidence(rawEvidence);
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

  static Map<String, Object?> _unwrapEvidence(Map<String, Object?> evidence) {
    final nested = evidence['evidence'];
    if (nested is Map<String, dynamic>) {
      return Map<String, Object?>.from(nested);
    }
    if (nested is Map) {
      return Map<String, Object?>.from(nested);
    }
    return evidence;
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
  String? _taskUid;

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
    _taskUid = item.inferredTaskUid;
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
            DropdownButtonFormField<String?>(
              initialValue: _taskUid,
              decoration: const InputDecoration(labelText: '关联任务'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('不关联任务'),
                ),
                for (final task in widget.tasks)
                  DropdownMenuItem<String?>(
                    value: task.uid,
                    child: Text(
                      task.summary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _taskUid = value),
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
          key: AppKeys.trackerReviewConfirmButton,
          onPressed: () {
            Navigator.of(context).pop(
              _SegmentConfirmationDraft(
                title: _titleController.text,
                taskUid: _taskUid,
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
    required this.serverId,
    required this.segment,
    required this.interpretation,
    required this.inferredTaskUid,
  });

  final String serverId;
  final ActivitySegment segment;
  final ActivityInterpretation? interpretation;
  final String? inferredTaskUid;
}

class _SegmentConfirmationDraft {
  const _SegmentConfirmationDraft({
    required this.title,
    required this.taskUid,
    required this.note,
  });

  final String title;
  final String? taskUid;
  final String? note;
}

class _ServerActivityBuildResult {
  const _ServerActivityBuildResult({
    required this.rawCount,
    required this.segmentsCreated,
    required this.segmentsUpdated,
    required this.lowConfidenceCount,
  });

  final int rawCount;
  final int segmentsCreated;
  final int segmentsUpdated;
  final int lowConfidenceCount;
  int get segmentCount => segmentsCreated + segmentsUpdated;

  factory _ServerActivityBuildResult.fromServer(Map<String, dynamic> value) {
    return _ServerActivityBuildResult(
      rawCount: _intValue(value['rawCount']),
      segmentsCreated: _intValue(value['segmentsCreated']),
      segmentsUpdated: _intValue(value['segmentsUpdated']),
      lowConfidenceCount: _intValue(value['lowConfidenceCount']),
    );
  }
}

List<Map<String, Object?>> _serverSegmentItems(Map<String, dynamic> response) {
  final items = response['items'];
  if (items is! List) {
    return const <Map<String, Object?>>[];
  }
  return items
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

_SegmentReviewItem _segmentReviewItemFromServer(
  Map<String, Object?> item,
  Map<String, TaskItem> taskByUid,
) {
  final serverId = _stringValue(item['id']) ?? '';
  final startAt =
      _dateValue(item['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
  final endAt = _dateValue(item['endAt']) ?? startAt;
  final evidenceJson = jsonEncode({
    'evidence': item['evidence'],
    'reason': item['reason'],
  });
  final matchedTaskUid = _stringValue(item['matchedTaskId']);
  final matchedTask = matchedTaskUid == null ? null : taskByUid[matchedTaskUid];
  final segment = ActivitySegment(
    id: _stablePositiveId(serverId),
    segmentUid: _stringValue(item['segmentUid']) ?? serverId,
    startAt: startAt,
    endAt: endAt,
    primaryProcessName: _stringValue(item['primaryProcessName']),
    primaryWindowTitle: _stringValue(item['primaryWindowTitle']),
    category: _stringValue(item['category']),
    label: _stringValue(item['title']),
    sourceRecordIdsJson: '[]',
    evidenceJson: evidenceJson,
    confidence: _doubleValue(item['confidence'], fallback: 0.5),
    status: _stringValue(item['status']) ?? 'candidate',
    createdAt: startAt,
    updatedAt: DateTime.now(),
  );
  final summary = _stringValue(item['summary']);
  if (summary == null) {
    return _SegmentReviewItem(
      serverId: serverId,
      segment: segment,
      interpretation: null,
      inferredTaskUid: matchedTaskUid,
    );
  }
  final interpretation = ActivityInterpretation(
    id: _stablePositiveId('$serverId:interpretation'),
    interpretationUid: '$serverId:interpretation',
    segmentId: segment.id,
    summary: summary,
    inferredProject: null,
    inferredDocument: null,
    inferredTaskId: matchedTask?.id,
    confidence: segment.confidence,
    evidenceJson: evidenceJson,
    status: segment.status,
    createdAt: startAt,
    updatedAt: DateTime.now(),
  );
  return _SegmentReviewItem(
    serverId: serverId,
    segment: segment,
    interpretation: interpretation,
    inferredTaskUid: matchedTaskUid,
  );
}

DateTime? _dateValue(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return num.tryParse(value)?.round() ?? 0;
  }
  return 0;
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

int _stablePositiveId(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

Map<String, Object?> _decodeEvidence(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
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
