// ActivityRecordRepository: activity record CRUD.
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity_service.dart';
import '../services/raw_input_service.dart';

class ActivityRecordRepository {
  final AppDatabase _db;
  final DeviceIdentityService _deviceIdentityService;

  ActivityRecordRepository(
    this._db, {
    DeviceIdentityService? deviceIdentityService,
  }) : _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService();

  Future<int> startRecord({
    required DateTime startTime,
    String? manualLabel,
    String? processName,
    String? windowTitle,
    String? packageName,
    String? category,
    String? deviceId,
    String? platform,
    int? linkedTaskId,
    bool isAuto = false,
    String source = 'manual',
  }) async {
    final id = await _db.into(_db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: startTime,
            manualLabel: Value(manualLabel),
            processName: Value(processName),
            windowTitle: Value(windowTitle),
            packageName: Value(packageName),
            category: Value(category),
            linkedTaskId: Value(linkedTaskId),
            isAuto: Value(isAuto),
            source: Value(source),
          ),
        );
    await _stampDeviceContext(id, deviceId: deviceId, platform: platform);
    return id;
  }

  Future<int> insertImportedRecord({
    required DateTime startTime,
    required DateTime endTime,
    String? processName,
    String? windowTitle,
    String? packageName,
    String? className,
    String? category,
    String? deviceId,
    String? platform,
    bool isAuto = true,
    String source = 'imported',
  }) async {
    final durationMinutes =
        endTime.difference(startTime).inMinutes.clamp(0, 1 << 31).toInt();
    final id = await _db.into(_db.activityRecords).insert(
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
    if (className?.trim().isNotEmpty ?? false) {
      await _db.customStatement(
        'UPDATE activity_records SET class_name = ? WHERE id = ?',
        [className!.trim(), id],
      );
    }
    await _stampDeviceContext(id, deviceId: deviceId, platform: platform);
    return id;
  }

  Future<void> _stampDeviceContext(
    int id, {
    String? deviceId,
    String? platform,
  }) async {
    var normalizedDeviceId = deviceId?.trim();
    var normalizedPlatform = platform?.trim();

    if (normalizedDeviceId == null || normalizedDeviceId.isEmpty) {
      normalizedDeviceId =
          await _deviceIdentityService.getOrCreateDeviceId(_db);
    }
    if (normalizedPlatform == null || normalizedPlatform.isEmpty) {
      normalizedPlatform = _deviceIdentityService.currentPlatform;
    }

    await _db.customStatement(
      '''
      UPDATE activity_records
      SET device_id = COALESCE(?, device_id),
          platform = COALESCE(?, platform)
      WHERE id = ?
      ''',
      [
        normalizedDeviceId.isEmpty ? null : normalizedDeviceId,
        normalizedPlatform.isEmpty ? null : normalizedPlatform,
        id,
      ],
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

  Future<List<ActivityRecord>> listInRangePage({
    required DateTime start,
    required DateTime end,
    String? processName,
    String? category,
    int? linkedTaskId,
    int limit = 200,
    int offset = 0,
  }) {
    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    return (_db.select(_db.activityRecords)
          ..where((r) {
            var expression = r.startTime.isSmallerThanValue(end) &
                (r.endTime.isNull() | r.endTime.isBiggerOrEqualValue(start));
            final trimmedProcess = processName?.trim();
            if (trimmedProcess != null && trimmedProcess.isNotEmpty) {
              expression = expression & r.processName.equals(trimmedProcess);
            }
            final trimmedCategory = category?.trim();
            if (trimmedCategory != null && trimmedCategory.isNotEmpty) {
              expression = expression & r.category.equals(trimmedCategory);
            }
            if (linkedTaskId != null) {
              expression = expression & r.linkedTaskId.equals(linkedTaskId);
            }
            return expression;
          })
          ..orderBy([(r) => OrderingTerm.desc(r.startTime)])
          ..limit(normalizedLimit, offset: normalizedOffset))
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
