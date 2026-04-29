import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/database_provider.dart';
import '../audit/data_operation_log_repository.dart';
import '../task/data/task_repository.dart';
import '../tracker/data/activity_record_repository.dart';
import 'task_schedule_segment_repository.dart';

class PlanExecutionSnapshot {
  const PlanExecutionSnapshot({
    required this.task,
    required this.planStart,
    required this.planEnd,
    required this.source,
    this.segment,
  });

  final TaskItem task;
  final DateTime planStart;
  final DateTime planEnd;
  final String source;
  final TaskScheduleSegment? segment;

  String get taskLabel => task.summary;
}

class ActivityExecutionSnapshot {
  const ActivityExecutionSnapshot({
    required this.record,
    required this.startedAt,
    this.endedAt,
    required this.label,
    required this.category,
    required this.processName,
    required this.packageName,
    required this.linkedTaskId,
  });

  final ActivityRecord record;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String label;
  final String? category;
  final String? processName;
  final String? packageName;
  final int? linkedTaskId;
}

class PlanDeviationSnapshot {
  const PlanDeviationSnapshot({
    required this.detectedAt,
    required this.plan,
    required this.activity,
    required this.reason,
    required this.promptKey,
    required this.shouldPrompt,
  });

  const PlanDeviationSnapshot.none()
      : detectedAt = null,
        plan = null,
        activity = null,
        reason = '',
        promptKey = '',
        shouldPrompt = false;

  final DateTime? detectedAt;
  final PlanExecutionSnapshot? plan;
  final ActivityExecutionSnapshot? activity;
  final String reason;
  final String promptKey;
  final bool shouldPrompt;
}

class PlanFeedbackService {
  PlanFeedbackService({
    required TaskRepository taskRepository,
    required ActivityRecordRepository activityRepository,
    required TaskScheduleSegmentRepository segmentRepository,
    required DataOperationLogRepository operationLogs,
    required AppDatabase database,
  })  : _taskRepository = taskRepository,
        _activityRepository = activityRepository,
        _segmentRepository = segmentRepository,
        _operationLogs = operationLogs,
        _db = database;

  static const _deviationGrace = Duration(minutes: 8);
  static const _recentActivityWindow = Duration(minutes: 12);
  static const _snoozeSettingKey = 'plan_feedback.deviation_snooze_until';
  static const _lastPromptKeySettingKey = 'plan_feedback.last_prompt_key';
  static const _lastDecisionSettingKey = 'plan_feedback.last_decision';

  final TaskRepository _taskRepository;
  final ActivityRecordRepository _activityRepository;
  final TaskScheduleSegmentRepository _segmentRepository;
  final DataOperationLogRepository _operationLogs;
  final AppDatabase _db;

  Future<PlanDeviationSnapshot> evaluateNow() async {
    final now = DateTime.now();
    final snoozeUntil = await _readDateTimeSetting(_snoozeSettingKey);
    if (snoozeUntil != null && snoozeUntil.isAfter(now)) {
      return const PlanDeviationSnapshot.none();
    }

    final plan = await _findCurrentPlan(now);
    if (plan == null) {
      return const PlanDeviationSnapshot.none();
    }

    if (now.difference(plan.planStart) < _deviationGrace) {
      return const PlanDeviationSnapshot.none();
    }

    final activity = await _findCurrentActivity(now);
    if (activity == null) {
      return const PlanDeviationSnapshot.none();
    }

    final relation = _compare(plan, activity);
    if (relation.isAligned) {
      return const PlanDeviationSnapshot.none();
    }

    final promptKey = [
      plan.task.id,
      plan.planStart.toIso8601String(),
      _dayKey(now),
      activity.record.id,
    ].join(':');
    final lastPromptKey = await _db.getSetting(_lastPromptKeySettingKey);
    if (lastPromptKey == promptKey) {
      return const PlanDeviationSnapshot.none();
    }

    return PlanDeviationSnapshot(
      detectedAt: now,
      plan: plan,
      activity: activity,
      reason: relation.reason,
      promptKey: promptKey,
      shouldPrompt: true,
    );
  }

  Future<void> markDecision(
    PlanDeviationSnapshot snapshot, {
    required String decision,
    Duration snooze = const Duration(minutes: 30),
  }) async {
    if (snapshot.promptKey.isNotEmpty) {
      await _db.setSetting(_lastPromptKeySettingKey, snapshot.promptKey);
    }
    await _db.setSetting(_lastDecisionSettingKey, decision);
    await _db.setSetting(
      _snoozeSettingKey,
      DateTime.now().add(snooze).toIso8601String(),
    );
    await _operationLogs.record(
      actor: '用户确认',
      action: 'plan_deviation_decision',
      entityType: 'scheduler_feedback',
      entityId: snapshot.promptKey,
      summary: decision == 'accepted'
          ? '用户确认根据计划偏离生成顺延预案'
          : '用户暂不处理计划偏离提示',
      metadata: {
        'decision': decision,
        'reason': snapshot.reason,
        'task_id': snapshot.plan?.task.id,
        'task_summary': snapshot.plan?.task.summary,
        'activity_record_id': snapshot.activity?.record.id,
        'activity_label': snapshot.activity?.label,
      },
    );
  }

