// 所有核心 Provider：手写形式（不依赖 riverpod_generator，避免 codegen 问题）
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/bootstrap/client_bootstrap_service.dart';
import '../../core/connection/server_connection_state.dart';
import '../../core/connection/server_connection_service.dart';
import '../../core/database/app_database.dart';
import '../../core/offline_queue/legacy_offline_mutation_cleanup_service.dart';
import '../../core/offline_queue/offline_mutation_store.dart';
import '../../core/offline_queue/offline_mutation_runner.dart';
import '../../core/online/online_primary_policy.dart';
import '../../core/platform/device_identity_service.dart';
import '../../core/server_api/api_client.dart';
import '../../core/server_api/analytics_api.dart';
import '../../core/server_api/ai_api.dart';
import '../../core/server_api/auth_token_store.dart';
import '../../core/server_api/client_api.dart';
import '../../core/server_api/file_cloud_api.dart';
import '../../core/server_api/file_context_api.dart';
import '../../core/server_api/models_api.dart';
import '../../core/server_api/remote_settings_repository.dart';
import '../../core/server_api/reports_api.dart';
import '../../core/server_api/request_context.dart';
import '../../core/server_api/scheduler_api.dart';
import '../../core/server_api/server_config_store.dart';
import '../../core/server_api/tracking_ingest_api.dart';
import '../../core/server_api/activity_understanding_api.dart';
import '../../core/server_first/activity_understanding_server_first_store.dart';
import '../../core/server_first/cloud_drive_server_first_store.dart';
import '../../core/server_first/mutation_coordinator.dart';
import '../../core/server_first/scheduler_server_first_store.dart';
import '../../core/server_first/server_first_repository.dart';
import '../../core/server_first/task_event_server_first_store.dart';
import '../../core/server_first/tracking_server_first_store.dart';
import '../../core/sync/server_sync_change_applier.dart';
import '../../core/sync/sync_conflict_store.dart';
import '../../core/sync/sync_cursor_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_object_state_store.dart';
import '../../core/sync/sync_write_recorder.dart';
import '../../shared/providers/database_provider.dart';
import '../../features/task/data/task_repository.dart';
import '../../features/calendar/data/event_repository.dart';
import '../../features/calendar/data/calendar_books_repository.dart';
import '../../features/tracker/data/tracker_repository.dart';
import '../../features/tracker/data/activity_record_repository.dart';
import '../../features/tracker/data/activity_fusion_repository.dart';
import '../../features/tracker/models/activity_log_archive_day.dart';
import '../../features/tracker/models/activity_log_entry.dart';
import '../../features/tracker/models/activity_insights.dart';
import '../../features/tracker/models/input_event_query.dart';
import '../../features/tracker/models/input_heatmap_summary.dart';
import '../../features/tracker/models/tracked_input_event.dart';
import '../../features/tracker/models/work_session.dart';
import '../../features/tracker/services/activity_fusion_service.dart';
import '../../features/tracker/services/activity_log_service.dart';
import '../../features/tracker/services/input_activity_event_service.dart';
import '../../features/tracker/services/tracking_upload_service.dart';
import '../../features/actual/data/actual_activity_log_repository.dart';
import '../../features/actual/services/blocking_event_actual_candidate_service.dart';
import '../../features/audit/data_operation_log_repository.dart';
import '../../features/files/data/file_context_repository.dart';
import '../../features/files/services/file_context_interaction_service.dart';
import '../../features/files/services/file_transfer_service.dart';
import '../../features/reports/data/report_repository.dart';
import '../../features/reports/services/report_generation_service.dart';
import '../../features/reports/services/report_push_service.dart';
import '../../features/scheduler/task_schedule_segment_repository.dart';
import '../../features/sync/outlook_sync_bindings_repository.dart';
import '../../features/sync/outlook_task_mirror_repository.dart';
import '../../features/sync/outlook_task_list_binding.dart';
import '../../features/sync/outlook_task_mirror_binding.dart';
import '../../features/sync/outlook_task_mirror_snapshot.dart';

part 'tracker_providers.dart';

// 鈹€鈹€ Repository Providers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return TaskRepository(db, operationLogs);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
]);

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return EventRepository(db, operationLogs);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
]);

