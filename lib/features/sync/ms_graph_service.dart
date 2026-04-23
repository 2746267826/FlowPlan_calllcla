import 'dart:convert';

import 'package:http/http.dart' as http;

import 'outlook_auth_service.dart';

class MsGraphService {
  static const _baseUrl = 'https://graph.microsoft.com/v1.0';
  static const _defaultTimezone = 'Asia/Shanghai';
  static const _defaultOutlookColor = '#0078D4';

  MsGraphService(
    this.config, {
    required this.syncMode,
  });

  final OutlookConfig config;
  final OutlookSyncMode syncMode;

  Future<Map<String, String>?> _authHeaders() async {
    if (!syncMode.allowsPull) {
      return null;
    }

    final token = await OutlookAuthService.getValidAccessToken(
      config,
      requestedMode: syncMode,
    );
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
    if (!syncMode.allowsPull) {
      return [];
    }

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
    if (!syncMode.allowsPull) {
      return (events: const <Map<String, dynamic>>[], deltaLink: null);
    }

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

  Future<Map<String, String>> _writeHeaders() async {
    final token = await OutlookAuthService.getValidAccessToken(
      config,
      requestedMode: OutlookSyncMode.bidirectional,
    );
    if (token == null) {
      throw StateError(
        '\u5f53\u524d Outlook \u6388\u6743\u4e0d\u8db3\u4ee5\u6267\u884c\u53cc\u5411\u540c\u6b65\uff0c\u8bf7\u5148\u5207\u6362\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\u5e76\u91cd\u65b0\u5b8c\u6210\u8ba4\u8bc1\u3002',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer': 'outlook.timezone="$_defaultTimezone"',
    };
  }

  void _assertWriteAllowed({
    required bool isFlowPlanManagedContainer,
  }) {
    if (!syncMode.allowsPush) {
      throw StateError(
        '\u5f53\u524d Outlook \u540c\u6b65\u6a21\u5f0f\u4e0d\u5141\u8bb8\u5199\u56de\u8fdc\u7aef\uff0c\u8bf7\u5148\u5207\u6362\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\u3002',
      );
    }
    if (!isFlowPlanManagedContainer) {
      throw StateError(
        'FlowPlan \u51fa\u4e8e\u6570\u636e\u5b89\u5168\u8003\u8651\uff0c\u76ee\u524d\u53ea\u5141\u8bb8\u5199\u5165 FlowPlan \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u65e5\u5386\u672c\uff0c\u4e0d\u4f1a\u76f4\u63a5\u4fee\u6539\u666e\u901a Outlook \u65e5\u5386\u3002',
      );
    }
  }

  Future<Map<String, dynamic>> createCalendar({
    required String name,
    required bool isFlowPlanManagedContainer,
  }) async {
    _assertWriteAllowed(isFlowPlanManagedContainer: isFlowPlanManagedContainer);
    final headers = await _writeHeaders();
    final uri = Uri.parse('$_baseUrl/me/calendars');
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(<String, dynamic>{
        'name': name,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '\u521b\u5efa Outlook \u65e5\u5386\u5bb9\u5668\u5931\u8d25\uff1a${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> createEvent(
    Map<String, dynamic> event, {
    required String calendarId,
    required bool isFlowPlanManagedContainer,
  }) async {
    _assertWriteAllowed(isFlowPlanManagedContainer: isFlowPlanManagedContainer);
    final headers = await _writeHeaders();
    final uri = Uri.parse('$_baseUrl/me/calendars/$calendarId/events');
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(event),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '\u521b\u5efa Outlook \u4e8b\u4ef6\u5931\u8d25\uff1a${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<bool> updateEvent({
    required String calendarId,
    required String eventId,
    required Map<String, dynamic> event,
    required bool isFlowPlanManagedContainer,
  }) async {
    _assertWriteAllowed(isFlowPlanManagedContainer: isFlowPlanManagedContainer);
    final headers = await _writeHeaders();
    final uri = Uri.parse('$_baseUrl/me/calendars/$calendarId/events/$eventId');
    final response = await http.patch(
      uri,
      headers: headers,
      body: jsonEncode(event),
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<Map<String, dynamic>?> getEvent({
    required String calendarId,
    required String eventId,
  }) async {
    if (!syncMode.allowsPull) {
      return null;
    }

    final headers = await _authHeaders();
    if (headers == null) {
      return null;
    }

    final uri = Uri.parse('$_baseUrl/me/calendars/$calendarId/events/$eventId')
        .replace(
      queryParameters: {
        r'$select':
            'id,subject,body,start,end,showAs,lastModifiedDateTime,categories',
      },
    );
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '读取 Outlook 事件失败：${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<bool> deleteEvent({
    required String calendarId,
    required String eventId,
    required bool isFlowPlanManagedContainer,
  }) async {
    _assertWriteAllowed(isFlowPlanManagedContainer: isFlowPlanManagedContainer);
    final headers = await _writeHeaders();
    final uri = Uri.parse('$_baseUrl/me/calendars/$calendarId/events/$eventId');
    final response = await http.delete(uri, headers: headers);
    return response.statusCode == 404 ||
        (response.statusCode >= 200 && response.statusCode < 300);
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
