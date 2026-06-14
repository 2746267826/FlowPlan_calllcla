part of 'tracker_page.dart';

Widget _card(BuildContext context, Widget child) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

Widget _emptyState({
  required IconData icon,
  required String title,
  required String subtitle,
  bool compact = false,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 8 : 24),
    child: Center(
      child: Column(
        children: [
          Icon(
            icon,
            size: compact ? 30 : 44,
            color: Colors.grey.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

Widget _summaryCard(String title, String value, String note) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final view = views.isEmpty ? null : views.first;
  final width =
      view == null ? 800.0 : view.physicalSize.width / view.devicePixelRatio;
  final compact = width < 520;
  return Container(
    width: compact ? math.max(180, width - 56) : 210,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F7F9),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    ),
  );
}

Widget _metricChip(IconData icon, String label, String value, Color color) {
  return Container(
    width: 170,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ),
  );
}

Widget _statusBadge(String label, Color color) {
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

Widget _pill(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label\uff1a$value',
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    ),
  );
}

Widget _tag(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, color: Colors.grey),
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
  return '$hour:$minute';
}

String _formatDateTimeShort(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return '$month-$day ${_formatTime(dateTime)}';
}

String _formatDayShort(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return '$month-$day';
}

String _formatSessionRange(DateTime start, DateTime end) {
  final isSameDay = start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (isSameDay) {
    return '${_formatDayShort(start)} ${_formatTime(start)} - ${_formatTime(end)}';
  }
  return '${_formatDateTimeShort(start)} - ${_formatDateTimeShort(end)}';
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) {
    return '0 \u5206\u949f';
  }
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours <= 0) {
    return '$mins \u5206\u949f';
  }
  if (mins == 0) {
    return '$hours \u5c0f\u65f6';
  }
  return '$hours \u5c0f\u65f6 $mins \u5206\u949f';
}

String _sessionTitle(String? processName, String? windowTitle, String? label) {
  final trimmedLabel = label?.trim();
  final trimmedTitle = windowTitle?.trim();
  if (trimmedLabel != null && trimmedLabel.isNotEmpty) {
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      return '$trimmedLabel \u00b7 $trimmedTitle';
    }
    return trimmedLabel;
  }
  if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
    return trimmedTitle;
  }
  final trimmedProcess = processName?.trim();
  return (trimmedProcess == null || trimmedProcess.isEmpty)
      ? '\u672a\u547d\u540d\u7a97\u53e3'
      : trimmedProcess;
}

String _sessionSubtitle(String? processName, String? category) {
  final parts = <String>[
    if (category != null && category.trim().isNotEmpty) category.trim(),
    if (processName != null && processName.trim().isNotEmpty)
      processName.trim(),
  ];
  return parts.isEmpty
      ? '\u672a\u5206\u7c7b\u5916\u90e8\u4f1a\u8bdd'
      : parts.join(' \u00b7 ');
}

String _statusText(TrackerState state) {
  if (!state.isRunning) {
    return '\u5df2\u505c\u6b62';
  }
  if (state.isViewingExcludedApp) {
    return '\u51bb\u7ed3\u67e5\u770b\u4e2d';
  }
  if (state.displaySnapshot == null) {
    return '\u7b49\u5f85\u91c7\u96c6';
  }
  return '\u91c7\u96c6\u4e2d';
}

Color _statusColor(TrackerState state) {
  if (!state.isRunning) {
    return Colors.grey;
  }
  if (state.isViewingExcludedApp) {
    return const Color(0xFFF5935A);
  }
  return const Color(0xFF0EA8A0);
}

int _sessionMinutes(DateTime? start, DateTime? end) {
  if (start == null || end == null) {
    return 0;
  }
  return end.difference(start).inMinutes.clamp(0, 1 << 31).toInt();
}

int _sessionInputScore(WorkSession session) {
  return session.keyCount +
      (session.mouseClicks * 4) +
      (session.scrollPx ~/ 120);
}

String _formatHourLabel(int hour) {
  final normalized = hour < 0 ? 0 : (hour > 23 ? 23 : hour);
  return '${normalized.toString().padLeft(2, '0')}:00';
}

