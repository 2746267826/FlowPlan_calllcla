import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../scheduler/scheduler_engine.dart';
import '../../task/presentation/quick_add_bar.dart';
import '../../task/presentation/task_detail_page.dart';
import '../../task/presentation/unscheduled_task_panel.dart';
import 'calendar_books_page.dart';
import 'event_detail_page.dart';

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
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '\u8bbe\u7f6e',
      route: AppRoutes.settings,
    ),
  ];

  int get _currentIndex {
    final route = widget.currentRoute;
    if (route.startsWith(AppRoutes.week)) return 1;
    if (route.startsWith(AppRoutes.month)) return 2;
    if (route.startsWith(AppRoutes.tracker)) return 3;
    if (route.startsWith(AppRoutes.settings)) return 4;
    return 0;
  }

  void _navigate(int index) => context.go(_items[index].route);

  Future<void> _autoSchedule() async {
    final date = ref.read(selectedDateProvider);
    final count = await ref.read(schedulerEngineProvider).autoSchedule(date);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? '\u5df2\u81ea\u52a8\u6392\u5165 $count \u4e2a\u4efb\u52a1'
              : '\u6ca1\u6709\u53ef\u6392\u5165\u7684\u4efb\u52a1\uff0c\u6216\u4eca\u5929\u5df2\u6392\u6ee1',
        ),
      ),
    );
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
                    child: Text(
                      'FlowPlan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
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
        final taskListId = await ref.read(calendarBooksRepositoryProvider).getOrCreateActiveTaskListId();
        await ref.read(taskRepositoryProvider).create(
              TaskItemsCompanion.insert(
                uid: const Uuid().v4(),
                dtstamp: DateTime.now(),
                summary: title,
                durationMinutes: Value(_taskDuration),
                priorityLocal: Value(_taskPriority),
                taskListId: Value(taskListId),
              ),
            );
      } else {
        final eventCalendarId =
            await ref.read(calendarBooksRepositoryProvider).getOrCreateWritableEventCalendarId();
        await ref.read(eventRepositoryProvider).create(
              CalendarEventsCompanion.insert(
                uid: const Uuid().v4(),
                dtstamp: DateTime.now(),
                summary: title,
                dtstart: _eventStart,
                dtend: Value(_eventEnd),
                eventCalendarId: Value(eventCalendarId),
              ),
            );
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
