import '../../../core/database/app_database.dart';
import '../../actual/data/actual_activity_log_repository.dart';
import '../../files/data/file_context_repository.dart';
import '../../task/data/task_repository.dart';
import '../data/activity_fusion_repository.dart';
import '../data/activity_record_repository.dart';
import '../models/activity_log_entry.dart';
import '../models/tracked_input_event.dart';
import 'activity_log_service.dart';
import 'input_activity_event_service.dart';

class ActivityFusionRunResult {
  const ActivityFusionRunResult({
    required this.sourceRecordCount,
    required this.rawLogCount,
    required this.inputEventCount,
    required this.segmentCount,
    required this.interpretationCount,
    required this.taskWorkLogCount,
    required this.actualCandidateCount,
  });

  final int sourceRecordCount;
  final int rawLogCount;
  final int inputEventCount;
  final int segmentCount;
  final int interpretationCount;
  final int taskWorkLogCount;
  final int actualCandidateCount;
}

class ActivitySegmentConfirmationResult {
  const ActivitySegmentConfirmationResult({
    required this.actual,
    required this.taskWorkLog,
  });

  final ActualActivityLog actual;
  final TaskWorkLog? taskWorkLog;
}

class ActivityFusionService {
  ActivityFusionService(
    this._activityRecords,
    this._activityLogs,
    this._inputEvents,
    this._fusionRepository,
    this._taskRepository,
    this._fileContextRepository,
    this._actualLogs,
  );

  final ActivityRecordRepository _activityRecords;
  final ActivityLogService _activityLogs;
  final InputActivityEventService _inputEvents;
  final ActivityFusionRepository _fusionRepository;
  final TaskRepository _taskRepository;
  final FileContextRepository _fileContextRepository;
  final ActualActivityLogRepository _actualLogs;

  Future<ActivityFusionRunResult> rebuildRange({
    required DateTime start,
    required DateTime end,
    Duration maxMergeGap = const Duration(minutes: 10),
  }) async {
    final records = await _activityRecords.listInRange(start, end);
    final rawLogs = await _activityLogs.readEntriesBetween(
      start,
      end,
      limit: 1000,
    );
    final inputEvents = await _inputEvents.listEvents(
      start: start,
      end: end,
      limit: 2000,
      includeIgnored: false,
    );
    final drafts = _buildSegments(
      records: records,
      rawLogs: rawLogs,
      inputEvents: inputEvents,
      maxMergeGap: maxMergeGap,
    );
    await _fusionRepository.replaceSegmentsForRange(
      start: start,
      end: end,
      segments: drafts,
    );

    final persistedSegments =
        await _fusionRepository.listSegmentsInRange(start, end);
    final tasks = await _taskRepository.listAllVisible();
    final taskFolders = await _loadTaskFolders(tasks);
    var interpretationCount = 0;
    var taskWorkLogCount = 0;
    var actualCandidateCount = 0;

    for (final segment in persistedSegments) {
      final link = _inferTask(segment, tasks, taskFolders);
      final document = _inferDocument(segment.primaryWindowTitle);
      final summary = _buildSummary(segment, link?.task);
      final interpretation = await _fusionRepository.insertInterpretation(
        segmentId: segment.id,
        summary: summary,
        inferredProject: link?.projectLabel,
        inferredDocument: document,
        inferredTaskId: link?.task.id,
        confidence: link?.confidence ?? segment.confidence,
        evidence: <String, Object?>{
          'segmentUid': segment.segmentUid,
          'process': segment.primaryProcessName,
          'windowTitle': segment.primaryWindowTitle,
          'category': segment.category,
          'label': segment.label,
          'matchedBy': link?.matchedBy,
          'matchedFolders': link?.matchedFolders,
        },
        status: 'candidate',
      );
      interpretationCount++;

      if (link != null) {
        await _fusionRepository.insertTaskWorkLog(
          taskId: link.task.id,
          segmentId: segment.id,
          startAt: segment.startAt,
          endAt: segment.endAt,
          confidence: link.confidence,
          sourceType: 'activity_interpretation',
          evidence: <String, Object?>{
            'interpretationUid': interpretation.interpretationUid,
            'matchedBy': link.matchedBy,
            'matchedFolders': link.matchedFolders,
            'summary': summary,
          },
          status: 'candidate',
        );
        taskWorkLogCount++;
      }

      // Rebuild only creates review candidates. Actual records are written by
      // confirmSegment after explicit user confirmation.
    }

    return ActivityFusionRunResult(
      sourceRecordCount: records.length,
      rawLogCount: rawLogs.length,
      inputEventCount: inputEvents.length,
      segmentCount: persistedSegments.length,
      interpretationCount: interpretationCount,
      taskWorkLogCount: taskWorkLogCount,
      actualCandidateCount: actualCandidateCount,
    );
  }

