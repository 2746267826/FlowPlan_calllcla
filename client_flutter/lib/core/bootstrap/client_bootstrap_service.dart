import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/foundation.dart';

import '../../features/audit/data_operation_log_repository.dart';
import '../database/app_database.dart';
import '../server_api/client_api.dart';
import '../server_api/remote_settings_repository.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_write_recorder.dart';

class ClientBootstrapService extends ChangeNotifier {
  ClientBootstrapService({
    required AppDatabase database,
    required ClientApi clientApi,
    required RemoteSettingsRepository remoteSettingsRepository,
    required Future<ServerSyncEngine> Function() syncEngineLoader,
    required DataOperationLogRepository operationLogs,
    Future<Map<String, Object?>> Function()? trackingUploadRunner,
  })  : _database = database,
        _clientApi = clientApi,
        _remoteSettingsRepository = remoteSettingsRepository,
        _syncEngineLoader = syncEngineLoader,
        _operationLogs = operationLogs,
        _trackingUploadRunner = trackingUploadRunner;

  static const stateKey = 'server.bootstrap.last_state_json';
  static const modeKey = 'server.connection.mode';
  static const lastErrorKey = 'server.connection.last_error';

  final AppDatabase _database;
  final ClientApi _clientApi;
  final RemoteSettingsRepository _remoteSettingsRepository;
  final Future<ServerSyncEngine> Function() _syncEngineLoader;
  final DataOperationLogRepository _operationLogs;
  final Future<Map<String, Object?>> Function()? _trackingUploadRunner;

  Timer? _timer;
  ClientRuntimeState _state = const ClientRuntimeState();

  ClientRuntimeState get state => _state;

