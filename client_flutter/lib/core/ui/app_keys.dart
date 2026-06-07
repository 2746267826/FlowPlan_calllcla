import 'package:flutter/widgets.dart';

class AppKeys {
  const AppKeys._();

  static const shellCreateTask = Key('flowplan.shell.create_task');
  static const shellTimeline = Key('flowplan.shell.timeline');
  static const shellWeek = Key('flowplan.shell.week');
  static const shellMonth = Key('flowplan.shell.month');
  static const shellTracker = Key('flowplan.shell.tracker');
  static const shellReports = Key('flowplan.shell.reports');
  static const shellFiles = Key('flowplan.shell.files');
  static const shellSettings = Key('flowplan.shell.settings');
  static const taskSummaryField = Key('flowplan.task.summary');
  static const taskSaveButton = Key('flowplan.task.save');
  static const taskCompleteButton = Key('flowplan.task.complete');
  static const eventSummaryField = Key('flowplan.event.summary');
  static const eventSaveButton = Key('flowplan.event.save');
  static const trackerStartButton = Key('flowplan.tracker.start');
  static const trackerReviewConfirmButton =
      Key('flowplan.tracker.review_confirm');
  static const reportGenerateButton = Key('flowplan.report.generate');
  static const fileTransferStartButton = Key('flowplan.file.transfer_start');
  static const syncRunButton = Key('flowplan.sync.run');
  static const settingsSaveButton = Key('flowplan.settings.save');
}