int? _selectedHourForCurrentBucket(
  ActivityHeatmapBucket? bucket,
  DateTime selectedDate,
) {
  if (bucket == null) {
    return null;
  }

  final dayStart = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));
  final isHourlyBucket =
      bucket.end.difference(bucket.start) == const Duration(hours: 1);
  if (!isHourlyBucket ||
      bucket.start.isBefore(dayStart) ||
      bucket.end.isAfter(dayEnd)) {
    return null;
  }
  return bucket.start.hour;
}

int? _dominantHourForRange({
  required DateTime itemStart,
  required DateTime itemEnd,
  required DateTime selectedDate,
}) {
  final dayStart = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));
  if (!_timeRangeOverlaps(
    rangeStart: dayStart,
    rangeEnd: dayEnd,
    itemStart: itemStart,
    itemEnd: itemEnd,
  )) {
    return null;
  }

  final normalizedEnd = itemEnd.isAfter(itemStart)
      ? itemEnd
      : itemStart.add(const Duration(seconds: 1));
  final effectiveStart = itemStart.isBefore(dayStart) ? dayStart : itemStart;
  final effectiveEnd = normalizedEnd.isAfter(dayEnd) ? dayEnd : normalizedEnd;
  if (!effectiveEnd.isAfter(effectiveStart)) {
    return null;
  }

  var bestHour = effectiveStart.hour;
  var bestOverlapSeconds = -1;
  for (var hour = 0; hour < 24; hour += 1) {
    final bucketStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hour,
    );
    final bucketEnd = bucketStart.add(const Duration(hours: 1));
    final overlapSeconds = _timeRangeOverlapSeconds(
      leftStart: effectiveStart,
      leftEnd: effectiveEnd,
      rightStart: bucketStart,
      rightEnd: bucketEnd,
    );
    if (overlapSeconds > bestOverlapSeconds) {
      bestOverlapSeconds = overlapSeconds;
      bestHour = hour;
    }
  }

  return bestOverlapSeconds <= 0 ? null : bestHour;
}

String _truncateLabel(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}

String _rangeSessionSortModeLabel(_RangeSessionSortMode mode) {
  switch (mode) {
    case _RangeSessionSortMode.recent:
      return '最近优先';
    case _RangeSessionSortMode.longest:
      return '时长优先';
    case _RangeSessionSortMode.input:
      return '输入优先';
  }
}

bool _isSameBucket(
  ActivityHeatmapBucket? left,
  ActivityHeatmapBucket? right,
) {
  if (left == null || right == null) {
    return left == null && right == null;
  }
  return left.start == right.start && left.end == right.end;
}

bool _matchesWorkSession(
  WorkSession session, {
  required String searchQuery,
  required String? selectedProcess,
  required String? selectedCategory,
  required int? selectedTaskId,
  required bool onlyWithInput,
  required ActivityHeatmapBucket? selectedHeatmapBucket,
}) {
  if (selectedProcess != null &&
      !session.processNames.contains(selectedProcess)) {
    return false;
  }

  if (selectedCategory != null &&
      !session.categories.contains(selectedCategory) &&
      session.category != selectedCategory) {
    return false;
  }

  if (selectedTaskId != null &&
      !session.records.any((record) => record.linkedTaskId == selectedTaskId)) {
    return false;
  }

  if (onlyWithInput &&
      !_hasInputActivity(
        keyCount: session.keyCount,
        mouseClicks: session.mouseClicks,
        mouseMovePx: session.mouseMovePx,
        scrollPx: session.scrollPx,
      )) {
    return false;
  }

  if (selectedHeatmapBucket != null &&
      !_timeRangeOverlaps(
        rangeStart: selectedHeatmapBucket.start,
        rangeEnd: selectedHeatmapBucket.end,
        itemStart: session.startTime,
        itemEnd: session.endTime,
      )) {
    return false;
  }

  final searchTarget = <String>[
    session.label,
    if (session.processName != null) session.processName!,
    if (session.category != null) session.category!,
    ...session.processNames,
    ...session.categories,
    ...session.records
        .map((record) => record.windowTitle?.trim())
        .whereType<String>(),
  ].join(' ');

  return _matchesSearchText(searchTarget, searchQuery);
}

