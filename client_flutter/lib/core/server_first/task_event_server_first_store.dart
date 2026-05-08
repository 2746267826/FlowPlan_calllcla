import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/calendar/data/event_repository.dart';
import '../../features/task/data/task_repository.dart';
import '../utils/payload_utils.dart';
import '../database/app_database.dart';
import '../offline_queue/offline_mutation.dart';
import '../sync/sync_object_registry.dart';
import '../sync/sync_object_state_store.dart';
import '../sync/sync_status.dart';
import 'mutation_coordinator.dart';
import 'server_first_repository.dart';

class TaskEventServerFirstStore {
  TaskEventServerFirstStore({
    required ServerFirstRepository repository,
    required MutationCoordinator mutationCoordinator,
    required SyncObjectStateStore stateStore,
    required AppDatabase database,
    required TaskRepository taskRepository,
    required EventRepository eventRepository,
  })  : _repository = repository,
        _mutationCoordinator = mutationCoordinator,
        _stateStore = stateStore,
        _database = database,
        _taskRepository = taskRepository,
        _eventRepository = eventRepository;

  final ServerFirstRepository _repository;
  final MutationCoordinator _mutationCoordinator;
  final SyncObjectStateStore _stateStore;
  final AppDatabase _database;
  final TaskRepository _taskRepository;
  final EventRepository _eventRepository;

