class ServerSyncResult {
  const ServerSyncResult({
    required this.acceptedCount,
    required this.conflictCount,
    required this.rejectedCount,
  });

  final int acceptedCount;
  final int conflictCount;
  final int rejectedCount;
}