bool _matchesActivityRecord(
  ActivityRecord record, {
  required String? selectedProcess,
  required String? selectedCategory,
  required bool onlyWithInput,
}) {
  if (selectedProcess != null &&
      record.processName?.trim() != selectedProcess) {
    return false;
  }

  if (selectedCategory != null && record.category?.trim() != selectedCategory) {
    return false;
  }

  if (onlyWithInput &&
      !_hasInputActivity(
        keyCount: record.keyCount,
        mouseClicks: record.mouseClicks,
        mouseMovePx: record.mouseMovePx,
        scrollPx: record.scrollPx,
      )) {
    return false;
  }

  return true;
}

bool _matchesLogEntry(
  ActivityLogEntry entry, {
  required String searchQuery,
  required String? selectedProcess,
  required String? selectedCategory,
  Set<int>? selectedRecordIds,
  required bool onlyWithInput,
  required ActivityHeatmapBucket? selectedHeatmapBucket,
}) {
  if (selectedProcess != null && entry.processName?.trim() != selectedProcess) {
    return false;
  }

  if (selectedCategory != null && entry.category?.trim() != selectedCategory) {
    return false;
  }

  if (selectedRecordIds != null &&
      (entry.recordId == null || !selectedRecordIds.contains(entry.recordId))) {
    return false;
  }

  if (onlyWithInput &&
      !_hasInputActivity(
        keyCount: entry.keyCount,
        mouseClicks: entry.mouseClicks,
        mouseMovePx: entry.mouseMovePx,
        scrollPx: entry.scrollPx,
      )) {
    return false;
  }

  if (selectedHeatmapBucket != null &&
      !_timeRangeContains(
        timestamp: entry.timestamp,
        rangeStart: selectedHeatmapBucket.start,
        rangeEnd: selectedHeatmapBucket.end,
      )) {
    return false;
  }

  final searchTarget = <String>[
    if (entry.label != null) entry.label!,
    if (entry.processName != null) entry.processName!,
    if (entry.windowTitle != null) entry.windowTitle!,
    if (entry.category != null) entry.category!,
    if (entry.note != null) entry.note!,
    _LogEntryTile._entryTypeLabel(entry.type),
  ].join(' ');

  return _matchesSearchText(searchTarget, searchQuery);
}

@visibleForTesting
bool trackerPresentationDebugMatchesLogEntry(
  ActivityLogEntry entry, {
  required String searchQuery,
  required String? selectedProcess,
  required String? selectedCategory,
  Set<int>? selectedRecordIds,
  required bool onlyWithInput,
  required ActivityHeatmapBucket? selectedHeatmapBucket,
}) {
  return _matchesLogEntry(
    entry,
    searchQuery: searchQuery,
    selectedProcess: selectedProcess,
    selectedCategory: selectedCategory,
    selectedRecordIds: selectedRecordIds,
    onlyWithInput: onlyWithInput,
    selectedHeatmapBucket: selectedHeatmapBucket,
  );
}

@visibleForTesting
int? trackerPresentationDebugDominantHourForRange({
  required DateTime itemStart,
  required DateTime itemEnd,
  required DateTime selectedDate,
}) {
  return _dominantHourForRange(
    itemStart: itemStart,
    itemEnd: itemEnd,
    selectedDate: selectedDate,
  );
}

@visibleForTesting
bool trackerPresentationDebugTimeRangeOverlaps({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime itemStart,
  required DateTime itemEnd,
}) {
  return _timeRangeOverlaps(
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    itemStart: itemStart,
    itemEnd: itemEnd,
  );
}

