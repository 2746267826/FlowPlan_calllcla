// go_router 路由配置
import 'package:go_router/go_router.dart';
import '../../features/calendar/presentation/calendar_shell.dart';
import '../../features/calendar/presentation/timeline_view.dart';
import '../../features/calendar/presentation/week_view.dart';
import '../../features/calendar/presentation/month_view.dart';
import '../../features/calendar/presentation/event_detail_page.dart';
import '../../features/audit/presentation/data_operation_log_page.dart';
import '../../features/data_management/presentation/data_management_page.dart';
import '../../features/task/presentation/task_detail_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/tracker/presentation/input_heatmap_page.dart';
import '../../features/tracker/presentation/activity_review_page.dart';
import '../../features/tracker/presentation/tracker_input_history_page.dart';
import '../../features/tracker/presentation/tracker_page.dart';
import '../../features/tracker/presentation/tracker_log_history_page.dart';
import '../../features/ical/ical_import_export_page.dart';
import '../../features/files/presentation/file_context_page.dart';
import '../../features/files/presentation/file_transfer_center_page.dart';
import '../../features/reports/presentation/report_center_page.dart';
import '../../features/sync/outlook_settings_page.dart';
import '../../features/sync/server_sync_status_page.dart';

/// 路由名称常量
class AppRoutes {
  static const String timeline = '/timeline';
  static const String week = '/week';
  static const String month = '/month';
  static const String taskCreate = '/task/create';
  static const String taskDetail = '/task/:id';
  static const String eventCreate = '/event/create';
  static const String eventDetail = '/event/:id';
  static const String tracker = '/tracker';
  static const String activityReview = '/tracker/activity-review';
  static const String trackerDayDetails = '/tracker/day-details';
  static const String trackerLogHistory = '/tracker/log-history';
  static const String trackerInputHistory = '/tracker/input-history';
  static const String trackerInputHeatmap = '/tracker/input-heatmap';
  static const String reports = '/reports';
  static const String files = '/files';
  static const String fileTransfers = '/files/transfers';
  static const String auditLogs = '/audit-logs';
  static const String dataManagement = '/data-management';
  static const String settings = '/settings';
  static const String icalImportExport = '/ical';
  static const String outlookSync = '/outlook-sync';
  static const String serverSync = '/server-sync';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.timeline,
  debugLogDiagnostics: false,
  routes: [
    ShellRoute(
      builder: (context, state, child) => CalendarShell(
        currentRoute: state.uri.path,
        child: child,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.timeline,
          name: 'timeline',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TimelineView(),
          ),
        ),
        GoRoute(
          path: AppRoutes.week,
          name: 'week',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WeekView(),
          ),
        ),
        GoRoute(
          path: AppRoutes.month,
          name: 'month',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MonthView(),
          ),
        ),
        GoRoute(
          path: AppRoutes.tracker,
          name: 'tracker',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TrackerPage(),
          ),
        ),
        GoRoute(
          path: AppRoutes.reports,
          name: 'reports',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ReportCenterPage(),
          ),
        ),
        GoRoute(
          path: AppRoutes.files,
          name: 'files',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FileContextPage(),
          ),
        ),
        GoRoute(
          path: AppRoutes.fileTransfers,
          name: 'fileTransfers',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FileTransferCenterPage(),
          ),
        ),
        GoRoute(
          path: AppRoutes.settings,
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsPage(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.activityReview,
      name: 'activityReview',
      builder: (context, state) => const ActivityReviewPage(),
    ),
    GoRoute(
      path: AppRoutes.trackerDayDetails,
      name: 'trackerDayDetails',
      builder: (context, state) => const TrackerDayDetailsPage(),
    ),
    GoRoute(
      path: AppRoutes.trackerLogHistory,
      name: 'trackerLogHistory',
      builder: (context, state) => const TrackerLogHistoryPage(),
    ),
    GoRoute(
      path: AppRoutes.trackerInputHistory,
      name: 'trackerInputHistory',
      builder: (context, state) => const TrackerInputHistoryPage(),
    ),
    GoRoute(
      path: AppRoutes.trackerInputHeatmap,
      name: 'trackerInputHeatmap',
      builder: (context, state) => const InputHeatmapPage(),
    ),
    GoRoute(
      path: AppRoutes.auditLogs,
      name: 'auditLogs',
      builder: (context, state) => const DataOperationLogPage(),
    ),
    GoRoute(
      path: AppRoutes.dataManagement,
      name: 'dataManagement',
      builder: (context, state) => const DataManagementPage(),
    ),
    // ── 任务路由 ──────────────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.taskCreate,
      name: 'taskCreate',
      builder: (context, state) => const TaskDetailPage(taskId: null),
    ),
    GoRoute(
      path: AppRoutes.taskDetail,
      name: 'taskDetail',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return TaskDetailPage(taskId: id);
      },
    ),
    // ── 日程路由 ──────────────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.eventCreate,
      name: 'eventCreate',
      builder: (context, state) => const EventDetailPage(eventId: null),
    ),
    GoRoute(
      path: AppRoutes.eventDetail,
      name: 'eventDetail',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return EventDetailPage(eventId: id);
      },
    ),
    // ── iCalendar 导入导出 ────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.icalImportExport,
      name: 'icalImportExport',
      builder: (context, state) => const ICalImportExportPage(),
    ),
    // ── Outlook 同步设置 ──────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.outlookSync,
      name: 'outlookSync',
      builder: (context, state) => const OutlookSettingsPage(),
    ),
    GoRoute(
      path: AppRoutes.serverSync,
      name: 'serverSync',
      builder: (context, state) => const ServerSyncStatusPage(),
    ),
  ],
);
