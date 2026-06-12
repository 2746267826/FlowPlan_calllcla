import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_object_registry.dart';
import '../../../core/sync/sync_write_recorder.dart';
import '../../audit/data_operation_log_repository.dart';

class ReportType {
  const ReportType();

  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';
  static const diary = 'diary';
  static const project = 'project';
  static const course = 'course';
  static const task = 'task';
}

class ReportStatus {
  const ReportStatus();

  static const draft = 'draft';
  static const confirmed = 'confirmed';
  static const archived = 'archived';
}

class PushDeliveryStatus {
  const PushDeliveryStatus();

  static const pending = 'pending';
  static const sending = 'sending';
  static const sent = 'sent';
  static const failed = 'failed';
}

class ReportDocument {
  const ReportDocument({
    required this.id,
    required this.reportUid,
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    required this.title,
    required this.summaryMarkdown,
    required this.metricsJson,
    required this.sourceSnapshotJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
  });

  final int id;
  final String reportUid;
  final String reportType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String title;
  final String summaryMarkdown;
  final String metricsJson;
  final String sourceSnapshotJson;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'reportUid': reportUid,
        'reportType': reportType,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'title': title,
        'summaryMarkdown': summaryMarkdown,
        'metricsJson': metricsJson,
        'sourceSnapshotJson': sourceSnapshotJson,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'confirmedAt': confirmedAt?.toIso8601String(),
      };

  factory ReportDocument.fromRow(QueryRow row) {
    return ReportDocument(
      id: row.read<int>('id'),
      reportUid: row.read<String>('report_uid'),
      reportType: row.read<String>('report_type'),
      periodStart: DateTime.parse(row.read<String>('period_start')),
      periodEnd: DateTime.parse(row.read<String>('period_end')),
      title: row.read<String>('title'),
      summaryMarkdown: row.read<String>('summary_markdown'),
      metricsJson: row.read<String>('metrics_json'),
      sourceSnapshotJson: row.read<String>('source_snapshot_json'),
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
      confirmedAt: _date(row.data['confirmed_at']),
    );
  }
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.diaryUid,
    required this.entryDate,
    required this.title,
    required this.bodyMarkdown,
    required this.sourceReportId,
    required this.linkedTaskIdsJson,
    required this.linkedFileIdsJson,
    required this.locationJson,
    required this.weatherJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
  });

  final int id;
  final String diaryUid;
  final DateTime entryDate;
  final String title;
  final String bodyMarkdown;
  final int? sourceReportId;
  final String linkedTaskIdsJson;
  final String linkedFileIdsJson;
  final String locationJson;
  final String weatherJson;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'diaryUid': diaryUid,
        'entryDate': entryDate.toIso8601String(),
        'title': title,
        'bodyMarkdown': bodyMarkdown,
        'sourceReportId': sourceReportId,
        'linkedTaskIdsJson': linkedTaskIdsJson,
        'linkedFileIdsJson': linkedFileIdsJson,
        'locationJson': locationJson,
        'weatherJson': weatherJson,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'confirmedAt': confirmedAt?.toIso8601String(),
      };

  factory DiaryEntry.fromRow(QueryRow row) {
    return DiaryEntry(
      id: row.read<int>('id'),
      diaryUid: row.read<String>('diary_uid'),
      entryDate: DateTime.parse(row.read<String>('entry_date')),
      title: row.read<String>('title'),
      bodyMarkdown: row.read<String>('body_markdown'),
      sourceReportId: row.data['source_report_id'] as int?,
      linkedTaskIdsJson: row.read<String>('linked_task_ids_json'),
      linkedFileIdsJson: row.read<String>('linked_file_ids_json'),
      locationJson: row.read<String>('location_json'),
      weatherJson: row.read<String>('weather_json'),
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
      confirmedAt: _date(row.data['confirmed_at']),
    );
  }
}

