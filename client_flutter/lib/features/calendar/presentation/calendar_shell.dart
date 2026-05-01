import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/widgets/server_connection_indicator.dart';
import '../../scheduler/plan_feedback_service.dart';
import '../../scheduler/scheduler_engine.dart';
import '../../task/presentation/quick_add_bar.dart';
import '../../task/presentation/task_detail_page.dart';
import '../../task/presentation/unscheduled_task_panel.dart';
import 'calendar_books_page.dart';
import 'event_detail_page.dart';

class _ScheduleRangeChoice {
  const _ScheduleRangeChoice({
    required this.label,
    required this.description,
    required this.date,
    required this.from,
    required this.until,
  });

  final String label;
  final String description;
  final DateTime date;
  final DateTime from;
  final DateTime until;
}

class CalendarShell extends ConsumerStatefulWidget {
  const CalendarShell({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  final Widget child;
  final String currentRoute;

  @override
  ConsumerState<CalendarShell> createState() => _CalendarShellState();
}

class _CalendarShellState extends ConsumerState<CalendarShell> {
  static const _items = <({IconData icon, IconData activeIcon, String label, String route})>[
    (
      icon: Icons.view_day_outlined,
      activeIcon: Icons.view_day_rounded,
      label: '\u65f6\u95f4\u8f74',
      route: AppRoutes.timeline,
    ),
    (
      icon: Icons.calendar_view_week_outlined,
      activeIcon: Icons.calendar_view_week_rounded,
      label: '\u672c\u5468',
      route: AppRoutes.week,
    ),
    (
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      label: '\u6708\u89c6\u56fe',
      route: AppRoutes.month,
    ),
    (
      icon: Icons.track_changes_outlined,
      activeIcon: Icons.track_changes_rounded,
      label: '\u8ffd\u8e2a',
      route: AppRoutes.tracker,
    ),
    (
      icon: Icons.summarize_outlined,
      activeIcon: Icons.summarize_rounded,
      label: '报告',
      route: AppRoutes.reports,
    ),
    (
      icon: Icons.folder_outlined,
      activeIcon: Icons.folder_rounded,
      label: '文件',
      route: AppRoutes.files,
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '\u8bbe\u7f6e',
      route: AppRoutes.settings,
    ),
  ];

  Timer? _planFeedbackTimer;
  bool _handlingPlanDeviation = false;
  String? _lastPlanDeviationPromptKey;

  @override
  void initState() {
    super.initState();
    _planFeedbackTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.read(planFeedbackRefreshTickProvider.notifier).state++;
    });
  }

  @override
  void dispose() {
    _planFeedbackTimer?.cancel();
    super.dispose();
  }

  int get _currentIndex {
    final route = widget.currentRoute;
    if (route.startsWith(AppRoutes.week)) return 1;
    if (route.startsWith(AppRoutes.month)) return 2;
    if (route.startsWith(AppRoutes.tracker)) return 3;
    if (route.startsWith(AppRoutes.reports)) return 4;
    if (route.startsWith(AppRoutes.files)) return 5;
    if (route.startsWith(AppRoutes.settings)) return 6;
    return 0;
  }

  void _navigate(int index) => context.go(_items[index].route);

