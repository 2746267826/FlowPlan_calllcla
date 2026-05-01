enum OutlookManagedCalendarKind {
  scheduleBook,
  taskMirrorBook,
}

class OutlookSyncPolicy {
  static const scheduleBookPrefix =
      'FlowPlanV2 \u65e5\u5386\u672c - ';
  static const taskMirrorBookPrefix =
      'FlowPlanV2 \u4efb\u52a1\u672c - ';

  static String buildManagedCalendarName({
    required OutlookManagedCalendarKind kind,
    required String containerName,
  }) {
    final safeName = containerName.trim();
    final prefix = switch (kind) {
      OutlookManagedCalendarKind.scheduleBook => scheduleBookPrefix,
      OutlookManagedCalendarKind.taskMirrorBook => taskMirrorBookPrefix,
    };
    return '$prefix$safeName';
  }

  static bool isFlowPlanV2ManagedCalendarName(String rawName) {
    final name = rawName.trim();
    return name.startsWith(scheduleBookPrefix) ||
        name.startsWith(taskMirrorBookPrefix);
  }

  static bool isTaskMirrorCalendarName(String rawName) =>
      rawName.trim().startsWith(taskMirrorBookPrefix);

  static String localCalendarDescription(String calendarName) {
    if (isTaskMirrorCalendarName(calendarName)) {
      return 'Outlook \u4e2d\u7684 FlowPlanV2 \u4efb\u52a1\u955c\u50cf\u65e5\u5386\u672c\uff0c\u540e\u7eed\u53cc\u5411\u540c\u6b65\u53ea\u4f1a\u5728\u8fd9\u7c7b\u4e13\u5c5e\u5bb9\u5668\u5185\u8fdb\u884c\u3002';
    }
    if (isFlowPlanV2ManagedCalendarName(calendarName)) {
      return 'Outlook \u4e2d\u7684 FlowPlanV2 \u4e13\u5c5e\u65e5\u5386\u672c\uff0c\u53ef\u4f5c\u4e3a\u540e\u7eed\u53d7\u63a7\u53cc\u5411\u540c\u6b65\u5bb9\u5668\u4f7f\u7528\u3002';
    }
    return 'Outlook \u4e2d\u7684\u5916\u90e8\u65e5\u5386\u672c\uff0c\u9ed8\u8ba4\u6309\u53ea\u8bfb\u65b9\u5f0f\u540c\u6b65\u5230 FlowPlanV2\u3002';
  }
}
