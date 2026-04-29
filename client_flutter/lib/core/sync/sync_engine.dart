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

  Future<Map<String, dynamic>> pullChanges() async {
    final cursor = await _cursorStore.readPullCursor();
    final response = await _apiClient.getJson(
      '/sync/pull',
      query: cursor == null || cursor.isEmpty ? null : {'cursor': cursor},
    );
    final appliedChangeIds =
        await _changeApplier?.applyPullResponse(response) ?? const <String>[];
    final nextCursor = response['nextCursor'] as String?;
    if (nextCursor != null && nextCursor.isNotEmpty) {
      await _cursorStore.savePullCursor(nextCursor);
      await _apiClient.postJson(
        '/sync/ack',
        body: {
          'cursor': nextCursor,
          'appliedChangeIds': appliedChangeIds,
        },
      );
    }
    await _cursorStore.markPulledAt(DateTime.now());
    return response;
  }
}
