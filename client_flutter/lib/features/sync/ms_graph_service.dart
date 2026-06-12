/// @deprecated Since Phase 6.1 (2026-05), all Microsoft Graph interactions
/// are handled exclusively by the server. This client-side service is fully
/// stubbed — all real methods return empty data or throw StateError.
/// See: server/src/outlook/outlook.service.ts
library;

import 'outlook_auth_service.dart';

typedef MsGraphServiceFactory = MsGraphService Function(
  OutlookConfig config, {
  required OutlookSyncMode syncMode,
});

class MsGraphService {
  static const _defaultTimezone = 'UTC';
  static const _defaultOutlookColor = '#0078D4';

  MsGraphService(
    this.config, {
    required this.syncMode,
  });

  final OutlookConfig config;
  final OutlookSyncMode syncMode;

  Future<List<Map<String, dynamic>>> getCalendars() async {
    return const <Map<String, dynamic>>[];
  }

  Future<({List<Map<String, dynamic>> events, String? deltaLink})> getEvents({
    required String calendarId,
    String? deltaLink,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return (events: const <Map<String, dynamic>>[], deltaLink: null);
  }

  void _assertWriteAllowed({
    required bool isFlowPlanV2ManagedContainer,
  }) {
    throw StateError('Outlook is server-managed and read-only on the client.');
  }

  Future<Map<String, dynamic>> createCalendar({
    required String name,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    _assertWriteAllowed(
        isFlowPlanV2ManagedContainer: isFlowPlanV2ManagedContainer);
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> createEvent(
    Map<String, dynamic> event, {
    required String calendarId,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    _assertWriteAllowed(
        isFlowPlanV2ManagedContainer: isFlowPlanV2ManagedContainer);
    return null;
  }

  Future<bool> updateEvent({
    required String calendarId,
    required String eventId,
    required Map<String, dynamic> event,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    _assertWriteAllowed(
        isFlowPlanV2ManagedContainer: isFlowPlanV2ManagedContainer);
    return false;
  }

  Future<Map<String, dynamic>?> getEvent({
    required String calendarId,
    required String eventId,
  }) async {
    return null;
  }

  Future<bool> deleteEvent({
    required String calendarId,
    required String eventId,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    _assertWriteAllowed(
        isFlowPlanV2ManagedContainer: isFlowPlanV2ManagedContainer);
    return false;
  }

  static bool isDeletedEvent(Map<String, dynamic> graphEvent) {
    return graphEvent.containsKey('@removed');
  }

  static String calendarIdOf(Map<String, dynamic> calendar) {
    return calendar['id'] as String? ?? '';
  }

  static String calendarNameOf(Map<String, dynamic> calendar) {
    final name = (calendar['name'] as String?)?.trim();
    return (name == null || name.isEmpty) ? 'Outlook \u65e5\u5386' : name;
  }

  static String calendarColorHexOf(Map<String, dynamic> calendar) {
    final rawHex = (calendar['hexColor'] as String?)?.trim();
    if (rawHex != null && rawHex.isNotEmpty) {
      return rawHex.startsWith('#') ? rawHex : '#$rawHex';
    }
    return _defaultOutlookColor;
  }

  static Map<String, dynamic> toGraphEvent({
    required String subject,
    required DateTime start,
    required DateTime end,
    String? body,
    String? location,
    bool isAllDay = false,
  }) {
    return {
      'subject': subject,
      'body': body != null ? {'contentType': 'HTML', 'content': body} : null,
      'start': {
        'dateTime': start.toIso8601String(),
        'timeZone': _defaultTimezone,
      },
      'end': {
        'dateTime': end.toIso8601String(),
        'timeZone': _defaultTimezone,
      },
      if (location != null) 'location': {'displayName': location},
      'isAllDay': isAllDay,
    };
  }

  static ({
    String id,
    String subject,
    String? body,
    String? location,
    DateTime start,
    DateTime end,
    String status,
  }) fromGraphEvent(Map<String, dynamic> graphEvent) {
    final id = graphEvent['id'] as String? ?? '';
    final subject = (graphEvent['subject'] as String? ?? '').trim();
    final body = _extractBodyText(graphEvent);
    final location = _extractLocation(graphEvent);

    final startRaw = graphEvent['start'] as Map<String, dynamic>? ?? const {};
    final endRaw = graphEvent['end'] as Map<String, dynamic>? ?? const {};

    final start =
        DateTime.tryParse(startRaw['dateTime'] as String? ?? '')?.toLocal() ??
            DateTime.now();
    final end =
        DateTime.tryParse(endRaw['dateTime'] as String? ?? '')?.toLocal() ??
            start.add(const Duration(hours: 1));

    final statusRaw = (graphEvent['showAs'] as String? ?? 'busy').toLowerCase();
    final status = switch (statusRaw) {
      'free' => 'CONFIRMED',
      'tentative' => 'TENTATIVE',
      'oof' => 'CONFIRMED',
      _ => 'CONFIRMED',
    };

    return (
      id: id,
      subject: subject,
      body: body,
      location: location,
      start: start,
      end: end,
      status: status,
    );
  }

  static bool needsEventDetails(Map<String, dynamic> graphEvent) {
    if (isDeletedEvent(graphEvent)) {
      return false;
    }
    return !graphEvent.containsKey('subject') ||
        !graphEvent.containsKey('body') ||
        !graphEvent.containsKey('bodyPreview') ||
        !graphEvent.containsKey('location');
  }

  static String? _extractLocation(Map<String, dynamic> graphEvent) {
    final location = graphEvent['location'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final displayName = (location['displayName'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final locations = graphEvent['locations'] as List<dynamic>?;
    if (locations == null || locations.isEmpty) {
      return null;
    }
    final names = locations
        .whereType<Map>()
        .map((item) => (item['displayName'] as String?)?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return names.isEmpty ? null : names.join(', ');
  }

  static String? _extractBodyText(Map<String, dynamic> graphEvent) {
    final bodyMap = graphEvent['body'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final bodyContent = (bodyMap['content'] as String?)?.trim();
    final bodyContentType =
        (bodyMap['contentType'] as String? ?? '').trim().toLowerCase();
    if (bodyContent != null && bodyContent.isNotEmpty) {
      final normalized = bodyContentType == 'html'
          ? _stripHtml(bodyContent)
          : bodyContent.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    final preview = (graphEvent['bodyPreview'] as String?)?.trim();
    if (preview == null || preview.isEmpty) {
      return null;
    }
    return preview;
  }

  static String _stripHtml(String input) {
    final withLineBreaks = input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li\s*>', caseSensitive: false), '- ');
    final withoutTags = withLineBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final decoded = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    final collapsedSpaces = decoded.replaceAll(RegExp(r'[ \t]+'), ' ');
    final collapsedLines =
        collapsedSpaces.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return collapsedLines.trim();
  }
}
