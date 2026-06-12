part of 'tracker_page.dart';

enum _TrackerMenuAction {
  viewActivityReview,
  viewDayDetails,
  viewLogHistory,
  viewInputHistory,
  exportDatabase,
  openDatabaseFolder,
}

enum _TaskBindingSheetAction {
  unbind,
  createNew,
}

class _TrackerPageLoadKey {
  final DateTime selectedDate;

  const _TrackerPageLoadKey({
    required this.selectedDate,
  });

  bool matches({
    required DateTime selectedDate,
  }) {
    return DateUtils.isSameDay(this.selectedDate, selectedDate);
  }
}

class _TrackerPageSnapshot {
  final AsyncValue<List<ActivityRecord>> dayRecordsAsync;
  final ActivityInsights insights;
  final List<WorkSession> workSessions;
  final AsyncValue<InputHeatmapSummary> inputBehaviorSummaryAsync;
  final TrackerState trackerState;
  final DateTime refreshedAt;

  const _TrackerPageSnapshot({
    required this.dayRecordsAsync,
    required this.insights,
    required this.workSessions,
    required this.inputBehaviorSummaryAsync,
    required this.trackerState,
    required this.refreshedAt,
  });

  _TrackerPageSnapshot copyWith({
    AsyncValue<List<ActivityRecord>>? dayRecordsAsync,
    ActivityInsights? insights,
    List<WorkSession>? workSessions,
    AsyncValue<InputHeatmapSummary>? inputBehaviorSummaryAsync,
    TrackerState? trackerState,
    DateTime? refreshedAt,
  }) {
    return _TrackerPageSnapshot(
      dayRecordsAsync: dayRecordsAsync ?? this.dayRecordsAsync,
      insights: insights ?? this.insights,
      workSessions: workSessions ?? this.workSessions,
      inputBehaviorSummaryAsync:
          inputBehaviorSummaryAsync ?? this.inputBehaviorSummaryAsync,
      trackerState: trackerState ?? this.trackerState,
      refreshedAt: refreshedAt ?? this.refreshedAt,
    );
  }
}

@visibleForTesting
DateTime trackerPresentationDebugCopySnapshotRefreshedAt(
  DateTime refreshedAt,
) {
  final snapshot = _TrackerPageSnapshot(
    dayRecordsAsync: const AsyncValue.data(<ActivityRecord>[]),
    insights: ActivityInsights.empty(),
    workSessions: const <WorkSession>[],
    inputBehaviorSummaryAsync: AsyncValue.data(
      InputHeatmapSummary.empty(const InputEventQuery()),
    ),
    trackerState: const TrackerState(),
    refreshedAt: refreshedAt,
  );
  return snapshot.copyWith().refreshedAt;
}

class _TrackerLoadTimeout implements Exception {
  final String message;

  const _TrackerLoadTimeout(this.message);

  @override
  String toString() => message;
}
