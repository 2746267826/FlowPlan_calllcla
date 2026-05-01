import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../tracker_defaults.dart';

class WorkSession {
  final DateTime startTime;
  final DateTime endTime;
  final String label;
  final String? processName;
  final String? category;
  final List<ActivityRecord> records;
  final int durationMinutes;
  final int keyCount;
  final int mouseClicks;
  final int mouseMovePx;
  final int scrollPx;
  final List<String> processNames;
  final List<String> categories;
  final int interruptionCount;
  final int? rawRecordCountOverride;

  const WorkSession({
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.processName,
    required this.category,
    required this.records,
    required this.durationMinutes,
    required this.keyCount,
    required this.mouseClicks,
    required this.mouseMovePx,
    required this.scrollPx,
    required this.processNames,
    required this.categories,
    required this.interruptionCount,
    this.rawRecordCountOverride,
  });

  int get rawRecordCount => rawRecordCountOverride ?? records.length;
  bool get spansMultipleProcesses => processNames.length > 1;
  bool get spansMultipleCategories => categories.length > 1;
}

class WorkSessionGrouper {
  static const Duration mergeGap = Duration(minutes: 3);
  static const Duration contextMergeGap = Duration(minutes: 1);
  static const int shortInterruptionMinutes = 2;
  static const int shortInterruptionInputThreshold = 12;
  static const int shortInterruptionRunMinutes = 6;
  static const int shortInterruptionRunInputThreshold = 24;
  static const Duration selfExcludedBridgeGap = Duration(minutes: 8);

  static List<WorkSession> fromRecords(List<ActivityRecord> records) {
    if (records.isEmpty) {
      return const <WorkSession>[];
    }

    final ordered = List<ActivityRecord>.from(records)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final filtered = List<ActivityRecord>.from(ordered);
    filtered.removeWhere(_shouldIgnore);
    if (filtered.isEmpty) {
      return const <WorkSession>[];
    }

    final sessions = _buildBaseSessions(filtered);
    _mergeShortInterruptionRuns(sessions);
    _mergeAcrossIgnoredRuns(sessions, ordered);
    return sessions.map((session) => session.build()).toList(growable: false);
  }

  static List<_WorkSessionAccumulator> _buildBaseSessions(
    List<ActivityRecord> records,
  ) {
    final sessions = <_WorkSessionAccumulator>[];
    _WorkSessionAccumulator? current;

    for (final record in records) {
      if (current == null) {
        current = _WorkSessionAccumulator.fromRecord(record);
        continue;
      }

      if (current.canAbsorbRecord(record)) {
        current.add(record);
        continue;
      }

      sessions.add(current);
      current = _WorkSessionAccumulator.fromRecord(record);
    }

    if (current != null) {
      sessions.add(current);
    }

    if (sessions.length < 2) {
      return sessions;
    }

    final merged = <_WorkSessionAccumulator>[sessions.first];
    for (final next in sessions.skip(1)) {
      final previous = merged.last;
      if (previous.canAbsorbSession(next)) {
        previous.absorbSession(next);
      } else {
        merged.add(next);
      }
    }
    return merged;
  }

  static void _mergeShortInterruptionRuns(
    List<_WorkSessionAccumulator> sessions,
  ) {
    if (sessions.length < 3) {
      return;
    }

    var index = 1;
    while (index < sessions.length - 1) {
      final previous = sessions[index - 1];
      final interruptions = <_WorkSessionAccumulator>[];
      var totalInterruptionMinutes = 0;
      var totalInterruptionInput = 0;
      var currentIndex = index;
      var merged = false;

      while (currentIndex < sessions.length - 1) {
        final current = sessions[currentIndex];
        if (!current.isShortInterruption) {
          break;
        }

        interruptions.add(current);
        totalInterruptionMinutes += current.durationMinutes;
        totalInterruptionInput += current.inputScore;

        if (totalInterruptionMinutes > shortInterruptionRunMinutes ||
            totalInterruptionInput > shortInterruptionRunInputThreshold) {
          break;
        }

        final next = sessions[currentIndex + 1];
        final shouldBridge =
            previous.canBridgeAcrossRun(interruptions, next);
        if (shouldBridge) {
          previous.absorbInterruptionRun(interruptions, next);
          sessions.removeRange(index, currentIndex + 2);
          merged = true;
          break;
        }

        currentIndex += 1;
      }

      if (!merged) {
        index += 1;
      }
      if (merged && index > 1) {
        index -= 1;
      }
    }
  }

