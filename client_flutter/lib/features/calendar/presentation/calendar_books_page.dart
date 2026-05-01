import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/calendar_books_repository.dart';
import '../../sync/outlook_auth_service.dart';
import '../../sync/outlook_managed_container_service.dart';
import '../../sync/outlook_task_list_binding.dart';

part 'calendar_books_widgets.dart';

class CalendarBooksPage extends ConsumerWidget {
  const CalendarBooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventCalendars = ref.watch(allEventCalendarsProvider);
    final taskLists = ref.watch(allTaskListsProvider);
    final archivedTaskLists = ref.watch(archivedTaskListsProvider);
    final outlookTaskListBindings = ref.watch(outlookTaskListBindingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u65e5\u5386\u672c\u7ba1\u7406'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _CalendarBooksBoundaryCard(),
          ),
          _SectionHeader(
            title: '\u65e5\u5386\u672c',
            subtitle: '\u65e5\u7a0b\u5bb9\u5668',
            icon: Icons.event_outlined,
            onAdd: () => _showEditEventCalendar(context, ref, null),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Outlook \u65e5\u5386\u4f1a\u5728\u540c\u6b65\u540e\u81ea\u52a8\u51fa\u73b0\uff0c\u5e76\u4ee5\u53ea\u8bfb\u65b9\u5f0f\u63a5\u5165\u3002\u4f60\u4ecd\u7136\u53ef\u4ee5\u63a7\u5236\u5b83\u4eec\u5728 FlowPlanV2 \u4e2d\u662f\u5426\u663e\u793a\u3002',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          eventCalendars.when(
            loading: () => const _LoadingTile(),
            error: (error, _) => _ErrorTile(message: error.toString()),
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyHint(
                  message: '\u6682\u65e0\u65e5\u5386\u672c\uff0c\u70b9\u51fb\u53f3\u4e0a\u89d2\u521b\u5efa',
                );
              }
              return Column(
                children: items.map((calendar) {
                  if (calendar.source == 'outlook') {
                    return _ReadOnlyEventCalendarTile(
                      calendar: calendar,
                      onToggle: (value) => ref
                          .read(calendarBooksRepositoryProvider)
                          .toggleEventCalendarVisible(calendar.id, value),
                    );
                  }
                  return _EventCalendarTile(
                    calendar: calendar,
                    onToggle: (value) => ref
                        .read(calendarBooksRepositoryProvider)
                        .toggleEventCalendarVisible(calendar.id, value),
                    onSetDefault: () =>
                        _setDefaultEventCalendar(context, ref, calendar),
                    onEdit: () => _showEditEventCalendar(context, ref, calendar),
                    onDelete: () =>
                        _confirmDeleteEventCalendar(context, ref, calendar),
                  );
                }).toList(),
              );
            },
          ),
          const Divider(height: 32),
          _SectionHeader(
            title: '\u4efb\u52a1\u672c',
            subtitle: '\u4efb\u52a1\u5bb9\u5668',
            icon: Icons.task_alt_outlined,
            onAdd: () => _showEditTaskList(context, ref, null),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '\u5f52\u6863\u6216\u5220\u9664\u4efb\u52a1\u672c\u65f6\uff0c\u5176\u4e2d\u4efb\u52a1\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\uff0c\u4ece\u800c\u4fdd\u8bc1\u4efb\u52a1\u4e0d\u4f1a\u8131\u79bb\u4efb\u52a1\u672c\u5355\u72ec\u5b58\u5728\u3002\u5982\u679c\u8be5\u4efb\u52a1\u672c\u7ed1\u5b9a\u4e86 Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\uff0cFlowPlanV2 \u53ea\u4f1a\u89e3\u9664\u672c\u5730\u6620\u5c04\uff0c\u5e76\u5728\u4e0b\u6b21\u53cc\u5411\u540c\u6b65\u65f6\u5b89\u5168\u6536\u53e3\u65e7\u955c\u50cf\uff0c\u4e0d\u4f1a\u7acb\u5373\u76f4\u63a5\u5220\u6389 Outlook \u4e13\u5c5e\u5bb9\u5668\u3002\u5df2\u5f52\u6863\u7684\u4efb\u52a1\u672c\u53ef\u4ee5\u5728\u4e0b\u65b9\u6062\u590d\u6216\u5f7b\u5e95\u5220\u9664\u3002',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          taskLists.when(
            loading: () => const _LoadingTile(),
            error: (error, _) => _ErrorTile(message: error.toString()),
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyHint(
                  message: '\u6682\u65e0\u4efb\u52a1\u672c\uff0c\u70b9\u51fb\u53f3\u4e0a\u89d2\u521b\u5efa',
                );
              }
              final bindings =
                  outlookTaskListBindings.asData?.value ??
                      const <int, OutlookTaskListBinding>{};
              return Column(
                children: items.map((taskList) {
                  final binding = bindings[taskList.id];
                  return _TaskListTile(
                    taskList: taskList,
                    outlookBinding: binding,
                    onToggle: (value) => ref
                        .read(calendarBooksRepositoryProvider)
                        .toggleTaskListVisible(taskList.id, value),
                    onSetDefault: () =>
                        _setDefaultTaskList(context, ref, taskList),
                    onEdit: () => _showEditTaskList(context, ref, taskList),
                    onBindOutlook: () =>
                        _bindTaskListToOutlook(context, ref, taskList),
                    onUnbindOutlook: () =>
                        _unbindTaskListFromOutlook(context, ref, taskList),
                    onArchive: () => _confirmArchiveTaskList(
                      context,
                      ref,
                      taskList,
                      binding,
                    ),
                    onDelete: () => _confirmDeleteTaskList(
                      context,
                      ref,
                      taskList,
                      binding,
                      isArchived: false,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          archivedTaskLists.when(
            loading: () => const SizedBox.shrink(),
            error: (error, _) => _ErrorTile(message: error.toString()),
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox.shrink();
              }
              final bindings =
                  outlookTaskListBindings.asData?.value ??
                      const <int, OutlookTaskListBinding>{};
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '\u5df2\u5f52\u6863\u4efb\u52a1\u672c',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ...items.map(
                    (taskList) {
                      final binding = bindings[taskList.id];
                      return _ArchivedTaskListTile(
                        taskList: taskList,
                        onRestore: () =>
                            _confirmRestoreTaskList(context, ref, taskList),
                        onDelete: () => _confirmDeleteTaskList(
                          context,
                          ref,
                          taskList,
                          binding,
                          isArchived: true,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _setDefaultEventCalendar(
    BuildContext context,
    WidgetRef ref,
    EventCalendar calendar,
  ) async {
    try {
      await ref
          .read(calendarBooksRepositoryProvider)
          .setDefaultEventCalendar(calendar.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('日历本「${calendar.name}」已设为默认日历本'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置默认日历本失败：$error')),
      );
    }
  }

  Future<void> _setDefaultTaskList(
    BuildContext context,
    WidgetRef ref,
    TaskList taskList,
  ) async {
    try {
      await ref.read(calendarBooksRepositoryProvider).setDefaultTaskList(
            taskList.id,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('任务本「${taskList.name}」已设为默认任务本'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置默认任务本失败：$error')),
      );
    }
  }

  Future<void> _showEditEventCalendar(
    BuildContext context,
    WidgetRef ref,
    EventCalendar? existing,
  ) async {
    if (existing?.source == 'outlook') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Outlook \u65e5\u5386\u672c\u7531\u540c\u6b65\u81ea\u52a8\u7ef4\u62a4\uff0c\u4e0d\u80fd\u5728 FlowPlanV2 \u4e2d\u76f4\u63a5\u7f16\u8f91\u3002',
          ),
        ),
      );
      return;
    }

    final repo = ref.read(calendarBooksRepositoryProvider);
    final defaults = existing == null
        ? const EventCalendarDefaults.fallback()
        : await repo.getEventCalendarDefaults(existing.id);
    if (!context.mounted) {
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _EditCalendarDialog(
        title: existing == null
            ? '\u65b0\u5efa\u65e5\u5386\u672c'
            : '\u7f16\u8f91\u65e5\u5386\u672c',
        initialName: existing?.name ?? '',
        initialColor: existing?.colorHex ?? '#6B5EE4',
        initialDefaultIsBlock: defaults.defaultIsBlock,
        onSave: (name, color, defaultIsBlock) async {
          final repo = ref.read(calendarBooksRepositoryProvider);
          late final int calendarId;
          if (existing == null) {
            calendarId = await repo.createEventCalendar(
              EventCalendarsCompanion.insert(
                name: name,
                colorHex: Value(color),
                createdAt: DateTime.now(),
              ),
            );
          } else {
            await repo.updateEventCalendar(
              EventCalendarsCompanion(
                id: Value(existing.id),
                name: Value(name),
                colorHex: Value(color),
              ),
            );
            calendarId = existing.id;
          }
          await repo.saveEventCalendarDefaults(
            id: calendarId,
            defaultIsBlock: defaultIsBlock,
          );
        },
      ),
    );
  }

  Future<void> _showEditTaskList(
    BuildContext context,
    WidgetRef ref,
    TaskList? existing,
  ) async {
    final repo = ref.read(calendarBooksRepositoryProvider);
    final fallbackReminderMinutes = ref.read(reminderMinutesProvider);
    final defaults = existing == null
        ? TaskListDefaults.fallback(
            reminderMinutesBefore: fallbackReminderMinutes,
          )
        : await repo.getTaskListDefaults(
            existing.id,
            fallbackReminderMinutes: fallbackReminderMinutes,
          );
    if (!context.mounted) {
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _EditTaskListDialog(
        title: existing == null
            ? '\u65b0\u5efa\u4efb\u52a1\u672c'
            : '\u7f16\u8f91\u4efb\u52a1\u672c',
        initialName: existing?.name ?? '',
        initialColor: existing?.colorHex ?? '#6B5EE4',
        initialEmoji:
            existing?.emoji?.isNotEmpty == true ? existing!.emoji! : '\u6536',
        initialDefaultIsAutoScheduled: defaults.defaultIsAutoScheduled,
        initialDefaultReminderMinutes:
            defaults.defaultReminderMinutesBefore,
        onSave: (
          name,
          color,
          emoji,
          defaultIsAutoScheduled,
          defaultReminderMinutesBefore,
        ) async {
          final repo = ref.read(calendarBooksRepositoryProvider);
          final finalEmoji = emoji.trim().isEmpty ? '\u6536' : emoji.trim();
          late final int taskListId;
          if (existing == null) {
            taskListId = await repo.createTaskList(
              TaskListsCompanion.insert(
                name: name,
                colorHex: Value(color),
                emoji: Value(finalEmoji),
                createdAt: DateTime.now(),
              ),
            );
          } else {
            await repo.updateTaskList(
              TaskListsCompanion(
                id: Value(existing.id),
                name: Value(name),
                colorHex: Value(color),
                emoji: Value(finalEmoji),
              ),
            );
            taskListId = existing.id;
          }
          await repo.saveTaskListDefaults(
            id: taskListId,
            defaultIsAutoScheduled: defaultIsAutoScheduled,
            defaultReminderMinutesBefore: defaultReminderMinutesBefore,
          );
        },
      ),
    );
  }

  Future<void> _runConfirmedAction(
    BuildContext context, {
    required String title,
    required String message,
    required String successMessage,
    required Future<dynamic> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '\u786e\u8ba4',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await onConfirm();
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u64cd\u4f5c\u5931\u8d25\uff1a$error'),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteEventCalendar(
    BuildContext context,
    WidgetRef ref,
    EventCalendar calendar,
  ) async {
    final repo = ref.read(calendarBooksRepositoryProvider);
    final eventCount = await repo.countEventsInCalendar(calendar.id);
    if (!context.mounted) {
      return;
    }

    final defaultMessage = calendar.isDefault
        ? '\n\n当前它还是默认日历本。删除后，FlowPlanV2 会自动把其他可写日历本补位为新的默认日历本；如果当前没有其他可写日历本，系统会自动新建一个本地默认日历本承接默认角色。'
        : '';
    final message = eventCount > 0
        ? '\u65e5\u5386\u672c\u201c${calendar.name}\u201d\u5f53\u524d\u5305\u542b $eventCount \u6761\u672c\u5730\u65e5\u7a0b\u3002\n\n\u5220\u9664\u540e\uff0c\u8fd9\u4e9b\u672c\u5730\u65e5\u7a0b\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u5199\u65e5\u5386\u672c\uff1b\u5982\u679c\u5f53\u524d\u6ca1\u6709\u5176\u4ed6\u53ef\u5199\u65e5\u5386\u672c\uff0c\u7cfb\u7edf\u4f1a\u81ea\u52a8\u521b\u5efa\u4e00\u4e2a\u672c\u5730\u9ed8\u8ba4\u65e5\u5386\u672c\u627f\u63a5\u8fd9\u4e9b\u65e5\u7a0b\u3002$defaultMessage'
        : '\u65e5\u5386\u672c\u201c${calendar.name}\u201d\u5f53\u524d\u6ca1\u6709\u672c\u5730\u65e5\u7a0b\u3002\n\n\u5220\u9664\u540e\u53ea\u4f1a\u79fb\u9664\u8fd9\u4e2a\u7a7a\u65e5\u5386\u672c\uff0c\u4e0d\u4f1a\u5f71\u54cd Outlook \u6216\u5176\u4ed6\u5916\u90e8\u6570\u636e\u3002$defaultMessage';
    final successMessage = eventCount > 0
        ? '\u65e5\u5386\u672c\u300c${calendar.name}\u300d\u5df2\u5220\u9664\uff0c$eventCount \u6761\u672c\u5730\u65e5\u7a0b\u5df2\u8fc1\u79fb${calendar.isDefault ? '\uff0c\u9ed8\u8ba4\u65e5\u5386\u672c\u5df2\u81ea\u52a8\u5207\u6362' : ''}'
        : '\u65e5\u5386\u672c\u300c${calendar.name}\u300d\u5df2\u5220\u9664';

    await _runConfirmedAction(
      context,
      title: '\u5220\u9664\u65e5\u5386\u672c',
      message: message,
      successMessage: successMessage,
      onConfirm: () => repo.deleteEventCalendar(calendar.id),
    );
  }

  Future<void> _confirmArchiveTaskList(
    BuildContext context,
    WidgetRef ref,
    TaskList taskList,
    OutlookTaskListBinding? binding,
  ) async {
    final impact = await _loadTaskListImpact(ref, taskList.id);
    if (!context.mounted) {
      return;
    }

    await _runConfirmedAction(
      context,
      title: '\u5f52\u6863\u4efb\u52a1\u672c',
      message: _buildTaskListImpactMessage(
        taskList: taskList,
        taskCount: impact.taskCount,
        mirrorCount: impact.mirrorCount,
        binding: binding,
        action: '\u5f52\u6863',
      ),
      successMessage: _buildTaskListImpactSuccessMessage(
        taskList: taskList,
        taskCount: impact.taskCount,
        mirrorCount: impact.mirrorCount,
        wasDefault: taskList.isDefault,
        action: '\u5f52\u6863',
      ),
      onConfirm: () async {
        await ref.read(calendarBooksRepositoryProvider).archiveTaskList(taskList.id);
        final refreshNotifier = ref.read(outlookBindingRefreshTickProvider.notifier);
        refreshNotifier.state = refreshNotifier.state + 1;
      },
    );
  }

  Future<void> _confirmRestoreTaskList(
    BuildContext context,
    WidgetRef ref,
    TaskList taskList,
  ) async {
    await _runConfirmedAction(
      context,
      title: '\u6062\u590d\u4efb\u52a1\u672c',
      message:
          '\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u5c06\u91cd\u65b0\u56de\u5230\u53ef\u7528\u5217\u8868\u4e2d\u3002\n\n\u8bf7\u6ce8\u610f\uff0c\u8fd9\u4e2a\u4efb\u52a1\u672c\u5728\u5f52\u6863\u65f6\uff0c\u5176\u4e2d\u4efb\u52a1\u5df2\u7ecf\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\uff0c\u6062\u590d\u540e\u4e0d\u4f1a\u81ea\u52a8\u628a\u4efb\u52a1\u79fb\u56de\u6765\u3002',
      successMessage: '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u6062\u590d',
      onConfirm: () => ref
          .read(calendarBooksRepositoryProvider)
          .unarchiveTaskList(taskList.id),
    );
  }

  Future<void> _confirmDeleteTaskList(
    BuildContext context,
    WidgetRef ref,
    TaskList taskList,
    OutlookTaskListBinding? binding, {
    required bool isArchived,
  }) async {
    final impact = await _loadTaskListImpact(ref, taskList.id);
    if (!context.mounted) {
      return;
    }

    await _runConfirmedAction(
      context,
      title: isArchived
          ? '\u5f7b\u5e95\u5220\u9664\u4efb\u52a1\u672c'
          : '\u5220\u9664\u4efb\u52a1\u672c',
      message: _buildTaskListImpactMessage(
        taskList: taskList,
        taskCount: impact.taskCount,
        mirrorCount: impact.mirrorCount,
        binding: binding,
        action: isArchived ? '\u5f7b\u5e95\u5220\u9664' : '\u5220\u9664',
      ),
      successMessage: _buildTaskListImpactSuccessMessage(
        taskList: taskList,
        taskCount: impact.taskCount,
        mirrorCount: impact.mirrorCount,
        wasDefault: taskList.isDefault,
        action: isArchived ? '\u5f7b\u5e95\u5220\u9664' : '\u5220\u9664',
      ),
      onConfirm: () async {
        await ref.read(calendarBooksRepositoryProvider).deleteTaskList(taskList.id);
        final refreshNotifier = ref.read(outlookBindingRefreshTickProvider.notifier);
        refreshNotifier.state = refreshNotifier.state + 1;
      },
    );
  }

  Future<({int taskCount, int mirrorCount})> _loadTaskListImpact(
    WidgetRef ref,
    int taskListId,
  ) async {
    final booksRepo = ref.read(calendarBooksRepositoryProvider);
    final mirrorRepo = ref.read(outlookTaskMirrorRepositoryProvider);
    final taskCount = await booksRepo.countTasksInTaskList(taskListId);
    final mirrorCount =
        await mirrorRepo.countTaskMirrorBindingsForTaskList(taskListId);
    return (taskCount: taskCount, mirrorCount: mirrorCount);
  }

  String _buildTaskListImpactMessage({
    required TaskList taskList,
    required int taskCount,
    required int mirrorCount,
    required OutlookTaskListBinding? binding,
    required String action,
  }) {
    final lines = <String>[
      '\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u5f53\u524d\u5305\u542b $taskCount \u6761\u4efb\u52a1\u3002',
      if (taskList.isDefault)
        '\u8be5\u4efb\u52a1\u672c\u5f53\u524d\u4ecd\u662f\u9ed8\u8ba4\u4efb\u52a1\u672c\u3002$action\u540e\uff0cFlowPlanV2 \u4f1a\u81ea\u52a8\u628a\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\u8865\u4f4d\u4e3a\u65b0\u7684\u9ed8\u8ba4\u4efb\u52a1\u672c\uff1b\u82e5\u5f53\u524d\u6ca1\u6709\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\uff0c\u5219\u4f1a\u81ea\u52a8\u521b\u5efa\u201c\u6536\u4ef6\u7bb1\u201d\u627f\u63a5\u9ed8\u8ba4\u89d2\u8272\u3002',
      taskCount > 0
          ? '$action\u540e\uff0c\u8fd9\u4e9b\u4efb\u52a1\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\uff1b\u5982\u679c\u5f53\u524d\u6ca1\u6709\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\uff0c\u7cfb\u7edf\u4f1a\u81ea\u52a8\u521b\u5efa\u201c\u6536\u4ef6\u7bb1\u201d\u627f\u63a5\u8fd9\u4e9b\u4efb\u52a1\u3002'
          : '$action\u540e\uff0c\u4e0d\u4f1a\u6709\u672c\u5730\u4efb\u52a1\u9700\u8981\u8fc1\u79fb\u3002',
      if (binding != null)
        '\u8be5\u4efb\u52a1\u672c\u5f53\u524d\u7ed1\u5b9a\u4e86 Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\u201c${binding.remoteCalendarName}\u201d\u3002\u672c\u6b21\u64cd\u4f5c\u4f1a\u7acb\u5373\u89e3\u9664 FlowPlanV2 \u4e0e\u8be5\u5bb9\u5668\u7684\u6620\u5c04\uff0c\u4f46\u4e0d\u4f1a\u76f4\u63a5\u5220\u6389 Outlook \u4e2d\u7684\u4e13\u5c5e\u5bb9\u5668\u3002',
      if (binding == null && mirrorCount > 0)
        '\u8be5\u4efb\u52a1\u672c\u5f53\u524d\u867d\u7136\u6ca1\u6709\u6d3b\u8dc3\u7684 Outlook \u5bb9\u5668\u7ed1\u5b9a\uff0c\u4f46\u4ecd\u4fdd\u7559\u4e86 $mirrorCount \u6761\u5f85\u6536\u53e3\u7684\u65e7\u955c\u50cf\u7d22\u5f15\u3002',
      if (mirrorCount > 0)
        '\u4e3a\u4e86\u5b89\u5168\u6e05\u7406 Outlook \u4fa7\u7684\u65e7\u955c\u50cf\uff0c\u8fd9 $mirrorCount \u6761\u5386\u53f2\u955c\u50cf\u7d22\u5f15\u4f1a\u88ab\u4fdd\u7559\u5230\u4e0b\u6b21\u53cc\u5411\u540c\u6b65\u65f6\u6536\u53e3\u3002',
      if (mirrorCount == 0 && binding != null)
        '\u5f53\u524d\u6ca1\u6709\u5f85\u6536\u53e3\u7684 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002',
    ];
    return lines.join('\n\n');
  }

  String _buildTaskListImpactSuccessMessage({
    required TaskList taskList,
    required int taskCount,
    required int mirrorCount,
    required bool wasDefault,
    required String action,
  }) {
    final suffix = <String>[
      if (taskCount > 0) '$taskCount \u6761\u4efb\u52a1\u5df2\u8fc1\u79fb',
      if (mirrorCount > 0)
        '$mirrorCount \u6761\u65e7 Outlook \u955c\u50cf\u5c06\u5728\u4e0b\u6b21\u53cc\u5411\u540c\u6b65\u65f6\u6536\u53e3',
      if (wasDefault) '\u9ed8\u8ba4\u4efb\u52a1\u672c\u5df2\u81ea\u52a8\u5207\u6362',
    ];
    if (suffix.isEmpty) {
      return '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2$action';
    }
    return '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2$action\uff1b${suffix.join('\uff1b')}';
  }

  Future<void> _bindTaskListToOutlook(
    BuildContext context,
    WidgetRef ref,
    TaskList taskList,
  ) async {
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u8bf7\u5148\u5728 Outlook \u540c\u6b65\u8bbe\u7f6e\u4e2d\u4fdd\u5b58 OAuth \u914d\u7f6e\u5e76\u5b8c\u6210 Outlook \u767b\u5f55\u3002',
          ),
        ),
      );
      return;
    }

    final service = OutlookManagedContainerService(
      config: config,
      bindingsRepository: ref.read(outlookSyncBindingsRepositoryProvider),
    );

    try {
      final binding = await service.ensureTaskListMirrorBinding(taskList);
      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u7ed1\u5b9a Outlook \u4e13\u5c5e\u5bb9\u5668\uff1a${binding.remoteCalendarName}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u7ed1\u5b9a Outlook \u5bb9\u5668\u5931\u8d25\uff1a$error'),
        ),
      );
    }
  }

  Future<void> _unbindTaskListFromOutlook(
    BuildContext context,
    WidgetRef ref,
    TaskList taskList,
  ) async {
    final mirrorCount = await ref
        .read(outlookTaskMirrorRepositoryProvider)
        .countTaskMirrorBindingsForTaskList(taskList.id);
    if (!context.mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u89e3\u9664 Outlook \u7ed1\u5b9a'),
        content: Text(
          mirrorCount > 0
              ? '\u786e\u5b9a\u8981\u89e3\u9664\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668\u7ed1\u5b9a\u5417\uff1f\n\n\u8fd9\u4e0d\u4f1a\u5220\u9664 Outlook \u4e2d\u5df2\u5efa\u7acb\u7684\u4e13\u5c5e\u65e5\u5386\u5bb9\u5668\uff0c\u53ea\u4f1a\u89e3\u9664 FlowPlanV2 \u4e0e\u5b83\u7684\u5bf9\u5e94\u5173\u7cfb\u3002\n\n\u4e3a\u4e86\u5b89\u5168\u6e05\u7406\u65e7\u955c\u50cf\uff0c\u5f53\u524d $mirrorCount \u6761\u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u4f1a\u4fdd\u7559\u5230\u4e0b\u6b21\u53cc\u5411\u540c\u6b65\u65f6\u6536\u53e3\u3002'
              : '\u786e\u5b9a\u8981\u89e3\u9664\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668\u7ed1\u5b9a\u5417\uff1f\n\n\u8fd9\u4e0d\u4f1a\u5220\u9664 Outlook \u4e2d\u5df2\u5efa\u7acb\u7684\u4e13\u5c5e\u65e5\u5386\u5bb9\u5668\uff0c\u53ea\u4f1a\u89e3\u9664 FlowPlanV2 \u4e0e\u5b83\u7684\u5bf9\u5e94\u5173\u7cfb\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '\u89e3\u9664',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(outlookSyncBindingsRepositoryProvider)
          .removeTaskListBinding(taskList.id);
      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mirrorCount > 0
                ? '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u89e3\u9664 Outlook \u7ed1\u5b9a\uff1b$mirrorCount \u6761\u65e7\u955c\u50cf\u5c06\u5728\u4e0b\u6b21\u53cc\u5411\u540c\u6b65\u65f6\u6536\u53e3'
                : '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u89e3\u9664 Outlook \u7ed1\u5b9a',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u89e3\u9664 Outlook \u7ed1\u5b9a\u5931\u8d25\uff1a$error'),
        ),
      );
    }
  }
}

