// CalendarShell — 三端自适应主骨架（导航 + 内容区）
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/providers/app_providers.dart';
import '../../task/presentation/quick_add_bar.dart';
import '../../task/presentation/task_detail_page.dart';
import '../../task/presentation/unscheduled_task_panel.dart';
import '../../../features/scheduler/scheduler_engine.dart';
import 'event_detail_page.dart';
import 'calendar_books_page.dart';

class CalendarShell extends ConsumerStatefulWidget {
  final Widget child;
  const CalendarShell({super.key, required this.child});

  @override
  ConsumerState<CalendarShell> createState() => _CalendarShellState();
}

class _CalendarShellState extends ConsumerState<CalendarShell> {
  int _selectedIndex = 0;

  static const _navItems = [
    (
      icon: Icons.view_day_outlined,
      activeIcon: Icons.view_day_rounded,
      label: '时间轴',
      route: '/timeline'
    ),
    (
      icon: Icons.calendar_view_week_outlined,
      activeIcon: Icons.calendar_view_week_rounded,
      label: '本周',
      route: '/week'
    ),
    (
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      label: '月视图',
      route: '/month'
    ),
    (
      icon: Icons.track_changes_outlined,
      activeIcon: Icons.track_changes_rounded,
      label: '追踪',
      route: '/tracker'
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
      route: '/settings'
    ),
  ];

  void _navigate(int index) {
    setState(() => _selectedIndex = index);
    context.go(_navItems[index].route);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1200;
    final isTablet = width >= 600 && width < 1200;

    if (isDesktop) {
      return _buildDesktopLayout(context);
    } else if (isTablet) {
      return _buildTabletLayout(context);
    } else {
      return _buildMobileLayout(context);
    }
  }

  // ─── 桌面三栏布局 ───────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(BuildContext context) {
    final showRightPanel = MediaQuery.of(context).size.width >= 1000;
    return Scaffold(
      endDrawer: showRightPanel ? null : const UnscheduledTaskPanel(),
      body: Row(
        children: [
          // 左侧固定导航栏
          Container(
            width: 220,
            color: Theme.of(context).cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('FlowPlan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          )),
                ),
                const SizedBox(height: 16),
                // ── 新建任务按钮 ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showQuickAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建任务'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final selected = _selectedIndex == i;
                  return _DesktopNavItem(
                    icon: selected ? item.activeIcon : item.icon,
                    label: item.label,
                    selected: selected,
                    onTap: () => _navigate(i),
                  );
                }),
                const SizedBox(height: 8),
                const Divider(height: 1, indent: 12, endIndent: 12),
                const SizedBox(height: 4),
                // ── 日历本列表（事件日历 + 任务清单）─────
                _SidebarCalendarList(ref: ref),
                const Spacer(),
                // ── 一键重排按钮 ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final engine = ref.read(schedulerEngineProvider);
                        final date = ref.read(selectedDateProvider);
                        final count = await engine.autoSchedule(date);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(count > 0
                                  ? '已自动排入 $count 个任务'
                                  : '没有可排入的任务（或今天已满）'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('一键重排'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // 主内容区（含底部活动追踪栏）
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
          ]
        ],
      ),
    );
  }

  // ─── 平板双栏布局 ────────────────────────────────────────────────────────────
  Widget _buildTabletLayout(BuildContext context) {
    return Scaffold(
      endDrawer: const UnscheduledTaskPanel(),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _navigate,
            labelType: NavigationRailLabelType.all,
            destinations: _navItems
                .map((item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: Text(item.label),
                    ))
                .toList(),
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

  // ─── 手机底部导航布局 ─────────────────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      endDrawer: const UnscheduledTaskPanel(),
      body: Column(
        children: [
          Expanded(child: widget.child),
          // 底部快速打卡栏
          const QuickAddBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _navigate,
        height: 64,
        destinations: _navItems
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.activeIcon),
                  label: item.label,
                ))
            .toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showQuickAdd,
        backgroundColor: AppColors.primary,
        mini: true,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showQuickAdd() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickAddSheet(),
    );
  }
}

