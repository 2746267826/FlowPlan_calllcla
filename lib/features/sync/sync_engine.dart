import 'package:shared_preferences/shared_preferences.dart';

import '../calendar/data/calendar_books_repository.dart';
import '../calendar/data/event_repository.dart';
import 'ms_graph_service.dart';
import 'outlook_auth_service.dart';

class SyncEngine {
  final EventRepository _eventRepo;
  final CalendarBooksRepository _calendarBooksRepo;
  final OutlookConfig _config;
  late final MsGraphService _graphService;

  static const _deltaLinkKeyPrefix = 'outlook_sync_delta_link.';
  static const _lastSyncKey = 'outlook_last_sync';

  SyncEngine(
    this._eventRepo,
    this._calendarBooksRepo,
    this._config,
  ) {
    _graphService = MsGraphService(_config);
  }

  Future<({int calendarBooks, int downloaded})> sync() async {
    final syncMode = await OutlookAuthService.loadSyncMode();
    if (syncMode == OutlookSyncMode.disabled) {
      return (calendarBooks: 0, downloaded: 0);
    }

    final calendars = await _syncCalendars();
    var downloaded = 0;

    for (final entry in calendars.entries) {
      downloaded += await _pullCalendarEvents(
        remoteCalendarId: entry.key,
        localCalendarId: entry.value.localCalendarId,
        calendarColorHex: entry.value.colorHex,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());

    return (calendarBooks: calendars.length, downloaded: downloaded);
  }

  Future<Map<String, ({int localCalendarId, String colorHex})>>
      _syncCalendars() async {
    final calendars = await _graphService.getCalendars();
    await _removeStaleCalendars(calendars);
    final mapping = <String, ({int localCalendarId, String colorHex})>{};

    for (final calendar in calendars) {
      final remoteCalendarId = MsGraphService.calendarIdOf(calendar);
      if (remoteCalendarId.isEmpty) {
        continue;
      }

      final colorHex = MsGraphService.calendarColorHexOf(calendar);
      final localCalendarId = await _calendarBooksRepo.upsertSyncedEventCalendar(
        source: 'outlook',
        remoteId: remoteCalendarId,
        name: MsGraphService.calendarNameOf(calendar),
        colorHex: colorHex,
        description:
            '\u6765\u81ea Outlook \u7684\u53ea\u8bfb\u65e5\u5386\u672c\uff0c\u7531\u540c\u6b65\u81ea\u52a8\u66f4\u65b0\u3002',
      );

      mapping[remoteCalendarId] = (
        localCalendarId: localCalendarId,
        colorHex: colorHex,
      );
    }

    return mapping;
  }

  Future<void> _removeStaleCalendars(
    List<Map<String, dynamic>> remoteCalendars,
  ) async {
    if (remoteCalendars.isEmpty) {
      return;
    }

    final remoteIds = remoteCalendars
        .map(MsGraphService.calendarIdOf)
        .where((id) => id.isNotEmpty)
        .toSet();
    final localCalendars =
        await _calendarBooksRepo.getEventCalendarsBySource('outlook');
    if (localCalendars.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final calendar in localCalendars) {
      final remoteId = calendar.syncUrl?.trim();
      if (remoteId == null || remoteId.isEmpty || remoteIds.contains(remoteId)) {
        continue;
      }

      await _eventRepo.deleteBySourceAndCalendarId(
        source: 'outlook',
        calendarId: calendar.id,
      );
      await _calendarBooksRepo.deleteEventCalendar(calendar.id);
      await prefs.remove('$_deltaLinkKeyPrefix$remoteId');
    }
  }

  Future<int> _pullCalendarEvents({
    required String remoteCalendarId,
    required int localCalendarId,
    required String calendarColorHex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deltaKey = '$_deltaLinkKeyPrefix$remoteCalendarId';
    final deltaLink = prefs.getString(deltaKey);

    final result = await _graphService.getEvents(
      calendarId: remoteCalendarId,
      deltaLink: deltaLink,
    );

    if (result.deltaLink != null) {
      await prefs.setString(deltaKey, result.deltaLink!);
    }

    var count = 0;
    for (final graphEvent in result.events) {
      final remoteEventId = graphEvent['id'] as String?;
      if (remoteEventId == null || remoteEventId.isEmpty) {
        continue;
      }

      final uid = 'outlook_$remoteEventId';

      if (MsGraphService.isDeletedEvent(graphEvent)) {
        await _eventRepo.deleteByUid(uid);
        count++;
        continue;
      }

      final parsed = MsGraphService.fromGraphEvent(graphEvent);
      await _eventRepo.upsertSyncedEvent(
        uid: uid,
        dtstamp: DateTime.now(),
        summary: parsed.subject,
        description: parsed.body,
        location: parsed.location,
        dtstart: parsed.start,
        dtend: parsed.end,
        status: parsed.status,
        source: 'outlook',
        eventCalendarId: localCalendarId,
        colorHex: calendarColorHex,
      );
      count++;
    }

    return count;
  }

  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  static Future<void> resetSync() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    for (final key in keys) {
      if (key.startsWith(_deltaLinkKeyPrefix)) {
        await prefs.remove(key);
      }
    }

    await prefs.remove(_lastSyncKey);
  }
}
