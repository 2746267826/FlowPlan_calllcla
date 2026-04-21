import 'dart:convert';

import 'package:http/http.dart' as http;

import 'outlook_auth_service.dart';

class MsGraphService {
  static const _baseUrl = 'https://graph.microsoft.com/v1.0';
  static const _defaultTimezone = 'Asia/Shanghai';
  static const _defaultOutlookColor = '#0078D4';

  MsGraphService(this.config);

  final OutlookConfig config;

  Future<Map<String, String>?> _authHeaders() async {
    final token = await OutlookAuthService.getValidAccessToken(config);
    if (token == null) {
      return null;
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer': 'outlook.timezone="$_defaultTimezone"',
    };
  }

  Future<List<Map<String, dynamic>>> getCalendars() async {
    final headers = await _authHeaders();
    if (headers == null) {
      return [];
    }

    final uri = Uri.parse('$_baseUrl/me/calendars').replace(
      queryParameters: {
        r'$top': '200',
        r'$select': 'id,name,color,hexColor,isDefaultCalendar,canEdit',
      },
    );

    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(
      data['value'] as List<dynamic>? ?? const <dynamic>[],
    );
  }

  Future<({List<Map<String, dynamic>> events, String? deltaLink})> getEvents({
    required String calendarId,
    String? deltaLink,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) {
      return (events: const <Map<String, dynamic>>[], deltaLink: null);
    }

    final uri = deltaLink != null
        ? Uri.parse(deltaLink)
        : Uri.parse('$_baseUrl/me/calendars/$calendarId/calendarView/delta').replace(
            queryParameters: {
              'startDateTime': (startDate ??
                      DateTime.now().subtract(const Duration(days: 30)))
                  .toUtc()
                  .toIso8601String(),
              'endDateTime': (endDate ?? DateTime.now().add(const Duration(days: 365)))
                  .toUtc()
                  .toIso8601String(),
            },
          );

    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      return (events: const <Map<String, dynamic>>[], deltaLink: null);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      events: List<Map<String, dynamic>>.from(
        data['value'] as List<dynamic>? ?? const <dynamic>[],
      ),
      deltaLink: data['@odata.deltaLink'] as String?,
    );
  }

  Never _throwWriteDisabled() {
    throw StateError(
      'FlowPlan \u5f53\u524d\u4ec5\u5141\u8bb8\u5355\u5411\u8bfb\u53d6 Outlook \u65e5\u5386\uff0c\u7981\u6b62\u5199\u56de\u8fdc\u7aef\u3002',
    );
  }

  Future<Map<String, dynamic>?> createEvent(
    Map<String, dynamic> event, {
    String? calendarId,
  }) async {
    _throwWriteDisabled();
  }

  Future<bool> updateEvent(String eventId, Map<String, dynamic> event) async {
    _throwWriteDisabled();
  }

  Future<bool> deleteEvent(String eventId) async {
    _throwWriteDisabled();
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
      'body': body != null ? {'contentType': 'Text', 'content': body} : null,
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
    final subject = graphEvent['subject'] as String? ?? '';
    final body = (graphEvent['bodyPreview'] as String?)?.trim();
    final location =
        (graphEvent['location'] as Map<String, dynamic>?)?['displayName'] as String?;

    final startRaw = graphEvent['start'] as Map<String, dynamic>? ?? const {};
    final endRaw = graphEvent['end'] as Map<String, dynamic>? ?? const {};

    final start = DateTime.tryParse(startRaw['dateTime'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    final end = DateTime.tryParse(endRaw['dateTime'] as String? ?? '')?.toLocal() ??
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
}