// ─── 桌面导航项组件 ─────────────────────────────────────────────────────────────
class _DesktopNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
            Icon(
              icon,
              size: 20,
              color: selected
                  ? AppColors.primary
                  : Theme.of(context).iconTheme.color,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 快速新建底部 Sheet：任务 / 日程 双 Tab ────────────────────────────────────
class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet();

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  int _tabIndex = 0; // 0 = 任务, 1 = 日程

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() => _tabIndex = _tabController.index));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tab 切换：任务 | 日程
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariantLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt_outlined, size: 15),
                        SizedBox(width: 4),
                        Text('任务'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_outlined, size: 15),
                        SizedBox(width: 4),
                        Text('日程'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 内容区
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _tabIndex == 0
                ? _TaskQuickForm(titleController: _titleController)
                : _EventQuickForm(titleController: _titleController),
          ),
          const SizedBox(height: 12),

          // 底部按钮组
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                // 「更多设置」→ 桌面端对话框，手机/平板路由跳转
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 关闭底部弹窗
                      final isDesktopOrTablet =
                          MediaQuery.of(context).size.width >= 700;
                      if (isDesktopOrTablet) {
                        // 桌面端：居中对话框，非全屏
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            insetPadding: const EdgeInsets.symmetric(
                                horizontal: 60, vertical: 40),
                            child: SizedBox(
                              width: 560,
                              child: _tabIndex == 0
                                  ? const _TaskDetailDialog()
                                  : const _EventDetailDialog(),
                            ),
                          ),
                        );
                      } else {
                        // 手机端：路由跳转
                        context.go(_tabIndex == 0
                            ? AppRoutes.taskCreate
                            : AppRoutes.eventCreate);
                      }
                    },
                    child: const Text('更多设置'),
                  ),
                ),
                const SizedBox(width: 12),
                // 「快速创建」
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_titleController.text.trim().isEmpty) return;
                      final title = _titleController.text.trim();
                      final nav = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      if (_tabIndex == 0) {
                        // ── 快速创建任务 ─────────────────────
                        final taskForm = context
                            .findAncestorStateOfType<_TaskQuickFormState>();
                        final repo = ref.read(taskRepositoryProvider);
                        await repo.create(TaskItemsCompanion.insert(
                          uid: const Uuid().v4(),
                          dtstamp: DateTime.now(),
                          summary: title,
                          durationMinutes: Value(taskForm?._duration ?? 60),
                          priorityLocal: Value(taskForm?._priority ?? 2),
                        ));
                        nav.pop();
                        messenger.showSnackBar(
                            SnackBar(content: Text('任务「$title」已创建')));
                      } else {
                        // ── 快速创建日程 ─────────────────────
                        final eventForm = context
                            .findAncestorStateOfType<_EventQuickFormState>();
                        final repo = ref.read(eventRepositoryProvider);
                        await repo.create(CalendarEventsCompanion.insert(
                          uid: const Uuid().v4(),
                          dtstamp: DateTime.now(),
                          summary: title,
                          dtstart: eventForm?._start ?? DateTime.now(),
                          dtend: Value(eventForm?._end),
                        ));
                        if (eventForm?._start != null) {
                          ref
                              .read(selectedDateProvider.notifier)
                              .setDate(eventForm!._start);
                        }
                        nav.pop();
                        messenger.showSnackBar(
                            SnackBar(content: Text('日程「$title」已创建')));
                      }
                    },
                    child: const Text('快速创建'),
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

// ── 任务快速表单 ──────────────────────────────────────────────────────────────
class _TaskQuickForm extends StatefulWidget {
  final TextEditingController titleController;
  const _TaskQuickForm({required this.titleController});

  @override
  State<_TaskQuickForm> createState() => _TaskQuickFormState();
}