  static void _mergeAcrossIgnoredRuns(
    List<_WorkSessionAccumulator> sessions,
    List<ActivityRecord> orderedRecords,
  ) {
    if (sessions.length < 2) {
      return;
    }

    var index = 0;
    while (index < sessions.length - 1) {
      final previous = sessions[index];
      final next = sessions[index + 1];
      final shouldBridge = _shouldBridgeAcrossIgnoredGap(
        previous,
        next,
        orderedRecords,
      );

      if (!shouldBridge) {
        index += 1;
        continue;
      }

      previous.absorbIgnoredGap(next);
      sessions.removeAt(index + 1);
      if (index > 0) {
        index -= 1;
      }
    }
  }

  static bool _shouldBridgeAcrossIgnoredGap(
    _WorkSessionAccumulator previous,
    _WorkSessionAccumulator next,
    List<ActivityRecord> orderedRecords,
  ) {
    final gap = next.startTime.difference(previous.endTime);
    if (gap <= Duration.zero || gap > selfExcludedBridgeGap) {
      return false;
    }

    if (!previous.hasSameContext(next)) {
      return false;
    }

    var sawIgnoredRecord = false;
    for (final record in orderedRecords) {
      if (!record.startTime.isAfter(previous.endTime)) {
        continue;
      }
      if (!record.startTime.isBefore(next.startTime)) {
        break;
      }
      if (!_shouldIgnore(record)) {
        return false;
      }
      sawIgnoredRecord = true;
    }

    return sawIgnoredRecord;
  }

  static bool _shouldIgnore(ActivityRecord record) {
    return isTrackerSelfExcludedWindow(
      processName: record.processName,
      windowTitle: record.windowTitle,
    );
  }

  static String preferredLabel(ActivityRecord record) {
    final manual = record.manualLabel?.trim();
    if (manual != null && manual.isNotEmpty) {
      return manual;
    }

    final category = record.category?.trim();
    final process = record.processName?.trim();
    if (category != null && category.isNotEmpty) {
      if (process != null && process.isNotEmpty) {
        return '$category · $process';
      }
      return category;
    }

    if (process != null && process.isNotEmpty) {
      return process;
    }

    final title = record.windowTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    return '未命名工作会话';
  }

  static String strictSignature(ActivityRecord record) {
    final manual = record.manualLabel?.trim();
    if (manual != null && manual.isNotEmpty) {
      return 'manual:$manual';
    }

    final linkedTaskId = record.linkedTaskId;
    if (linkedTaskId != null) {
      return 'task:$linkedTaskId';
    }

    final process = record.processName?.trim().toLowerCase();
    if (process != null && process.isNotEmpty) {
      return 'process:$process';
    }

    final category = record.category?.trim();
    if (category != null && category.isNotEmpty) {
      return 'category:$category';
    }

    final title = record.windowTitle?.trim().toLowerCase();
    if (title != null && title.isNotEmpty) {
      return 'window:$title';
    }

    return 'unknown';
  }

  static String contextSignature(ActivityRecord record) {
    final manual = record.manualLabel?.trim();
    if (manual != null && manual.isNotEmpty) {
      return 'manual:$manual';
    }

    final linkedTaskId = record.linkedTaskId;
    if (linkedTaskId != null) {
      return 'task:$linkedTaskId';
    }

    final category = record.category?.trim();
    if (category != null && category.isNotEmpty) {
      return 'category:$category';
    }

    final process = record.processName?.trim().toLowerCase();
    if (process != null && process.isNotEmpty) {
      return 'process:$process';
    }

    final title = record.windowTitle?.trim().toLowerCase();
    if (title != null && title.isNotEmpty) {
      return 'window:$title';
    }

    return 'unknown';
  }

