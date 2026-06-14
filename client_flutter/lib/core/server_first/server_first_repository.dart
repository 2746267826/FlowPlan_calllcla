import '../offline_queue/offline_mutation.dart';
import '../server_api/api_error.dart';
import '../server_api/client_api.dart';
import 'mutation_coordinator.dart';

enum ServerFirstWriteState {
  canonical,
  pending,
}

class ServerFirstWriteResult {
  const ServerFirstWriteResult._({
    required this.state,
    this.response,
    this.queuedMutation,
    this.error,
  });

  factory ServerFirstWriteResult.canonical(Map<String, dynamic> response) {
    return ServerFirstWriteResult._(
      state: ServerFirstWriteState.canonical,
      response: response,
    );
  }

  factory ServerFirstWriteResult.pending({
    required QueuedMutationResult queuedMutation,
    required Object error,
  }) {
    return ServerFirstWriteResult._(
      state: ServerFirstWriteState.pending,
      queuedMutation: queuedMutation,
      error: error,
    );
  }

  final ServerFirstWriteState state;
  final Map<String, dynamic>? response;
  final QueuedMutationResult? queuedMutation;
  final Object? error;

  bool get isCanonical => state == ServerFirstWriteState.canonical;
  bool get isPending => state == ServerFirstWriteState.pending;
}

class ServerFirstRepository {
  ServerFirstRepository({
    required ClientApi clientApi,
    required MutationCoordinator mutationCoordinator,
  })  : _clientApi = clientApi,
        _mutationCoordinator = mutationCoordinator;

  final ClientApi _clientApi;
  final MutationCoordinator _mutationCoordinator;

  Future<Map<String, dynamic>> tasks({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) {
    return _clientApi.tasks(from: from, to: to, q: q, limit: limit);
  }

  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload, {
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'task_item',
      action: OfflineMutationAction.create,
      payload: payload,
      remoteWrite: () => _clientApi.createTask(payload),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<ServerFirstWriteResult> updateTask({
    required String id,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'task_item',
      action: OfflineMutationAction.update,
      localId: id,
      serverId: id,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
      payload: patch,
      remoteWrite: () => _clientApi.updateTask(
        id: id,
        patch: _withBaseVersion(patch, baseServerVersion),
      ),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<ServerFirstWriteResult> completeTask({
    required String id,
    Map<String, Object?> body = const <String, Object?>{},
    int? baseServerVersion,
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'task_item',
      action: OfflineMutationAction.update,
      localId: id,
      serverId: id,
      baseServerVersion: baseServerVersion,
      changedFields: const <String>['status', 'completedAt'],
      payload: <String, Object?>{
        'status': 'done',
        'completedAt': DateTime.now().toIso8601String(),
        ...body,
      },
      remoteWrite: () => _clientApi.completeTask(
        id: id,
        body: _withBaseVersion(body, baseServerVersion),
      ),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<ServerFirstWriteResult> deleteTask({
    required String id,
    int? baseServerVersion,
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'task_item',
      action: OfflineMutationAction.delete,
      localId: id,
      serverId: id,
      baseServerVersion: baseServerVersion,
      payload: <String, Object?>{'id': id},
      remoteWrite: () => _clientApi.deleteTask(id),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<Map<String, dynamic>> events({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) {
    return _clientApi.events(from: from, to: to, q: q, limit: limit);
  }

  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload, {
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'calendar_event',
      action: OfflineMutationAction.create,
      payload: payload,
      remoteWrite: () => _clientApi.createEvent(payload),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<ServerFirstWriteResult> updateEvent({
    required String id,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'calendar_event',
      action: OfflineMutationAction.update,
      localId: id,
      serverId: id,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
      payload: patch,
      remoteWrite: () => _clientApi.updateEvent(
        id: id,
        patch: _withBaseVersion(patch, baseServerVersion),
      ),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<ServerFirstWriteResult> deleteEvent({
    required String id,
    int? baseServerVersion,
    bool queueOnFailure = false,
  }) {
    return _write(
      objectType: 'calendar_event',
      action: OfflineMutationAction.delete,
      localId: id,
      serverId: id,
      baseServerVersion: baseServerVersion,
      payload: <String, Object?>{'id': id},
      remoteWrite: () => _clientApi.deleteEvent(id),
      queueOnFailure: queueOnFailure,
    );
  }

  Future<Map<String, dynamic>> actualRecords({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) {
    return _clientApi.actualRecords(from: from, to: to, limit: limit);
  }

  Future<Map<String, dynamic>> effectiveSettings() {
    return _clientApi.effectiveSettings();
  }

  Future<ServerFirstWriteResult> _write({
    required String objectType,
    required OfflineMutationAction action,
    required Map<String, Object?> payload,
    required Future<Map<String, dynamic>> Function() remoteWrite,
    String? localId,
    String? serverId,
    int? baseServerVersion,
    List<String>? changedFields,
    bool queueOnFailure = false,
  }) async {
    try {
      final response = await remoteWrite();
      return ServerFirstWriteResult.canonical(response);
    } on ApiError catch (error) {
      if (!queueOnFailure) {
        rethrow;
      }
      final queued = await _queue(
        objectType: objectType,
        action: action,
        payload: payload,
        localId: localId,
        serverId: serverId,
        baseServerVersion: baseServerVersion,
        changedFields: changedFields,
      );
      return ServerFirstWriteResult.pending(
        queuedMutation: queued,
        error: error,
      );
    } catch (error) {
      if (!queueOnFailure) {
        rethrow;
      }
      final queued = await _queue(
        objectType: objectType,
        action: action,
        payload: payload,
        localId: localId,
        serverId: serverId,
        baseServerVersion: baseServerVersion,
        changedFields: changedFields,
      );
      return ServerFirstWriteResult.pending(
        queuedMutation: queued,
        error: error,
      );
    }
  }

  Future<QueuedMutationResult> _queue({
    required String objectType,
    required OfflineMutationAction action,
    required Map<String, Object?> payload,
    String? localId,
    String? serverId,
    int? baseServerVersion,
    List<String>? changedFields,
  }) {
    return _mutationCoordinator.enqueueBusinessMutation(
      objectType: objectType,
      action: action,
      payload: payload,
      localId: localId,
      serverId: serverId,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
    );
  }

  Map<String, Object?> _withBaseVersion(
    Map<String, Object?> payload,
    int? baseServerVersion,
  ) {
    if (baseServerVersion == null) {
      return payload;
    }
    return <String, Object?>{
      ...payload,
      'baseServerVersion': baseServerVersion,
    };
  }
}