final calendarBooksRepositoryProvider =
    Provider<CalendarBooksRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return CalendarBooksRepository(db, operationLogs);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
]);

final actualActivityLogRepositoryProvider =
    Provider<ActualActivityLogRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  final repository = ActualActivityLogRepository(db, operationLogs);
  ref.onDispose(repository.dispose);
  return repository;
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
]);

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return ReportRepository(db, operationLogs);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
]);

final reportGenerationServiceProvider =
    Provider<ReportGenerationService>((ref) {
  return ReportGenerationService(
    reportRepository: ref.watch(reportRepositoryProvider),
    eventRepository: ref.watch(eventRepositoryProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    segmentRepository: ref.watch(taskScheduleSegmentRepositoryProvider),
    actualRepository: ref.watch(actualActivityLogRepositoryProvider),
    fusionRepository: ref.watch(activityFusionRepositoryProvider),
  );
}, dependencies: [
  reportRepositoryProvider,
  eventRepositoryProvider,
  taskRepositoryProvider,
  taskScheduleSegmentRepositoryProvider,
  actualActivityLogRepositoryProvider,
  activityFusionRepositoryProvider,
]);

final reportPushServiceProvider = Provider<ReportPushService>((ref) {
  return ReportPushService(
    database: ref.watch(databaseProvider),
    reportRepository: ref.watch(reportRepositoryProvider),
  );
}, dependencies: [
  databaseProvider,
  reportRepositoryProvider,
]);

final fileContextRepositoryProvider = Provider<FileContextRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return FileContextRepository(
    db,
    operationLogs,
    null,
    () => ref.read(fileContextApiProvider.future),
  );
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
  fileContextApiProvider,
]);

final fileContextInteractionServiceProvider =
    Provider<FileContextInteractionService>((ref) {
  return FileContextInteractionService(
    repository: ref.watch(fileContextRepositoryProvider),
    apiLoader: () => ref.read(fileContextApiProvider.future),
  );
}, dependencies: [fileContextRepositoryProvider, fileContextApiProvider]);

final fileTransferServiceProvider =
    ChangeNotifierProvider<FileTransferService>((ref) {
  final service = FileTransferService(
    apiLoader: () => ref.read(fileCloudApiProvider.future),
    policyLoader: () async => ref.read(onlinePrimaryPolicyProvider),
    operationLogs: ref.watch(dataOperationLogRepositoryProvider),
  );
  service.load();
  return service;
}, dependencies: [
  fileCloudApiProvider,
  onlinePrimaryPolicyProvider,
  dataOperationLogRepositoryProvider,
]);

final dataOperationLogRepositoryProvider =
    Provider<DataOperationLogRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final syncRecorder = ref.watch(syncWriteRecorderProvider);
  return DataOperationLogRepository(db, syncRecorder);
}, dependencies: [databaseProvider, syncWriteRecorderProvider]);

final syncObjectStateStoreProvider = Provider<SyncObjectStateStore>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncObjectStateStore(db);
}, dependencies: [databaseProvider]);

final offlineMutationStoreProvider = Provider<OfflineMutationStore>((ref) {
  final db = ref.watch(databaseProvider);
  return OfflineMutationStore(db);
}, dependencies: [databaseProvider]);

final syncConflictStoreProvider = Provider<SyncConflictStore>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncConflictStore(db);
}, dependencies: [databaseProvider]);

final syncWriteRecorderProvider = Provider<SyncWriteRecorder>((ref) {
  final mutationStore = ref.watch(offlineMutationStoreProvider);
  final stateStore = ref.watch(syncObjectStateStoreProvider);
  return SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: stateStore,
  );
}, dependencies: [
  offlineMutationStoreProvider,
  syncObjectStateStoreProvider,
]);

final authTokenStoreProvider = Provider<AuthTokenStore>((ref) {
  final db = ref.watch(databaseProvider);
  return AuthTokenStore(db);
}, dependencies: [databaseProvider]);

final serverConfigStoreProvider = Provider<ServerConfigStore>((ref) {
  final db = ref.watch(databaseProvider);
  return ServerConfigStore(db);
}, dependencies: [databaseProvider]);

