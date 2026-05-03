import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/platform/device_identity_service.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/providers/settings_provider.dart';
import '../models/activity_log_entry.dart';
import '../models/tracked_input_event.dart';
import '../tracker_defaults.dart';
import 'activity_classifier.dart';
import 'android_usage_import_service.dart';
import 'android_usage_stats_service.dart';
import 'raw_input_service.dart';
import 'tracker_platform_source.dart';
import 'window_sensor.dart';

part 'tracker_service.g.dart';

class TrackerState {
  static const Object _unset = Object();

  final bool isRunning;
  final WindowSnapshot? currentSnapshot;
  final ActivityClassification? currentClassification;
  final DateTime? sessionStart;
  final int? activeRecordId;
  final InputTelemetry? currentTelemetry;
  final WindowSnapshot? displaySnapshot;
  final ActivityClassification? displayClassification;
  final DateTime? displaySessionStart;
  final InputTelemetry? displayTelemetry;
  final bool isViewingExcludedApp;
  final bool? hasUsageStatsPermission;
  final DateTime? lastSampleAt;
  final String? lastError;

  const TrackerState({
    this.isRunning = false,
    this.currentSnapshot,
    this.currentClassification,
    this.sessionStart,
    this.activeRecordId,
    this.currentTelemetry,
    this.displaySnapshot,
    this.displayClassification,
    this.displaySessionStart,
    this.displayTelemetry,
    this.isViewingExcludedApp = false,
    this.hasUsageStatsPermission,
    this.lastSampleAt,
    this.lastError,
  });

  TrackerState copyWith({
    bool? isRunning,
    Object? currentSnapshot = _unset,
    Object? currentClassification = _unset,
    Object? sessionStart = _unset,
    Object? activeRecordId = _unset,
    Object? currentTelemetry = _unset,
    Object? displaySnapshot = _unset,
    Object? displayClassification = _unset,
    Object? displaySessionStart = _unset,
    Object? displayTelemetry = _unset,
    bool? isViewingExcludedApp,
    Object? hasUsageStatsPermission = _unset,
    Object? lastSampleAt = _unset,
    Object? lastError = _unset,
  }) {
    return TrackerState(
      isRunning: isRunning ?? this.isRunning,
      currentSnapshot: identical(currentSnapshot, _unset)
          ? this.currentSnapshot
          : currentSnapshot as WindowSnapshot?,
      currentClassification: identical(currentClassification, _unset)
          ? this.currentClassification
          : currentClassification as ActivityClassification?,
      sessionStart: identical(sessionStart, _unset)
          ? this.sessionStart
          : sessionStart as DateTime?,
      activeRecordId: identical(activeRecordId, _unset)
          ? this.activeRecordId
          : activeRecordId as int?,
      currentTelemetry: identical(currentTelemetry, _unset)
          ? this.currentTelemetry
          : currentTelemetry as InputTelemetry?,
      displaySnapshot: identical(displaySnapshot, _unset)
          ? this.displaySnapshot
          : displaySnapshot as WindowSnapshot?,
      displayClassification: identical(displayClassification, _unset)
          ? this.displayClassification
          : displayClassification as ActivityClassification?,
      displaySessionStart: identical(displaySessionStart, _unset)
          ? this.displaySessionStart
          : displaySessionStart as DateTime?,
      displayTelemetry: identical(displayTelemetry, _unset)
          ? this.displayTelemetry
          : displayTelemetry as InputTelemetry?,
      isViewingExcludedApp:
          isViewingExcludedApp ?? this.isViewingExcludedApp,
      hasUsageStatsPermission: identical(hasUsageStatsPermission, _unset)
          ? this.hasUsageStatsPermission
          : hasUsageStatsPermission as bool?,
      lastSampleAt: identical(lastSampleAt, _unset)
          ? this.lastSampleAt
          : lastSampleAt as DateTime?,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
    );
  }
}

@Riverpod(keepAlive: true)
class TrackerServiceNotifier extends _$TrackerServiceNotifier {
  Timer? _timer;
  Timer? _inputEventTimer;
  final WindowSensor _sensor = const WindowSensor();
  final ActivityClassifier _classifier = ActivityClassifier();
  final DeviceIdentityService _deviceIdentityService = DeviceIdentityService();
  final TrackerPlatformSource _platform = TrackerPlatformSource.current();
  final Duration _sampleInterval = const Duration(seconds: 5);
  final Duration _inputEventPollInterval = const Duration(seconds: 1);
  InputTelemetry? _telemetryBaseline;
  InputTelemetry _activeTelemetry = InputTelemetry.empty();
  bool _sampleInFlight = false;
  bool _inputEventPollInFlight = false;