  Future<ActivitySegmentConfirmationResult> confirmSegment(
    int segmentId, {
    String? title,
    int? taskId,
    String? note,
    String actor = 'user',
  }) async {
    final segment = await _fusionRepository.getSegmentById(segmentId);
    if (segment == null) {
      throw StateError('Activity segment not found.');
    }

    final interpretations =
        await _fusionRepository.listInterpretationsForSegment(segmentId);
    final bestInterpretation = interpretations.isEmpty
        ? null
        : (List<ActivityInterpretation>.from(interpretations)
              ..sort((left, right) => right.confidence.compareTo(left.confidence)))
            .first;
    final actualTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : bestInterpretation?.summary ?? _buildSummary(segment, null);
    final resolvedTaskId = taskId ?? bestInterpretation?.inferredTaskId;
    final confidence = (bestInterpretation?.confidence ?? segment.confidence)
        .clamp(0, 1)
        .toDouble();

    final actualId = await _actualLogs.insertCandidate(
      title: actualTitle,
      startAt: segment.startAt,
      endAt: segment.endAt,
      sourceType: ActualActivitySourceType.trackingInference,
      sourceId: segment.segmentUid,
      sourcePayload: <String, Object?>{
        'segmentId': segment.id,
        'segmentUid': segment.segmentUid,
        'interpretationUid': bestInterpretation?.interpretationUid,
        'taskId': resolvedTaskId,
        'confirmedFrom': 'activity_review',
      },
      confidence: confidence,
      note: note,
      actor: actor,
    );
    await _actualLogs.confirm(actualId, actor: actor, note: note);
    final actual = await _actualLogs.getById(actualId);
    if (actual == null) {
      throw StateError('Confirmed actual record not found.');
    }

    TaskWorkLog? taskWorkLog;
    if (resolvedTaskId != null) {
      taskWorkLog = await _fusionRepository.upsertConfirmedTaskWorkLogForSegment(
        taskId: resolvedTaskId,
        segmentId: segment.id,
        actualId: actual.id,
        startAt: segment.startAt,
        endAt: segment.endAt,
        confidence: confidence,
        evidence: <String, Object?>{
          'segmentUid': segment.segmentUid,
          'actualUid': actual.actualUid,
          'interpretationUid': bestInterpretation?.interpretationUid,
          'confirmedBy': actor,
          'summary': actualTitle,
        },
        actor: actor,
      );
      await _fusionRepository.rejectTaskWorkLogsForSegmentExcept(
        segmentId: segment.id,
        taskId: resolvedTaskId,
        actor: actor,
      );
    }

    await _fusionRepository.updateSegmentStatus(
      segment.id,
      status: 'confirmed',
      actor: actor,
    );
    await _fusionRepository.updateInterpretationsStatusForSegment(
      segment.id,
      status: 'confirmed',
      actor: actor,
    );

    return ActivitySegmentConfirmationResult(
      actual: actual,
      taskWorkLog: taskWorkLog,
    );
  }

  List<ActivitySegmentDraft> _buildSegments({
    required List<ActivityRecord> records,
    required List<ActivityLogEntry> rawLogs,
    required List<TrackedInputEvent> inputEvents,
    required Duration maxMergeGap,
  }) {
    final sources = <_ActivityEvidenceSource>[
      for (final record in records)
        if (record.endTime != null) _ActivityEvidenceSource.fromRecord(record),
      for (final log in rawLogs)
        if (!log.isIgnored) _ActivityEvidenceSource.fromRawLog(log),
      ..._inputEventSources(inputEvents),
    ]..sort((left, right) => left.start.compareTo(right.start));

    if (sources.isEmpty) {
      return const <ActivitySegmentDraft>[];
    }

    final groups = <List<_ActivityEvidenceSource>>[];
    var current = <_ActivityEvidenceSource>[sources.first];
    for (final source in sources.skip(1)) {
      final previous = current.last;
      final closeEnough = source.start.difference(previous.end) <= maxMergeGap;
      if (_sameContext(previous, source) && closeEnough) {
        current.add(source);
      } else {
        groups.add(current);
        current = <_ActivityEvidenceSource>[source];
      }
    }
    groups.add(current);

    return groups.map(_draftFromGroup).toList(growable: false);
  }