  static int recordWeight(ActivityRecord record) {
    final durationWeight = math.max(record.durationMinutes, 1);
    final inputWeight =
        record.keyCount + (record.mouseClicks * 4) + (record.scrollPx ~/ 120);
    return durationWeight + inputWeight;
  }
}

class _WorkSessionAccumulator {
  _WorkSessionAccumulator._(
    this._strictSignature,
    this._contextSignature,
    this._startTime,
    this._endTime,
    this._durationMinutes,
    this._keyCount,
    this._mouseClicks,
    this._mouseMovePx,
    this._scrollPx,
  );

  factory _WorkSessionAccumulator.fromRecord(ActivityRecord record) {
    final endTime = record.endTime ?? record.startTime;
    return _WorkSessionAccumulator._(
      WorkSessionGrouper.strictSignature(record),
      WorkSessionGrouper.contextSignature(record),
      record.startTime,
      endTime,
      record.durationMinutes,
      record.keyCount,
      record.mouseClicks,
      record.mouseMovePx,
      record.scrollPx,
    ).._appendRecord(record);
  }

  final String _strictSignature;
  final String _contextSignature;
  final List<ActivityRecord> _records = <ActivityRecord>[];
  final Map<String, int> _labelWeights = <String, int>{};
  final Map<String, int> _processWeights = <String, int>{};
  final Map<String, int> _categoryWeights = <String, int>{};
  DateTime _startTime;
  DateTime _endTime;
  int _durationMinutes;
  int _keyCount;
  int _mouseClicks;
  int _mouseMovePx;
  int _scrollPx;
  int _interruptionCount = 0;

  int get rawRecordCount => _records.length;
  DateTime get startTime => _startTime;
  DateTime get endTime => _endTime;

  int get inputScore {
    return _keyCount + (_mouseClicks * 4) + (_scrollPx ~/ 120);
  }

  int get durationMinutes {
    final computed = _endTime.difference(_startTime).inMinutes;
    return math.max(_durationMinutes, computed);
  }

  bool get isShortInterruption {
    return durationMinutes <= WorkSessionGrouper.shortInterruptionMinutes &&
        inputScore <= WorkSessionGrouper.shortInterruptionInputThreshold &&
        rawRecordCount <= 2;
  }

  bool canAbsorbRecord(ActivityRecord record) {
    final gap = record.startTime.difference(_endTime);
    if (gap > WorkSessionGrouper.mergeGap) {
      return false;
    }

    final strictSignature = WorkSessionGrouper.strictSignature(record);
    if (strictSignature == _strictSignature) {
      return true;
    }

    final contextSignature = WorkSessionGrouper.contextSignature(record);
    return gap <= WorkSessionGrouper.contextMergeGap &&
        contextSignature == _contextSignature;
  }

  bool canAbsorbSession(_WorkSessionAccumulator other) {
    final gap = other._startTime.difference(_endTime);
    if (gap > WorkSessionGrouper.mergeGap) {
      return false;
    }

    if (other._strictSignature == _strictSignature) {
      return true;
    }

    return gap <= WorkSessionGrouper.contextMergeGap &&
        other._contextSignature == _contextSignature;
  }

  bool hasSameContext(_WorkSessionAccumulator other) {
    return _contextSignature == other._contextSignature;
  }

  bool canBridgeAcrossRun(
    List<_WorkSessionAccumulator> interruptions,
    _WorkSessionAccumulator next,
  ) {
    if (interruptions.isEmpty || _contextSignature != next._contextSignature) {
      return false;
    }

    final firstInterruption = interruptions.first;
    final lastInterruption = interruptions.last;
    final gapToFirst = firstInterruption._startTime.difference(_endTime);
    if (gapToFirst > WorkSessionGrouper.mergeGap) {
      return false;
    }

    for (var index = 0; index < interruptions.length - 1; index += 1) {
      final current = interruptions[index];
      final following = interruptions[index + 1];
      final gap = following._startTime.difference(current._endTime);
      if (gap > WorkSessionGrouper.mergeGap) {
        return false;
      }
    }

    final gapToNext = next._startTime.difference(lastInterruption._endTime);
    return gapToNext <= WorkSessionGrouper.mergeGap;
  }