class ReportPushDelivery {
  const ReportPushDelivery({
    required this.id,
    required this.deliveryUid,
    required this.reportId,
    required this.diaryId,
    required this.channel,
    required this.target,
    required this.payloadJson,
    required this.status,
    required this.attempts,
    required this.lastError,
    required this.scheduledAt,
    required this.sentAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String deliveryUid;
  final int? reportId;
  final int? diaryId;
  final String channel;
  final String? target;
  final String payloadJson;
  final String status;
  final int attempts;
  final String? lastError;
  final DateTime scheduledAt;
  final DateTime? sentAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'deliveryUid': deliveryUid,
        'reportId': reportId,
        'diaryId': diaryId,
        'channel': channel,
        'target': target,
        'payloadJson': payloadJson,
        'status': status,
        'attempts': attempts,
        'lastError': lastError,
        'scheduledAt': scheduledAt.toIso8601String(),
        'sentAt': sentAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ReportPushDelivery.fromRow(QueryRow row) {
    return ReportPushDelivery(
      id: row.read<int>('id'),
      deliveryUid: row.read<String>('delivery_uid'),
      reportId: row.data['report_id'] as int?,
      diaryId: row.data['diary_id'] as int?,
      channel: row.read<String>('channel'),
      target: row.data['target'] as String?,
      payloadJson: row.read<String>('payload_json'),
      status: row.read<String>('status'),
      attempts: row.read<int>('attempts'),
      lastError: row.data['last_error'] as String?,
      scheduledAt: DateTime.parse(row.read<String>('scheduled_at')),
      sentAt: _date(row.data['sent_at']),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class ReportRepository {
  ReportRepository(
    this._db, [
    this._operationLogs,
    this._syncWriteRecorder,
  ]);

  final AppDatabase _db;
  final DataOperationLogRepository? _operationLogs;
  final SyncWriteRecorder? _syncWriteRecorder;
  final Uuid _uuid = const Uuid();

  Future<ReportDocument> upsertReportDraft({
    required String reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String summaryMarkdown,
    required Map<String, Object?> metrics,
    required Map<String, Object?> sourceSnapshot,
  }) async {
    final now = DateTime.now();
    final reportUid = _reportUid(reportType, periodStart);
    final existing = await getReportForPeriod(
          reportType: reportType,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ) ??
        await getReportByUid(reportUid);
    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO report_documents (
          report_uid,
          report_type,
          period_start,
          period_end,
          title,
          summary_markdown,
          metrics_json,
          source_snapshot_json,
          status,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(report_uid) DO UPDATE SET
          report_type = excluded.report_type,
          period_start = excluded.period_start,
          period_end = excluded.period_end,
          title = excluded.title,
          summary_markdown = excluded.summary_markdown,
          metrics_json = excluded.metrics_json,
          source_snapshot_json = excluded.source_snapshot_json,
          status = excluded.status,
          updated_at = excluded.updated_at,
          confirmed_at = NULL
        ''',
        [
          reportUid,
          reportType,
          periodStart.toIso8601String(),
          periodEnd.toIso8601String(),
          title,
          summaryMarkdown,
          jsonEncode(metrics),
          jsonEncode(sourceSnapshot),
          ReportStatus.draft,
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );
      final report = await getReportByUid(reportUid) ??
          ReportDocument.fromRow(await _lastRow('report_documents'));
      await _recordReportCreate(report);
      return report;
    }

    await _db.customStatement(
      '''
      UPDATE report_documents
      SET title = ?,
          summary_markdown = ?,
          metrics_json = ?,
          source_snapshot_json = ?,
          status = ?,
          updated_at = ?,
          confirmed_at = NULL
      WHERE id = ?
      ''',
      [
        title,
        summaryMarkdown,
        jsonEncode(metrics),
        jsonEncode(sourceSnapshot),
        ReportStatus.draft,
        now.toIso8601String(),
        existing.id,
      ],
    );
    final report = (await getReportById(existing.id))!;
    await _recordReportUpdate(existing, report);
    return report;
  }

  Future<DiaryEntry> upsertDiaryDraft({
    required DateTime entryDate,
    required String title,
    required String bodyMarkdown,
    int? sourceReportId,
    List<int> linkedTaskIds = const <int>[],
    List<String> linkedFileIds = const <String>[],
    Map<String, Object?> location = const <String, Object?>{},
    Map<String, Object?> weather = const <String, Object?>{},
  }) async {
    final now = DateTime.now();
    final existing = await getDiaryForDate(entryDate);
    if (existing == null) {
      await _db.customStatement(
        '''
        INSERT INTO diary_entries (
          diary_uid,
          entry_date,
          title,
          body_markdown,
          source_report_id,
          linked_task_ids_json,
          linked_file_ids_json,
          location_json,
          weather_json,
          status,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _uuid.v4(),
          _dayKey(entryDate),
          title,
          bodyMarkdown,
          sourceReportId,
          jsonEncode(linkedTaskIds),
          jsonEncode(linkedFileIds),
          jsonEncode(location),
          jsonEncode(weather),
          ReportStatus.draft,
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );
      final diary = DiaryEntry.fromRow(await _lastRow('diary_entries'));
      await _recordDiaryCreate(diary);
      return diary;
    }

    await _db.customStatement(
      '''
      UPDATE diary_entries
      SET title = ?,
          body_markdown = ?,
          source_report_id = ?,
          linked_task_ids_json = ?,
          linked_file_ids_json = ?,
          location_json = ?,
          weather_json = ?,
          status = ?,
          updated_at = ?,
          confirmed_at = NULL
      WHERE id = ?
      ''',
      [
        title,
        bodyMarkdown,
        sourceReportId,
        jsonEncode(linkedTaskIds),
        jsonEncode(linkedFileIds),
        jsonEncode(location),
        jsonEncode(weather),
        ReportStatus.draft,
        now.toIso8601String(),
        existing.id,
      ],
    );
    final diary = (await getDiaryById(existing.id))!;
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.diaryEntry.key,
      localId: diary.id.toString(),
      uid: diary.diaryUid,
      payload: diary.toJson(),
    );
    return diary;
  }

  Future<ReportPushDelivery> queueDelivery({
    int? reportId,
    int? diaryId,
    required String channel,
    String? target,
    required Map<String, Object?> payload,
    DateTime? scheduledAt,
  }) async {
    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO report_push_deliveries (
        delivery_uid,
        report_id,
        diary_id,
        channel,
        target,
        payload_json,
        status,
        scheduled_at,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        reportId,
        diaryId,
        channel,
        target,
        jsonEncode(payload),
        PushDeliveryStatus.pending,
        (scheduledAt ?? now).toIso8601String(),
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    final delivery =
        ReportPushDelivery.fromRow(await _lastRow('report_push_deliveries'));
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.reportPushDelivery.key,
      localId: delivery.id.toString(),
      uid: delivery.deliveryUid,
      payload: delivery.toJson(),
    );
    return delivery;
  }

  Future<void> markDeliverySending(int id) async {
    await _db.customStatement(
      '''
      UPDATE report_push_deliveries
      SET status = ?, attempts = attempts + 1, last_error = NULL, updated_at = ?
      WHERE id = ?
      ''',
      [PushDeliveryStatus.sending, DateTime.now().toIso8601String(), id],
    );
  }

  Future<void> markDeliverySent(int id) async {
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE report_push_deliveries
      SET status = ?, sent_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      [PushDeliveryStatus.sent, now, now, id],
    );
    final delivery = await getDeliveryById(id);
    if (delivery != null) {
      await _syncWriteRecorder?.recordUpdate(
        objectType: SyncObjectType.reportPushDelivery.key,
        localId: delivery.id.toString(),
        uid: delivery.deliveryUid,
        payload: delivery.toJson(),
      );
    }
  }

  Future<void> markDeliveryFailed(int id, Object error) async {
    await _db.customStatement(
      '''
      UPDATE report_push_deliveries
      SET status = ?, last_error = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        PushDeliveryStatus.failed,
        error.toString(),
        DateTime.now().toIso8601String(),
        id,
      ],
    );
  }

  Future<void> confirmReport(int id) async {
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE report_documents
      SET status = ?, confirmed_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      [ReportStatus.confirmed, now, now, id],
    );
    final report = await getReportById(id);
    if (report != null) {
      await _syncWriteRecorder?.recordUpdate(
        objectType: SyncObjectType.reportDocument.key,
        localId: report.id.toString(),
        uid: report.reportUid,
        payload: report.toJson(),
      );
    }
  }

  Future<void> confirmDiary(int id) async {
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE diary_entries
      SET status = ?, confirmed_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      [ReportStatus.confirmed, now, now, id],
    );
    final diary = await getDiaryById(id);
    if (diary != null) {
      await _syncWriteRecorder?.recordUpdate(
        objectType: SyncObjectType.diaryEntry.key,
        localId: diary.id.toString(),
        uid: diary.diaryUid,
        payload: diary.toJson(),
      );
    }
  }

  Future<ReportDocument?> getReportById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM report_documents WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : ReportDocument.fromRow(row);
  }

  Future<ReportDocument?> getReportByUid(String reportUid) async {
    final row = await _db.customSelect(
      'SELECT * FROM report_documents WHERE report_uid = ? LIMIT 1',
      variables: [Variable<String>(reportUid)],
    ).getSingleOrNull();
    return row == null ? null : ReportDocument.fromRow(row);
  }

  Future<ReportDocument?> getReportForPeriod({
    required String reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final row = await _db.customSelect(
      '''
      SELECT *
      FROM report_documents
      WHERE report_type = ? AND period_start = ? AND period_end = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(reportType),
        Variable<String>(periodStart.toIso8601String()),
        Variable<String>(periodEnd.toIso8601String()),
      ],
    ).getSingleOrNull();
    return row == null ? null : ReportDocument.fromRow(row);
  }

  Future<DiaryEntry?> getDiaryById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM diary_entries WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : DiaryEntry.fromRow(row);
  }

  Future<DiaryEntry?> getDiaryForDate(DateTime date) async {
    final row = await _db.customSelect(
      'SELECT * FROM diary_entries WHERE entry_date = ? LIMIT 1',
      variables: [Variable<String>(_dayKey(date))],
    ).getSingleOrNull();
    return row == null ? null : DiaryEntry.fromRow(row);
  }

  Future<ReportPushDelivery?> getDeliveryById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM report_push_deliveries WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : ReportPushDelivery.fromRow(row);
  }

