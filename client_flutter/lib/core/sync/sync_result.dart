class ServerSyncResult {
  const ServerSyncResult({
    required this.acceptedCount,
    required this.conflictCount,
    required this.rejectedCount,
    this.pendingCount = 0,
  });

  final int acceptedCount;
  final int conflictCount;
  final int rejectedCount;
  final int pendingCount;

  int get processedCount => acceptedCount + conflictCount + rejectedCount;
}