  void start() {
    SyncWriteRecorder.onMutationRecorded = () => syncNow(source: 'write');
    _timer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(syncNow(source: 'timer'));
    });
    unawaited(bootstrapAndSync(source: 'startup'));
  }

  @override
  void dispose() {
    _timer?.cancel();
    SyncWriteRecorder.onMutationRecorded = null;
    super.dispose();
  }

  Future<ClientRuntimeState> bootstrapAndSync({String source = 'manual'}) async {
    _setState(_state.copyWith(syncing: true, lastError: null));
    try {
      final bootstrap = await _clientApi.bootstrap();
      await _database.setSetting(stateKey, jsonEncode(bootstrap));
      await _database.setSetting(modeKey, 'server_first');
      final remoteSettings = await _remoteSettingsRepository.refresh();
      final engine = await _syncEngineLoader();
      final push = await engine.pushPending();
      final trackingUpload = await _tryUploadTrackingBuffer(source);
      final pull = await engine.pullChanges();
      await _operationLogs.record(
        actor: 'system',
        action: 'client_bootstrap_sync',
        entityType: 'server_sync',
        summary: '客户端启动或手动触发服务端化同步',
        metadata: <String, Object?>{
          'source': source,
          'settingsVersion': remoteSettings.version,
          'pulledChanges': (pull['changes'] as List?)?.length ?? 0,
          'accepted': push.acceptedCount,
          'conflicts': push.conflictCount,
          'rejected': push.rejectedCount,
          'trackingUpload': trackingUpload,
        },
      );
      final next = ClientRuntimeState.fromBootstrap(
        bootstrap,
        mode: 'server_first',
        syncing: false,
      );
      _setState(next.copyWith(
        settingsVersion: remoteSettings.version,
        lastSyncAt: DateTime.now(),
      ));
      return _state;
    } catch (error) {
      await _database.setSetting(modeKey, 'local_cache');
      await _database.setSetting(lastErrorKey, error.toString());
      await _operationLogs.record(
        actor: 'system',
        action: 'client_bootstrap_sync_failed',
        entityType: 'server_sync',
        summary: '服务端不可用，客户端保留本地缓存模式',
        metadata: <String, Object?>{
          'source': source,
          'error': error.toString(),
        },
      );
      _setState(_state.copyWith(
        mode: 'local_cache',
        syncing: false,
        serverReachable: false,
        lastError: error.toString(),
      ));
      return _state;
    }
  }

  Future<ClientRuntimeState> syncNow({String source = 'manual'}) async {
    _setState(_state.copyWith(syncing: true, lastError: null));
    try {
      final engine = await _syncEngineLoader();
      final push = await engine.pushPending();
      final trackingUpload = await _tryUploadTrackingBuffer(source);
      final pull = await engine.pullChanges();
      await _operationLogs.record(
        actor: source == 'manual' ? 'user' : 'system',
        action: 'client_sync_now',
        entityType: 'server_sync',
        summary: '立即同步服务端',
        metadata: <String, Object?>{
          'source': source,
          'accepted': push.acceptedCount,
          'conflicts': push.conflictCount,
          'rejected': push.rejectedCount,
          'pulledChanges': (pull['changes'] as List?)?.length ?? 0,
          'trackingUpload': trackingUpload,
        },
      );
      _setState(_state.copyWith(
        mode: 'server_first',
        syncing: false,
        serverReachable: true,
        lastSyncAt: DateTime.now(),
      ));
      return _state;
    } catch (error) {
      await _database.setSetting(lastErrorKey, error.toString());
      _setState(_state.copyWith(
        mode: 'local_cache',
        syncing: false,
        serverReachable: false,
        lastError: error.toString(),
      ));
      return _state;
    }
  }

  Future<Map<String, dynamic>> prepareLocalImport() async {
    final snapshot = await buildLocalSnapshot();
    final response = await _clientApi.createLocalSnapshotImport(snapshot);
    await _operationLogs.record(
      actor: 'user',
      action: 'client_import_prepare',
      entityType: 'server_import',
      summary: '准备将本地数据导入服务端事实库',
      metadata: response,
    );
    return response;
  }

  Future<Map<String, dynamic>> confirmImport(String importId) async {
    final response = await _clientApi.confirmImport(importId);
    await _operationLogs.record(
      actor: 'user',
      action: 'client_import_confirm',
      entityType: 'server_import',
      entityId: importId,
      summary: '确认服务端接管本地数据',
      metadata: response,
    );
    await bootstrapAndSync(source: 'import_confirmed');
    return response;
  }

  Future<Map<String, Object?>> buildLocalSnapshot() async {
    final tables = <String>[
      'task_items',
      'task_lists',
      'calendar_events',
      'event_calendars',
      'task_schedule_segments',
      'actual_activity_logs',
      'activity_records',
      'file_folders',
      'file_items',
      'file_nodes',
      'file_context_links',
      'report_documents',
      'diary_entries',
    ];
    final objects = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      objects[table] = await _selectTable(table);
    }
    return <String, Object?>{
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toIso8601String(),
      'objects': objects,
      'settings': await _exportServerManagedSettings(),
      'localStateSummary': await _localStateSummary(),
    };
  }

  Future<List<Map<String, Object?>>> _selectTable(String table) async {
    try {
      final rows = await _database.customSelect(
        'SELECT * FROM $table ORDER BY id ASC LIMIT 5000',
      ).get();
      return rows.map(_rowToJson).toList(growable: false);
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
  }

  Future<List<Map<String, Object?>>> _exportServerManagedSettings() async {
    final rows = await _database.customSelect(
      '''
      SELECT setting_key, setting_value, updated_at
      FROM app_settings
      WHERE setting_key NOT LIKE 'server.api.%'
        AND setting_key NOT LIKE 'auth.%'
        AND setting_key NOT LIKE 'device.%'
        AND setting_key NOT LIKE 'window.%'
        AND setting_key NOT LIKE 'tray.%'
        AND setting_key NOT LIKE 'startup.%'
        AND setting_key NOT LIKE 'permission.%'
        AND setting_key NOT LIKE 'download.%'
        AND setting_key NOT LIKE 'cache.%'
      ORDER BY setting_key ASC
      ''',
    ).get();
    return rows.map(_rowToJson).toList(growable: false);
  }

  Future<Map<String, Object?>> _localStateSummary() async {
    Future<int> count(String table) async {
      try {
        final row = await _database
            .customSelect('SELECT COUNT(*) AS count FROM $table')
            .getSingle();
        final value = row.data['count'];
        return value is int ? value : int.tryParse(value.toString()) ?? 0;
      } catch (_) {
        return 0;
      }
    }

    return <String, Object?>{
      'tasks': await count('task_items'),
      'events': await count('calendar_events'),
      'offlineMutations': await count('offline_mutations'),
      'syncStates': await count('sync_object_states'),
      'conflicts': await count('sync_conflicts'),
    };
  }

  Future<Map<String, Object?>> _tryUploadTrackingBuffer(String source) async {
    final runner = _trackingUploadRunner;
    if (runner == null) {
      return const <String, Object?>{'enabled': false};
    }
    try {
      final result = await runner();
      return <String, Object?>{
        'enabled': true,
        'ok': true,
        ...result,
      };
    } catch (error) {
      await _database.setSetting('tracking.upload.last_error', error.toString());
      await _operationLogs.record(
        actor: 'system',
        action: 'tracking_upload_failed',
        entityType: 'tracking_ingest',
        summary: '追踪缓冲上传失败，保留本地等待下次重试',
        metadata: <String, Object?>{
          'source': source,
          'error': error.toString(),
        },
      );
      return <String, Object?>{
        'enabled': true,
        'ok': false,
        'error': error.toString(),
      };
    }
  }

  Map<String, Object?> _rowToJson(QueryRow row) {
    return row.data.map((key, value) {
      if (value is DateTime) {
        return MapEntry(key, value.toIso8601String());
      }
      return MapEntry(key, value);
    });
  }

  void _setState(ClientRuntimeState next) {
    _state = next;
    notifyListeners();
  }
}

