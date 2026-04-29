import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../tracker/data/activity_record_repository.dart';
import '../data/actual_activity_log_repository.dart';

class BlockingEventCandidateRunResult {
  const BlockingEventCandidateRunResult({
    required this.created,
    required this.skippedExisting,
    required this.skippedConfirmedOverlap,
    required this.skippedTrackingConflict,
    required this.skippedNotEnded,
  });

  final int created;
  final int skippedExisting;
  final int skippedConfirmedOverlap;
  final int skippedTrackingConflict;
  final int skippedNotEnded;

  int get skippedTotal =>
      skippedExisting +
      skippedConfirmedOverlap +
      skippedTrackingConflict +
      skippedNotEnded;
}

class BlockingEventActualCandidateService {
  BlockingEventActualCandidateService(
    this._db,
    this._actualLogs,
    this._activityRecords,
  );

  final AppDatabase _db;
  final ActualActivityLogRepository _actualLogs;
  final ActivityRecordRepository _activityRecords;

  Future<BlockingEventCandidateRunResult> generateForRange({
    required DateTime start,
    required DateTime end,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final events = await (_db.select(_db.calendarEvents)
          ..where(
            (event) =>
                event.isBlock.equals(true) &
                event.dtstart.isBiggerOrEqualValue(start) &
                event.dtstart.isSmallerThanValue(end),
          )
          ..orderBy([(event) => OrderingTerm.asc(event.dtstart)]))
        .get();

    var created = 0;
    var skippedExisting = 0;
    var skippedConfirmedOverlap = 0;
    var skippedTrackingConflict = 0;
    var skippedNotEnded = 0;

    for (final event in events) {
      if (event.status.trim().toUpperCase() == 'CANCELLED') {
        continue;
      }

      final eventEnd = event.dtend ?? event.dtstart.add(const Duration(hours: 1));
      if (eventEnd.isAfter(current)) {
        skippedNotEnded++;
        continue;
      }

      final existing = await _actualLogs.getBySource(
        sourceType: ActualActivitySourceType.blockingEvent,
        sourceId: event.id.toString(),
      );
      if (existing != null &&
          existing.status != ActualActivityStatus.rejected) {
        skippedExisting++;
        continue;
      }

      if (await _actualLogs.hasOverlappingConfirmed(event.dtstart, eventEnd)) {
        skippedConfirmedOverlap++;
        continue;
      }

      if (await _hasObviousTrackingConflict(event, eventEnd)) {
        skippedTrackingConflict++;
        continue;
      }

      await _actualLogs.insertCandidate(
        title: event.summary,
        startAt: event.dtstart,
        endAt: eventEnd,
        sourceType: ActualActivitySourceType.blockingEvent,
        sourceId: event.id.toString(),
        sourcePayload: <String, Object?>{
          'eventId': event.id,
          'eventUid': event.uid,
          'summary': event.summary,
          'location': event.location,
          'source': event.source,
          'status': event.status,
          'isBlock': event.isBlock,
        },
        confidence: 0.82,
        note: '阻挡日程已结束，且未发现已确认实际记录或明显冲突追踪证据。',
      );
      created++;
    }

    return BlockingEventCandidateRunResult(
      created: created,
      skippedExisting: skippedExisting,
      skippedConfirmedOverlap: skippedConfirmedOverlap,
      skippedTrackingConflict: skippedTrackingConflict,
      skippedNotEnded: skippedNotEnded,
    );
  }

  Future<bool> _hasObviousTrackingConflict(
    CalendarEvent event,
    DateTime eventEnd,
  ) async {
    final records = await _activityRecords.listInRange(event.dtstart, eventEnd);
    if (records.isEmpty) {
      return false;
    }

    var conflictingMinutes = 0;
    for (final record in records) {
      final recordEnd = record.endTime ?? eventEnd;
      final overlapStart =
          record.startTime.isAfter(event.dtstart) ? record.startTime : event.dtstart;
      final overlapEnd = recordEnd.isBefore(eventEnd) ? recordEnd : eventEnd;
      if (!overlapEnd.isAfter(overlapStart)) {
        continue;
      }
      if (_isClearlyUnrelated(record, event.summary)) {
        conflictingMinutes += overlapEnd.difference(overlapStart).inMinutes;
      }
    }

    final eventMinutes = eventEnd.difference(event.dtstart).inMinutes;
    final threshold = eventMinutes <= 30 ? 10 : (eventMinutes * 0.4).round();
    return conflictingMinutes >= threshold.clamp(10, 60);
  }

  bool _isClearlyUnrelated(ActivityRecord record, String eventTitle) {
    final category = record.category?.trim().toLowerCase();
    const conflictingCategories = <String>{
      'game',
      'gaming',
      'entertainment',
      'video',
      'social',
      'shopping',
    };
    if (category != null && conflictingCategories.contains(category)) {
      return true;
    }

    final haystack = [
      record.manualLabel,
      record.processName,
      record.windowTitle,
      record.packageName,
      record.category,
    ]
        .whereType<String>()
        .map((value) => value.toLowerCase())
        .join(' ');
    final tokens = eventTitle
        .toLowerCase()
        .split(RegExp(r'[\s,.;:，。；：、/\\_\-]+'))
        .where((token) => token.length >= 2)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return false;
    }
    return !tokens.any(haystack.contains);
  }
}