bool _hasInputActivity({
  required int keyCount,
  required int mouseClicks,
  required int mouseMovePx,
  required int scrollPx,
}) {
  return keyCount > 0 || mouseClicks > 0 || mouseMovePx > 0 || scrollPx > 0;
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

bool _timeRangeOverlaps({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime itemStart,
  required DateTime itemEnd,
}) {
  final normalizedItemEnd = itemEnd.isAfter(itemStart)
      ? itemEnd
      : itemStart.add(const Duration(seconds: 1));
  return itemStart.isBefore(rangeEnd) && normalizedItemEnd.isAfter(rangeStart);
}

bool _timeRangeContains({
  required DateTime timestamp,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  return !timestamp.isBefore(rangeStart) && timestamp.isBefore(rangeEnd);
}

int _timeRangeOverlapSeconds({
  required DateTime leftStart,
  required DateTime leftEnd,
  required DateTime rightStart,
  required DateTime rightEnd,
}) {
  final effectiveStart = leftStart.isAfter(rightStart) ? leftStart : rightStart;
  final effectiveEnd = leftEnd.isBefore(rightEnd) ? leftEnd : rightEnd;
  if (!effectiveEnd.isAfter(effectiveStart)) {
    return 0;
  }
  return effectiveEnd.difference(effectiveStart).inSeconds;
}

String _buildLogTypeSummary(List<ActivityLogEntry> entries) {
  if (entries.isEmpty) {
    return '';
  }

  final counts = <ActivityLogEntryType, int>{};
  for (final entry in entries) {
    counts.update(entry.type, (value) => value + 1, ifAbsent: () => 1);
  }

  final orderedTypes = ActivityLogEntryType.values
      .where(counts.containsKey)
      .toList(growable: false);
  return orderedTypes
      .map((type) => '${_LogEntryTile._entryTypeLabel(type)} ${counts[type]}')
      .join(' · ');
}

String _buildLogDaySummary(List<ActivityLogEntry> entries) {
  if (entries.isEmpty) {
    return '';
  }

  final counts = <String, int>{};
  for (final entry in entries) {
    final day = _formatDate(entry.timestamp);
    counts.update(day, (value) => value + 1, ifAbsent: () => 1);
  }

  final orderedDays = counts.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  return orderedDays.take(5).map((day) => '$day ${counts[day]}条').join(' · ');
}

List<String> _collectRangeProcessOptions({
  required List<ActivityRecord> records,
  required List<ActivityLogEntry> logEntries,
}) {
  final values = <String>{};

  for (final record in records) {
    final process = record.processName?.trim();
    if (process != null && process.isNotEmpty) {
      values.add(process);
    }
  }

  for (final entry in logEntries) {
    final process = entry.processName?.trim();
    if (process != null && process.isNotEmpty) {
      values.add(process);
    }
  }

  final sorted = values.toList()
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return sorted;
}

List<String> _collectRangeCategoryOptions({
  required List<ActivityRecord> records,
  required List<ActivityLogEntry> logEntries,
}) {
  final values = <String>{};

  for (final record in records) {
    final category = record.category?.trim();
    if (category != null && category.isNotEmpty) {
      values.add(category);
    }
  }

  for (final entry in logEntries) {
    final category = entry.category?.trim();
    if (category != null && category.isNotEmpty) {
      values.add(category);
    }
  }

  final sorted = values.toList()..sort((left, right) => left.compareTo(right));
  return sorted;
}

String _buildSessionDaySummary(
  List<WorkSession> sessions, {
  int limit = 6,
}) {
  if (sessions.isEmpty) {
    return '';
  }

  final counts = <String, int>{};
  for (final session in sessions) {
    final day = _formatDayShort(session.startTime);
    counts.update(day, (value) => value + 1, ifAbsent: () => 1);
  }

  final orderedDays = counts.keys.toList()
    ..sort((left, right) => right.compareTo(left));

  final preview = orderedDays.take(limit).map(
        (day) => '$day ${counts[day]}段',
      );
  final result = preview.join(' · ');
  if (orderedDays.length <= limit) {
    return result;
  }
  return '$result · 等 ${orderedDays.length} 天';
}

String _joinPreview(List<String> values, {int limit = 3}) {
  if (values.isEmpty) {
    return '\u672a\u77e5\u5e94\u7528';
  }
  if (values.length <= limit) {
    return values.join('\u3001');
  }
  final preview = values.take(limit).join('\u3001');
  return '$preview \u7b49 ${values.length} \u4e2a\u5e94\u7528';
}

List<TaskItem> _buildTaskFilterOptions({
  required List<ActivityRecord> records,
  required Map<int, TaskItem> taskById,
}) {
  final orderedIds = <int>[];
  final seenIds = <int>{};

  for (final record in records) {
    final taskId = record.linkedTaskId;
    if (taskId == null || !seenIds.add(taskId)) {
      continue;
    }
    orderedIds.add(taskId);
  }

  final tasks = orderedIds
      .map((taskId) => taskById[taskId])
      .whereType<TaskItem>()
      .toList(growable: false);
  tasks.sort((left, right) => left.summary.compareTo(right.summary));
  return tasks;
}

List<int> _collectLinkedTaskIds(Iterable<ActivityRecord> records) {
  final ids = <int>{};
  for (final record in records) {
    final taskId = record.linkedTaskId;
    if (taskId != null) {
      ids.add(taskId);
    }
  }
  final sorted = ids.toList()..sort();
  return sorted;
}

String _taskLabel(TaskItem? task, {required int fallbackId}) {
  final summary = task?.summary.trim();
  if (summary != null && summary.isNotEmpty) {
    return summary;
  }
  return '任务 #$fallbackId';
}

List<TaskItem> _buildTrackerTaskCandidates(
  List<TaskItem> tasks,
  DateTime referenceDate,
) {
  final candidates = List<TaskItem>.from(tasks);
  final referenceDay = DateUtils.dateOnly(referenceDate);
  candidates.sort(
    (left, right) => _compareTrackerTaskCandidates(left, right, referenceDay),
  );

  return candidates.take(24).toList(growable: false);
}

@visibleForTesting
List<TaskItem> trackerPresentationDebugBuildTaskCandidates(
  List<TaskItem> tasks,
  DateTime referenceDate,
) {
  return _buildTrackerTaskCandidates(tasks, referenceDate);
}

@visibleForTesting
int trackerPresentationDebugCompareTaskCandidates(
  TaskItem left,
  TaskItem right,
  DateTime referenceDate,
) {
  return _compareTrackerTaskCandidates(
    left,
    right,
    DateUtils.dateOnly(referenceDate),
  );
}

int _compareTrackerTaskCandidates(
  TaskItem left,
  TaskItem right,
  DateTime referenceDay,
) {
  final leftCompletion = _taskCompletionRank(left);
  final rightCompletion = _taskCompletionRank(right);
  if (leftCompletion != rightCompletion) {
    return leftCompletion.compareTo(rightCompletion);
  }

  final leftDistance = _taskDayDistance(left, referenceDay);
  final rightDistance = _taskDayDistance(right, referenceDay);
  if (leftDistance != rightDistance) {
    return leftDistance.compareTo(rightDistance);
  }

  final leftAnchor = _taskAnchorTime(left);
  final rightAnchor = _taskAnchorTime(right);
  if (leftAnchor != null && rightAnchor != null) {
    final byAnchor = leftAnchor.compareTo(rightAnchor);
    if (byAnchor != 0) {
      return byAnchor;
    }
  } else if (leftAnchor != null || rightAnchor != null) {
    return leftAnchor == null ? 1 : -1;
  }

  return left.summary.toLowerCase().compareTo(right.summary.toLowerCase());
}

int _taskCompletionRank(TaskItem task) {
  return task.status == 'COMPLETED' ? 1 : 0;
}

DateTime? _taskAnchorTime(TaskItem task) {
  return task.dtstart ?? task.due ?? task.completed;
}

int _taskDayDistance(TaskItem task, DateTime referenceDay) {
  final anchor = _taskAnchorTime(task);
  if (anchor == null) {
    return 1 << 20;
  }
  return DateUtils.dateOnly(anchor).difference(referenceDay).inDays.abs();
}

String _taskCandidateSubtitle(TaskItem task) {
  final parts = <String>[
    if (task.status.trim().isNotEmpty) _taskStatusLabel(task.status),
    if (task.due != null) '截止 ${_formatDateTimeShort(task.due!)}',
    if (task.dtstart != null) '安排于 ${_formatDateTimeShort(task.dtstart!)}',
  ];
  if (parts.isEmpty) {
    return '暂无时间信息';
  }
  return parts.join(' · ');
}

String _taskStatusLabel(String status) {
  switch (status) {
    case 'COMPLETED':
      return '已完成';
    case 'IN-PROCESS':
      return '进行中';
    case 'CANCELLED':
      return '已取消';
    case 'NEEDS-ACTION':
    default:
      return '待处理';
  }
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

String? _stringValue(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
