import 'dart:async';

import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('onlinePrimaryPolicyProvider falls back to read-only cache', () {
    final container = ProviderContainer(
      overrides: <Override>[
        serverConnectionStateProvider.overrideWith(
          (ref) => const Stream<ServerConnectionState>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final policy = container.read(onlinePrimaryPolicyProvider);

    expect(policy.readOnlyCache, isTrue);
    expect(policy.level, ServerConnectionLevel.localCacheOnly);
  });

  test('onlinePrimaryPolicyProvider mirrors connection state changes',
      () async {
    final controller = StreamController<ServerConnectionState>();
    final container = ProviderContainer(
      overrides: <Override>[
        serverConnectionStateProvider.overrideWith(
          (ref) => controller.stream,
        ),
      ],
    );
    addTearDown(() async {
      await controller.close();
      container.dispose();
    });
    final sub = container.listen(
      onlinePrimaryPolicyProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    controller.add(const ServerConnectionState(
      level: ServerConnectionLevel.online,
    ));
    await pumpEventQueue();

    expect(container.read(onlinePrimaryPolicyProvider).readOnlyCache, isFalse);

    controller.add(const ServerConnectionState(
      level: ServerConnectionLevel.authRequired,
    ));
    await pumpEventQueue();

    expect(container.read(onlinePrimaryPolicyProvider).readOnlyCache, isTrue);
    expect(container.read(onlinePrimaryPolicyProvider).authenticated, isFalse);
  });

  test('server-managed repository providers do not enqueue offline mutations',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    final taskListId = await insertFixtureTaskList(db);
    final calendarId = await insertFixtureCalendar(db);
    final taskRepository = container.read(taskRepositoryProvider);
    final eventRepository = container.read(eventRepositoryProvider);

    await taskRepository.create(
      fixtureTask(
        uid: 'provider-task-1',
        summary: 'Provider task',
        taskListId: taskListId,
      ),
    );
    await eventRepository.create(
      fixtureEvent(
        uid: 'provider-event-1',
        summary: 'Provider event',
        calendarId: calendarId,
      ),
    );

    final mutations = await db
        .customSelect(
          'SELECT object_type FROM offline_mutations ORDER BY id ASC',
        )
        .get();
    final objectTypes = mutations
        .map((row) => row.read<String>('object_type'))
        .toList(growable: false);

    expect(objectTypes, isNot(contains(SyncObjectType.taskItem.key)));
    expect(objectTypes, isNot(contains(SyncObjectType.calendarEvent.key)));
    expect(objectTypes, everyElement(SyncObjectType.auditLog.key));
  });
}