  Future<Map<String, dynamic>> tasks({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) {
    return _repository.tasks(from: from, to: to, q: q, limit: limit);
  }

  Future<Map<String, dynamic>> events({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) {
    return _repository.events(from: from, to: to, q: q, limit: limit);
  }

  Future<ServerFirstWriteResult> createTask(Map<String, Object?> payload) async {
    final writePayload = _ensureUid(payload);
    try {
      final result = await _repository.createTask(
        writePayload,
        queueOnFailure: false,
      );
      final localId = await _createLocalTask(_payloadForLocal(result, writePayload));
      await _markSyncedFromResult(
        objectType: SyncObjectType.taskItem.key,
        localId: localId.toString(),
        fallbackUid: stringFromMap(writePayload, 'uid'),
        result: result,
      );
      return result;
    } catch (error) {
      final localId = await _createLocalTask(writePayload);
      final queued = await queueLegacyCacheMutation(
        objectType: SyncObjectType.taskItem.key,
        localId: localId.toString(),
        action: OfflineMutationAction.create,
        payload: writePayload,
        changedFields: writePayload.keys.toList(growable: false),
      );
      return ServerFirstWriteResult.pending(
        queuedMutation: queued,
        error: error,
      );
    }
  }

  Future<ServerFirstWriteResult> updateTask({
    required String id,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) {
    return _repository.updateTask(
      id: id,
      patch: patch,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
    );
  }

  Future<ServerFirstWriteResult> updateLocalTask({
    required int localId,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    final state = await _state(
      objectType: SyncObjectType.taskItem.key,
      localId: localId,
    );
    final serverId = _usableServerId(state);
    final version = baseServerVersion ?? state?.serverVersion;
    if (serverId != null) {
      try {
        final result = await _repository.updateTask(
          id: serverId,
          patch: patch,
          baseServerVersion: version,
          changedFields: changedFields,
          queueOnFailure: false,
        );
        await _updateLocalTask(localId, _payloadForLocal(result, patch));
        await _markSyncedFromResult(
          objectType: SyncObjectType.taskItem.key,
          localId: localId.toString(),
          fallbackUid: state?.uid ?? stringFromMap(patch, 'uid'),
          fallbackServerId: serverId,
          result: result,
        );
        return result;
      } catch (error) {
        await _updateLocalTask(localId, patch);
        final queued = await queueLegacyCacheMutation(
          objectType: SyncObjectType.taskItem.key,
          localId: localId.toString(),
          serverId: serverId,
          action: OfflineMutationAction.update,
          payload: patch,
          baseServerVersion: version,
          changedFields: changedFields,
        );
        return ServerFirstWriteResult.pending(
          queuedMutation: queued,
          error: error,
        );
      }
    }

    await _updateLocalTask(localId, patch);
    final queued = await queueLegacyCacheMutation(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      action: OfflineMutationAction.update,
      payload: patch,
      baseServerVersion: version,
      changedFields: changedFields,
    );
    return ServerFirstWriteResult.pending(
      queuedMutation: queued,
      error: StateError('Task has no server id yet. Queued locally.'),
    );
  }

  Future<ServerFirstWriteResult> completeTask({
    required String id,
    Map<String, Object?> body = const <String, Object?>{},
    int? baseServerVersion,
  }) {
    return _repository.completeTask(
      id: id,
      body: body,
      baseServerVersion: baseServerVersion,
    );
  }

  Future<ServerFirstWriteResult> completeLocalTask({
    required int localId,
    Map<String, Object?> body = const <String, Object?>{},
    int? baseServerVersion,
  }) {
    return updateLocalTask(
      localId: localId,
      patch: <String, Object?>{
        'status': 'done',
        'completedAt': DateTime.now().toIso8601String(),
        ...body,
      },
      baseServerVersion: baseServerVersion,
      changedFields: const <String>['status', 'completedAt'],
    );
  }

  Future<ServerFirstWriteResult> deleteTask({
    required String id,
    int? baseServerVersion,
  }) {
    return _repository.deleteTask(id: id, baseServerVersion: baseServerVersion);
  }

  Future<ServerFirstWriteResult> deleteLocalTask({
    required int localId,
    int? baseServerVersion,
  }) async {
    final state = await _state(
      objectType: SyncObjectType.taskItem.key,
      localId: localId,
    );
    final serverId = _usableServerId(state);
    final version = baseServerVersion ?? state?.serverVersion;
    if (serverId != null) {
      try {
        final result = await _repository.deleteTask(
          id: serverId,
          baseServerVersion: version,
          queueOnFailure: false,
        );
        await _taskRepository.delete(localId, audit: false);
        await _markSyncedFromResult(
          objectType: SyncObjectType.taskItem.key,
          localId: localId.toString(),
          fallbackUid: state?.uid,
          fallbackServerId: serverId,
          result: result,
        );
        return result;
      } catch (error) {
        await _taskRepository.delete(localId, audit: false);
        final queued = await queueLegacyCacheMutation(
          objectType: SyncObjectType.taskItem.key,
          localId: localId.toString(),
          serverId: serverId,
          action: OfflineMutationAction.delete,
          payload: <String, Object?>{'id': localId.toString(), 'uid': state?.uid},
          baseServerVersion: version,
        );
        return ServerFirstWriteResult.pending(
          queuedMutation: queued,
          error: error,
        );
      }
    }

    await _taskRepository.delete(localId, audit: false);
    final queued = await queueLegacyCacheMutation(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      action: OfflineMutationAction.delete,
      payload: <String, Object?>{'id': localId.toString(), 'uid': state?.uid},
      baseServerVersion: version,
    );
    return ServerFirstWriteResult.pending(
      queuedMutation: queued,
      error: StateError('Task has no server id yet. Queued locally.'),
    );
  }

  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload,
  ) async {
    final writePayload = _ensureUid(payload);
    try {
      final result = await _repository.createEvent(
        writePayload,
        queueOnFailure: false,
      );
      final localId =
          await _createLocalEvent(_payloadForLocal(result, writePayload));
      await _markSyncedFromResult(
        objectType: SyncObjectType.calendarEvent.key,
        localId: localId.toString(),
        fallbackUid: stringFromMap(writePayload, 'uid'),
        result: result,
      );
      return result;
    } catch (error) {
      final localId = await _createLocalEvent(writePayload);
      final queued = await queueLegacyCacheMutation(
        objectType: SyncObjectType.calendarEvent.key,
        localId: localId.toString(),
        action: OfflineMutationAction.create,
        payload: writePayload,
        changedFields: writePayload.keys.toList(growable: false),
      );
      return ServerFirstWriteResult.pending(
        queuedMutation: queued,
        error: error,
      );
    }
  }

  Future<ServerFirstWriteResult> updateEvent({
    required String id,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) {
    return _repository.updateEvent(
      id: id,
      patch: patch,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
    );
  }

  Future<ServerFirstWriteResult> updateLocalEvent({
    required int localId,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    final state = await _state(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId,
    );
    final serverId = _usableServerId(state);
    final version = baseServerVersion ?? state?.serverVersion;
    if (serverId != null) {
      try {
        final result = await _repository.updateEvent(
          id: serverId,
          patch: patch,
          baseServerVersion: version,
          changedFields: changedFields,
          queueOnFailure: false,
        );
        await _updateLocalEvent(localId, _payloadForLocal(result, patch));
        await _markSyncedFromResult(
          objectType: SyncObjectType.calendarEvent.key,
          localId: localId.toString(),
          fallbackUid: state?.uid ?? stringFromMap(patch, 'uid'),
          fallbackServerId: serverId,
          result: result,
        );
        return result;
      } catch (error) {
        await _updateLocalEvent(localId, patch);
        final queued = await queueLegacyCacheMutation(
          objectType: SyncObjectType.calendarEvent.key,
          localId: localId.toString(),
          serverId: serverId,
          action: OfflineMutationAction.update,
          payload: patch,
          baseServerVersion: version,
          changedFields: changedFields,
        );
        return ServerFirstWriteResult.pending(
          queuedMutation: queued,
          error: error,
        );
      }
    }

    await _updateLocalEvent(localId, patch);
    final queued = await queueLegacyCacheMutation(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      action: OfflineMutationAction.update,
      payload: patch,
      baseServerVersion: version,
      changedFields: changedFields,
    );
    return ServerFirstWriteResult.pending(
      queuedMutation: queued,
      error: StateError('Event has no server id yet. Queued locally.'),
    );
  }

  Future<ServerFirstWriteResult> deleteEvent({
    required String id,
    int? baseServerVersion,
  }) {
    return _repository.deleteEvent(id: id, baseServerVersion: baseServerVersion);
  }

  Future<ServerFirstWriteResult> deleteLocalEvent({
    required int localId,
    int? baseServerVersion,
  }) async {
    final state = await _state(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId,
    );
    final serverId = _usableServerId(state);
    final version = baseServerVersion ?? state?.serverVersion;
    if (serverId != null) {
      try {
        final result = await _repository.deleteEvent(
          id: serverId,
          baseServerVersion: version,
          queueOnFailure: false,
        );
        await _eventRepository.delete(localId, audit: false);
        await _markSyncedFromResult(
          objectType: SyncObjectType.calendarEvent.key,
          localId: localId.toString(),
          fallbackUid: state?.uid,
          fallbackServerId: serverId,
          result: result,
        );
        return result;
      } catch (error) {
        await _eventRepository.delete(localId, audit: false);
        final queued = await queueLegacyCacheMutation(
          objectType: SyncObjectType.calendarEvent.key,
          localId: localId.toString(),
          serverId: serverId,
          action: OfflineMutationAction.delete,
          payload: <String, Object?>{'id': localId.toString(), 'uid': state?.uid},
          baseServerVersion: version,
        );
        return ServerFirstWriteResult.pending(
          queuedMutation: queued,
          error: error,
        );
      }
    }

    await _eventRepository.delete(localId, audit: false);
    final queued = await queueLegacyCacheMutation(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      action: OfflineMutationAction.delete,
      payload: <String, Object?>{'id': localId.toString(), 'uid': state?.uid},
      baseServerVersion: version,
    );
    return ServerFirstWriteResult.pending(
      queuedMutation: queued,
      error: StateError('Event has no server id yet. Queued locally.'),
    );
  }

  Future<QueuedMutationResult> queueLegacyCacheMutation({
    required String objectType,
    required String localId,
    required OfflineMutationAction action,
    required Map<String, Object?> payload,
    String? serverId,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    final queued = await _mutationCoordinator.enqueueBusinessMutation(
      objectType: objectType,
      localId: localId,
      serverId: serverId,
      action: action,
      payload: payload,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
    );
    await _stateStore.markPending(
      objectType: objectType,
      localId: localId,
      serverId: serverId,
      uid: stringFromMap(payload, 'uid'),
      state: _pendingState(action),
    );
    return queued;
  }

  Future<SyncObjectState?> _state({
    required String objectType,
    required int localId,
  }) {
    return _stateStore.getState(
      objectType: objectType,
      localId: localId.toString(),
    );
  }

  Future<int> _createLocalTask(Map<String, Object?> payload) {
    return _taskRepository.create(_taskInsertCompanion(payload), audit: false);
  }

  Future<void> _updateLocalTask(
    int localId,
    Map<String, Object?> patch,
  ) async {
    await (_database.update(_database.taskItems)
          ..where((row) => row.id.equals(localId)))
        .write(_taskUpdateCompanion(patch));
  }

  Future<int> _createLocalEvent(Map<String, Object?> payload) {
    return _eventRepository.create(_eventInsertCompanion(payload), audit: false);
  }

  Future<void> _updateLocalEvent(
    int localId,
    Map<String, Object?> patch,
  ) async {
    await (_database.update(_database.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .write(_eventUpdateCompanion(patch));
  }

  TaskItemsCompanion _taskInsertCompanion(Map<String, Object?> payload) {
    final now = DateTime.now();
    final completedAt = dateAny(payload, const ['completedAt', 'completed']);
    final completed = boolAny(payload, const ['completed']) == true ||
        isDone(stringFromMap(payload, 'status'));
    return TaskItemsCompanion.insert(
      uid: stringFromMap(payload, 'uid') ?? const Uuid().v4(),
      dtstamp: dateAny(payload, const ['dtstamp']) ?? now,
      summary:
          stringAny(payload, const ['summary', 'title', 'name']) ?? '未命名任务',
      description: Value(stringFromMap(payload, 'description')),
      location: Value(stringFromMap(payload, 'location')),
      dtstart: Value(dateAny(payload, const ['dtstart', 'startAt'])),
      due: Value(dateAny(payload, const ['dueAt', 'due', 'dueDate'])),
      completed: Value(completedAt),
      priority: Value(intAny(payload, const ['priority']) ?? 0),
      status: Value(taskStatus(stringFromMap(payload, 'status'))),
      percentComplete: Value(
        intAny(payload, const ['percentComplete']) ?? (completed ? 100 : 0),
      ),
      categories: Value(stringFromMap(payload, 'categories') ?? '[]'),
      rrule: Value(stringFromMap(payload, 'rrule')),
      durationMinutes: Value(intAny(payload, const ['durationMinutes']) ?? 60),
      isSplittable: Value(boolAny(payload, const ['isSplittable']) ?? false),
      priorityLocal: Value(intAny(payload, const ['priorityLocal']) ?? 2),
      isAutoScheduled: Value(boolAny(payload, const ['isAutoScheduled']) ?? true),
      taskListId: Value(intAny(payload, const ['taskListId'])),
      tagId: Value(stringFromMap(payload, 'tagId')),
      isLocked: Value(boolAny(payload, const ['isLocked']) ?? false),
      reminderMinutesBefore: Value(
        intAny(payload, const ['reminderMinutesBefore']) ?? 15,
      ),
    );
  }

  TaskItemsCompanion _taskUpdateCompanion(Map<String, Object?> patch) {
    final status = stringFromMap(patch, 'status');
    final completed = dateAny(patch, const ['completedAt', 'completed']);
    return TaskItemsCompanion(
      uid: _valueString(patch, const ['uid']),
      dtstamp: Value(DateTime.now()),
      summary: _valueString(patch, const ['summary', 'title', 'name']),
      description: _nullableStringValue(patch, const ['description']),
      location: _nullableStringValue(patch, const ['location']),
      dtstart: _nullableDateValue(patch, const ['dtstart', 'startAt']),
      due: _nullableDateValue(patch, const ['dueAt', 'due', 'dueDate']),
      completed: patch.containsKey('completedAt') || patch.containsKey('completed')
          ? Value(completed)
          : const Value.absent(),
      priority: _valueInt(patch, const ['priority']),
      status: patch.containsKey('status')
          ? Value(taskStatus(status))
          : const Value.absent(),
      percentComplete: hasAny(patch, const ['percentComplete'])
          ? _valueInt(patch, const ['percentComplete'])
          : isDone(status)
              ? const Value(100)
              : const Value.absent(),
      categories: _valueString(patch, const ['categories']),
      rrule: _nullableStringValue(patch, const ['rrule']),
      durationMinutes: _valueInt(patch, const ['durationMinutes']),
      isSplittable: _valueBool(patch, const ['isSplittable']),
      priorityLocal: _valueInt(patch, const ['priorityLocal']),
      isAutoScheduled: _valueBool(patch, const ['isAutoScheduled']),
      taskListId: _nullableIntValue(patch, const ['taskListId']),
      tagId: _nullableStringValue(patch, const ['tagId']),
      isLocked: _valueBool(patch, const ['isLocked']),
      reminderMinutesBefore: _valueInt(patch, const ['reminderMinutesBefore']),
    );
  }

  CalendarEventsCompanion _eventInsertCompanion(Map<String, Object?> payload) {
    final now = DateTime.now();
    final start = dateAny(payload, const ['startAt', 'dtstart']) ?? now;
    return CalendarEventsCompanion.insert(
      uid: stringFromMap(payload, 'uid') ?? const Uuid().v4(),
      dtstamp: dateAny(payload, const ['dtstamp']) ?? now,
      summary:
          stringAny(payload, const ['summary', 'title', 'name']) ?? '未命名日程',
      description: Value(stringAny(payload, const ['description', 'notes'])),
      location: Value(stringFromMap(payload, 'location')),
      dtstart: start,
      dtend: Value(dateAny(payload, const ['endAt', 'dtend'])),
      rrule: Value(stringFromMap(payload, 'rrule')),
      status: Value(eventStatus(stringFromMap(payload, 'status'))),
      transp: Value(stringFromMap(payload, 'transp') ?? 'OPAQUE'),
      source: Value(stringFromMap(payload, 'source') ?? 'local'),
      eventCalendarId: Value(intAny(payload, const ['eventCalendarId'])),
      colorHex: Value(stringFromMap(payload, 'colorHex') ?? '#6B5EE4'),
      isBlock: Value(boolAny(payload, const ['isBlock', 'blocking']) ?? false),
    );
  }

  CalendarEventsCompanion _eventUpdateCompanion(Map<String, Object?> patch) {
    return CalendarEventsCompanion(
      uid: _valueString(patch, const ['uid']),
      dtstamp: Value(DateTime.now()),
      summary: _valueString(patch, const ['summary', 'title', 'name']),
      description: _nullableStringValue(patch, const ['description', 'notes']),
      location: _nullableStringValue(patch, const ['location']),
      dtstart: _valueDate(patch, const ['startAt', 'dtstart']),
      dtend: _nullableDateValue(patch, const ['endAt', 'dtend']),
      rrule: _nullableStringValue(patch, const ['rrule']),
      status: patch.containsKey('status')
          ? Value(eventStatus(stringFromMap(patch, 'status')))
          : const Value.absent(),
      transp: _valueString(patch, const ['transp']),
      source: _valueString(patch, const ['source']),
      eventCalendarId: _nullableIntValue(patch, const ['eventCalendarId']),
      colorHex: _valueString(patch, const ['colorHex']),
      isBlock: _valueBool(patch, const ['isBlock', 'blocking']),
    );
  }

  Future<void> _markSyncedFromResult({
    required String objectType,
    required String localId,
    required ServerFirstWriteResult result,
    String? fallbackUid,
    String? fallbackServerId,
  }) async {
    final serverId = _serverIdFromResult(result) ?? fallbackServerId;
    final version = _serverVersionFromResult(result);
    if (serverId == null || version == null) {
      await _stateStore.markPending(
        objectType: objectType,
        localId: localId,
        uid: fallbackUid,
        serverId: serverId,
        state: SyncState.pendingUpdate,
      );
      return;
    }
    await _stateStore.markSynced(
      objectType: objectType,
      localId: localId,
      serverId: serverId,
      serverVersion: version,
      uid: _uidFromResult(result) ?? fallbackUid,
    );
  }

  Map<String, Object?> _ensureUid(Map<String, Object?> payload) {
    final uid = stringFromMap(payload, 'uid');
    if (uid != null && uid.isNotEmpty) {
      return Map<String, Object?>.from(payload);
    }
    return <String, Object?>{
      ...payload,
      'uid': const Uuid().v4(),
    };
  }

  Map<String, Object?> _payloadForLocal(
    ServerFirstWriteResult result,
    Map<String, Object?> fallback,
  ) {
    final item = _itemFromResult(result);
    final payload = item == null ? null : item['payload'];
    if (payload is Map) {
      final itemUid = item == null ? null : item['uid'];
      return <String, Object?>{
        ...fallback,
        ...payload.cast<String, Object?>(),
        'uid': itemUid ?? payload['uid'] ?? fallback['uid'],
      };
    }
    if (item == null) {
      return fallback;
    }
    return <String, Object?>{
      ...fallback,
      ...item.cast<String, Object?>(),
      'uid': item['uid'] ?? fallback['uid'],
    };
  }

  String? _usableServerId(SyncObjectState? state) {
    final value = state?.serverId;
    return value == null || value.trim().isEmpty ? null : value;
  }

  Map<String, Object?>? _itemFromResult(ServerFirstWriteResult result) {
    final item = result.response?['item'];
    return item is Map ? item.cast<String, Object?>() : null;
  }

  String? _serverIdFromResult(ServerFirstWriteResult result) {
    final response = result.response;
    final item = _itemFromResult(result);
    return stringFromMap(response, 'serverId') ?? stringFromMap(item, 'id');
  }

  String? _uidFromResult(ServerFirstWriteResult result) {
    final item = _itemFromResult(result);
    return stringFromMap(item, 'uid');
  }

  int? _serverVersionFromResult(ServerFirstWriteResult result) {
    final responseVersion = result.response?['serverVersion'];
    if (responseVersion is num) {
      return responseVersion.toInt();
    }
    final itemVersion = _itemFromResult(result)?['serverVersion'];
    if (itemVersion is num) {
      return itemVersion.toInt();
    }
    return null;
  }

  SyncState _pendingState(OfflineMutationAction action) {
    switch (action) {
      case OfflineMutationAction.create:
        return SyncState.pendingCreate;
      case OfflineMutationAction.update:
        return SyncState.pendingUpdate;
      case OfflineMutationAction.delete:
        return SyncState.pendingDelete;
    }
  }

  // Status helpers now imported from payload_utils.dart (aligned with server 5.1)
  // _taskStatus → taskStatus()  (returns 'todo'/'done' etc.)
  // _eventStatus → eventStatus()  (returns 'confirmed'/'tentative'/'cancelled')
  // _isDone → isDone()

  // Drift Value<T> wrappers (use shared payload utils internally)
  Value<String> _valueString(Map<String, Object?> map, List<String> keys) {
    if (!hasAny(map, keys)) return const Value.absent();
    return Value(stringAny(map, keys) ?? '');
  }
  Value<String?> _nullableStringValue(Map<String, Object?> map, List<String> keys) {
    if (!hasAny(map, keys)) return const Value.absent();
    return Value(stringAny(map, keys));
  }
  Value<int> _valueInt(Map<String, Object?> map, List<String> keys) {
    if (!hasAny(map, keys)) return const Value.absent();
    return Value(intAny(map, keys) ?? 0);
  }
  Value<int?> _nullableIntValue(Map<String, Object?> map, List<String> keys) {
    if (!hasAny(map, keys)) return const Value.absent();
    return Value(intAny(map, keys));
  }
  Value<bool> _valueBool(Map<String, Object?> map, List<String> keys) {
    if (!hasAny(map, keys)) return const Value.absent();
    return Value(boolAny(map, keys) ?? false);
  }
  Value<DateTime> _valueDate(Map<String, Object?> map, List<String> keys) {
    if (!hasAny(map, keys)) return const Value.absent();
    return Value(dateAny(map, keys) ?? DateTime.now());
  }
  // All payload extraction helpers now imported from payload_utils.dart

  Value<DateTime?> _nullableDateValue(
    Map<String, Object?> map,
    List<String> keys,
  ) {
    if (!hasAny(map, keys)) {
      return const Value.absent();
    }
    return Value(dateAny(map, keys));
  }
}