final syncCursorStoreProvider = Provider<SyncCursorStore>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncCursorStore(db);
}, dependencies: [databaseProvider]);

final serverRequestContextProvider =
    FutureProvider<RequestContext>((ref) async {
  final db = ref.watch(databaseProvider);
  final identity = DeviceIdentityService();
  final deviceId = await identity.getOrCreateDeviceId(db);
  return RequestContext(
    deviceId: deviceId,
    platform: identity.currentPlatform,
  );
}, dependencies: [databaseProvider]);

final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  final config = ref.watch(serverConfigStoreProvider);
  final tokenStore = ref.watch(authTokenStoreProvider);
  final context = await ref.watch(serverRequestContextProvider.future);
  return ApiClient(
    baseUri: await config.readBaseUri(),
    tokenStore: tokenStore,
    defaultHeaders: context.toHeaders(),
  );
}, dependencies: [
  serverConfigStoreProvider,
  authTokenStoreProvider,
  serverRequestContextProvider,
]);

final analyticsApiProvider = FutureProvider<AnalyticsApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return AnalyticsApi(apiClient);
}, dependencies: [apiClientProvider]);

final aiApiProvider = FutureProvider<AiApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return AiApi(apiClient);
}, dependencies: [apiClientProvider]);

final fileCloudApiProvider = FutureProvider<FileCloudApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return FileCloudApi(apiClient);
}, dependencies: [apiClientProvider]);

final fileContextApiProvider = FutureProvider<FileContextApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return FileContextApi(apiClient);
}, dependencies: [apiClientProvider]);

final trackingIngestApiProvider =
    FutureProvider<TrackingIngestApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return TrackingIngestApi(apiClient);
}, dependencies: [apiClientProvider]);

final reportsApiProvider = FutureProvider<ReportsApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return ReportsApi(apiClient);
}, dependencies: [apiClientProvider]);

final schedulerApiProvider = FutureProvider<SchedulerApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return SchedulerApi(apiClient);
}, dependencies: [apiClientProvider]);

final activityUnderstandingApiProvider =
    FutureProvider<ActivityUnderstandingApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return ActivityUnderstandingApi(apiClient);
}, dependencies: [apiClientProvider]);

final modelsApiProvider = FutureProvider<ModelsApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return ModelsApi(apiClient);
}, dependencies: [apiClientProvider]);

final clientApiProvider = FutureProvider<ClientApi>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return ClientApi(apiClient);
}, dependencies: [apiClientProvider]);

final trackingUploadServiceProvider =
    FutureProvider<TrackingUploadService>((ref) async {
  final database = ref.watch(databaseProvider);
  final api = await ref.watch(trackingIngestApiProvider.future);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return TrackingUploadService(
    database: database,
    api: api,
    operationLogs: operationLogs,
  );
}, dependencies: [
  databaseProvider,
  trackingIngestApiProvider,
  dataOperationLogRepositoryProvider,
]);

final remoteSettingsRepositoryProvider =
    FutureProvider<RemoteSettingsRepository>((ref) async {
  final database = ref.watch(databaseProvider);
  final clientApi = await ref.watch(clientApiProvider.future);
  return RemoteSettingsRepository(
    database: database,
    clientApi: clientApi,
  );
}, dependencies: [databaseProvider, clientApiProvider]);

final serverSyncChangeApplierProvider =
    Provider<ServerSyncChangeApplier>((ref) {
  final db = ref.watch(databaseProvider);
  final stateStore = ref.watch(syncObjectStateStoreProvider);
  return ServerSyncChangeApplier(db, stateStore);
}, dependencies: [databaseProvider, syncObjectStateStoreProvider]);