  Future<List<ReportDocument>> listRecentReports({int limit = 30}) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM report_documents
      ORDER BY period_start DESC, updated_at DESC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map(ReportDocument.fromRow).toList();
  }

  Future<List<ReportPushDelivery>> listPendingDeliveries({
    String? channel,
    int limit = 20,
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM report_push_deliveries
      WHERE status IN (?, ?)
        AND scheduled_at <= ?
        ${channel == null ? '' : 'AND channel = ?'}
      ORDER BY scheduled_at ASC, id ASC
      LIMIT ?
      ''',
      variables: [
        const Variable<String>(PushDeliveryStatus.pending),
        const Variable<String>(PushDeliveryStatus.failed),
        Variable<String>(DateTime.now().toIso8601String()),
        if (channel != null) Variable<String>(channel),
        Variable<int>(limit),
      ],
    ).get();
    return rows.map(ReportPushDelivery.fromRow).toList();
  }

  Future<QueryRow> _lastRow(String tableName) {
    return _db
        .customSelect(
          'SELECT * FROM $tableName WHERE id = last_insert_rowid()',
        )
        .getSingle();
  }

  Future<void> _recordReportCreate(ReportDocument report) async {
    await _operationLogs?.record(
      actor: 'system',
      action: 'generate_report_draft',
      entityType: 'report_document',
      entityId: report.id.toString(),
      summary: '生成报告草稿 ${report.title}',
      after: report.toJson(),
    );
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.reportDocument.key,
      localId: report.id.toString(),
      uid: report.reportUid,
      payload: report.toJson(),
    );
  }

  Future<void> _recordReportUpdate(
    ReportDocument before,
    ReportDocument after,
  ) async {
    await _operationLogs?.record(
      actor: 'system',
      action: 'refresh_report_draft',
      entityType: 'report_document',
      entityId: after.id.toString(),
      summary: '刷新报告草稿 ${after.title}',
      before: before.toJson(),
      after: after.toJson(),
    );
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.reportDocument.key,
      localId: after.id.toString(),
      uid: after.reportUid,
      payload: after.toJson(),
    );
  }

  Future<void> _recordDiaryCreate(DiaryEntry diary) async {
    await _operationLogs?.record(
      actor: 'system',
      action: 'generate_diary_draft',
      entityType: 'diary_entry',
      entityId: diary.id.toString(),
      summary: '生成日记草稿 ${diary.title}',
      after: diary.toJson(),
    );
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.diaryEntry.key,
      localId: diary.id.toString(),
      uid: diary.diaryUid,
      payload: diary.toJson(),
    );
  }

  String _dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _reportUid(String reportType, DateTime periodStart) {
    return 'report:$reportType:${_dayKey(periodStart)}';
  }
}

DateTime? _date(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
