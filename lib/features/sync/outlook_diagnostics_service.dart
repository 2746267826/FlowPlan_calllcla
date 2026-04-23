import 'dart:convert';

import '../../core/database/app_database.dart';
import '../calendar/data/calendar_books_repository.dart';
import '../task/data/task_repository.dart';
import 'outlook_auth_service.dart';
import 'outlook_sync_bindings_repository.dart';
import 'outlook_sync_policy.dart';
import 'outlook_task_list_binding.dart';
import 'outlook_task_mirror_binding.dart';
import 'outlook_task_mirror_repository.dart';
import 'outlook_task_mirror_snapshot.dart';
import 'sync_engine.dart';

class OutlookDiagnosticsService {
  const OutlookDiagnosticsService({
    required this.calendarBooksRepository,
    required this.taskRepository,
    required this.taskListBindingsRepository,
    required this.taskMirrorRepository,
  });

  final CalendarBooksRepository calendarBooksRepository;
  final TaskRepository taskRepository;
  final OutlookSyncBindingsRepository taskListBindingsRepository;
  final OutlookTaskMirrorRepository taskMirrorRepository;

  Future<String> buildMarkdownReport() async {
    final generatedAt = DateTime.now();
    final syncMode = await OutlookAuthService.loadSyncMode();
    final token = await OutlookAuthService.loadToken();
    final config = await OutlookAuthService.loadConfig();
    final lastReport = await SyncEngine.getLastSyncReport();
    final eventCalendars = await calendarBooksRepository.getAllEventCalendars();
    final taskLists = await calendarBooksRepository.getAllTaskLists();
    final taskListBindings =
        await taskListBindingsRepository.loadTaskListBindings();
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();
    final mirroredTasks = await taskRepository.getByIds(mirrorBindings.keys);
    final taskById = <int, TaskItem>{
      for (final task in mirroredTasks) task.id: task,
    };
    final taskListById = <int, TaskList>{
      for (final taskList in taskLists) taskList.id: taskList,
    };

    final outlookCalendars =
        eventCalendars.where((calendar) => calendar.source == 'outlook').toList();
    final managedCalendars = outlookCalendars
        .where((calendar) =>
            OutlookSyncPolicy.isFlowPlanManagedCalendarName(calendar.name))
        .toList();
    final mirrorDiagnostics = _buildMirrorDiagnostics(
      taskListBindings: taskListBindings,
      mirrorBindings: mirrorBindings,
      taskById: taskById,
      taskListById: taskListById,
    );

    final buffer = StringBuffer()
      ..writeln('# FlowPlan Outlook 同步诊断报告')
      ..writeln()
      ..writeln('- 生成时间：${_formatDateTime(generatedAt)}')
      ..writeln('- 同步模式：${syncMode.label}')
      ..writeln('- OAuth 配置：${config == null ? '未配置' : '已配置'}')
      ..writeln('- 当前授权：${_authorizationLabel(token)}')
      ..writeln('- 写回边界：只允许写入 FlowPlan 托管的 Outlook 专属日历容器')
      ..writeln()
      ..writeln('## 1. 安全边界')
      ..writeln()
      ..writeln('- 普通 Outlook 日历：始终只读，只会导入到 FlowPlan 本地。')
      ..writeln('- FlowPlan 托管日历：仅在“双向同步 + 读写授权”同时满足时允许写回。')
      ..writeln('- 任务镜像：只写入明确绑定的 `FlowPlan 任务本 - ...` 专属容器。')
      ..writeln('- 冲突策略：远端更新失败或疑似被删除时，不静默覆盖远端数据，而是记录为冲突候选。')
      ..writeln()
      ..writeln('## 2. 最近同步结果')
      ..writeln();

    if (lastReport == null) {
      buffer.writeln('当前还没有最近同步报告。');
    } else {
      buffer
        ..writeln('- 时间：${_formatDateTime(lastReport.attemptedAt)}')
        ..writeln('- 状态：${lastReport.success ? '成功' : '失败'}')
        ..writeln('- 模式：${lastReport.mode.label}')
        ..writeln('- 日历本数量：${lastReport.calendarBooks}')
        ..writeln('- 日程更新：${lastReport.downloaded}')
        ..writeln('- 任务镜像新增：${lastReport.mirroredCreated}')
        ..writeln('- 任务镜像更新：${lastReport.mirroredUpdated}')
        ..writeln('- 任务镜像删除：${lastReport.mirroredDeleted}')
        ..writeln('- 任务镜像冲突：${lastReport.mirroredConflicted}');
      if (lastReport.errorMessage != null &&
          lastReport.errorMessage!.trim().isNotEmpty) {
        buffer.writeln('- 错误信息：${lastReport.errorMessage}');
      }
    }

    buffer
      ..writeln()
      ..writeln('## 3. Outlook 日历本')
      ..writeln()
      ..writeln('- 已接入 Outlook 日历本：${outlookCalendars.length}')
      ..writeln('- FlowPlan 托管容器：${managedCalendars.length}')
      ..writeln();
    for (final calendar in outlookCalendars) {
      final managed =
          OutlookSyncPolicy.isFlowPlanManagedCalendarName(calendar.name);
      buffer
        ..writeln('### ${calendar.name}')
        ..writeln('- 本地 ID：${calendar.id}')
        ..writeln('- 类型：${managed ? 'FlowPlan 托管容器' : '外部 Outlook 日历，只读'}')
        ..writeln('- 可见状态：${calendar.isVisible ? '显示' : '隐藏'}')
        ..writeln('- 远端 ID：${calendar.syncUrl ?? '无'}')
        ..writeln();
    }

    buffer
      ..writeln('## 4. 任务本镜像绑定')
      ..writeln()
      ..writeln('- 任务本总数：${taskLists.length}')
      ..writeln('- 已绑定任务本：${taskListBindings.length}')
      ..writeln('- 镜像索引总数：${mirrorBindings.length}')
      ..writeln('- 正常镜像：${mirrorDiagnostics.active}')
      ..writeln('- 待清理镜像：${mirrorDiagnostics.pendingCleanup}')
      ..writeln('- 本地任务已不存在：${mirrorDiagnostics.missingTasks}')
      ..writeln('- 任务本已解绑：${mirrorDiagnostics.unboundTaskLists}')
      ..writeln('- 镜像目标变更：${mirrorDiagnostics.movedTargets}')
      ..writeln('- 本地字段变更待写回：${mirrorDiagnostics.localChanged}')
      ..writeln();

    for (final taskList in taskLists) {
      final binding = taskListBindings[taskList.id];
      buffer
        ..writeln('### ${taskList.name}')
        ..writeln('- 本地 ID：${taskList.id}')
        ..writeln('- 状态：${taskList.isArchived ? '已归档' : '未归档'}')
        ..writeln('- 可见状态：${taskList.isVisible ? '显示' : '隐藏'}')
        ..writeln('- Outlook 镜像：${binding == null ? '未绑定' : binding.remoteCalendarName}');
      if (binding != null) {
        buffer
          ..writeln('- 远端容器 ID：${binding.remoteCalendarId}')
          ..writeln('- 绑定时间：${_formatDateTime(binding.linkedAt)}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## 5. 字段级冲突候选')
      ..writeln();
    if (mirrorDiagnostics.conflictLines.isEmpty) {
      buffer.writeln('当前没有发现字段级冲突候选。');
    } else {
      for (final line in mirrorDiagnostics.conflictLines) {
        buffer.writeln('- $line');
      }
    }

    buffer
      ..writeln()
      ..writeln('## 6. 机器可读快照')
      ..writeln()
      ..writeln('```json')
      ..writeln(
        const JsonEncoder.withIndent('  ').convert({
          'generated_at': generatedAt.toIso8601String(),
          'sync_mode': syncMode.storageValue,
          'authorization': _authorizationLabel(token),
          'outlook_calendar_count': outlookCalendars.length,
          'managed_calendar_count': managedCalendars.length,
          'task_list_binding_count': taskListBindings.length,
          'mirror_binding_count': mirrorBindings.length,
          'mirror_diagnostics': mirrorDiagnostics.toJson(),
          'last_sync': lastReport == null
              ? null
              : {
                  'attempted_at': lastReport.attemptedAt.toIso8601String(),
                  'mode': lastReport.mode.storageValue,
                  'success': lastReport.success,
                  'calendar_books': lastReport.calendarBooks,
                  'downloaded': lastReport.downloaded,
                  'mirrored_created': lastReport.mirroredCreated,
                  'mirrored_updated': lastReport.mirroredUpdated,
                  'mirrored_deleted': lastReport.mirroredDeleted,
                  'mirrored_conflicted': lastReport.mirroredConflicted,
                  'error': lastReport.errorMessage,
                },
        }),
      )
      ..writeln('```');

    return buffer.toString();
  }

  _MirrorDiagnostics _buildMirrorDiagnostics({
    required Map<int, OutlookTaskListBinding> taskListBindings,
    required Map<int, OutlookTaskMirrorBinding> mirrorBindings,
    required Map<int, TaskItem> taskById,
    required Map<int, TaskList> taskListById,
  }) {
    var active = 0;
    var pendingCleanup = 0;
    var missingTasks = 0;
    var unboundTaskLists = 0;
    var movedTargets = 0;
    var localChanged = 0;
    final conflictLines = <String>[];

    for (final entry in mirrorBindings.entries) {
      final binding = entry.value;
      final task = taskById[entry.key];
      if (task == null) {
        missingTasks++;
        pendingCleanup++;
        conflictLines.add(
          '本地任务 #${entry.key} 已不存在，但仍有 Outlook 镜像索引：${binding.remoteCalendarName}',
        );
        continue;
      }

      final taskListId = task.taskListId;
      if (taskListId == null) {
        missingTasks++;
        pendingCleanup++;
        conflictLines.add('任务「${task.summary}」缺少任务本归属，镜像需要人工检查。');
        continue;
      }

      final taskListBinding = taskListBindings[taskListId];
      if (taskListBinding == null) {
        unboundTaskLists++;
        pendingCleanup++;
        conflictLines.add('任务「${task.summary}」所在任务本已解绑 Outlook 镜像容器。');
        continue;
      }

      final remoteCalendarId = taskListBinding.remoteCalendarId;
      final remoteCalendarName = taskListBinding.remoteCalendarName;
      if (remoteCalendarId != binding.remoteCalendarId) {
        movedTargets++;
        pendingCleanup++;
        conflictLines.add(
          '任务「${task.summary}」的镜像目标已从 ${binding.remoteCalendarName} 变更为 $remoteCalendarName。',
        );
        continue;
      }

      final taskListName = taskListById[taskListId]?.name ??
          _previousTaskListName(binding.localSnapshotJson) ??
          remoteCalendarName;
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task,
        taskListName: taskListName,
      );
      final previousHash = binding.localSnapshotHash?.trim();
      if (previousHash != null &&
          previousHash.isNotEmpty &&
          previousHash != snapshot.fingerprint) {
        localChanged++;
        final changedFields = OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: binding.localSnapshotJson,
          current: snapshot,
        );
        conflictLines.add(
          '任务「${task.summary}」本地字段已变化，待写回字段：${changedFields.join('、')}。',
        );
      }

      active++;
    }

    return _MirrorDiagnostics(
      active: active,
      pendingCleanup: pendingCleanup,
      missingTasks: missingTasks,
      unboundTaskLists: unboundTaskLists,
      movedTargets: movedTargets,
      localChanged: localChanged,
      conflictLines: conflictLines,
    );
  }

  static String? _previousTaskListName(String? rawSnapshotJson) {
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

  static String _authorizationLabel(AuthToken? token) {
    if (token == null) {
      return '未授权';
    }
    return token.grantedMode == OutlookSyncMode.bidirectional
        ? '读写授权'
        : '只读授权';
  }

  static String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}

class _MirrorDiagnostics {
  const _MirrorDiagnostics({
    required this.active,
    required this.pendingCleanup,
    required this.missingTasks,
    required this.unboundTaskLists,
    required this.movedTargets,
    required this.localChanged,
    required this.conflictLines,
  });

  final int active;
  final int pendingCleanup;
  final int missingTasks;
  final int unboundTaskLists;
  final int movedTargets;
  final int localChanged;
  final List<String> conflictLines;

  Map<String, dynamic> toJson() => {
        'active': active,
        'pending_cleanup': pendingCleanup,
        'missing_tasks': missingTasks,
        'unbound_task_lists': unboundTaskLists,
        'moved_targets': movedTargets,
        'local_changed': localChanged,
        'conflict_lines': conflictLines,
      };
}