  List<_ActivityEvidenceSource> _inputEventSources(
    List<TrackedInputEvent> events,
  ) {
    final groups = <String, List<TrackedInputEvent>>{};
    for (final event in events.where((event) => !event.isIgnored)) {
      final bucket = DateTime(
        event.timestamp.year,
        event.timestamp.month,
        event.timestamp.day,
        event.timestamp.hour,
        (event.timestamp.minute ~/ 5) * 5,
      );
      final key = [
        bucket.toIso8601String(),
        _norm(event.processName) ?? '',
        _norm(event.windowTitle) ?? '',
        _norm(event.category) ?? '',
      ].join('|');
      groups.putIfAbsent(key, () => <TrackedInputEvent>[]).add(event);
    }

    return groups.values.map(_ActivityEvidenceSource.fromInputEvents).toList();
  }

  ActivitySegmentDraft _draftFromGroup(List<_ActivityEvidenceSource> group) {
    final start = group.first.start;
    final end = group
        .map((source) => source.end)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final process = _mostFrequent(group.map((source) => source.processName));
    final title = _mostFrequent(group.map((source) => source.windowTitle));
    final category = _mostFrequent(group.map((source) => source.category));
    final label =
        _mostFrequent(group.map((source) => source.label)) ?? category ?? process;
    final linkedTaskIds = group
        .map((source) => source.linkedTaskId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final telemetryMinutes = group.fold<int>(
      0,
      (sum, source) => sum + source.durationMinutes,
    );
    final hasInput = group.any(
      (source) =>
          source.keyCount > 0 ||
          source.mouseClicks > 0 ||
          source.mouseMovePx > 0 ||
          source.scrollPx > 0,
    );
    final rawLogCount =
        group.where((source) => source.sourceType == 'raw_log').length;
    final inputEventCount =
        group.fold<int>(0, (sum, source) => sum + source.inputEventCount);
    final confidence = _segmentConfidence(
      groupSize: group.length,
      linkedTaskIds: linkedTaskIds,
      hasInput: hasInput,
      category: category,
      rawLogCount: rawLogCount,
      inputEventCount: inputEventCount,
    );

    return ActivitySegmentDraft(
      startAt: start,
      endAt: end,
      primaryProcessName: process,
      primaryWindowTitle: title,
      category: category,
      label: label,
      sourceRecordIds: group
          .map((source) => source.id)
          .where((id) => id > 0)
          .toSet()
          .toList(growable: false),
      confidence: confidence,
      status: 'candidate',
      evidence: <String, Object?>{
        'sourceCount': group.length,
        'activityRecordCount':
            group.where((source) => source.sourceType == 'activity_record').length,
        'rawLogCount': rawLogCount,
        'inputEventCount': inputEventCount,
        'linkedTaskIds': linkedTaskIds,
        'telemetryMinutes': telemetryMinutes,
        'hasInputTelemetry': hasInput,
        'processes': _topValues(group.map((source) => source.processName)),
        'windowTitles': _topValues(group.map((source) => source.windowTitle)),
      },
    );
  }

  bool _sameContext(
    _ActivityEvidenceSource left,
    _ActivityEvidenceSource right,
  ) {
    final leftTask = left.linkedTaskId;
    final rightTask = right.linkedTaskId;
    if (leftTask != null && rightTask != null && leftTask == rightTask) {
      return true;
    }
    final leftProcess = _norm(left.processName);
    final rightProcess = _norm(right.processName);
    if (leftProcess != null && leftProcess == rightProcess) {
      return true;
    }
    final leftCategory = _norm(left.category);
    final rightCategory = _norm(right.category);
    return leftCategory != null &&
        leftCategory == rightCategory &&
        leftProcess == rightProcess;
  }

  double _segmentConfidence({
    required int groupSize,
    required List<int> linkedTaskIds,
    required bool hasInput,
    required String? category,
    required int rawLogCount,
    required int inputEventCount,
  }) {
    var score = 0.46;
    if (groupSize >= 2) {
      score += 0.10;
    }
    if (linkedTaskIds.length == 1) {
      score += 0.22;
    }
    if (hasInput) {
      score += 0.08;
    }
    if (rawLogCount > 0) {
      score += 0.06;
    }
    if (inputEventCount >= 3) {
      score += 0.08;
    }
    if (category != null && category.trim().isNotEmpty) {
      score += 0.08;
    }
    return score.clamp(0, 0.95).toDouble();
  }

  _TaskInference? _inferTask(
    ActivitySegment segment,
    List<TaskItem> tasks,
    Map<int, List<FileFolder>> taskFolders,
  ) {
    final evidenceText = [
      segment.label,
      segment.category,
      segment.primaryProcessName,
      segment.primaryWindowTitle,
      segment.evidenceJson,
    ].whereType<String>().join(' ').toLowerCase();

    _TaskInference? best;
    for (final task in tasks) {
      final taskText = [
        task.summary,
        task.description,
        task.categories,
      ].whereType<String>().join(' ').toLowerCase();
      final taskMatches =
          _tokens(taskText).where((token) => evidenceText.contains(token)).length;
      final folders = taskFolders[task.id] ?? const <FileFolder>[];
      final folderTokens = <String>{};
      final matchedFolders = <String>[];
      for (final folder in folders) {
        final folderText = [
          folder.displayName,
          folder.localPath,
          folder.parentPath,
          folder.sourceContext,
        ].whereType<String>().join(' ').toLowerCase();
        folderTokens.addAll(_tokens(folderText));
        if (folderText.trim().isNotEmpty && evidenceText.contains(folderText)) {
          matchedFolders.add(folder.displayName);
        }
      }
      final folderMatches = folderTokens
          .where((token) => evidenceText.contains(token))
          .length;
      if (taskMatches == 0 && folderMatches == 0) {
        continue;
      }
      final confidence = (0.50 + taskMatches * 0.07 + folderMatches * 0.08)
          .clamp(0, 0.9)
          .toDouble();
      final inference = _TaskInference(
        task: task,
        confidence: confidence,
        matchedBy: folderMatches > 0 ? 'keyword+folder' : 'keyword',
        projectLabel: task.categories,
        matchedFolders: matchedFolders,
      );
      if (best == null || inference.confidence > best.confidence) {
        best = inference;
      }
    }
    return best;
  }

  Future<Map<int, List<FileFolder>>> _loadTaskFolders(
    List<TaskItem> tasks,
  ) async {
    final result = <int, List<FileFolder>>{};
    for (final task in tasks) {
      final folders = await _fileContextRepository.listConfirmedFoldersForEntity(
        entityType: FileContextEntityType.task,
        entityId: task.id.toString(),
      );
      if (folders.isNotEmpty) {
        result[task.id] = folders;
      }
    }
    return result;
  }

  String _buildSummary(ActivitySegment segment, TaskItem? task) {
    final duration = segment.durationMinutes;
    if (task != null) {
      return '处理任务「${task.summary}」约 $duration 分钟';
    }
    final label =
        segment.label ?? segment.category ?? segment.primaryProcessName ?? '未分类活动';
    return '$label 约 $duration 分钟';
  }

  String? _inferDocument(String? windowTitle) {
    final title = windowTitle?.trim();
    if (title == null || title.isEmpty) {
      return null;
    }
    final match =
        RegExp(r'([^\\/:*?"<>|]+\.[A-Za-z0-9]{1,8})').firstMatch(title);
    return match?.group(1);
  }

  String? _mostFrequent(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final raw in values) {
      final value = raw?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return null;
    }
    return counts.entries
        .reduce((left, right) => left.value >= right.value ? left : right)
        .key;
  }

