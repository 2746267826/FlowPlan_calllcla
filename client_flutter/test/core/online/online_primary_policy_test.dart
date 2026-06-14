import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection states expose read-only cache and write capability', () {
    for (final level in ServerConnectionLevel.values) {
      final state = ServerConnectionState(level: level);
      final expectedReadOnly = switch (level) {
        ServerConnectionLevel.online ||
        ServerConnectionLevel.syncing ||
        ServerConnectionLevel.conflicted =>
          false,
        ServerConnectionLevel.unknown ||
        ServerConnectionLevel.degraded ||
        ServerConnectionLevel.offline ||
        ServerConnectionLevel.authRequired ||
        ServerConnectionLevel.localCacheOnly =>
          true,
      };

      expect(state.isReadOnlyCache, expectedReadOnly, reason: level.name);
      expect(state.canAttemptServerWrite, !expectedReadOnly,
          reason: level.name);
    }
  });

  test('online state allows ordinary server writes', () {
    final policy = OnlinePrimaryPolicy.fromConnectionState(
      const ServerConnectionState(level: ServerConnectionLevel.online),
    );

    expect(policy.readOnlyCache, isFalse);
    expect(policy.canAttemptServerWrite, isTrue);
    expect(
        () => policy.requireOnlineBusinessWrite('save task'), returnsNormally);
  });

  test('offline and auth states reject ordinary business writes', () {
    for (final state in const <ServerConnectionState>[
      ServerConnectionState(level: ServerConnectionLevel.offline),
      ServerConnectionState(level: ServerConnectionLevel.degraded),
      ServerConnectionState(level: ServerConnectionLevel.localCacheOnly),
      ServerConnectionState(level: ServerConnectionLevel.authRequired),
    ]) {
      final policy = OnlinePrimaryPolicy.fromConnectionState(state);

      expect(policy.readOnlyCache, isTrue);
      expect(policy.canAttemptServerWrite, isFalse);
      expect(
        () => policy.requireOnlineBusinessWrite('save task'),
        throwsA(isA<OnlinePrimaryWriteRejected>()),
      );
    }
  });

  test('tracking spool and device local state remain allowed offline', () {
    final policy = OnlinePrimaryPolicy.fromConnectionState(
      const ServerConnectionState(level: ServerConnectionLevel.offline),
    );

    expect(policy.allowsTrackingSpoolWrite, isTrue);
    expect(policy.allowsDeviceLocalWrite, isTrue);
    expect(
      () => policy.requireOnlineFileUploadStart('upload file'),
      throwsA(isA<OnlinePrimaryWriteRejected>()),
    );
  });

  test('write rejection describes action kind and reason', () {
    const rejection = OnlinePrimaryWriteRejected(
      action: 'retry file',
      kind: OnlinePrimaryWriteKind.fileTransferRetry,
      reason: 'Server connection is required.',
    );

    expect(
      rejection.toString(),
      contains('retry file'),
    );
    expect(
      rejection.toString(),
      contains('OnlinePrimaryWriteKind.fileTransferRetry'),
    );

    final policy = OnlinePrimaryPolicy.fromConnectionState(
      const ServerConnectionState(level: ServerConnectionLevel.offline),
    );
    expect(
      () => policy.requireOnlineFileTransferRetry('retry file'),
      throwsA(
        isA<OnlinePrimaryWriteRejected>().having(
          (error) => error.kind,
          'kind',
          OnlinePrimaryWriteKind.fileTransferRetry,
        ),
      ),
    );
  });
}
