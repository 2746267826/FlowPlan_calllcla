import '../../../core/database/app_database.dart';
import '../../actual/data/actual_activity_log_repository.dart';
import '../../calendar/data/event_repository.dart';
import '../../scheduler/task_schedule_segment_repository.dart';
import '../../task/data/task_repository.dart';
import '../../tracker/data/activity_fusion_repository.dart';
import '../data/report_repository.dart';

class ReportGenerationResult {
  const ReportGenerationResult({
    required this.report,
    required this.diary,
  });

  final ReportDocument report;
  final DiaryEntry? diary;
}

class ReportGenerationService {
  ReportGenerationService({
    required ReportRepository reportRepository,
    required EventRepository eventRepository,
    required TaskRepository taskRepository,
    required TaskScheduleSegmentRepository segmentRepository,
    required ActualActivityLogRepository actualRepository,
    required ActivityFusionRepository fusionRepository,
  })  : _reports = reportRepository,
        _events = eventRepository,
        _tasks = taskRepository,
        _segments = segmentRepository,
        _actuals = actualRepository,
        _fusion = fusionRepository;

  final ReportRepository _reports;
  final EventRepository _events;
  final TaskRepository _tasks;
  final TaskScheduleSegmentRepository _segments;
  final ActualActivityLogRepository _actuals;
  final ActivityFusionRepository _fusion;