  List<String> _topValues(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final raw in values) {
      final value = raw?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries.take(5).map((entry) => entry.key).toList(growable: false);
  }

  String? _norm(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Set<String> _tokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[\s\\/_\-.,;:()\[\]{}]+'))
        .where((token) => token.trim().length >= 2)
        .toSet();
  }
}

class _TaskInference {
  const _TaskInference({
    required this.task,
    required this.confidence,
    required this.matchedBy,
    required this.projectLabel,
    required this.matchedFolders,
  });

  final TaskItem task;
  final double confidence;
  final String matchedBy;
  final String? projectLabel;
  final List<String> matchedFolders;
}

class _ActivityEvidenceSource {
  const _ActivityEvidenceSource({
    required this.id,
    required this.start,
    required this.end,
    required this.sourceType,
    this.processName,
    this.windowTitle,
    this.category,
    this.label,
    this.linkedTaskId,
    this.keyCount = 0,
    this.mouseClicks = 0,
    this.mouseMovePx = 0,
    this.scrollPx = 0,
    this.inputEventCount = 0,
  });

  final int id;
  final DateTime start;
  final DateTime end;
  final String sourceType;
  final String? processName;
  final String? windowTitle;
  final String? category;
  final String? label;
  final int? linkedTaskId;
  final int keyCount;
  final int mouseClicks;
  final int mouseMovePx;
  final int scrollPx;
  final int inputEventCount;