class _TaskQuickFormState extends State<_TaskQuickForm> {
  int _duration = 60;
  int _priority = 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.titleController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '任务标题...',
            prefixIcon: Icon(Icons.task_alt_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // 时长
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _duration,
                decoration: const InputDecoration(
                  labelText: '时长',
                  prefixIcon: Icon(Icons.timer_outlined, size: 18),
                ),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15分钟')),
                  DropdownMenuItem(value: 30, child: Text('30分钟')),
                  DropdownMenuItem(value: 60, child: Text('1小时')),
                  DropdownMenuItem(value: 90, child: Text('1.5小时')),
                  DropdownMenuItem(value: 120, child: Text('2小时')),
                  DropdownMenuItem(value: 180, child: Text('3小时')),
                  DropdownMenuItem(value: 240, child: Text('4小时')),
                ],
                onChanged: (v) => setState(() => _duration = v ?? 60),
              ),
            ),
            const SizedBox(width: 12),
            // 优先级
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: '优先级',
                  prefixIcon: Icon(Icons.flag_outlined, size: 18),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('🔴 高')),
                  DropdownMenuItem(value: 2, child: Text('🟡 中')),
                  DropdownMenuItem(value: 3, child: Text('🟢 低')),
                ],
                onChanged: (v) => setState(() => _priority = v ?? 2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 日程快速表单 ──────────────────────────────────────────────────────────────
class _EventQuickForm extends StatefulWidget {
  final TextEditingController titleController;
  const _EventQuickForm({required this.titleController});

  @override
  State<_EventQuickForm> createState() => _EventQuickFormState();
}

class _EventQuickFormState extends State<_EventQuickForm> {
  DateTime _start = DateTime.now()
      .copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0);
  DateTime _end = DateTime.now()
      .copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0)
      .add(const Duration(hours: 1));

  String _format(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day}  $h:$m';
  }

  Future<void> _pick(bool isStart) async {
    final init = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (time == null || !mounted) return;
    final result =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = result;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      } else if (result.isAfter(_start)) {
        _end = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.titleController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '日程标题...',
            prefixIcon: Icon(Icons.event_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _pick(true),
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '开始',
                    prefixIcon: Icon(Icons.play_arrow_outlined, size: 18),
                  ),
                  child: Text(_format(_start),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => _pick(false),
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '结束',
                    prefixIcon: Icon(Icons.stop_outlined, size: 18),
                  ),
                  child:
                      Text(_format(_end), style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── 桌面端详情对话框包装 ─────────────────────────────────────────────────────
// 把 TaskDetailPage / EventDetailPage 嵌入 Dialog，无须全屏路由跳转

class _TaskDetailDialog extends StatelessWidget {
  const _TaskDetailDialog();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: const TaskDetailPage(taskId: null),
    );
  }
}

class _EventDetailDialog extends StatelessWidget {
  const _EventDetailDialog();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: const EventDetailPage(eventId: null),
    );
  }
}

// ─── 侧边栏日历本列表 ──────────────────────────────────────────────────────────
class _SidebarCalendarList extends ConsumerWidget {
  // ignore: unused_element
  final WidgetRef ref;
  const _SidebarCalendarList({required this.ref});

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventCals = ref.watch(allEventCalendarsProvider);
    final taskLists = ref.watch(allTaskListsProvider);
    final repo = ref.read(calendarBooksRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 日历本分组 ──────────────────────────────────────────────────────
        _SidebarGroupLabel(
          label: '日历本',
          onManage: () => showDialog(
            context: context,
            builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
              child: const SizedBox(width: 480, child: CalendarBooksPage()),
            ),
          ),
        ),
        eventCals.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (cals) => Column(
            children: cals
                .map((cal) => _SidebarCalItem(
                      color: _parseColor(cal.colorHex),
                      label: cal.name,
                      isVisible: cal.isVisible,
                      onToggle: (v) =>
                          repo.toggleEventCalendarVisible(cal.id, v),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),

        // ── 任务清单分组 ────────────────────────────────────────────────────
        _SidebarGroupLabel(label: '任务清单', onManage: null),
        taskLists.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (lists) => Column(
            children: lists
                .map((list) => _SidebarCalItem(
                      color: _parseColor(list.colorHex),
                      label: '${list.emoji ?? ''} ${list.name}',
                      isVisible: list.isVisible,
                      onToggle: (v) => repo.toggleTaskListVisible(list.id, v),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SidebarGroupLabel extends StatelessWidget {
  final String label;
  final VoidCallback? onManage;
  const _SidebarGroupLabel({required this.label, required this.onManage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.grey, fontSize: 10, letterSpacing: 0.8))),
          if (onManage != null)
            GestureDetector(
              onTap: onManage,
              child: const Icon(Icons.settings_outlined,
                  size: 14, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

class _SidebarCalItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isVisible;
  final ValueChanged<bool> onToggle;
  const _SidebarCalItem({
    required this.color,
    required this.label,
    required this.isVisible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!isVisible),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isVisible ? color : Colors.grey.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isVisible ? null : Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
          ],
        ),
      ),
    );
  }
}