  void add(ActivityRecord record) {
    _appendRecord(record);
    _endTime = _maxDateTime(_endTime, record.endTime ?? record.startTime);
    _durationMinutes += record.durationMinutes;
    _keyCount += record.keyCount;
    _mouseClicks += record.mouseClicks;
    _mouseMovePx += record.mouseMovePx;
    _scrollPx += record.scrollPx;
  }

  void absorbSession(_WorkSessionAccumulator other) {
    for (final record in other._records) {
      _appendRecord(record);
    }
    _endTime = _maxDateTime(_endTime, other._endTime);
    _durationMinutes += other._durationMinutes;
    _keyCount += other._keyCount;
    _mouseClicks += other._mouseClicks;
    _mouseMovePx += other._mouseMovePx;
    _scrollPx += other._scrollPx;
    _interruptionCount += other._interruptionCount;
  }

  void absorbInterruptionRun(
    List<_WorkSessionAccumulator> interruptions,
    _WorkSessionAccumulator next,
  ) {
    for (final interruption in interruptions) {
      absorbSession(interruption);
    }
    _interruptionCount += interruptions.length;
    absorbSession(next);
  }

  void absorbIgnoredGap(_WorkSessionAccumulator next) {
    _interruptionCount += 1;
    absorbSession(next);
  }

  WorkSession build() {
    _records.sort((left, right) => left.startTime.compareTo(right.startTime));
    final processNames = _sortedKeysByWeight(_processWeights);
    final categories = _sortedKeysByWeight(_categoryWeights);
    final primaryProcess = processNames.isEmpty ? null : processNames.first;
    final primaryCategory = categories.isEmpty ? null : categories.first;

    return WorkSession(
      startTime: _startTime,
      endTime: _endTime,
      label: _buildPreferredLabel(primaryCategory, primaryProcess),
      processName: primaryProcess,
      category: primaryCategory,
      records: List<ActivityRecord>.unmodifiable(_records),
      durationMinutes: durationMinutes,
      keyCount: _keyCount,
      mouseClicks: _mouseClicks,
      mouseMovePx: _mouseMovePx,
      scrollPx: _scrollPx,
      processNames: List<String>.unmodifiable(processNames),
      categories: List<String>.unmodifiable(categories),
      interruptionCount: _interruptionCount,
    );
  }

  void _appendRecord(ActivityRecord record) {
    _records.add(record);

    final label = WorkSessionGrouper.preferredLabel(record);
    _labelWeights.update(
      label,
      (value) => value + WorkSessionGrouper.recordWeight(record),
      ifAbsent: () => WorkSessionGrouper.recordWeight(record),
    );

    final process = record.processName?.trim();
    if (process != null && process.isNotEmpty) {
      _processWeights.update(
        process,
        (value) => value + WorkSessionGrouper.recordWeight(record),
        ifAbsent: () => WorkSessionGrouper.recordWeight(record),
      );
    }

    final category = record.category?.trim();
    if (category != null && category.isNotEmpty) {
      _categoryWeights.update(
        category,
        (value) => value + WorkSessionGrouper.recordWeight(record),
        ifAbsent: () => WorkSessionGrouper.recordWeight(record),
      );
    }
  }

  String _buildPreferredLabel(String? primaryCategory, String? primaryProcess) {
    final rankedLabels = _sortedKeysByWeight(_labelWeights);
    if (rankedLabels.isEmpty) {
      return '未命名工作会话';
    }

    if (_processWeights.length > 1 && primaryCategory != null) {
      return '$primaryCategory 工作组合';
    }

    if (_categoryWeights.length > 1 && primaryProcess != null) {
      return '$primaryProcess 多场景工作';
    }

    return rankedLabels.first;
  }

  static List<String> _sortedKeysByWeight(Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((left, right) {
        final byWeight = right.value.compareTo(left.value);
        if (byWeight != 0) {
          return byWeight;
        }
        return left.key.compareTo(right.key);
      });
    return entries.map((entry) => entry.key).toList(growable: false);
  }

  static DateTime _maxDateTime(DateTime left, DateTime right) {
    return left.isAfter(right) ? left : right;
  }
}