final serverSyncEngineProvider = FutureProvider<ServerSyncEngine>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  final mutationStore = ref.watch(offlineMutationStoreProvider);
  final stateStore = ref.watch(syncObjectStateStoreProvider);
  final conflictStore = ref.watch(syncConflictStoreProvider);
  final context = await ref.watch(serverRequestContextProvider.future);
  return ServerSyncEngine(
    apiClient: apiClient,
    cursorStore: ref.watch(syncCursorStoreProvider),
    offlineMutationRunner: OfflineMutationRunner(
      mutationStore,
      stateStore: stateStore,
      conflictStore: conflictStore,
      requestContext: context,
      clientBatchIdFactory: const Uuid().v4,
    ),
    changeApplier: ref.watch(serverSyncChangeApplierProvider),
  );
}, dependencies: [
  apiClientProvider,
  offlineMutationStoreProvider,
  syncObjectStateStoreProvider,
  syncConflictStoreProvider,
  serverRequestContextProvider,
  syncCursorStoreProvider,
  serverSyncChangeApplierProvider,
]);

final mutationCoordinatorProvider = Provider<MutationCoordinator>((ref) {
  return MutationCoordinator(
    mutationStore: ref.watch(offlineMutationStoreProvider),
    pushPending: () async {
      final engine = await ref.read(serverSyncEngineProvider.future);
      await engine.pushPending();
    },
  );
}, dependencies: [
  offlineMutationStoreProvider,
  serverSyncEngineProvider,
]);

final serverFirstRepositoryProvider =
    FutureProvider<ServerFirstRepository>((ref) async {
  final clientApi = await ref.watch(clientApiProvider.future);
  return ServerFirstRepository(
    clientApi: clientApi,
    mutationCoordinator: ref.watch(mutationCoordinatorProvider),
  );
}, dependencies: [
  clientApiProvider,
  mutationCoordinatorProvider,
]);

final taskEventServerFirstStoreProvider =
    FutureProvider<TaskEventServerFirstStore>((ref) async {
  final repository = await ref.watch(serverFirstRepositoryProvider.future);
  return TaskEventServerFirstStore(
    repository: repository,
    mutationCoordinator: ref.watch(mutationCoordinatorProvider),
    stateStore: ref.watch(syncObjectStateStoreProvider),
    database: ref.watch(databaseProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    eventRepository: ref.watch(eventRepositoryProvider),
  );
}, dependencies: [
  serverFirstRepositoryProvider,
  mutationCoordinatorProvider,
  syncObjectStateStoreProvider,
  databaseProvider,
  taskRepositoryProvider,
  eventRepositoryProvider,
]);

final cloudDriveServerFirstStoreProvider =
    FutureProvider<CloudDriveServerFirstStore>((ref) async {
  final api = await ref.watch(fileContextApiProvider.future);
  return CloudDriveServerFirstStore(api);
}, dependencies: [fileContextApiProvider]);

final schedulerServerFirstStoreProvider =
    FutureProvider<SchedulerServerFirstStore>((ref) async {
  final api = await ref.watch(schedulerApiProvider.future);
  return SchedulerServerFirstStore(api);
}, dependencies: [schedulerApiProvider]);

final activityUnderstandingServerFirstStoreProvider =
    FutureProvider<ActivityUnderstandingServerFirstStore>((ref) async {
  final api = await ref.watch(activityUnderstandingApiProvider.future);
  return ActivityUnderstandingServerFirstStore(api);
}, dependencies: [activityUnderstandingApiProvider]);

final trackingServerFirstStoreProvider =
    FutureProvider<TrackingServerFirstStore>((ref) async {
  final analytics = await ref.watch(analyticsApiProvider.future);
  final tracking = await ref.watch(trackingIngestApiProvider.future);
  final activityUnderstanding =
      await ref.watch(activityUnderstandingApiProvider.future);
  return TrackingServerFirstStore(
    analytics: analytics,
    tracking: tracking,
    activityUnderstanding: activityUnderstanding,
  );
}, dependencies: [
  analyticsApiProvider,
  trackingIngestApiProvider,
  activityUnderstandingApiProvider,
]);

final clientBootstrapServiceProvider =
    FutureProvider<ClientBootstrapService>((ref) async {
  final database = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  final clientApi = await ref.watch(clientApiProvider.future);
  final remoteSettings =
      await ref.watch(remoteSettingsRepositoryProvider.future);
  return ClientBootstrapService(
    database: database,
    clientApi: clientApi,
    remoteSettingsRepository: remoteSettings,
    syncEngineLoader: () => ref.read(serverSyncEngineProvider.future),
    operationLogs: operationLogs,
    trackingUploadRunner: () async {
      final service = await ref.read(trackingUploadServiceProvider.future);
      return service.uploadPending().then((result) => result.toJson());
    },
  );
}, dependencies: [
  databaseProvider,
  clientApiProvider,
  remoteSettingsRepositoryProvider,
  serverSyncEngineProvider,
  dataOperationLogRepositoryProvider,
  trackingUploadServiceProvider,
]);

final serverConnectionServiceProvider =
    FutureProvider<ServerConnectionService>((ref) async {
  final database = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  final serverConfig = ref.watch(serverConfigStoreProvider);
  final context = await ref.watch(serverRequestContextProvider.future);
  final clientApi = await ref.watch(clientApiProvider.future);
  final bootstrap = await ref.watch(clientBootstrapServiceProvider.future);
  final service = ServerConnectionService(
    database: database,
    clientApi: clientApi,
    bootstrapService: bootstrap,
    serverConfigStore: serverConfig,
    operationLogs: operationLogs,
    deviceId: context.deviceId,
    platform: context.platform,
  );
  ref.onDispose(service.dispose);
  return service;
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
  serverConfigStoreProvider,
  serverRequestContextProvider,
  clientApiProvider,
  clientBootstrapServiceProvider,
]);

final serverConnectionStateProvider =
    StreamProvider<ServerConnectionState>((ref) async* {
  final service = await ref.watch(serverConnectionServiceProvider.future);
  yield service.state;
  final controller = StreamController<ServerConnectionState>();
  void listener() {
    controller.add(service.state);
  }

  service.addListener(listener);
  ref.onDispose(() {
    service.removeListener(listener);
    unawaited(controller.close());
  });
  yield* controller.stream;
}, dependencies: [serverConnectionServiceProvider]);

final onlinePrimaryPolicyProvider = Provider<OnlinePrimaryPolicy>((ref) {
  final state = ref.watch(serverConnectionStateProvider).valueOrNull ??
      const ServerConnectionState(level: ServerConnectionLevel.localCacheOnly);
  return OnlinePrimaryPolicy.fromConnectionState(state);
}, dependencies: [serverConnectionStateProvider]);

final legacyOfflineMutationCleanupServiceProvider =
    Provider<LegacyOfflineMutationCleanupService>((ref) {
  return LegacyOfflineMutationCleanupService(ref.watch(databaseProvider));
}, dependencies: [databaseProvider]);

final taskScheduleSegmentRepositoryProvider =
    Provider<TaskScheduleSegmentRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  final syncRecorder = ref.watch(syncWriteRecorderProvider);
  return TaskScheduleSegmentRepository(db, operationLogs, syncRecorder);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
  syncWriteRecorderProvider,
]);

