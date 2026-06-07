import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed Outlook containers are identifiable by reserved prefixes', () {
    final scheduleName = OutlookSyncPolicy.buildManagedCalendarName(
      kind: OutlookManagedCalendarKind.scheduleBook,
      containerName: 'Work',
    );
    final mirrorName = OutlookSyncPolicy.buildManagedCalendarName(
      kind: OutlookManagedCalendarKind.taskMirrorBook,
      containerName: 'Inbox',
    );

    expect(OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(scheduleName), isTrue);
    expect(OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(mirrorName), isTrue);
    expect(OutlookSyncPolicy.isTaskMirrorCalendarName(mirrorName), isTrue);
    expect(OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName('Personal'), isFalse);
  });
}
