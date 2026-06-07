import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppKeys expose stable ValueKey names for user workflow controls', () {
    const expected = <Key>{
      Key('flowplan.shell.create_task'),
      Key('flowplan.shell.timeline'),
      Key('flowplan.shell.week'),
      Key('flowplan.shell.month'),
      Key('flowplan.task.summary'),
      Key('flowplan.task.save'),
      Key('flowplan.sync.run'),
    };

    expect(
      <Key>{
        AppKeys.shellCreateTask,
        AppKeys.shellTimeline,
        AppKeys.shellWeek,
        AppKeys.shellMonth,
        AppKeys.taskSummaryField,
        AppKeys.taskSaveButton,
        AppKeys.syncRunButton,
      },
      expected,
    );
  });
}
