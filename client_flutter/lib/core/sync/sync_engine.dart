import '../server_api/api_client.dart';
import 'sync_cursor_store.dart';
import '../offline_queue/offline_mutation_runner.dart';
import 'server_sync_change_applier.dart';
import 'sync_result.dart';

class ServerSyncEngine {
  ServerSyncEngine({
    required ApiClient apiClient,
    required SyncCursorStore cursorStore,
    required OfflineMutationRunner offlineMutationRunner,
    ServerSyncChangeApplier? changeApplier,
  })  : _apiClient = apiClient,
        _cursorStore = cursorStore,
        _offlineMutationRunner = offlineMutationRunner,
        _changeApplier = changeApplier;

  final ApiClient _apiClient;
  final SyncCursorStore _cursorStore;
  final OfflineMutationRunner _offlineMutationRunner;
  final ServerSyncChangeApplier? _changeApplier;

  Future<ServerSyncResult> pushPending() async {
    final pushed = await _offlineMutationRunner.pushPending(_apiClient);
    if (pushed.acceptedCount > 0) {
      await _cursorStore.markPushedAt(DateTime.now());
    }
    return pushed;
  }

  Future<Map<String, dynamic>> refreshCacheFromServer({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) {
    return pullChanges(limit: limit, onProgress: onProgress);
  }

  Future<Map<String, dynamic>> pullChanges({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) async {
    var cursor = await _cursorStore.readPullCursor();
    var pageCount = 0;
    var pulledChanges = 0;
    var appliedChanges = 0;
    var skippedChanges = 0;
    var failedChanges = 0;
    var repairedOrphanCalendarEvents = 0;
    final perType = <String, int>{};
    final applyErrors = <String>[];
    final allChanges = <Object?>[];
    Map<String, dynamic> latestResponse = const <String, dynamic>{};

    while (true) {
      final query = <String, String>{
        'limit': limit.toString(),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      };
      final response = await _apiClient.getJson('/sync/pull', query: query);
      latestResponse = response;
      pageCount++;
      final rawChanges = response['changes'];
      final changes = rawChanges is List ? rawChanges : const <Object?>[];
      allChanges.addAll(changes);
      pulledChanges += changes.length;
      onProgress?.call(pulledChanges, pageCount);

      final applyResult = await _changeApplier?.applyPullResponse(response);
      if (applyResult != null) {
        appliedChanges += applyResult.applied;
        skippedChanges += applyResult.skipped;
        failedChanges += applyResult.failed;
        repairedOrphanCalendarEvents += applyResult.orphanCalendarEvents;
        applyErrors.addAll(applyResult.errors);
        for (final entry in applyResult.perType.entries) {
          perType.update(entry.key, (value) => value + entry.value,
              ifAbsent: () => entry.value);
        }
      }
      if (applyResult?.hasFailures == true) {
        throw StateError(
          'Failed to apply server changes: ${applyResult!.errors.take(3).join('; ')}',
        );
      }
      final appliedChangeIds =
          applyResult?.appliedChangeIds ?? const <String>[];
      final nextCursor = response['nextCursor'] as String?;
      if (nextCursor != null && nextCursor.isNotEmpty) {
        await _apiClient.postJson(
          '/sync/ack',
          body: {
            'cursor': nextCursor,
            'appliedChangeIds': appliedChangeIds,
          },
        );
        await _cursorStore.savePullCursor(nextCursor);
      }

      if (changes.length < limit ||
          nextCursor == null ||
          nextCursor == cursor) {
        break;
      }
      cursor = nextCursor;
    }

    await _cursorStore.markPulledAt(DateTime.now());
    final finalOrphanRepair =
        await _changeApplier?.repairOutlookOrphanEvents() ?? 0;
    repairedOrphanCalendarEvents += finalOrphanRepair;
    return <String, dynamic>{
      ...latestResponse,
      'changes': allChanges,
      'pageCount': pageCount,
      'pulledChanges': pulledChanges,
      'appliedChanges': appliedChanges,
      'skippedChanges': skippedChanges,
      'failedChanges': failedChanges,
      'perType': perType,
      'orphanCalendarEvents': repairedOrphanCalendarEvents,
      if (applyErrors.isNotEmpty)
        'applyErrors': applyErrors.take(5).toList(growable: false),
    };
  }
}