final outlookSyncBindingsRepositoryProvider =
    Provider<OutlookSyncBindingsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return OutlookSyncBindingsRepository(db);
}, dependencies: [databaseProvider]);

final outlookTaskMirrorRepositoryProvider =
    Provider<OutlookTaskMirrorRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return OutlookTaskMirrorRepository(db);
}, dependencies: [databaseProvider]);

final outlookBindingRefreshTickProvider = StateProvider<int>((ref) => 0);

final outlookTaskListBindingsProvider =
    FutureProvider<Map<int, OutlookTaskListBinding>>((ref) {
  ref.watch(outlookBindingRefreshTickProvider);
  final repo = ref.watch(outlookSyncBindingsRepositoryProvider);
  return repo.loadTaskListBindings();
});

class OutlookTaskMirrorDiagnostics {
  const OutlookTaskMirrorDiagnostics({
    required this.totalBindings,
    required this.activeBindings,
    required this.pendingCleanup,
    required this.missingTasks,
    required this.unboundTaskLists,
    required this.movedTargets,
    required this.localChangedSinceLastMirror,
  });

  const OutlookTaskMirrorDiagnostics.empty()
      : totalBindings = 0,
        activeBindings = 0,
        pendingCleanup = 0,
        missingTasks = 0,
        unboundTaskLists = 0,
        movedTargets = 0,
        localChangedSinceLastMirror = 0;

  final int totalBindings;
  final int activeBindings;
  final int pendingCleanup;
  final int missingTasks;
  final int unboundTaskLists;
  final int movedTargets;
  final int localChangedSinceLastMirror;

