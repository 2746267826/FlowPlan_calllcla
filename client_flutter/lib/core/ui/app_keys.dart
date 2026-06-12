import 'package:flutter/widgets.dart';

class AppKeys {
  const AppKeys();

  static const shellCreateTask = Key('flowplan.shell.create_task');
  static const shellTimeline = Key('flowplan.shell.timeline');
  static const shellWeek = Key('flowplan.shell.week');
  static const shellMonth = Key('flowplan.shell.month');
  static const shellTracker = Key('flowplan.shell.tracker');
  static const shellReports = Key('flowplan.shell.reports');
  static const shellFiles = Key('flowplan.shell.files');
  static const shellSettings = Key('flowplan.shell.settings');
  static const quickAddTaskTab = Key('flowplan.quick_add.task_tab');
  static const quickAddEventTab = Key('flowplan.quick_add.event_tab');
  static const taskSummaryField = Key('flowplan.task.summary');
  static const taskSaveButton = Key('flowplan.task.save');
  static const taskCompleteButton = Key('flowplan.task.complete');
  static const eventSummaryField = Key('flowplan.event.summary');
  static const eventSaveButton = Key('flowplan.event.save');
  static const trackerStartButton = Key('flowplan.tracker.start');
  static const trackerReviewConfirmButton =
      Key('flowplan.tracker.review_confirm');
  static const trackerInputHistoryPreviousPageButton =
      Key('flowplan.tracker.input_history.previous_page');
  static const trackerInputHistoryNextPageButton =
      Key('flowplan.tracker.input_history.next_page');
  static const trackerLogHistoryPreviousPageButton =
      Key('flowplan.tracker.log_history.previous_page');
  static const trackerLogHistoryNextPageButton =
      Key('flowplan.tracker.log_history.next_page');
  static const reportGenerateButton = Key('flowplan.report.generate');
  static const fileContextSavePreviewButton =
      Key('flowplan.file_context.save_preview');
  static const fileTransferStartButton = Key('flowplan.file.transfer_start');
  static const syncRunButton = Key('flowplan.sync.run');
  static const settingsSaveButton = Key('flowplan.settings.save');
  static const aiChatClearButton = Key('flowplan.ai_chat.clear');
  static const webShellToday = Key('flowplan.web_shell.today');
  static const webShellEvents = Key('flowplan.web_shell.events');
  static const webShellTasks = Key('flowplan.web_shell.tasks');
  static const webShellDrive = Key('flowplan.web_shell.drive');
  static const webShellTracking = Key('flowplan.web_shell.tracking');
  static const webShellReports = Key('flowplan.web_shell.reports');
  static const webShellSettings = Key('flowplan.web_shell.settings');
  static const webShellRefreshConnection =
      Key('flowplan.web_shell.refresh_connection');
  static const webTasksCreateButton = Key('flowplan.web.tasks.create');
  static const webTasksRefreshButton = Key('flowplan.web.tasks.refresh');
}
