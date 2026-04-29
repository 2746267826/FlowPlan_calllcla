// ActivityRecords table: activity tracking records
import 'package:drift/drift.dart';

class ActivityRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();

  // Total duration after the record is finalized.
  IntColumn get durationMinutes => integer().withDefault(const Constant(0))();

  // Phase 2C: richer telemetry payload attached to each record.
  IntColumn get keyCount => integer().withDefault(const Constant(0))();
  IntColumn get mouseClicks => integer().withDefault(const Constant(0))();
  IntColumn get mouseMovePx => integer().withDefault(const Constant(0))();
  IntColumn get scrollPx => integer().withDefault(const Constant(0))();
  TextColumn get keySequence => text().nullable()();

  // Manual records.
  TextColumn get manualLabel => text().nullable()();

  // Windows auto tracking.
  TextColumn get processName => text().nullable()();
  TextColumn get windowTitle => text().nullable()();

  // Android UsageStats.
  TextColumn get packageName => text().nullable()();

  // AI classification.
  TextColumn get category => text().nullable()();
  TextColumn get appUsageRuleId => text().nullable()();

  // Deep binding.
  IntColumn get linkedTaskId => integer().nullable()();

  // Whether the record was auto-generated.
  BoolColumn get isAuto => boolean().withDefault(const Constant(false))();

  TextColumn get source =>
      text().withDefault(const Constant('manual'))();
}
