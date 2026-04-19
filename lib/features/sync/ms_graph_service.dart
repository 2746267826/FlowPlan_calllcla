// Microsoft Graph API 服务：日历事件 CRUD
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'outlook_auth_service.dart';

/// Microsoft Graph API 日历事件操作
class MsGraphService {
  static const _baseUrl = 'https://graph.microsoft.com/v1.0';

  final OutlookConfig config;
  MsGraphService(this.config);

  /// 获取认证头
  Future<Map<String, String>?> _authHeaders() async {
    final token = await OutlookAuthService.getValidAccessToken(config);
    if (token == null) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// 获取用户自己的日历列表
  Future<List<Map<String, dynamic>>> getCalendars() async {
    final headers = await _authHeaders();
    if (headers == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/me/calendars'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['value'] ?? []);
    }
    return [];
  }

  /// 获取指定日历的事件（带增量查询支持）
  Future<({List<Map<String, dynamic>> events, String? deltaLink})> getEvents({
    String? calendarId,
    String? deltaLink,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) {
      return (events: <Map<String, dynamic>>[], deltaLink: null);
    }

    // 如果有 deltaLink，直接使用（增量同步）
    final String url;
    if (deltaLink != null) {
      url = deltaLink;
    } else {
      final calPath = calendarId != null
          ? '/me/calendars/$calendarId/events'
          : '/me/events';
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now().add(const Duration(days: 365));
      url = '$_baseUrl$calPath?\$top=100'
          '&\$filter=start/dateTime ge \'${start.toIso8601String()}\''
          ' and end/dateTime le \'${end.toIso8601String()}\''
          '&\$orderby=start/dateTime';
    }

    final response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final events = List<Map<String, dynamic>>.from(data['value'] ?? []);
      final nextDelta = data['@odata.deltaLink'] as String?;
      return (events: events, deltaLink: nextDelta);
    }
    return (events: <Map<String, dynamic>>[], deltaLink: null);
  }

  /// 创建日历事件
  Future<Map<String, dynamic>?> createEvent(Map<String, dynamic> event,
      {String? calendarId}) async {
    final headers = await _authHeaders();
    if (headers == null) return null;

    final path =
        calendarId != null ? '/me/calendars/$calendarId/events' : '/me/events';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: headers,
      body: jsonEncode(event),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    return null;
  }

  /// 更新日历事件
  Future<bool> updateEvent(String eventId, Map<String, dynamic> event) async {
    final headers = await _authHeaders();
    if (headers == null) return false;

    final response = await http.patch(
      Uri.parse('$_baseUrl/me/events/$eventId'),
      headers: headers,
      body: jsonEncode(event),
    );

    return response.statusCode == 200;
  }

  /// 删除日历事件
  Future<bool> deleteEvent(String eventId) async {
    final headers = await _authHeaders();
    if (headers == null) return false;

    final response = await http.delete(
      Uri.parse('$_baseUrl/me/events/$eventId'),
      headers: headers,
    );

    return response.statusCode == 204;
  }

  /// 将 CalendarEvent 转换为 Graph API 格式
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
        'timeZone': 'Asia/Shanghai',
      },
      'end': {
        'dateTime': end.toIso8601String(),
        'timeZone': 'Asia/Shanghai',
      },
      if (location != null) 'location': {'displayName': location},
      'isAllDay': isAllDay,
    };
  }

  /// 将 Graph API 事件转换为简单 Map（供同步引擎使用）
  static ({
    String id,
    String subject,
    DateTime start,
    DateTime end,
    String? body,
    String? location,
  }) fromGraphEvent(Map<String, dynamic> graphEvent) {
    return (
      id: graphEvent['id'] as String,
      subject: graphEvent['subject'] as String? ?? '',
      start: DateTime.parse(graphEvent['start']['dateTime'] as String),
      end: DateTime.parse(graphEvent['end']['dateTime'] as String),
      body: (graphEvent['body'] as Map?)?['content'] as String?,
      location: (graphEvent['location'] as Map?)?['displayName'] as String?,
    );
  }
}
