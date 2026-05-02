import 'outlook_auth_service.dart';

class OutlookCalendarService {
  OutlookCalendarService(this.config);

  final OutlookConfig config;

  Future<bool> signInWithMicrosoft({
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) async {
    return false;
  }

  Future<AuthToken> exchangeCodeForToken(
    String rawAuthorizationInput, {
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) {
    throw StateError('Outlook is configured in the admin console.');
  }

  Future<AuthToken?> refreshAccessToken() async {
    return null;
  }

  Future<List<Map<String, dynamic>>> getCalendarEvents(
    DateTime startDateTime,
    DateTime endDateTime,
  ) async {
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createCalendarEvent(
    String title,
    DateTime start,
    DateTime end,
    String description,
  ) {
    throw StateError('Outlook is server-managed and read-only on the client.');
  }

  Future<Map<String, dynamic>?> updateCalendarEvent(
    String eventId,
    Map<String, dynamic> fields,
  ) {
    throw StateError('Outlook is server-managed and read-only on the client.');
  }

  Future<void> deleteCalendarEvent(String eventId) {
    throw StateError('Outlook is server-managed and read-only on the client.');
  }
}
