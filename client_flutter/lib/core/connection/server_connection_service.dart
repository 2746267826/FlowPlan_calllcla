import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/app_release.dart';
import '../../features/audit/data_operation_log_repository.dart';
import '../bootstrap/client_bootstrap_service.dart';
import '../database/app_database.dart';
import '../server_api/client_api.dart';
import '../server_api/server_config_store.dart';
import 'server_connection_state.dart';

class ServerConnectionService extends ChangeNotifier {
  ServerConnectionService({
    required AppDatabase database,
    required ClientApi clientApi,
    required ClientBootstrapService bootstrapService,
    required ServerConfigStore serverConfigStore,
    required DataOperationLogRepository operationLogs,
    required String deviceId,
    required String platform,
  })  : _database = database,
        _clientApi = clientApi,
        _bootstrapService = bootstrapService,
        _serverConfigStore = serverConfigStore,
        _operationLogs = operationLogs,
        _deviceId = deviceId,
        _platform = platform {
    _bootstrapProgressHandler = _handleBootstrapProgress;
    _bootstrapService.onProgress = _bootstrapProgressHandler;
  }

  static const _maxBackoffSeconds = 300;

  final AppDatabase _database;
  final ClientApi _clientApi;
  final ClientBootstrapService _bootstrapService;
  final ServerConfigStore _serverConfigStore;
  final DataOperationLogRepository _operationLogs;
  final String _deviceId;
  final String _platform;

  Timer? _heartbeatTimer;
  Timer? _fullSyncTimer;
  Timer? _syncDebounceTimer;
  bool _started = false;
  bool _busy = false;
  bool _syncRequestedWhileBusy = false;
  int _failureCount = 0;
  String? _queuedSource;
  String? _queuedReason;
  ValueChanged<ClientSyncProgress>? _bootstrapProgressHandler;

  ServerConnectionState _state = const ServerConnectionState();