  Future<void> _autoSchedule() async {
    final range = await _pickScheduleRange();
    if (range == null || !mounted) {
      return;
    }
    final result = await ref.read(schedulerEngineProvider).autoScheduleDetailed(
          range.date,
          from: range.from,
          until: range.until,
          trigger: 'manual_range_reschedule',
        );
    if (!mounted) return;

    if (!result.requiresConfirmation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summary),
          action: SnackBarAction(
            label: '\u8be6\u60c5',
            onPressed: () {
              _showScheduleReport(result);
            },
          ),
        ),
      );
      return;
    }

    final confirmed = await _showScheduleReport(
      result,
      allowApply: true,
    );
    if (confirmed != true || !mounted) {
      await _recordScheduleDraftDecision(result, decision: 'rejected');
      return;
    }

    await _recordScheduleDraftDecision(result, decision: 'approved');
    await ref.read(schedulerEngineProvider).applyRunResult(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('\u5df2\u6309\u4f60\u786e\u8ba4\u7684\u9884\u6848\u5e94\u7528\u91cd\u6392\uff1a${result.summary}'),
      ),
    );
  }

  Future<_ScheduleRangeChoice?> _pickScheduleRange() {
    final selectedDate = ref.read(selectedDateProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final selectedDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final selectedStart = _sameDay(selectedDay, today)
        ? now
        : selectedDay.add(const Duration(hours: 8));
    final options = <_ScheduleRangeChoice>[
      _ScheduleRangeChoice(
        label: '所选日期剩余时间',
        description: '${_formatDateTime(selectedStart)} - ${_formatDateTime(selectedDay.add(const Duration(hours: 23, minutes: 59)))}',
        date: selectedDay,
        from: selectedStart,
        until: selectedDay.add(const Duration(hours: 23, minutes: 59)),
      ),
      _ScheduleRangeChoice(
        label: '今天晚上',
        description: '${_formatDateTime(today.add(const Duration(hours: 18)))} - ${_formatDateTime(today.add(const Duration(hours: 23, minutes: 59)))}',
        date: today,
        from: today.add(const Duration(hours: 18)),
        until: today.add(const Duration(hours: 23, minutes: 59)),
      ),
      _ScheduleRangeChoice(
        label: '明天',
        description: '${_formatDateTime(tomorrow)} - ${_formatDateTime(tomorrow.add(const Duration(hours: 23, minutes: 59)))}',
        date: tomorrow,
        from: tomorrow,
        until: tomorrow.add(const Duration(hours: 23, minutes: 59)),
      ),
    ];

    return showDialog<_ScheduleRangeChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择排程范围'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _recordScheduleDraftDecision(
    SchedulerRunResult result, {
    required String decision,
  }) {
    return ref.read(dataOperationLogRepositoryProvider).record(
          actor: '用户确认',
          action: 'scheduler_draft_decision',
          entityType: 'scheduler_run',
          entityId: result.planRunId,
          summary: decision == 'approved'
              ? '用户批准排程草案：${result.summary}'
              : '用户拒绝排程草案，未写入排程片段：${result.summary}',
          metadata: {
            'decision': decision,
            'date': result.date.toIso8601String(),
            'effective_start': result.effectiveStart.toIso8601String(),
            'effective_end': result.effectiveEnd.toIso8601String(),
            'scheduled_task_count': result.scheduledTaskCount,
            'unscheduled_task_count': result.unscheduledTaskCount,
          },
        );
  }

  Future<void> _handlePlanDeviation(PlanDeviationSnapshot snapshot) async {
    if (_handlingPlanDeviation ||
        !snapshot.shouldPrompt ||
        snapshot.plan == null ||
        snapshot.activity == null ||
        snapshot.promptKey == _lastPlanDeviationPromptKey) {
      return;
    }
    _handlingPlanDeviation = true;
    _lastPlanDeviationPromptKey = snapshot.promptKey;

    final plan = snapshot.plan!;
    final activity = snapshot.activity!;
    final shouldReschedule = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u68c0\u6d4b\u5230\u8ba1\u5212\u504f\u79bb'),
        content: Text(
          '\u5f53\u524d\u8ba1\u5212\uff1a\u300c${plan.taskLabel}\u300d\n'
          '\u5f53\u524d\u8ffd\u8e2a\uff1a${activity.label}\n'
          '\u5224\u65ad\u539f\u56e0\uff1a${snapshot.reason}\n\n'
          '\u8981\u751f\u6210\u4e00\u4e2a\u5c06\u5f53\u524d\u4efb\u52a1\u548c\u540e\u7eed\u53ef\u81ea\u52a8\u6392\u7a0b\u4efb\u52a1\u5411\u540e\u987a\u5ef6\u7684\u91cd\u6392\u9884\u6848\u5417\uff1f',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u6682\u4e0d\u5904\u7406'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('\u751f\u6210\u91cd\u6392\u9884\u6848'),
          ),
        ],
      ),
    );

    try {
      if (shouldReschedule != true) {
        await ref
            .read(planFeedbackServiceProvider)
            .markDecision(snapshot, decision: 'snoozed');
        return;
      }

      final now = DateTime.now();
      await ref
          .read(planFeedbackServiceProvider)
          .markDecision(snapshot, decision: 'accepted');
      final result = await ref.read(schedulerEngineProvider).autoScheduleDetailed(
            plan.planStart,
            from: now,
            forceMovableTaskIds: {plan.task.id},
            trigger: 'plan_deviation_confirmed',
          );
      if (!mounted) {
        return;
      }
      final confirmed = await _showScheduleReport(
        result,
        allowApply: result.requiresConfirmation,
      );
      if (!mounted) {
        return;
      }
      if (!result.requiresConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.summary)),
        );
        return;
      }
      if (confirmed != true || !mounted) {
        await _recordScheduleDraftDecision(result, decision: 'rejected');
        return;
      }
      await _recordScheduleDraftDecision(result, decision: 'approved');
      await ref.read(schedulerEngineProvider).applyRunResult(result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u5df2\u6839\u636e\u8ba1\u5212\u504f\u79bb\u786e\u8ba4\u987a\u5ef6\uff1a${result.summary}'),
        ),
      );
    } finally {
      _handlingPlanDeviation = false;
      if (mounted) {
        ref.read(planFeedbackRefreshTickProvider.notifier).state++;
      }
    }
  }

  Future<bool?> _showScheduleReport(
    SchedulerRunResult result, {
    bool allowApply = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          allowApply ? '\u786e\u8ba4\u5e94\u7528\u91cd\u6392\u9884\u6848' : '\u6392\u7a0b\u53d8\u66f4\u8bb0\u5f55',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.summary),
                const SizedBox(height: 6),
                Text(
                  '范围：${_formatDateTime(result.effectiveStart)} - ${_formatDateTime(result.effectiveEnd)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (result.placements.isNotEmpty) ...[
                  Text(
                    '排程草案',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final placement in result.placements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            placement.taskSummary,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            placement.segments
                                .map((segment) =>
                                    '${_formatDateTime(segment.start)} - ${_formatDateTime(segment.end)}')
                                .join('；'),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '预计 ${placement.originalDurationMinutes} 分钟，已确认投入 ${placement.actualWorkedMinutes} 分钟，剩余 ${placement.remainingMinutes} 分钟。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '原因：${placement.reason}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                ],
                if (result.unscheduledTasks.isNotEmpty) ...[
                  Text(
                    '未排任务',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final task in result.unscheduledTasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '「${task.taskSummary}」：${task.reason} 剩余 ${task.remainingMinutes} 分钟。',
                      ),
                    ),
                  const Divider(height: 20),
                ],
                if (result.splitSuggestedTaskCount > 0)
                  Text(
                    '\u6709 ${result.splitSuggestedTaskCount} \u4e2a\u53ef\u62c6\u5206\u4efb\u52a1\u5c06\u5199\u5165\u591a\u4e2a\u6392\u7a0b\u7247\u6bb5\uff0c\u65f6\u95f4\u8f74\u4f1a\u6309\u7247\u6bb5\u663e\u793a\u3002',
                    style: const TextStyle(color: Colors.orange),
                  ),
                const SizedBox(height: 12),
                for (final entry in result.logEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          entry.level == 'success'
                              ? Icons.check_circle_outline
                              : entry.level == 'warning'
                                  ? Icons.info_outline
                                  : Icons.notes_outlined,
                          size: 18,
                          color: entry.level == 'success'
                              ? Colors.green
                              : entry.level == 'warning'
                                  ? Colors.orange
                                  : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.taskSummary == null
                                ? entry.message
                                : '\u300c${entry.taskSummary}\u300d：${entry.message}',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(allowApply ? '\u53d6\u6d88' : '\u77e5\u9053\u4e86'),
          ),
          if (allowApply)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('\u786e\u8ba4\u5e94\u7528'),
            ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  void _showBooksPage() {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: const SizedBox(width: 520, child: CalendarBooksPage()),
      ),
    );
  }

  void _showQuickAdd() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickAddSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<PlanDeviationSnapshot>>(
      planDeviationSnapshotProvider,
      (previous, next) {
        next.whenData((snapshot) {
          if (!snapshot.shouldPrompt) {
            return;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(_handlePlanDeviation(snapshot));
            }
          });
        });
      },
    );

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1200;
    final isTablet = width >= 700 && width < 1200;

    if (isDesktop) {
      final showRightPanel = width >= 1000;
      return Scaffold(
        endDrawer: showRightPanel ? null : const UnscheduledTaskPanel(),
        body: Row(
          children: [
            Container(
              width: 236,
              color: Theme.of(context).cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'FlowPlan',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const ServerConnectionIndicator(compact: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showQuickAdd,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('\u65b0\u5efa'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _items.length; i++)
                    _NavItem(
                      icon: _currentIndex == i ? _items[i].activeIcon : _items[i].icon,
                      label: _items[i].label,
                      selected: _currentIndex == i,
                      onTap: () => _navigate(i),
                    ),
                  const Divider(height: 20, indent: 12, endIndent: 12),
                  Expanded(
                    child: _SidebarBooks(onManage: _showBooksPage),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _autoSchedule,
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text('\u4e00\u952e\u91cd\u6392'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: widget.child),
                  const QuickAddBar(),
                ],
              ),
            ),
            if (showRightPanel) ...[
              const VerticalDivider(width: 1),
              const UnscheduledTaskPanel(),
            ],
          ],
        ),
      );
    }

    if (isTablet) {
      return Scaffold(
        endDrawer: const UnscheduledTaskPanel(),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: _navigate,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 12),
                child: ServerConnectionIndicator(compact: true),
              ),
              destinations: _items
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(growable: false),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: widget.child),
                  const QuickAddBar(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showQuickAdd,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      );
    }

    return Scaffold(
      endDrawer: const UnscheduledTaskPanel(),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Text(
                    'FlowPlan',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  const ServerConnectionIndicator(),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
          const QuickAddBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _navigate,
        destinations: _items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              ),
            )
            .toList(growable: false),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showQuickAdd,
        backgroundColor: AppColors.primary,
        mini: true,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet();

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _titleController = TextEditingController();
  int _tab = 0;
  int _taskDuration = 60;
  int _taskPriority = 2;
  late DateTime _eventStart;
  late DateTime _eventEnd;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _tab = _tabController.index);
        }
      });
    final now = DateTime.now();
    final rounded = now.copyWith(
      hour: now.minute > 0 ? now.hour + 1 : now.hour,
      minute: 0,
      second: 0,
      millisecond: 0,
      microsecond: 0,
    );
    _eventStart = rounded;
    _eventEnd = rounded.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? _eventStart : _eventEnd;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _eventStart = result;
        if (!_eventEnd.isAfter(_eventStart)) {
          _eventEnd = _eventStart.add(const Duration(hours: 1));
        }
      } else if (result.isAfter(_eventStart)) {
        _eventEnd = result;
      }
    });
  }

  Future<void> _openFullEditor() async {
    Navigator.of(context).pop();
    final desktop = MediaQuery.of(context).size.width >= 700;
    if (desktop) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          child: SizedBox(
            width: 560,
            child: _tab == 0 ? const TaskDetailPage(taskId: null) : const EventDetailPage(eventId: null),
          ),
        ),
      );
      return;
    }
    context.go(_tab == 0 ? AppRoutes.taskCreate : AppRoutes.eventCreate);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      if (_tab == 0) {
        final booksRepo = ref.read(calendarBooksRepositoryProvider);
        final taskListId = await booksRepo.getOrCreateActiveTaskListId();
        final taskListDefaults = await booksRepo.getTaskListDefaults(
          taskListId,
          fallbackReminderMinutes: ref.read(reminderMinutesProvider),
        );
        final store = await ref.read(taskEventServerFirstStoreProvider.future);
        await store.createTask(<String, Object?>{
          'uid': const Uuid().v4(),
          'summary': title,
          'title': title,
          'durationMinutes': _taskDuration,
          'priorityLocal': _taskPriority,
          'isAutoScheduled': taskListDefaults.defaultIsAutoScheduled,
          'taskListId': taskListId,
          'reminderMinutesBefore':
              taskListDefaults.defaultReminderMinutesBefore,
        });
      } else {
        final booksRepo = ref.read(calendarBooksRepositoryProvider);
        final eventCalendarId =
            await booksRepo.getOrCreateWritableEventCalendarId();
        final eventCalendarDefaults =
            await booksRepo.getEventCalendarDefaults(eventCalendarId);
        final store = await ref.read(taskEventServerFirstStoreProvider.future);
        await store.createEvent(<String, Object?>{
          'uid': const Uuid().v4(),
          'summary': title,
          'title': title,
          'startAt': _eventStart.toIso8601String(),
          'endAt': _eventEnd.toIso8601String(),
          'isBlock': eventCalendarDefaults.defaultIsBlock,
          'eventCalendarId': eventCalendarId,
        });
        ref.read(selectedDateProvider.notifier).setDate(_eventStart);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tab == 0
                ? '\u4efb\u52a1\u300c$title\u300d\u5df2\u521b\u5efa'
                : '\u65e5\u7a0b\u300c$title\u300d\u5df2\u521b\u5efa',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u521b\u5efa\u5931\u8d25\uff1a$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _format(DateTime value) {
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$m/$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              tabs: const [Tab(text: '\u4efb\u52a1'), Tab(text: '\u65e5\u7a0b')],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: _tab == 0 ? '\u4efb\u52a1\u6807\u9898' : '\u65e5\u7a0b\u6807\u9898',
                  ),
                ),
                const SizedBox(height: 12),
                if (_tab == 0)
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _taskDuration,
                          decoration: const InputDecoration(labelText: '\u65f6\u957f'),
                          items: const [
                            DropdownMenuItem(value: 15, child: Text('15 \u5206\u949f')),
                            DropdownMenuItem(value: 30, child: Text('30 \u5206\u949f')),
                            DropdownMenuItem(value: 60, child: Text('1 \u5c0f\u65f6')),
                            DropdownMenuItem(value: 90, child: Text('1.5 \u5c0f\u65f6')),
                            DropdownMenuItem(value: 120, child: Text('2 \u5c0f\u65f6')),
                          ],
                          onChanged: (value) => setState(() => _taskDuration = value ?? 60),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _taskPriority,
                          decoration: const InputDecoration(labelText: '\u4f18\u5148\u7ea7'),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('\u9ad8')),
                            DropdownMenuItem(value: 2, child: Text('\u4e2d')),
                            DropdownMenuItem(value: 3, child: Text('\u4f4e')),
                          ],
                          onChanged: (value) => setState(() => _taskPriority = value ?? 2),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _pick(true),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: '\u5f00\u59cb'),
                            child: Text(_format(_eventStart)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pick(false),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: '\u7ed3\u675f'),
                            child: Text(_format(_eventEnd)),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openFullEditor,
                    child: const Text('\u66f4\u591a\u8bbe\u7f6e'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('\u5feb\u901f\u521b\u5efa'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBooks extends ConsumerWidget {
  const _SidebarBooks({required this.onManage});

  final VoidCallback onManage;

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(allEventCalendarsProvider);
    final lists = ref.watch(allTaskListsProvider);
    final repo = ref.read(calendarBooksRepositoryProvider);

    Widget buildSection(
      String title,
      AsyncValue<List<dynamic>> data,
      Future<void> Function(int id, bool value) toggle,
      String Function(dynamic item) labelOf,
      String Function(dynamic item) colorOf,
      bool Function(dynamic item) visibleOf,
      int Function(dynamic item) idOf,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey, letterSpacing: 0.8))),
                GestureDetector(
                  onTap: onManage,
                  child: const Icon(Icons.settings_outlined, size: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          data.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (items) => Column(
              children: items
                  .map(
                    (item) => InkWell(
                      onTap: () => toggle(idOf(item), !visibleOf(item)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: visibleOf(item) ? _parseColor(colorOf(item)) : Colors.grey.withValues(alpha: 0.3), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                labelOf(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: visibleOf(item) ? null : Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSection(
            '\u65e5\u5386\u672c',
            calendars,
            repo.toggleEventCalendarVisible,
            (item) => (item as EventCalendar).name,
            (item) => (item as EventCalendar).colorHex,
            (item) => (item as EventCalendar).isVisible,
            (item) => (item as EventCalendar).id,
          ),
          const SizedBox(height: 8),
          buildSection(
            '\u4efb\u52a1\u672c',
            lists,
            repo.toggleTaskListVisible,
            (item) {
              final list = item as TaskList;
              final prefix = list.emoji == null || list.emoji!.trim().isEmpty ? '' : '${list.emoji!.trim()} ';
              return '$prefix${list.name}';
            },
            (item) => (item as TaskList).colorHex,
            (item) => (item as TaskList).isVisible,
            (item) => (item as TaskList).id,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? AppColors.primary : Theme.of(context).iconTheme.color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.primary : null),
            ),
          ],
        ),
      ),
    );
  }
}
