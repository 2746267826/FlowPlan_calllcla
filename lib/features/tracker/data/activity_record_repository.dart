// ActivityRecordRepository: activity record CRUD.
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../services/raw_input_service.dart';

class ActivityRecordRepository {
  final AppDatabase _db;
  ActivityRecordRepository(this._db);

  Future<int> startRecord({
    required DateTime startTime,
    String? manualLabel,
    String? processName,
    String? windowTitle,
    String? packageName,
    String? category,
    int? linkedTaskId,
    bool isAuto = false,
    String source = 'manual',
  }) =>
      _db.into(_db.activityRecords).insert(ActivityRecordsCompanion.insert(
            startTime: startTime,
            manualLabel: Value(manualLabel),
            processName: Value(processName),
            windowTitle: Value(windowTitle),
            packageName: Value(packageName),
            category: Value(category),
            linkedTaskId: Value(linkedTaskId),
            isAuto: Value(isAuto),
            source: Value(source),
          ));

  Future<int> insertImportedRecord({
    required DateTime startTime,
    required DateTime endTime,
    String? processName,
    String? windowTitle,
    String? packageName,
    String? category,
    bool isAuto = true,
    String source = 'imported',
  }) {
    final durationMinutes =
        endTime.difference(startTime).inMinutes.clamp(0, 1 << 31).toInt();
    return _db.into(_db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: startTime,
            endTime: Value(endTime),
            durationMinutes: Value(durationMinutes),
            processName: Value(processName),
            windowTitle: Value(windowTitle),
            packageName: Value(packageName),
            category: Value(category),
            isAuto: Value(isAuto),
            source: Value(source),
          ),
        );
  }

  Future<void> endRecord(
    int id,
    DateTime endTime, {
    InputTelemetry? telemetry,
  }) async {
    final record = await getById(id);
    if (record == null) return;

    final duration = endTime.difference(record.startTime).inMinutes;
    if (telemetry == null) {
      await (_db.update(_db.activityRecords)..where((r) => r.id.equals(id)))
          .write(ActivityRecordsCompanion(
        endTime: Value(endTime),
        durationMinutes: Value(duration),
      ));
      return;
    }

    await (_db.update(_db.activityRecords)..where((r) => r.id.equals(id)))
        .write(ActivityRecordsCompanion(
      endTime: Value(endTime),
      durationMinutes: Value(duration),
      keyCount: Value(telemetry.keyCount),
      mouseClicks: Value(telemetry.clicks.total),
      mouseMovePx: Value(telemetry.mouseMovePx),
      scrollPx: Value(telemetry.scrollPx),
      keySequence: Value(telemetry.keySequence),
    ));
  }

  Future<void> updateTelemetry(
    int id, {
    InputTelemetry? telemetry,
    int? durationMinutes,
  }) async {
    if (telemetry == null) return;
    await (_db.update(_db.activityRecords)..where((r) => r.id.equals(id)))
        .write(ActivityRecordsCompanion(
      durationMinutes: durationMinutes == null
          ? const Value.absent()
          : Value(durationMinutes),
      keyCount: Value(telemetry.keyCount),
      mouseClicks: Value(telemetry.clicks.total),
      mouseMovePx: Value(telemetry.mouseMovePx),
      scrollPx: Value(telemetry.scrollPx),
      keySequence: Value(telemetry.keySequence),
    ));
  }

  Future<ActivityRecord?> getById(int id) =>
      (_db.select(_db.activityRecords)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  Stream<List<ActivityRecord>> watchForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return watchInRange(start, end);
  }

  Stream<List<ActivityRecord>> watchInRange(DateTime start, DateTime end) {
    return (_db.select(_db.activityRecords)
          ..where((r) =>
              r.startTime.isSmallerThanValue(end) &
              (r.endTime.isNull() | r.endTime.isBiggerOrEqualValue(start)))
          ..orderBy([(r) => OrderingTerm(expression: r.startTime)]))
        .watch();
  }

  Future<List<ActivityRecord>> listInRange(DateTime start, DateTime end) {
    return (_db.select(_db.activityRecords)
          ..where((r) =>
              r.startTime.isSmallerThanValue(end) &
              (r.endTime.isNull() | r.endTime.isBiggerOrEqualValue(start)))
          ..orderBy([(r) => OrderingTerm(expression: r.startTime)]))
        .get();
  }

  Stream<List<ActivityRecord>> watchByTaskId(int taskId) {
    return (_db.select(_db.activityRecords)
          ..where((r) => r.linkedTaskId.equals(taskId))
          ..orderBy([(r) => OrderingTerm(expression: r.startTime)]))
        .watch();
  }

  Future<List<ActivityRecord>> listByTaskId(int taskId) {
    return (_db.select(_db.activityRecords)
          ..where((r) => r.linkedTaskId.equals(taskId))
          ..orderBy([(r) => OrderingTerm(expression: r.startTime)]))
        .get();
  }

  Future<void> linkTask(int recordId, int? taskId) =>
      (_db.update(_db.activityRecords)..where((r) => r.id.equals(recordId)))
          .write(ActivityRecordsCompanion(linkedTaskId: Value(taskId)));

  Future<void> linkTasks(Iterable<int> recordIds, int? taskId) async {
    final ids = recordIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    await _db.transaction(() async {
      for (final recordId in ids) {
        await (_db.update(_db.activityRecords)
              ..where((r) => r.id.equals(recordId)))
            .write(ActivityRecordsCompanion(linkedTaskId: Value(taskId)));
      }
    });
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.activityRecords)..where((r) => r.id.equals(id))).go();

  Future<ActivityRecord?> getActiveRecord() => (_db.select(_db.activityRecords)
        ..where((r) => r.endTime.isNull())
        ..orderBy([(r) => OrderingTerm.desc(r.startTime)])
        ..limit(1))
      .getSingleOrNull();
}