  bool get hasPendingCleanup => pendingCleanup > 0;
}

final outlookTaskMirrorDiagnosticsProvider =
    FutureProvider<OutlookTaskMirrorDiagnostics>((ref) async {
  ref.watch(outlookBindingRefreshTickProvider);
  final mirrorRepo = ref.watch(outlookTaskMirrorRepositoryProvider);
  final taskListBindingsRepo = ref.watch(outlookSyncBindingsRepositoryProvider);
  final taskRepo = ref.watch(taskRepositoryProvider);

  final mirrorBindings = await mirrorRepo.loadTaskMirrorBindings();
  if (mirrorBindings.isEmpty) {
    return const OutlookTaskMirrorDiagnostics.empty();
  }

  final taskListBindings = await taskListBindingsRepo.loadTaskListBindings();
  final tasks = await taskRepo.getByIds(mirrorBindings.keys);
  final taskById = <int, TaskItem>{
    for (final task in tasks) task.id: task,
  };

  var activeBindings = 0;
  var pendingCleanup = 0;
  var missingTasks = 0;
  var unboundTaskLists = 0;
  var movedTargets = 0;
  var localChangedSinceLastMirror = 0;

  for (final entry in mirrorBindings.entries) {
    final task = taskById[entry.key];
    if (task == null) {
      missingTasks++;
      pendingCleanup++;
      continue;
    }

    final taskListId = task.taskListId;
    if (taskListId == null) {
      missingTasks++;
      pendingCleanup++;
      continue;
    }

    final taskListBinding = taskListBindings[taskListId];
    if (taskListBinding == null) {
      unboundTaskLists++;
      pendingCleanup++;
      continue;
    }

    if (taskListBinding.remoteCalendarId != entry.value.remoteCalendarId) {
      movedTargets++;
      pendingCleanup++;
      continue;
    }

    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: _previousSnapshotTaskListName(
            entry.value.localSnapshotJson,
          ) ??
          taskListBinding.remoteCalendarName,
    );
    final previousHash = entry.value.localSnapshotHash?.trim();
    if (previousHash != null &&
        previousHash.isNotEmpty &&
        previousHash != snapshot.fingerprint) {
      localChangedSinceLastMirror++;
    }

    activeBindings++;
  }

  return OutlookTaskMirrorDiagnostics(
    totalBindings: mirrorBindings.length,
    activeBindings: activeBindings,
    pendingCleanup: pendingCleanup,
    missingTasks: missingTasks,
    unboundTaskLists: unboundTaskLists,
    movedTargets: movedTargets,
    localChangedSinceLastMirror: localChangedSinceLastMirror,
  );
});

