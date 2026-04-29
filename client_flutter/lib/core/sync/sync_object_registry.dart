class SyncObjectType {
  const SyncObjectType._(this.key);

  final String key;

  static const calendarBook = SyncObjectType._('calendar_book');
  static const taskList = SyncObjectType._('task_list');
  static const calendarEvent = SyncObjectType._('calendar_event');
  static const taskItem = SyncObjectType._('task_item');
  static const taskScheduleSegment = SyncObjectType._('task_schedule_segment');
  static const auditLog = SyncObjectType._('audit_log');
  static const userSetting = SyncObjectType._('user_setting');
  static const actualActivityLog = SyncObjectType._('actual_activity_log');
  static const activitySegment = SyncObjectType._('activity_segment');
  static const activityInterpretation =
      SyncObjectType._('activity_interpretation');
  static const taskWorkLog = SyncObjectType._('task_work_log');
  static const reportDocument = SyncObjectType._('report_document');
  static const diaryEntry = SyncObjectType._('diary_entry');
  static const reportPushDelivery = SyncObjectType._('report_push_delivery');
  static const fileFolder = SyncObjectType._('file_folder');
  static const fileItem = SyncObjectType._('file_item');
  static const fileContextLink = SyncObjectType._('file_context_link');
  static const fileFolderUsage = SyncObjectType._('file_folder_usage');
  static const fileVersionRecord = SyncObjectType._('file_version_record');

  static const p1Objects = <SyncObjectType>[
    calendarBook,
    taskList,
    calendarEvent,
    taskItem,
    taskScheduleSegment,
    auditLog,
    userSetting,
    actualActivityLog,
    activitySegment,
    activityInterpretation,
    taskWorkLog,
    reportDocument,
    diaryEntry,
    reportPushDelivery,
    fileFolder,
    fileItem,
    fileContextLink,
    fileFolderUsage,
    fileVersionRecord,
  ];
}

class SyncObjectRegistry {
  const SyncObjectRegistry(this.objectTypes);

  final List<SyncObjectType> objectTypes;

  factory SyncObjectRegistry.p1() {
    return const SyncObjectRegistry(SyncObjectType.p1Objects);
  }

  bool contains(String objectType) {
    return objectTypes.any((type) => type.key == objectType);
  }
}
