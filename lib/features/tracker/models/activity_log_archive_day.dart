class ActivityLogArchiveDay {
  final DateTime date;
  final String dayKey;
  final String filePath;
  final int fileSizeBytes;

  const ActivityLogArchiveDay({
    required this.date,
    required this.dayKey,
    required this.filePath,
    required this.fileSizeBytes,
  });
}