  @override
  TrackerState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _inputEventTimer?.cancel();
    });
    ref.listen<bool>(sequenceRecordingProvider, (previous, next) {
      if (_platform.supportsSequenceRecording) {
        unawaited(rawInputService.setSequenceRecording(next));
      }
    });
    if (_platform.supportsSequenceRecording) {
      unawaited(
        rawInputService.setSequenceRecording(
          ref.read(sequenceRecordingProvider),
        ),
      );
    }
    return const TrackerState();
  }

  void start() {
    if (state.isRunning) {
      return;
    }

    if (_platform.collectionMode == TrackerCollectionMode.manualUsageStatsImport) {
      state = state.copyWith(isRunning: true);
      unawaited(_importAndroidUsage());
      return;
    }

    if (_platform.collectionMode !=
        TrackerCollectionMode.continuousWindowSampling) {
      return;
    }

    state = state.copyWith(isRunning: true);
    unawaited(_startWindowsTracking());
  }

  Future<void> _startWindowsTracking() async {
    try {
      await rawInputService.start();
    } catch (error) {
      state = state.copyWith(
        isRunning: false,
        lastError: 'RawInput 启动失败：$error',
      );
      return;
    }

    if (!state.isRunning) {
      return;
    }

    unawaited(_sample());
    unawaited(_pollInputEvents());
    _timer = Timer.periodic(_sampleInterval, (_) {
      unawaited(_sample());
    });
    _inputEventTimer = Timer.periodic(_inputEventPollInterval, (_) {
      unawaited(_pollInputEvents());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _inputEventTimer?.cancel();
    _inputEventTimer = null;
    if (_platform.supportsInputAnalytics) {
      unawaited(rawInputService.stop());
    }
    unawaited(_stopAsync());
  }

  Future<void> refreshNow() async {
    if (_platform.collectionMode == TrackerCollectionMode.manualUsageStatsImport) {
      await _importAndroidUsage();
      return;
    }

    if (_platform.collectionMode !=
        TrackerCollectionMode.continuousWindowSampling) {
      return;
    }
    await _sample();
  }

  Future<void> openAndroidUsageAccessSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    await const AndroidUsageStatsService().openUsageAccessSettings();
  }

  Future<void> _stopAsync() async {
    if (_platform.collectionMode == TrackerCollectionMode.manualUsageStatsImport) {
      state = const TrackerState(isRunning: false);
      return;
    }

    final wroteLog = await _finishCurrentRecord();
    if (wroteLog) {
      _notifyLogChanged();
    }
    state = const TrackerState(isRunning: false);
    _telemetryBaseline = null;
    _activeTelemetry = InputTelemetry.empty();
  }

  Future<void> _importAndroidUsage() async {
    try {
      final importService = AndroidUsageImportService(
        database: ref.read(databaseProvider),
        activityRecordRepository: ref.read(activityRecordRepositoryProvider),
        activityLogService: ref.read(activityLogServiceProvider),
        classifier: _classifier,
        deviceIdentityService: _deviceIdentityService,
      );
      final result = await importService.importLatest();
      final sampledAt = result.importedUntil ?? DateTime.now();
      final latestSnapshot = result.latestSnapshot ?? state.currentSnapshot;
      final latestClassification =
          result.latestClassification ?? state.currentClassification;
      final latestSessionStart = result.latestSessionStart ?? state.sessionStart;
      final emptyTelemetry = InputTelemetry.empty(sampledAt);

      state = state.copyWith(
        isRunning: true,
        currentSnapshot: latestSnapshot,
        currentClassification: latestClassification,
        sessionStart: latestSessionStart,
        activeRecordId: null,
        currentTelemetry: emptyTelemetry,
        displaySnapshot: latestSnapshot,
        displayClassification: latestClassification,
        displaySessionStart: latestSessionStart,
        displayTelemetry: emptyTelemetry,
        isViewingExcludedApp: false,
        hasUsageStatsPermission:
            result.supported ? result.permissionGranted : null,
        lastSampleAt: sampledAt,
      );

      if (result.importedRecordCount > 0 || result.importedLogCount > 0) {
        _notifyLogChanged();
      }
    } catch (_) {
      state = state.copyWith(
        isRunning: true,
        lastSampleAt: DateTime.now(),
      );
    }
  }

  Future<void> _sample() async {
    if (_sampleInFlight) {
      return;
    }
    _sampleInFlight = true;
    try {
      await _sampleOnce();
    } catch (error) {
      state = state.copyWith(
        lastSampleAt: DateTime.now(),
        lastError: error.toString(),
      );
    } finally {
      _sampleInFlight = false;
    }
  }

  Future<void> _pollInputEvents() async {
    if (!_platform.supportsInputAnalytics ||
        !rawInputService.isRunning ||
        _inputEventPollInFlight) {
      return;
    }
    _inputEventPollInFlight = true;
    try {
      final events = await rawInputService.getPendingInputEvents(
        maxEvents: 1000,
      );
      if (events.isEmpty) {
        return;
      }
      final currentSnapshot = state.currentSnapshot;
      await ref.read(inputActivityEventServiceProvider).appendEvents(
        events: events,
        bindings: <InputEventContextBinding>[
          _buildInputBinding(
            snapshot: currentSnapshot,
            classification: state.currentClassification,
            recordId: state.activeRecordId,
            isIgnored:
                currentSnapshot == null ? false : _isSelfExcluded(currentSnapshot),
          ),
        ],
      );
      var maxSequenceId = 0;
      for (final event in events) {
        if (event.sequenceId > maxSequenceId) {
          maxSequenceId = event.sequenceId;
        }
      }
      await rawInputService.ackInputEvents(maxSequenceId);
      _notifyLogChanged();
    } catch (error) {
      state = state.copyWith(
        lastSampleAt: DateTime.now(),
        lastError: error.toString(),
      );
    } finally {
      _inputEventPollInFlight = false;
    }
  }

  Future<void> _sampleOnce() async {
    final snapshot = _sensor.capture();
    if (snapshot == null) {
      state = state.copyWith(lastSampleAt: DateTime.now());
      return;
    }

    final classification = _classifier.classify(snapshot);
    final telemetry = await rawInputService.getStats();
    final rawInputError = rawInputService.lastError;
    final previousSnapshot = state.currentSnapshot;
    final previousClassification = state.currentClassification;
    final previousRecordId = state.activeRecordId;
    final contextChanged =
        previousSnapshot == null || !snapshot.isSameContext(previousSnapshot);
    final isIgnored = _isSelfExcluded(snapshot);
    final inputEvents = telemetry?.inputEvents ?? const <RawInputEvent>[];
    final previousBaseline = _telemetryBaseline;
    final deltaTelemetry = telemetry != null && previousBaseline != null
        ? telemetry.subtract(previousBaseline)
        : InputTelemetry.empty(snapshot.timestamp);

    var wroteLog = false;

    if (isIgnored) {
      wroteLog = await _persistInputEvents(
            events: inputEvents,
            bindings: <InputEventContextBinding>[
              _buildInputBinding(
                snapshot: previousSnapshot ?? snapshot,
                classification: previousClassification ?? classification,
                recordId: previousRecordId,
                isIgnored: _isSelfExcluded(previousSnapshot ?? snapshot),
              ),
            ],
          ) ||
          wroteLog;

      final frozenSnapshot = state.displaySnapshot ?? state.currentSnapshot;
      final frozenClassification =
          state.displayClassification ?? state.currentClassification;
      final frozenSessionStart =
          state.displaySessionStart ?? state.sessionStart;
      final frozenTelemetry = state.displayTelemetry ??
          state.currentTelemetry ??
          _activeTelemetry;

      wroteLog =
          await _finishCurrentRecord(endedAt: snapshot.timestamp) || wroteLog;

      _telemetryBaseline = telemetry;
      _activeTelemetry = InputTelemetry.empty(snapshot.timestamp);

      state = state.copyWith(
        currentSnapshot: snapshot,
        currentClassification: classification,
        sessionStart: null,
        activeRecordId: null,
        currentTelemetry: InputTelemetry.empty(snapshot.timestamp),
        displaySnapshot: frozenSnapshot,
        displayClassification: frozenClassification,
        displaySessionStart: frozenSessionStart,
        displayTelemetry: frozenTelemetry,
        isViewingExcludedApp: true,
        lastSampleAt: snapshot.timestamp,
        lastError: rawInputError,
      );

      wroteLog = await _appendLog(
            ActivityLogEntry.fromTelemetry(
              timestamp: snapshot.timestamp,
              type: ActivityLogEntryType.sample,
              isIgnored: true,
              isFullscreen: snapshot.isFullscreen,
              processName: snapshot.processName,
              className: snapshot.className,
              windowTitle: snapshot.windowTitle,
              category: classification.category,
              label: classification.label,
              recordId: null,
              durationMinutes: null,
              telemetry: deltaTelemetry,
              note: 'foreground_self_excluded',
            ),
          ) ||
          wroteLog;

      if (wroteLog) {
        _notifyLogChanged();
      }
      return;
    }

    if (contextChanged) {
      final hadPreviousContext =
          previousSnapshot != null || previousRecordId != null;
      if (hadPreviousContext) {
        wroteLog = await _persistInputEvents(
              events: inputEvents,
              bindings: <InputEventContextBinding>[
                _buildInputBinding(
                  snapshot: previousSnapshot,
                  classification: previousClassification,
                  recordId: previousRecordId,
                ),
              ],
            ) ||
            wroteLog;
      }

      wroteLog =
          await _finishCurrentRecord(endedAt: snapshot.timestamp) || wroteLog;
      _telemetryBaseline = telemetry;
      _activeTelemetry = InputTelemetry.empty(snapshot.timestamp);
      wroteLog =
          await _startNewRecord(snapshot, classification) || wroteLog;

      if (!hadPreviousContext) {
        wroteLog = await _persistInputEvents(
              events: inputEvents,
              bindings: <InputEventContextBinding>[
                _buildInputBinding(
                  snapshot: snapshot,
                  classification: classification,
                  recordId: state.activeRecordId,
                ),
              ],
            ) ||
            wroteLog;
      }
    } else if (telemetry != null) {
      final delta = previousBaseline == null
          ? InputTelemetry.empty(snapshot.timestamp)
          : telemetry.subtract(previousBaseline);
      _activeTelemetry = _activeTelemetry.add(delta);
      _telemetryBaseline = telemetry;

      wroteLog = await _persistInputEvents(
            events: inputEvents,
            bindings: <InputEventContextBinding>[
              _buildInputBinding(
                snapshot: snapshot,
                classification: classification,
                recordId: state.activeRecordId,
              ),
            ],
          ) ||
          wroteLog;
    }

    final sessionStart = contextChanged
        ? snapshot.timestamp
        : (state.sessionStart ?? snapshot.timestamp);

    state = state.copyWith(
      currentSnapshot: snapshot,
      currentClassification: classification,
      sessionStart: sessionStart,
      currentTelemetry: _activeTelemetry,
      displaySnapshot: snapshot,
      displayClassification: classification,
      displaySessionStart: sessionStart,
      displayTelemetry: _activeTelemetry,
      isViewingExcludedApp: false,
      lastSampleAt: snapshot.timestamp,
      lastError: rawInputError,
    );

    wroteLog = await _persistActiveRecord(snapshot.timestamp) || wroteLog;
    wroteLog = await _appendLog(
          ActivityLogEntry.fromTelemetry(
            timestamp: snapshot.timestamp,
            type: ActivityLogEntryType.sample,
            isIgnored: false,
            isFullscreen: snapshot.isFullscreen,
            processName: snapshot.processName,
            className: snapshot.className,
            windowTitle: snapshot.windowTitle,
            category: classification.category,
            label: classification.label,
            recordId: state.activeRecordId,
            durationMinutes:
                snapshot.timestamp.difference(sessionStart).inMinutes,
            telemetry: deltaTelemetry,
            note: contextChanged ? 'context_changed' : null,
          ),
        ) ||
        wroteLog;

    if (wroteLog) {
      _notifyLogChanged();
    }
  }

  Future<bool> _startNewRecord(
    WindowSnapshot snapshot,
    ActivityClassification classification,
  ) async {
    try {
      final repo = ref.read(activityRecordRepositoryProvider);
      final database = ref.read(databaseProvider);
      final deviceId =
          await _deviceIdentityService.getOrCreateDeviceId(database);
      final id = await repo.startRecord(
        startTime: snapshot.timestamp,
        processName: snapshot.processName,
        windowTitle: snapshot.windowTitle,
        category: classification.category,
        deviceId: deviceId,
        platform: _deviceIdentityService.currentPlatform,
        isAuto: true,
        source: 'windows_auto',
      );
      state = state.copyWith(activeRecordId: id);
      return _appendLog(
        ActivityLogEntry.fromTelemetry(
          timestamp: snapshot.timestamp,
          type: ActivityLogEntryType.sessionOpen,
          isIgnored: false,
          isFullscreen: snapshot.isFullscreen,
          processName: snapshot.processName,
          className: snapshot.className,
          windowTitle: snapshot.windowTitle,
          category: classification.category,
          label: classification.label,
          recordId: id,
          durationMinutes: 0,
          telemetry: _activeTelemetry,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _finishCurrentRecord({
    DateTime? endedAt,
  }) async {
    final recordId = state.activeRecordId;
    final currentSnapshot = state.currentSnapshot;
    final currentClassification = state.currentClassification;
    final finishTime = endedAt ?? DateTime.now();

    if (recordId == null || currentSnapshot == null) {
      _telemetryBaseline = null;
      _activeTelemetry = InputTelemetry.empty(finishTime);
      state = state.copyWith(
        activeRecordId: null,
        sessionStart: null,
        currentTelemetry: InputTelemetry.empty(finishTime),
      );
      return false;
    }

    final sessionStart = state.sessionStart ?? finishTime;
    final durationMinutes =
        finishTime.difference(sessionStart).inMinutes.clamp(0, 1 << 31).toInt();

    var wroteLog = false;

    try {
      final repo = ref.read(activityRecordRepositoryProvider);
      await repo.endRecord(
        recordId,
        finishTime,
        telemetry: _activeTelemetry,
      );
      wroteLog = await _appendLog(
        ActivityLogEntry.fromTelemetry(
          timestamp: finishTime,
          type: ActivityLogEntryType.sessionClose,
          isIgnored: false,
          isFullscreen: currentSnapshot.isFullscreen,
          processName: currentSnapshot.processName,
          className: currentSnapshot.className,
          windowTitle: currentSnapshot.windowTitle,
          category: currentClassification?.category,
          label: currentClassification?.label,
          recordId: recordId,
          durationMinutes: durationMinutes,
          telemetry: _activeTelemetry,
        ),
      );
    } catch (_) {
      // 持久化失败时保持追踪服务继续工作
    } finally {
      state = state.copyWith(
        activeRecordId: null,
        sessionStart: null,
        currentTelemetry: InputTelemetry.empty(finishTime),
      );
      _telemetryBaseline = null;
      _activeTelemetry = InputTelemetry.empty(finishTime);
    }

    return wroteLog;
  }

  Future<bool> _persistActiveRecord(DateTime sampledAt) async {
    final recordId = state.activeRecordId;
    if (recordId == null) {
      return false;
    }

    final sessionStart = state.sessionStart ?? sampledAt;
    final durationMinutes =
        sampledAt.difference(sessionStart).inMinutes.clamp(0, 1 << 31).toInt();

    try {
      final repo = ref.read(activityRecordRepositoryProvider);
      await repo.updateTelemetry(
        recordId,
        telemetry: _activeTelemetry,
        durationMinutes: durationMinutes,
      );
      return _appendLog(
        ActivityLogEntry.fromTelemetry(
          timestamp: sampledAt,
          type: ActivityLogEntryType.sessionUpdate,
          isIgnored: false,
          isFullscreen: state.currentSnapshot?.isFullscreen ?? false,
          processName: state.currentSnapshot?.processName,
          className: state.currentSnapshot?.className,
          windowTitle: state.currentSnapshot?.windowTitle,
          category: state.currentClassification?.category,
          label: state.currentClassification?.label,
          recordId: recordId,
          durationMinutes: durationMinutes,
          telemetry: _activeTelemetry,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _appendLog(ActivityLogEntry entry) async {
    try {
      final service = ref.read(activityLogServiceProvider);
      await service.append(entry);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _persistInputEvents({
    required List<RawInputEvent> events,
    required List<InputEventContextBinding> bindings,
  }) async {
    if (events.isEmpty) {
      return false;
    }

    try {
      final service = ref.read(inputActivityEventServiceProvider);
      await service.appendEvents(
        events: events,
        bindings: bindings,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  InputEventContextBinding _buildInputBinding({
    required WindowSnapshot? snapshot,
    required ActivityClassification? classification,
    required int? recordId,
    bool isIgnored = false,
  }) {
    return InputEventContextBinding(
      recordId: recordId,
      processName: snapshot?.processName,
      className: snapshot?.className,
      windowTitle: snapshot?.windowTitle,
      category: classification?.category,
      activityLabel: classification?.label,
      isIgnored: isIgnored,
    );
  }

  void _notifyLogChanged() {
    final controller = ref.read(activityLogRefreshTickProvider.notifier);
    controller.state = controller.state + 1;
  }

  bool _isSelfExcluded(WindowSnapshot snapshot) {
    return isTrackerSelfExcludedWindow(
      processName: snapshot.processName,
      windowTitle: snapshot.windowTitle,
    );
  }

  ActivityClassifier get classifier => _classifier;
  InputTelemetry? get currentTelemetry => state.currentTelemetry;
}
