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
        .where(
          (calendar) =>
              OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(calendar.name),
        )
        .toList(growable: false);
    final mirrorDiagnostics = _buildMirrorDiagnostics(
      taskListBindings: taskListBindings,
      mirrorBindings: mirrorBindings,
      taskById: taskById,
      taskListById: taskListById,
    );

    final buffer = StringBuffer()
      ..writeln('# FlowPlanV2 Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a')
      ..writeln()
      ..writeln('- \u751f\u6210\u65f6\u95f4\uff1a${_formatDateTime(generatedAt)}')
      ..writeln('- \u540c\u6b65\u6a21\u5f0f\uff1a${syncMode.label}')
      ..writeln('- OAuth \u914d\u7f6e\uff1a${config == null ? '\u672a\u914d\u7f6e' : '\u5df2\u914d\u7f6e'}')
      ..writeln('- \u5f53\u524d\u6388\u6743\uff1a${_authorizationLabel(token)}')
      ..writeln('- \u5199\u56de\u8fb9\u754c\uff1a\u53ea\u5141\u8bb8\u5199\u5165 FlowPlanV2 \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668')
      ..writeln()
      ..writeln('## 1. \u5b89\u5168\u8fb9\u754c')
      ..writeln()
      ..writeln('- \u666e\u901a Outlook \u65e5\u5386\uff1a\u59cb\u7ec8\u53ea\u8bfb\uff0c\u53ea\u4f1a\u5bfc\u5165\u5230 FlowPlanV2 \u672c\u5730\u3002')
      ..writeln(
        '- FlowPlanV2 \u6258\u7ba1\u65e5\u5386\uff1a\u4ec5\u5728\u201c\u53cc\u5411\u540c\u6b65 + \u8bfb\u5199\u6388\u6743\u201d\u540c\u65f6\u6ee1\u8db3\u65f6\u5141\u8bb8\u5199\u56de\u3002',
      )
      ..writeln(
        '- \u4efb\u52a1\u955c\u50cf\uff1a\u53ea\u5199\u5165\u660e\u786e\u7ed1\u5b9a\u7684 FlowPlanV2 \u4efb\u52a1\u672c - ... \u4e13\u5c5e\u5bb9\u5668\u3002',
      )
      ..writeln(
        '- \u51b2\u7a81\u7b56\u7565\uff1a\u8fdc\u7aef\u66f4\u65b0\u5931\u8d25\u3001\u8fdc\u7aef\u5df2\u6539\u52a8\u6216\u8fdc\u7aef\u5df2\u5220\u9664\u65f6\uff0c\u4e0d\u4f1a\u9759\u9ed8\u8986\u76d6\u6570\u636e\uff0c\u800c\u662f\u8bb0\u5f55\u4e3a\u5f85\u4eba\u5de5\u786e\u8ba4\u7684\u51b2\u7a81\u3002',
      )
      ..writeln()
      ..writeln('## 2. \u6700\u8fd1\u540c\u6b65\u7ed3\u679c')
      ..writeln();

    if (lastReport == null) {
      buffer.writeln('\u5f53\u524d\u8fd8\u6ca1\u6709\u6700\u8fd1\u540c\u6b65\u62a5\u544a\u3002');
    } else {
      buffer
        ..writeln('- \u65f6\u95f4\uff1a${_formatDateTime(lastReport.attemptedAt)}')
        ..writeln('- \u72b6\u6001\uff1a${lastReport.success ? '\u6210\u529f' : '\u5931\u8d25'}')
        ..writeln('- \u6a21\u5f0f\uff1a${lastReport.mode.label}')
        ..writeln('- \u65e5\u5386\u672c\u6570\u91cf\uff1a${lastReport.calendarBooks}')
        ..writeln('- \u65e5\u7a0b\u66f4\u65b0\uff1a${lastReport.downloaded}')
        ..writeln('- \u4efb\u52a1\u955c\u50cf\u65b0\u589e\uff1a${lastReport.mirroredCreated}')
        ..writeln('- \u4efb\u52a1\u955c\u50cf\u66f4\u65b0\uff1a${lastReport.mirroredUpdated}')
        ..writeln('- \u4efb\u52a1\u955c\u50cf\u5220\u9664\uff1a${lastReport.mirroredDeleted}')
        ..writeln('- \u4efb\u52a1\u955c\u50cf\u51b2\u7a81\uff1a${lastReport.mirroredConflicted}');
      if (lastReport.errorMessage != null &&
          lastReport.errorMessage!.trim().isNotEmpty) {
        buffer.writeln('- \u9519\u8bef\u4fe1\u606f\uff1a${lastReport.errorMessage}');
      }
    }

    buffer
      ..writeln()
      ..writeln('## 3. Outlook \u65e5\u5386\u672c')
      ..writeln()
      ..writeln('- \u5df2\u63a5\u5165 Outlook \u65e5\u5386\u672c\uff1a${outlookCalendars.length}')
      ..writeln('- FlowPlanV2 \u6258\u7ba1\u5bb9\u5668\uff1a${managedCalendars.length}')
      ..writeln();
    for (final calendar in outlookCalendars) {
      final managed =
          OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(calendar.name);
      buffer
        ..writeln('### ${calendar.name}')
        ..writeln('- \u672c\u5730 ID\uff1a${calendar.id}')
        ..writeln('- \u7c7b\u578b\uff1a${managed ? 'FlowPlanV2 \u6258\u7ba1\u5bb9\u5668' : '\u5916\u90e8 Outlook \u65e5\u5386\uff08\u53ea\u8bfb\uff09'}')
        ..writeln('- \u53ef\u89c1\u72b6\u6001\uff1a${calendar.isVisible ? '\u663e\u793a' : '\u9690\u85cf'}')
        ..writeln('- \u8fdc\u7aef ID\uff1a${calendar.syncUrl ?? '\u65e0'}')
        ..writeln();
    }

    buffer
      ..writeln('## 4. \u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a')
      ..writeln()
      ..writeln('- \u4efb\u52a1\u672c\u603b\u6570\uff1a${taskLists.length}')
      ..writeln('- \u5df2\u7ed1\u5b9a\u4efb\u52a1\u672c\uff1a${taskListBindings.length}')
      ..writeln('- \u955c\u50cf\u7d22\u5f15\u603b\u6570\uff1a${mirrorBindings.length}')
      ..writeln('- \u6b63\u5e38\u955c\u50cf\uff1a${mirrorDiagnostics.active}')
      ..writeln('- \u5f85\u6e05\u7406\u955c\u50cf\uff1a${mirrorDiagnostics.pendingCleanup}')
      ..writeln('- \u672c\u5730\u4efb\u52a1\u5df2\u4e0d\u5b58\u5728\uff1a${mirrorDiagnostics.missingTasks}')
      ..writeln('- \u4efb\u52a1\u672c\u5df2\u89e3\u7ed1\uff1a${mirrorDiagnostics.unboundTaskLists}')
      ..writeln('- \u955c\u50cf\u76ee\u6807\u53d8\u66f4\uff1a${mirrorDiagnostics.movedTargets}')
      ..writeln('- \u672c\u5730\u5b57\u6bb5\u5f85\u5199\u56de\uff1a${mirrorDiagnostics.localChanged}')
      ..writeln('- \u8fdc\u7aef\u955c\u50cf\u5df2\u5220\u9664\uff1a${mirrorDiagnostics.remoteDeleted}')
      ..writeln('- \u8fdc\u7aef\u955c\u50cf\u5df2\u4fee\u6539\uff1a${mirrorDiagnostics.remoteChanged}')
      ..writeln('- \u53cc\u4fa7\u540c\u65f6\u4fee\u6539\uff1a${mirrorDiagnostics.divergent}')
      ..writeln('- \u6700\u8fd1\u5199\u56de\u5931\u8d25\uff1a${mirrorDiagnostics.writeFailed}')
      ..writeln();

    for (final taskList in taskLists) {
      final binding = taskListBindings[taskList.id];
      buffer
        ..writeln('### ${taskList.name}')
        ..writeln('- \u672c\u5730 ID\uff1a${taskList.id}')
        ..writeln('- \u72b6\u6001\uff1a${taskList.isArchived ? '\u5df2\u5f52\u6863' : '\u672a\u5f52\u6863'}')
        ..writeln('- \u53ef\u89c1\u72b6\u6001\uff1a${taskList.isVisible ? '\u663e\u793a' : '\u9690\u85cf'}')
        ..writeln('- Outlook \u955c\u50cf\uff1a${binding == null ? '\u672a\u7ed1\u5b9a' : binding.remoteCalendarName}');
      if (binding != null) {
        buffer
          ..writeln('- \u8fdc\u7aef\u5bb9\u5668 ID\uff1a${binding.remoteCalendarId}')
          ..writeln('- \u7ed1\u5b9a\u65f6\u95f4\uff1a${_formatDateTime(binding.linkedAt)}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## 5. \u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009')
      ..writeln();
    if (mirrorDiagnostics.conflictLines.isEmpty) {
      buffer.writeln('\u5f53\u524d\u6ca1\u6709\u53d1\u73b0\u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009\u3002');
    } else {
      for (final line in mirrorDiagnostics.conflictLines) {
        buffer.writeln('- $line');
      }
    }

    buffer
      ..writeln()
      ..writeln('## 6. \u673a\u5668\u53ef\u8bfb\u5feb\u7167')
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
    var remoteDeleted = 0;
    var remoteChanged = 0;
    var divergent = 0;
    var writeFailed = 0;
    final conflictLines = <String>[];

    for (final entry in mirrorBindings.entries) {
      final binding = entry.value;
      switch (binding.conflictState) {
        case OutlookTaskMirrorConflictState.remoteDeleted:
          remoteDeleted++;
          break;
        case OutlookTaskMirrorConflictState.remoteChanged:
          remoteChanged++;
          break;
        case OutlookTaskMirrorConflictState.divergent:
          divergent++;
          break;
        case OutlookTaskMirrorConflictState.writeFailed:
          writeFailed++;
          break;
        case OutlookTaskMirrorConflictState.pendingLocalPush:
        case OutlookTaskMirrorConflictState.none:
          break;
      }

      final task = taskById[entry.key];
      if (task == null) {
        missingTasks++;
        pendingCleanup++;
        conflictLines.add(
          '\u672c\u5730\u4efb\u52a1 #${entry.key} \u5df2\u4e0d\u5b58\u5728\uff0c\u4f46\u4ecd\u4fdd\u7559\u4e86 Outlook \u955c\u50cf\u7d22\u5f15\uff1a${binding.remoteCalendarName}',
        );
        continue;
      }

      final taskListId = task.taskListId;
      if (taskListId == null) {
        missingTasks++;
        pendingCleanup++;
        conflictLines.add('\u4efb\u52a1\u201c${task.summary}\u201d\u7f3a\u5c11\u4efb\u52a1\u672c\u5f52\u5c5e\uff0c\u955c\u50cf\u9700\u8981\u4eba\u5de5\u68c0\u67e5\u3002');
        continue;
      }

      final taskListBinding = taskListBindings[taskListId];
      if (taskListBinding == null) {
        unboundTaskLists++;
        pendingCleanup++;
        conflictLines.add('\u4efb\u52a1\u201c${task.summary}\u201d\u6240\u5728\u4efb\u52a1\u672c\u5df2\u89e3\u7ed1 Outlook \u955c\u50cf\u5bb9\u5668\u3002');
        continue;
      }

      final remoteCalendarId = taskListBinding.remoteCalendarId;
      final remoteCalendarName = taskListBinding.remoteCalendarName;
      if (remoteCalendarId != binding.remoteCalendarId) {
        movedTargets++;
        pendingCleanup++;
        conflictLines.add(
          '\u4efb\u52a1\u201c${task.summary}\u201d\u7684\u955c\u50cf\u76ee\u6807\u5df2\u4ece ${binding.remoteCalendarName} \u53d8\u66f4\u4e3a $remoteCalendarName\u3002',
        );
        continue;
      }

      final taskListName =
          taskListById[taskListId]?.name ??
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
          '\u4efb\u52a1\u201c${task.summary}\u201d\u672c\u5730\u5b57\u6bb5\u5df2\u53d8\u5316\uff0c\u5f85\u5199\u56de\u5b57\u6bb5\uff1a${changedFields.join('\u3001')}\u3002',
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
      remoteDeleted: remoteDeleted,
      remoteChanged: remoteChanged,
      divergent: divergent,
      writeFailed: writeFailed,
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
      return '\u672a\u6388\u6743';
    }
    return token.grantedMode == OutlookSyncMode.bidirectional ? '\u8bfb\u5199\u6388\u6743' : '\u53ea\u8bfb\u6388\u6743';
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
    required this.remoteDeleted,
    required this.remoteChanged,
    required this.divergent,
    required this.writeFailed,
    required this.conflictLines,
  });

  final int active;
  final int pendingCleanup;
  final int missingTasks;
  final int unboundTaskLists;
  final int movedTargets;
  final int localChanged;
  final int remoteDeleted;
  final int remoteChanged;
  final int divergent;
  final int writeFailed;
  final List<String> conflictLines;

  Map<String, dynamic> toJson() => {
        'active': active,
        'pending_cleanup': pendingCleanup,
        'missing_tasks': missingTasks,
        'unbound_task_lists': unboundTaskLists,
        'moved_targets': movedTargets,
        'local_changed': localChanged,
        'remote_deleted': remoteDeleted,
        'remote_changed': remoteChanged,
        'divergent': divergent,
        'write_failed': writeFailed,
        'conflict_lines': conflictLines,
      };
}