String? _previousSnapshotTaskListName(String? rawSnapshotJson) {
  if (rawSnapshotJson == null || rawSnapshotJson.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(rawSnapshotJson) as Map<String, dynamic>;
    final name = (decoded['task_list_name'] as String?)?.trim();
    return name == null || name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}

class OutlookFieldConflictSummary {
  const OutlookFieldConflictSummary({
    required this.taskId,
    required this.taskSummary,
    required this.taskListName,
    required this.remoteCalendarName,
    required this.conflictState,
    required this.changedFields,
    required this.detail,
    required this.canPushLocal,
    required this.canPullRemote,
    required this.canRecreateRemote,
    required this.canDetachMirror,
  });

  final int taskId;
  final String taskSummary;
  final String taskListName;
  final String remoteCalendarName;
  final OutlookTaskMirrorConflictState conflictState;
  final List<String> changedFields;
  final String detail;
  final bool canPushLocal;
  final bool canPullRemote;
  final bool canRecreateRemote;
  final bool canDetachMirror;
}

final outlookFieldConflictSummariesProvider =
    FutureProvider<List<OutlookFieldConflictSummary>>((ref) async {
  ref.watch(outlookBindingRefreshTickProvider);
  final mirrorRepo = ref.watch(outlookTaskMirrorRepositoryProvider);
  final taskListBindingsRepo = ref.watch(outlookSyncBindingsRepositoryProvider);
  final taskRepo = ref.watch(taskRepositoryProvider);
  final calendarBooksRepo = ref.watch(calendarBooksRepositoryProvider);

  final mirrorBindings = await mirrorRepo.loadTaskMirrorBindings();
  if (mirrorBindings.isEmpty) {
    return const <OutlookFieldConflictSummary>[];
  }

  final taskListBindings = await taskListBindingsRepo.loadTaskListBindings();
  final tasks = await taskRepo.getByIds(mirrorBindings.keys);
  final taskLists = await calendarBooksRepo.getAllTaskLists();
  final taskById = <int, TaskItem>{
    for (final task in tasks) task.id: task,
  };
  final taskListById = <int, TaskList>{
    for (final taskList in taskLists) taskList.id: taskList,
  };

  final results = <OutlookFieldConflictSummary>[];
  for (final entry in mirrorBindings.entries) {
    final binding = entry.value;
    final task = taskById[entry.key];
    if (task == null) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: entry.key,
          taskSummary: '任务 #${entry.key}',
          taskListName:
              _previousSnapshotTaskListName(binding.localSnapshotJson) ?? '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
          changedFields: const <String>['本地任务已不存在'],
          detail: '本地任务已经不存在，但仍保留了 Outlook 镜像绑定。建议先清理镜像索引，或导出诊断报告后再处理。',
          canPushLocal: false,
          canPullRemote: false,
          canRecreateRemote: false,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    if (task.taskListId == null) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: task.id,
          taskSummary: task.summary,
          taskListName:
              _previousSnapshotTaskListName(binding.localSnapshotJson) ?? '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.writeFailed,
          changedFields: const <String>['缺少任务本归属'],
          detail: '该任务已经失去任务本归属，当前无法继续安全同步，请先检查容器归属关系。',
          canPushLocal: false,
          canPullRemote: false,
          canRecreateRemote: false,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    final taskListBinding = taskListBindings[task.taskListId!];
    if (taskListBinding == null) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: task.id,
          taskSummary: task.summary,
          taskListName: taskListById[task.taskListId!]?.name ??
              _previousSnapshotTaskListName(binding.localSnapshotJson) ??
              '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.writeFailed,
          changedFields: const <String>['任务本已解除绑定'],
          detail: '该任务本已经解除 Outlook 镜像绑定，当前任务无法继续写回远端。',
          canPushLocal: false,
          canPullRemote: false,
          canRecreateRemote: false,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    if (taskListBinding.remoteCalendarId != binding.remoteCalendarId) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: task.id,
          taskSummary: task.summary,
          taskListName: taskListById[task.taskListId!]?.name ??
              _previousSnapshotTaskListName(binding.localSnapshotJson) ??
              '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.remoteChanged,
          changedFields: const <String>['镜像目标已变更'],
          detail: '任务本绑定的 Outlook 容器已经变化，旧镜像需要人工确认是重建还是解除绑定。',
          canPushLocal: true,
          canPullRemote: false,
          canRecreateRemote: true,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    final taskListName = taskListById[task.taskListId!]?.name ??
        _previousSnapshotTaskListName(binding.localSnapshotJson) ??
        taskListBinding.remoteCalendarName;
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: taskListName,
    );
    final previousHash = binding.localSnapshotHash?.trim();
    final localChanged = previousHash != null &&
        previousHash.isNotEmpty &&
        previousHash != snapshot.fingerprint;

    final conflictState =
        binding.conflictState == OutlookTaskMirrorConflictState.none
            ? (localChanged
                ? OutlookTaskMirrorConflictState.pendingLocalPush
                : OutlookTaskMirrorConflictState.none)
            : binding.conflictState;
    List<String> changedFields;
    String detail;
    var canPushLocal = false;
    var canPullRemote = false;
    var canRecreateRemote = false;
    var canDetachMirror = false;

    switch (conflictState) {
      case OutlookTaskMirrorConflictState.none:
        continue;
      case OutlookTaskMirrorConflictState.pendingLocalPush:
        changedFields = OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: binding.localSnapshotJson,
          current: snapshot,
        );
        detail = '本地任务字段已经变化，等待用户确认是否按 FlowPlanV2 当前内容写回 Outlook 镜像。';
        canPushLocal = true;
        break;
      case OutlookTaskMirrorConflictState.remoteDeleted:
        changedFields = const <String>['远端镜像已删除'];
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : '远端镜像已经不存在。可以重建镜像，也可以仅解除镜像绑定并保留本地任务。';
        canPushLocal = true;
        canRecreateRemote = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.remoteChanged:
        changedFields = OutlookTaskMirrorSnapshot.changedFieldLabelsBetween(
          leftSnapshotJson: binding.localSnapshotJson,
          rightSnapshotJson: binding.remoteSnapshotJson,
        );
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : 'Outlook 镜像已被修改，请确认是用本地内容覆盖远端，还是把远端内容回填到 FlowPlanV2。';
        canPushLocal = true;
        canPullRemote = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.divergent:
        changedFields = OutlookTaskMirrorSnapshot.changedFieldLabelsBetween(
          leftSnapshotJson: binding.localSnapshotJson,
          rightSnapshotJson: binding.remoteSnapshotJson,
        );
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : 'FlowPlanV2 与 Outlook 两侧都已经修改，请人工选择以哪一侧为准。';
        canPushLocal = true;
        canPullRemote = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.writeFailed:
        changedFields = localChanged
            ? OutlookTaskMirrorSnapshot.changedFieldLabels(
                previousSnapshotJson: binding.localSnapshotJson,
                current: snapshot,
              )
            : const <String>['远端写回失败'];
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : '最近一次远端写回失败，请稍后重试，或导出诊断报告进一步检查。';
        canPushLocal = true;
        canDetachMirror = true;
        break;
    }

    results.add(
      OutlookFieldConflictSummary(
        taskId: task.id,
        taskSummary: task.summary,
        taskListName: taskListName,
        remoteCalendarName: taskListBinding.remoteCalendarName,
        conflictState: conflictState,
        changedFields: changedFields,
        detail: detail,
        canPushLocal: canPushLocal,
        canPullRemote: canPullRemote,
        canRecreateRemote: canRecreateRemote,
        canDetachMirror: canDetachMirror,
      ),
    );
  }

  results.sort((left, right) => left.taskSummary.compareTo(right.taskSummary));
  return results;
});

