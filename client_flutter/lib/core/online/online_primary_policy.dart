import '../connection/server_connection_state.dart';

enum OnlinePrimaryWriteKind {
  businessFact,
  fileUploadStart,
  fileTransferRetry,
  trackingSpool,
  deviceLocal,
}

class OnlinePrimaryWriteRejected implements Exception {
  const OnlinePrimaryWriteRejected({
    required this.action,
    required this.kind,
    required this.reason,
  });

  final String action;
  final OnlinePrimaryWriteKind kind;
  final String reason;

  @override
  String toString() {
    return 'OnlinePrimaryWriteRejected($action, $kind, $reason)';
  }
}

class OnlinePrimaryPolicy {
  const OnlinePrimaryPolicy({
    required this.serverReachable,
    required this.authenticated,
    required this.level,
  });

  factory OnlinePrimaryPolicy.fromConnectionState(ServerConnectionState state) {
    final serverReachable = switch (state.level) {
      ServerConnectionLevel.online ||
      ServerConnectionLevel.syncing ||
      ServerConnectionLevel.conflicted =>
        true,
      ServerConnectionLevel.unknown ||
      ServerConnectionLevel.degraded ||
      ServerConnectionLevel.offline ||
      ServerConnectionLevel.authRequired ||
      ServerConnectionLevel.localCacheOnly =>
        false,
    };
    return OnlinePrimaryPolicy(
      serverReachable: serverReachable,
      authenticated: state.level != ServerConnectionLevel.authRequired,
      level: state.level,
    );
  }

  final bool serverReachable;
  final bool authenticated;
  final ServerConnectionLevel level;

  bool get readOnlyCache => !serverReachable || !authenticated;
  bool get canAttemptServerWrite => !readOnlyCache;
  bool get allowsTrackingSpoolWrite => true;
  bool get allowsDeviceLocalWrite => true;

  void requireOnlineBusinessWrite(String action) {
    _requireServerWrite(action, OnlinePrimaryWriteKind.businessFact);
  }

  void requireOnlineFileUploadStart(String action) {
    _requireServerWrite(action, OnlinePrimaryWriteKind.fileUploadStart);
  }

  void requireOnlineFileTransferRetry(String action) {
    _requireServerWrite(action, OnlinePrimaryWriteKind.fileTransferRetry);
  }

  void _requireServerWrite(String action, OnlinePrimaryWriteKind kind) {
    if (!authenticated) {
      throw OnlinePrimaryWriteRejected(
        action: action,
        kind: kind,
        reason: 'Authentication is required before this write can be accepted.',
      );
    }
    if (!serverReachable) {
      throw OnlinePrimaryWriteRejected(
        action: action,
        kind: kind,
        reason:
            'Server connection is required before this write can be accepted.',
      );
    }
  }
}