  Future<PlanExecutionSnapshot?> _findCurrentPlan(DateTime now) async {
    final segments = await _segmentRepository.getForDate(now);
    final activeSegments = segments
        .where(
          (item) =>
              !item.segment.startAt.isAfter(now) &&
              item.segment.endAt.isAfter(now) &&
              item.task.isAutoScheduled &&
              !item.task.isLocked,
        )
        .toList()
      ..sort(
        (left, right) => left.segment.startAt.compareTo(right.segment.startAt),
      );
    if (activeSegments.isNotEmpty) {
      final item = activeSegments.first;
      return PlanExecutionSnapshot(
        task: item.task,
        planStart: item.segment.startAt,
        planEnd: item.segment.endAt,
        source: 'segment',
        segment: item.segment,
      );
    }

    final tasks = await _taskRepository.getActiveScheduledForDate(now);
    final segmentTaskIds = segments.map((item) => item.task.id).toSet();
    final activeTasks = tasks.where((task) {
      final start = task.dtstart;
      if (start == null ||
          segmentTaskIds.contains(task.id) ||
          !task.isAutoScheduled ||
          task.isLocked) {
        return false;
      }
      final end = start.add(
        Duration(minutes: task.durationMinutes <= 0 ? 30 : task.durationMinutes),
      );
      return !start.isAfter(now) && end.isAfter(now);
    }).toList()
      ..sort((left, right) => left.dtstart!.compareTo(right.dtstart!));

    if (activeTasks.isEmpty) {
      return null;
    }
    final task = activeTasks.first;
    final start = task.dtstart!;
    return PlanExecutionSnapshot(
      task: task,
      planStart: start,
      planEnd: start.add(
        Duration(minutes: task.durationMinutes <= 0 ? 30 : task.durationMinutes),
      ),
      source: 'task',
    );
  }

  Future<ActivityExecutionSnapshot?> _findCurrentActivity(DateTime now) async {
    final active = await _activityRepository.getActiveRecord();
    final recentRecords = active == null
        ? await _activityRepository.listInRange(
            now.subtract(_recentActivityWindow),
            now,
          )
        : const <ActivityRecord>[];
    final record =
        active ?? (recentRecords.isEmpty ? null : recentRecords.last);
    if (record == null) {
      return null;
    }

    final label = _firstNonEmpty([
      record.manualLabel,
      record.windowTitle,
      record.processName,
      record.packageName,
      record.category,
    ]);
    if (label.isEmpty) {
      return null;
    }

    return ActivityExecutionSnapshot(
      record: record,
      startedAt: record.startTime,
      endedAt: record.endTime,
      label: label,
      category: record.category,
      processName: record.processName,
      packageName: record.packageName,
      linkedTaskId: record.linkedTaskId,
    );
  }

  _PlanActivityRelation _compare(
    PlanExecutionSnapshot plan,
    ActivityExecutionSnapshot activity,
  ) {
    if (activity.linkedTaskId == plan.task.id) {
      return const _PlanActivityRelation.aligned('追踪记录已绑定当前计划任务。');
    }

    final activityText = [
      activity.label,
      activity.category,
      activity.processName,
      activity.packageName,
    ].whereType<String>().join(' ').toLowerCase();
    final taskText = [
      plan.task.summary,
      plan.task.description,
    ].whereType<String>().join(' ').toLowerCase();

    final tokens = _tokensFor(taskText);
    if (tokens.any(activityText.contains)) {
      return const _PlanActivityRelation.aligned('当前活动与任务关键词匹配。');
    }

    final category = activity.category?.trim();
    if (_strongDeviationCategories.contains(category)) {
      return _PlanActivityRelation.deviated(
        '当前活动分类为「$category」，与计划任务缺少关联。',
      );
    }

    if (_strongDeviationText.any(activityText.contains)) {
      return const _PlanActivityRelation.deviated(
        '当前活动看起来属于娱乐、游戏或社交场景，与计划任务缺少关联。',
      );
    }

    return const _PlanActivityRelation.deviated(
      '当前活动没有绑定该任务，也没有匹配到任务关键词。',
    );
  }

  List<String> _tokensFor(String text) {
    final rawTokens = text
        .split(RegExp(r'''[\s,，。；;、/\\|:：\[\]（）()【】<>《》"'`~!！?？]+'''))
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.length >= 2)
        .where((token) => !_stopWords.contains(token))
        .toSet()
        .toList();
    return rawTokens.take(8).toList();
  }

  Future<DateTime?> _readDateTimeSetting(String key) async {
    final raw = await _db.getSetting(key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.trim());
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _PlanActivityRelation {
  const _PlanActivityRelation({
    required this.isAligned,
    required this.reason,
  });

  const _PlanActivityRelation.aligned(String reason)
      : this(isAligned: true, reason: reason);

  const _PlanActivityRelation.deviated(String reason)
      : this(isAligned: false, reason: reason);

  final bool isAligned;
  final String reason;
}

const _strongDeviationCategories = {
  '游戏',
  '娱乐',
  '社交',
};

const _strongDeviationText = {
  'game',
  'steam',
  'epic',
  'bilibili',
  'youtube',
  'netflix',
  '抖音',
  '视频',
  '游戏',
  '娱乐',
};

const _stopWords = {
  '任务',
  '工作',
  '计划',
  '学习',
  '项目',
  '处理',
  '完成',
};

final planFeedbackRefreshTickProvider = StateProvider<int>((ref) => 0);

final planFeedbackServiceProvider = Provider<PlanFeedbackService>((ref) {
  return PlanFeedbackService(
    taskRepository: ref.watch(taskRepositoryProvider),
    activityRepository: ref.watch(activityRecordRepositoryProvider),
    segmentRepository: ref.watch(taskScheduleSegmentRepositoryProvider),
    operationLogs: ref.watch(dataOperationLogRepositoryProvider),
    database: ref.watch(databaseProvider),
  );
});

final planDeviationSnapshotProvider =
    FutureProvider<PlanDeviationSnapshot>((ref) {
  ref.watch(planFeedbackRefreshTickProvider);
  return ref.watch(planFeedbackServiceProvider).evaluateNow();
});