// 鈹€鈹€ 褰撳墠鏌ョ湅鏃ユ湡 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

class _SelectedDateNotifier extends StateNotifier<DateTime> {
  _SelectedDateNotifier()
      : super(DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        ));

  void setDate(DateTime date) =>
      state = DateTime(date.year, date.month, date.day);
  void goToToday() => setDate(DateTime.now());
  void goToPrevDay() => state = state.subtract(const Duration(days: 1));
  void goToNextDay() => state = state.add(const Duration(days: 1));
}

final selectedDateProvider =
    StateNotifierProvider<_SelectedDateNotifier, DateTime>(
  (ref) => _SelectedDateNotifier(),
);

// 鈹€鈹€ 褰撴棩浠诲姟娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final tasksForSelectedDateProvider = StreamProvider<List<TaskItem>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchForDate(date);
});

final taskScheduleSegmentsForSelectedDateProvider =
    StreamProvider<List<TaskScheduleSegmentWithTask>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskScheduleSegmentRepositoryProvider);
  return repo.watchForDate(date);
});

// 鈹€鈹€ 褰撴棩浜嬩欢娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final eventsForSelectedDateProvider =
    StreamProvider<List<CalendarEvent>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchVisibleForDate(date);
});

// 鈹€鈹€ 浜嬩欢鏃ュ巻鏈垪琛ㄦ祦 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final allEventCalendarsProvider = StreamProvider<List<EventCalendar>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchAllEventCalendars();
});

// 鈹€鈹€ 浠诲姟娓呭崟鍒楄〃娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final allTaskListsProvider = StreamProvider<List<TaskList>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchAllTaskLists();
});
final archivedTaskListsProvider = StreamProvider<List<TaskList>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchArchivedTaskLists();
});

// 鈹€鈹€ 鎵€鏈変换鍔℃祦 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final allTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAll();
});

final managementTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAllForManagement();
});

final managementEventsProvider = StreamProvider<List<CalendarEvent>>((ref) {
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchAllForManagement();
});