  int get durationMinutes =>
      end.difference(start).inMinutes.clamp(1, 1 << 31).toInt();

  factory _ActivityEvidenceSource.fromRecord(ActivityRecord record) {
    return _ActivityEvidenceSource(
      id: record.id,
      start: record.startTime,
      end: record.endTime ?? record.startTime.add(const Duration(minutes: 1)),
      sourceType: 'activity_record',
      processName: record.processName ?? record.packageName,
      windowTitle: record.windowTitle,
      category: record.category,
      label: record.manualLabel,
      linkedTaskId: record.linkedTaskId,
      keyCount: record.keyCount,
      mouseClicks: record.mouseClicks,
      mouseMovePx: record.mouseMovePx,
      scrollPx: record.scrollPx,
    );
  }

  factory _ActivityEvidenceSource.fromRawLog(ActivityLogEntry log) {
    final duration =
        Duration(minutes: (log.durationMinutes ?? 1).clamp(1, 240).toInt());
    return _ActivityEvidenceSource(
      id: log.recordId ?? 0,
      start: log.timestamp,
      end: log.timestamp.add(duration),
      sourceType: 'raw_log',
      processName: log.processName ?? log.packageName,
      windowTitle: log.windowTitle,
      category: log.category,
      label: log.label,
      keyCount: log.keyCount,
      mouseClicks: log.mouseClicks,
      mouseMovePx: log.mouseMovePx,
      scrollPx: log.scrollPx,
    );
  }

  factory _ActivityEvidenceSource.fromInputEvents(
    List<TrackedInputEvent> events,
  ) {
    final ordered = List<TrackedInputEvent>.from(events)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final first = ordered.first;
    final last = ordered.last;
    final eventCount =
        ordered.fold<int>(0, (sum, event) => sum + event.eventCount);
    final keyCount = ordered
        .where((event) => event.kind == TrackedInputEventKind.keyDown)
        .fold<int>(0, (sum, event) => sum + event.eventCount);
    final clicks = ordered
        .where((event) => event.kind == TrackedInputEventKind.mouseButton)
        .fold<int>(0, (sum, event) => sum + event.eventCount);
    final movePx = ordered
        .where((event) => event.kind == TrackedInputEventKind.mouseMove)
        .fold<int>(0, (sum, event) => sum + event.moveDistance);
    final scrollPx = ordered
        .where((event) => event.kind == TrackedInputEventKind.mouseWheel)
        .fold<int>(0, (sum, event) => sum + event.wheelDelta.abs());
    return _ActivityEvidenceSource(
      id: first.recordId ?? 0,
      start: first.timestamp,
      end: last.timestamp.add(const Duration(minutes: 1)),
      sourceType: 'tracked_input_event',
      processName: first.processName,
      windowTitle: first.windowTitle,
      category: first.category,
      label: first.activityLabel,
      keyCount: keyCount,
      mouseClicks: clicks,
      mouseMovePx: movePx,
      scrollPx: scrollPx,
      inputEventCount: eventCount,
    );
  }
}
