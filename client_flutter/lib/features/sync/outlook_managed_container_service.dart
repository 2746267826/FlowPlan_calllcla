import '../../core/database/app_database.dart';
import 'ms_graph_service.dart';
import 'outlook_auth_service.dart';
import 'outlook_sync_bindings_repository.dart';
import 'outlook_sync_policy.dart';
import 'outlook_task_list_binding.dart';

class OutlookManagedContainerService {
  OutlookManagedContainerService({
    required this.config,
    required this.bindingsRepository,
    MsGraphServiceFactory? graphServiceFactory,
  }) : _graphServiceFactory =
            graphServiceFactory ?? _defaultGraphServiceFactory;

  final OutlookConfig config;
  final OutlookSyncBindingsRepository bindingsRepository;
  final MsGraphServiceFactory _graphServiceFactory;

  static MsGraphService _defaultGraphServiceFactory(
    OutlookConfig config, {
    required OutlookSyncMode syncMode,
  }) {
    return MsGraphService(config, syncMode: syncMode);
  }

  Future<OutlookTaskListBinding> ensureTaskListMirrorBinding(
    TaskList taskList,
  ) async {
    final existing = await bindingsRepository.getTaskListBinding(taskList.id);
    if (existing != null) {
      return existing;
    }

    final syncMode = await OutlookAuthService.loadSyncMode();
    if (syncMode != OutlookSyncMode.bidirectional) {
      throw StateError(
        '\u5f53\u524d Outlook \u540c\u6b65\u6a21\u5f0f\u4e0d\u662f\u53cc\u5411\u540c\u6b65\uff0c\u4e0d\u80fd\u4e3a\u4efb\u52a1\u672c\u521b\u5efa Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\u3002',
      );
    }

    final hasPermission = await OutlookAuthService.isAuthorizedForMode(
      OutlookSyncMode.bidirectional,
    );
    if (!hasPermission) {
      throw StateError(
        '\u5f53\u524d Outlook \u6388\u6743\u4ecd\u662f\u53ea\u8bfb\uff0c\u8bf7\u5148\u5728 Outlook \u540c\u6b65\u8bbe\u7f6e\u4e2d\u5207\u6362\u5230\u53cc\u5411\u540c\u6b65\u5e76\u91cd\u65b0\u5b8c\u6210\u8ba4\u8bc1\u3002',
      );
    }

    final graphService = _graphServiceFactory(
      config,
      syncMode: OutlookSyncMode.bidirectional,
    );
    final remoteCalendarName = OutlookSyncPolicy.buildManagedCalendarName(
      kind: OutlookManagedCalendarKind.taskMirrorBook,
      containerName: taskList.name,
    );
    final existingRemoteCalendars = await graphService.getCalendars();
    Map<String, dynamic>? managedCalendar;
    for (final calendar in existingRemoteCalendars) {
      final name = MsGraphService.calendarNameOf(calendar);
      if (name == remoteCalendarName) {
        managedCalendar = calendar;
        break;
      }
    }

    managedCalendar ??= await graphService.createCalendar(
      name: remoteCalendarName,
      isFlowPlanV2ManagedContainer: true,
    );

    final remoteCalendarId = MsGraphService.calendarIdOf(managedCalendar);
    if (remoteCalendarId.isEmpty) {
      throw StateError(
        'Outlook \u5df2\u8fd4\u56de\u7ed3\u679c\uff0c\u4f46\u7f3a\u5c11\u53ef\u7528\u7684\u65e5\u5386\u5bb9\u5668 ID\u3002',
      );
    }

    final binding = OutlookTaskListBinding(
      localTaskListId: taskList.id,
      remoteCalendarId: remoteCalendarId,
      remoteCalendarName: remoteCalendarName,
      linkedAt: DateTime.now(),
    );
    await bindingsRepository.saveTaskListBinding(binding);
    return binding;
  }

  Future<void> unbindTaskListMirror(int taskListId) {
    return bindingsRepository.removeTaskListBinding(taskListId);
  }
}