@immutable
class ClientRuntimeState {
  const ClientRuntimeState({
    this.mode = 'unknown',
    this.syncing = false,
    this.serverReachable,
    this.lastBootstrapAt,
    this.lastSyncAt,
    this.lastError,
    this.settingsVersion,
    this.syncCursor,
    this.pendingActions = const <String, Object?>{},
  });

  final String mode;
  final bool syncing;
  final bool? serverReachable;
  final DateTime? lastBootstrapAt;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int? settingsVersion;
  final String? syncCursor;
  final Map<String, Object?> pendingActions;

  factory ClientRuntimeState.fromBootstrap(
    Map<String, dynamic> json, {
    required String mode,
    required bool syncing,
  }) {
    final actions = json['pendingActions'];
    return ClientRuntimeState(
      mode: mode,
      syncing: syncing,
      serverReachable: true,
      lastBootstrapAt: DateTime.now(),
      settingsVersion: _readInt(json['settingsVersion']),
      syncCursor: json['syncCursor']?.toString(),
      pendingActions: actions is Map
          ? Map<String, Object?>.from(actions)
          : const <String, Object?>{},
    );
  }

  ClientRuntimeState copyWith({
    String? mode,
    bool? syncing,
    bool? serverReachable,
    DateTime? lastBootstrapAt,
    DateTime? lastSyncAt,
    String? lastError,
    int? settingsVersion,
    String? syncCursor,
    Map<String, Object?>? pendingActions,
  }) {
    return ClientRuntimeState(
      mode: mode ?? this.mode,
      syncing: syncing ?? this.syncing,
      serverReachable: serverReachable ?? this.serverReachable,
      lastBootstrapAt: lastBootstrapAt ?? this.lastBootstrapAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError,
      settingsVersion: settingsVersion ?? this.settingsVersion,
      syncCursor: syncCursor ?? this.syncCursor,
      pendingActions: pendingActions ?? this.pendingActions,
    );
  }

  static int? _readInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }
}