  Future<ReportGenerationResult> generateDaily(
    DateTime date, {
    bool includeDiaryDraft = true,
  }) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snapshot = await _collectSnapshot(start, end, forSingleDay: start);
    final title = '日报 ${_formatDate(start)}';
    final markdown = _buildDailyMarkdown(title, snapshot);
    final report = await _reports.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: title,
      summaryMarkdown: markdown,
      metrics: snapshot.metrics,
      sourceSnapshot: snapshot.toJson(),
    );

    final diary = includeDiaryDraft
        ? await _reports.upsertDiaryDraft(
            entryDate: start,
            title: '日记草稿 ${_formatDate(start)}',
            bodyMarkdown: _buildDiaryMarkdown(start, snapshot),
            sourceReportId: report.id,
            linkedTaskIds: snapshot.linkedTaskIds,
          )
        : null;
    return ReportGenerationResult(report: report, diary: diary);
  }

  Future<ReportDocument> generateWeekly(DateTime anchorDate) async {
    final start = DateTime(anchorDate.year, anchorDate.month, anchorDate.day)
        .subtract(Duration(days: anchorDate.weekday - 1));
    final end = start.add(const Duration(days: 7));
    final snapshot = await _collectSnapshot(start, end);
    final title = '周报 ${_formatDate(start)} - ${_formatDate(end.subtract(const Duration(days: 1)))}';
    return _reports.upsertReportDraft(
      reportType: ReportType.weekly,
      periodStart: start,
      periodEnd: end,
      title: title,
      summaryMarkdown: _buildPeriodMarkdown(title, snapshot),
      metrics: snapshot.metrics,
      sourceSnapshot: snapshot.toJson(),
    );
  }

  Future<ReportDocument> generateMonthly(DateTime anchorDate) async {
    final start = DateTime(anchorDate.year, anchorDate.month);
    final end = DateTime(anchorDate.year, anchorDate.month + 1);
    final snapshot = await _collectSnapshot(start, end);
    final title = '月报 ${anchorDate.year}-${anchorDate.month.toString().padLeft(2, '0')}';
    return _reports.upsertReportDraft(
      reportType: ReportType.monthly,
      periodStart: start,
      periodEnd: end,
      title: title,
      summaryMarkdown: _buildPeriodMarkdown(title, snapshot),
      metrics: snapshot.metrics,
      sourceSnapshot: snapshot.toJson(),
    );
  }

  Future<_ReportSnapshot> _collectSnapshot(
    DateTime start,
    DateTime end, {
    DateTime? forSingleDay,
  }) async {
    final days = <DateTime>[];
    for (var cursor = start;
        cursor.isBefore(end);
        cursor = cursor.add(const Duration(days: 1))) {
      days.add(cursor);
    }

    final events = <CalendarEvent>[];
    final scheduleSegments = <TaskScheduleSegmentWithTask>[];
    for (final day in days) {
      events.addAll(await _events.getEventsForDate(day));
      scheduleSegments.addAll(await _segments.getForDate(day));
    }
    final scheduledTasks = scheduleSegments.map((item) => item.task).toList();
    final actuals = await _actuals.listInRange(
      start,
      end,
      statuses: const <String>[
        ActualActivityStatus.candidate,
        ActualActivityStatus.confirmed,
      ],
    );
    final activitySegments = await _fusion.listSegmentsInRange(start, end);
    final allVisibleTasks = await _tasks.listAllVisible();
    final completedTasks = allVisibleTasks
        .where((task) => task.completed != null && !task.completed!.isBefore(start) && task.completed!.isBefore(end))
        .toList(growable: false);
    final taskWorkLogs = <TaskWorkLog>[];
    for (final task in allVisibleTasks) {
      final logs = await _fusion.listTaskWorkLogsForTask(task.id);
      taskWorkLogs.addAll(
        logs.where((log) => log.startAt.isBefore(end) && log.endAt.isAfter(start)),
      );
    }

    return _ReportSnapshot(
      start: start,
      end: end,
      events: events,
      scheduleSegments: scheduleSegments,
      actuals: actuals,
      activitySegments: activitySegments,
      completedTasks: completedTasks,
      scheduledTasks: scheduledTasks,
      taskWorkLogs: taskWorkLogs,
      singleDay: forSingleDay,
    );
  }

  String _buildDailyMarkdown(String title, _ReportSnapshot snapshot) {
    final confirmedActuals =
        snapshot.actuals.where((item) => item.isConfirmed).toList();
    final candidateActuals = snapshot.actuals
        .where((item) => item.status == ActualActivityStatus.candidate)
        .toList();
    final topSegments = snapshot.activitySegments.take(8).toList();
    final lines = <String>[
      '# $title',
      '',
      '## 摘要',
      '- 日程 ${snapshot.events.length} 个，排程片段 ${snapshot.scheduleSegments.length} 段。',
      '- 已确认实际记录 ${confirmedActuals.length} 条，待确认候选 ${candidateActuals.length} 条。',
      '- 活动片段 ${snapshot.activitySegments.length} 段，任务实际投入 ${snapshot.totalTaskWorkMinutes} 分钟。',
      '- 已完成任务 ${snapshot.completedTasks.length} 个。',
      '',
      '## 实际发生',
      if (confirmedActuals.isEmpty) '- 暂无已确认实际记录。',
      for (final actual in confirmedActuals.take(12))
        '- ${_timeRange(actual.startAt, actual.endAt)} ${actual.title}',
      if (candidateActuals.isNotEmpty) ...[
        '',
        '## 待确认候选',
        for (final actual in candidateActuals.take(8))
          '- ${_timeRange(actual.startAt, actual.endAt)} ${actual.title}，置信度 ${(actual.confidence * 100).round()}%',
      ],
      '',
      '## 任务推进',
      if (snapshot.completedTasks.isEmpty && snapshot.taskWorkLogs.isEmpty)
        '- 暂无任务完成或实际投入记录。',
      for (final task in snapshot.completedTasks.take(8))
        '- 已完成：${task.summary}',
      for (final entry in snapshot.taskWorkByTask.entries.take(8))
        '- 任务 #${entry.key} 实际投入 ${entry.value} 分钟。',
      '',
      '## 追踪摘要',
      if (topSegments.isEmpty) '- 暂无活动片段。',
      for (final segment in topSegments)
        '- ${_timeRange(segment.startAt, segment.endAt)} ${segment.label ?? segment.category ?? segment.primaryProcessName ?? '未分类活动'}',
      '',
      '## 上下文占位',
      '- 文件打开和修改、位置、天气将在 P8/P12 数据源接入后补充。',
      '- 本报告不包含敏感原始键鼠序列，只引用聚合结果和人工可确认事实。',
    ];
    return lines.join('\n');
  }

  String _buildPeriodMarkdown(String title, _ReportSnapshot snapshot) {
    final lines = <String>[
      '# $title',
      '',
      '## 总览',
      '- 覆盖 ${_formatDate(snapshot.start)} 到 ${_formatDate(snapshot.end.subtract(const Duration(days: 1)))}。',
      '- 日程 ${snapshot.events.length} 个，排程片段 ${snapshot.scheduleSegments.length} 段。',
      '- 已确认/候选实际记录 ${snapshot.actuals.length} 条。',
      '- 活动片段 ${snapshot.activitySegments.length} 段。',
      '- 任务实际投入 ${snapshot.totalTaskWorkMinutes} 分钟，完成任务 ${snapshot.completedTasks.length} 个。',
      '',
      '## 任务投入排行',
      if (snapshot.taskWorkByTask.isEmpty) '- 暂无任务投入日志。',
      for (final entry in snapshot.sortedTaskWork.take(12))
        '- 任务 #${entry.key}: ${entry.value} 分钟',
      '',
      '## 复盘线索',
      '- 可对照实际记录与排程片段，检查计划偏离和剩余时间估算。',
      '- 文件、位置、天气上下文将在后续模块接入后进入报告。',
    ];
    return lines.join('\n');
  }

  String _buildDiaryMarkdown(DateTime date, _ReportSnapshot snapshot) {
    final actuals = snapshot.actuals.where((item) => item.isConfirmed).toList();
    final segments = snapshot.activitySegments.take(6).toList();
    final lines = <String>[
      '# ${_formatDate(date)} 日记草稿',
      '',
      '今天的主要节奏：',
      if (actuals.isEmpty && segments.isEmpty)
        '- 目前还没有足够的实际记录或活动片段，适合手动补充。',
      for (final actual in actuals.take(8))
        '- ${_timeRange(actual.startAt, actual.endAt)}：${actual.title}',
      for (final segment in segments)
        '- ${_timeRange(segment.startAt, segment.endAt)}：${segment.label ?? segment.category ?? '活动片段'}',
      '',
      '可以补充的主观感受：',
      '- 今天最顺利的部分是：',
      '- 今天被打断或偏离计划的部分是：',
      '- 明天优先处理：',
      '',
      '> 这是本地生成的日记草稿。确认前不会作为正式日记保存，也不会发送给第三方 AI。',
    ];
    return lines.join('\n');
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _timeRange(DateTime start, DateTime end) {
    String format(DateTime value) {
      final hour = value.hour.toString().padLeft(2, '0');
      final minute = value.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return '${format(start)}-${format(end)}';
  }
}

class _ReportSnapshot {
  const _ReportSnapshot({
    required this.start,
    required this.end,
    required this.events,
    required this.scheduleSegments,
    required this.actuals,
    required this.activitySegments,
    required this.completedTasks,
    required this.scheduledTasks,
    required this.taskWorkLogs,
    this.singleDay,
  });

  final DateTime start;
  final DateTime end;
  final List<CalendarEvent> events;
  final List<TaskScheduleSegmentWithTask> scheduleSegments;
  final List<ActualActivityLog> actuals;
  final List<ActivitySegment> activitySegments;
  final List<TaskItem> completedTasks;
  final List<TaskItem> scheduledTasks;
  final List<TaskWorkLog> taskWorkLogs;
  final DateTime? singleDay;

  int get totalTaskWorkMinutes =>
      taskWorkLogs.fold(0, (sum, item) => sum + item.durationMinutes);

  List<int> get linkedTaskIds => taskWorkByTask.keys.toList(growable: false);

  Map<int, int> get taskWorkByTask {
    final result = <int, int>{};
    for (final log in taskWorkLogs) {
      result[log.taskId] = (result[log.taskId] ?? 0) + log.durationMinutes;
    }
    return result;
  }

  List<MapEntry<int, int>> get sortedTaskWork {
    final entries = taskWorkByTask.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries;
  }

  Map<String, Object?> get metrics => <String, Object?>{
        'event_count': events.length,
        'schedule_segment_count': scheduleSegments.length,
        'actual_count': actuals.length,
        'confirmed_actual_count': actuals.where((item) => item.isConfirmed).length,
        'activity_segment_count': activitySegments.length,
        'completed_task_count': completedTasks.length,
        'scheduled_task_count': scheduledTasks.length,
        'task_work_minutes': totalTaskWorkMinutes,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'single_day': singleDay?.toIso8601String(),
        'metrics': metrics,
        'events': events
            .take(50)
            .map((event) => <String, Object?>{
                  'id': event.id,
                  'summary': event.summary,
                  'start': event.dtstart.toIso8601String(),
                  'end': event.dtend?.toIso8601String(),
                  'is_block': event.isBlock,
                })
            .toList(),
        'actuals': actuals.take(50).map((item) => item.toJson()).toList(),
        'activity_segments':
            activitySegments.take(50).map((item) => item.toJson()).toList(),
        'task_work_by_task': taskWorkByTask.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      };
}