  ServerConnectionState get state => _state;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_initialize());
    _fullSyncTimer?.cancel();
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      requestSync(source: 'timer', reason: 'periodic_full_sync');
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _fullSyncTimer?.cancel();
    _syncDebounceTimer?.cancel();
    if (identical(_bootstrapService.onProgress, _bootstrapProgressHandler)) {
      _bootstrapService.onProgress = null;
    }
    _bootstrapProgressHandler = null;
    super.dispose();
  }

  void requestSync({
    String source = 'manual',
    String? reason,
    bool immediate = false,
  }) {
    _queuedSource = source;
    _queuedReason = reason;
    if (_busy) {
      _syncRequestedWhileBusy = true;
      _setState(_state.copyWith(
        syncPhase: 'queued',
        syncReason: reason ?? source,
      ));
      return;
    }
    _syncDebounceTimer?.cancel();
    final delay = immediate ? Duration.zero : const Duration(seconds: 2);
    _syncDebounceTimer = Timer(delay, () {
      unawaited(
          syncNow(source: _queuedSource ?? source, reason: _queuedReason));
    });
  }

  Future<void> syncNow({String source = 'manual', String? reason}) async {
    _queuedSource = _queuedSource ?? source;
    _queuedReason = _queuedReason ?? reason;
    if (_busy) {
      _syncRequestedWhileBusy = true;
      _setState(_state.copyWith(
        syncPhase: 'queued',
        syncReason: reason ?? source,
      ));
      return;
    }
    do {
      final runSource = _queuedSource ?? source;
      final runReason = _queuedReason ?? reason;
      _queuedSource = null;
      _queuedReason = null;
      _syncRequestedWhileBusy = false;
      await _runSync(source: runSource, reason: runReason);
    } while (_syncRequestedWhileBusy);
  }

  Future<void> _runSync({required String source, String? reason}) async {
    _busy = true;
    try {
      await _refreshLocalSummary();
      _setState(_state.copyWith(
        level: ServerConnectionLevel.syncing,
        syncing: true,
        syncPhase: 'preparing',
        syncReason: reason ?? source,
        clearError: true,
      ));
      try {
        final runtime = source == 'startup'
            ? await _bootstrapService.bootstrapAndSync(source: source)
            : await _bootstrapService.syncNow(source: source);
        if (runtime.serverReachable == false) {
          throw runtime.lastError ?? 'Server is not reachable.';
        }
        _failureCount = 0;
        await _refreshLocalSummary();
        final syncError = runtime.lastError;
        final hasSyncError = syncError != null && syncError.isNotEmpty;
        _setState(_state.copyWith(
          level: hasSyncError
              ? ServerConnectionLevel.degraded
              : _state.conflictCount > 0
                  ? ServerConnectionLevel.conflicted
                  : ServerConnectionLevel.online,
          lastSyncAt: hasSyncError
              ? runtime.lastSyncAt ?? _state.lastSyncAt
              : runtime.lastSyncAt ?? DateTime.now(),
          syncing: false,
          syncPhase: hasSyncError ? 'failed' : 'completed',
          syncReason: reason ?? source,
          lastError: syncError,
          clearError: !hasSyncError,
        ));
        if (hasSyncError) {
          _scheduleHeartbeat(const Duration(seconds: 30));
        } else {
          await heartbeat(eventSource: 'sync_success');
        }
      } catch (error) {
        await _handleFailure(error, source: source);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> heartbeat({String eventSource = 'timer'}) async {
    try {
      await _refreshLocalSummary();
      final serverUrl = (await _serverConfigStore.readBaseUri()).toString();
      final response = await _clientApi.heartbeat(
        deviceId: _deviceId,
        body: <String, Object?>{
          'clientTime': DateTime.now().toIso8601String(),
          'appVersion': appPackageVersion,
          'platform': _platform,
          'networkType': 'unknown',
          'networkSummary': <String, Object?>{
            'source': eventSource,
          },
          'syncSummary': <String, Object?>{
            'pendingCount': _state.pendingCount,
            'failedCount': _state.failedCount,
            'conflictCount': _state.conflictCount,
          },
          if (_state.lastError != null) 'errorMessage': _state.lastError,
        },
      );
      if (response['authRequired'] == true ||
          response['connectionStatus'] == 'revoked') {
        _setState(_state.copyWith(
          level: ServerConnectionLevel.authRequired,
          serverUrl: serverUrl,
          deviceId: _deviceId,
          platform: _platform,
          syncing: false,
          lastError: _readMessage(response, fallback: '服务端要求重新登录或设备已被撤销'),
        ));
        _scheduleHeartbeat(const Duration(minutes: 5));
        return;
      }
      if (response['ok'] == false) {
        throw _readMessage(response, fallback: '服务端拒绝 heartbeat');
      }
      _failureCount = 0;
      final nextSeconds = _readInt(response['nextHeartbeatSeconds']) ?? 30;
      _setState(_state.copyWith(
        level: _state.conflictCount > 0
            ? ServerConnectionLevel.conflicted
            : ServerConnectionLevel.online,
        serverUrl: serverUrl,
        deviceId: _deviceId,
        platform: _platform,
        lastHeartbeatAt: DateTime.now(),
        nextHeartbeatSeconds: nextSeconds,
        clearError: true,
      ));
      _scheduleHeartbeat(Duration(seconds: nextSeconds));
      if (response['hasServerChanges'] == true &&
          eventSource != 'sync_success') {
        requestSync(
          source: 'heartbeat_remote_change',
          reason: 'server_changes_available',
          immediate: true,
        );
      }
    } catch (error) {
      await _handleFailure(error, source: 'heartbeat');
    }
  }

  Future<void> _initialize() async {
    final serverUrl = (await _serverConfigStore.readBaseUri()).toString();
    _setState(_state.copyWith(
      serverUrl: serverUrl,
      deviceId: _deviceId,
      platform: _platform,
      level: ServerConnectionLevel.localCacheOnly,
    ));
    await syncNow(source: 'startup');
    _scheduleHeartbeat(const Duration(seconds: 30));
  }

  Future<void> _handleFailure(Object error, {required String source}) async {
    _failureCount++;
    await _database.setSetting(
      ClientBootstrapService.lastErrorKey,
      error.toString(),
    );
    await _operationLogs.record(
      actor: 'system',
      action: 'server_connection_failed',
      entityType: 'server_connection',
      summary: '服务端连接或同步失败，客户端保留本地缓存模式',
      metadata: <String, Object?>{
        'source': source,
        'failureCount': _failureCount,
        'error': error.toString(),
      },
    );
    await _refreshLocalSummary();
    _setState(_state.copyWith(
      level: _failureCount <= 1
          ? ServerConnectionLevel.degraded
          : ServerConnectionLevel.offline,
      syncing: false,
      lastError: error.toString(),
    ));
    _scheduleHeartbeat(_backoff);
  }

  Future<void> _refreshLocalSummary() async {
    try {
      final row = await _database.customSelect(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN status IN ('pending', 'sending') THEN 1 ELSE 0 END), 0) AS pending_count,
          COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0) AS failed_count,
          COALESCE(SUM(CASE WHEN status = 'conflict' THEN 1 ELSE 0 END), 0) AS conflict_count
        FROM offline_mutations
        ''',
      ).getSingle();
      final localConflicts = await _database.customSelect(
        '''
        SELECT COUNT(*) AS count
        FROM sync_conflicts
        WHERE status IN ('open', 'pending')
        ''',
      ).getSingleOrNull();
      final mutationConflict = _readInt(row.data['conflict_count']) ?? 0;
      final conflictCount =
          mutationConflict + (_readInt(localConflicts?.data['count']) ?? 0);
      _setState(_state.copyWith(
        pendingCount: _readInt(row.data['pending_count']) ?? 0,
        failedCount: _readInt(row.data['failed_count']) ?? 0,
        conflictCount: conflictCount,
      ));
    } catch (error) {
      debugPrint(
        'ServerConnectionService local summary refresh failed: $error',
      );
    }
  }

  Duration get _backoff {
    final seconds = switch (_failureCount) {
      <= 1 => 30,
      2 => 60,
      3 => 120,
      _ => _maxBackoffSeconds,
    };
    return Duration(seconds: seconds);
  }

  void _scheduleHeartbeat(Duration delay) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(delay, () {
      unawaited(heartbeat());
    });
  }

  void _setState(ServerConnectionState next) {
    _state = next;
    notifyListeners();
  }

  void _handleBootstrapProgress(ClientSyncProgress progress) {
    _setState(_state.copyWith(
      syncPhase: progress.phase,
      syncReason: progress.source,
      progressCurrent: progress.current,
      progressTotal: progress.total,
      lastSyncSummary: progress.summary.isEmpty
          ? null
          : Map<String, Object?>.from(progress.summary),
    ));
  }

  int? _readInt(Object? value) {
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

  String _readMessage(
    Map<String, dynamic> response, {
    required String fallback,
  }) {
    final reason = response['reason']?.toString().trim();
    if (reason != null && reason.isNotEmpty) {
      return reason;
    }
    final message = response['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return fallback;
  }
}
