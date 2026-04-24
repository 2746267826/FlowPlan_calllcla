import 'dart:convert';

import 'package:http/http.dart' as http;

import 'outlook_auth_service.dart';
import 'outlook_oauth_config.dart';

class OutlookCalendarService {
  OutlookCalendarService(this.config);

  final OutlookConfig config;

  Future<bool> signInWithMicrosoft({
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) {
    return OutlookAuthService.signInWithMicrosoft(
      config,
      requestedMode: requestedMode,
    );
  }

  Future<AuthToken> exchangeCodeForToken(
    String rawAuthorizationInput, {
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) {
    return OutlookAuthService.exchangeCodeForToken(
      config,
      rawAuthorizationInput,
      requestedMode: requestedMode,
    );
  }

  Future<AuthToken?> refreshAccessToken() {
    return OutlookAuthService.refreshAccessToken(config);
  }

  Future<List<Map<String, dynamic>>> getCalendarEvents(
    DateTime startDateTime,
    DateTime endDateTime,
  ) async {
    final headers = await _buildHeaders(
      requestedMode: OutlookSyncMode.readOnly,
    );
    final uri = Uri.parse(
      '${OutlookOAuthPlatformConfig.graphBaseUrl}/me/calendarView',
    ).replace(
      queryParameters: <String, String>{
        'startDateTime': startDateTime.toIso8601String(),
        'endDateTime': endDateTime.toIso8601String(),
      },
    );
    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '读取 Outlook 日程失败：${response.statusCode} ${_shortBody(response.body)}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(
      data['value'] as List<dynamic>? ?? const <dynamic>[],
    );
  }

  Future<Map<String, dynamic>> createCalendarEvent(
    String title,
    DateTime start,
    DateTime end,
    String description,
  ) async {
    final headers = await _buildHeaders(
      requestedMode: OutlookSyncMode.bidirectional,
    );
    final response = await http.post(
      Uri.parse('${OutlookOAuthPlatformConfig.graphBaseUrl}/me/events'),
      headers: headers,
      body: jsonEncode(<String, dynamic>{
        'subject': title,
        'body': <String, dynamic>{
          'contentType': 'HTML',
          'content': description,
        },
        'start': <String, dynamic>{
          'dateTime': start.toIso8601String(),
          'timeZone': OutlookOAuthPlatformConfig.preferTimezone,
        },
        'end': <String, dynamic>{
          'dateTime': end.toIso8601String(),
          'timeZone': OutlookOAuthPlatformConfig.preferTimezone,
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '创建 Outlook 日程失败：${response.statusCode} ${_shortBody(response.body)}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> updateCalendarEvent(
    String eventId,
    Map<String, dynamic> fields,
  ) async {
    final headers = await _buildHeaders(
      requestedMode: OutlookSyncMode.bidirectional,
    );
    final uri = Uri.parse(
      '${OutlookOAuthPlatformConfig.graphBaseUrl}/me/events/$eventId',
    );
    final response = await http.patch(
      uri,
      headers: headers,
      body: jsonEncode(fields),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '更新 Outlook 日程失败：${response.statusCode} ${_shortBody(response.body)}',
      );
    }
    final readResponse = await http.get(uri, headers: headers);
    if (readResponse.statusCode < 200 || readResponse.statusCode >= 300) {
      return null;
    }
    return jsonDecode(readResponse.body) as Map<String, dynamic>;
  }

  Future<void> deleteCalendarEvent(String eventId) async {
    final headers = await _buildHeaders(
      requestedMode: OutlookSyncMode.bidirectional,
    );
    final response = await http.delete(
      Uri.parse('${OutlookOAuthPlatformConfig.graphBaseUrl}/me/events/$eventId'),
      headers: headers,
    );
    if (response.statusCode == 404) {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '删除 Outlook 日程失败：${response.statusCode} ${_shortBody(response.body)}',
      );
    }
  }

  Future<Map<String, String>> _buildHeaders({
    required OutlookSyncMode requestedMode,
  }) async {
    final token = await OutlookAuthService.getValidAccessToken(
      config,
      requestedMode: requestedMode,
    );
    if (token == null || token.trim().isEmpty) {
      throw StateError('当前没有可用的 Outlook 访问令牌，请先重新连接 Outlook。');
    }
    return <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer':
          'outlook.timezone="${OutlookOAuthPlatformConfig.preferTimezone}"',
    };
  }

  String _shortBody(String body) {
    final trimmed = body.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    if (trimmed.length <= 180) {
      return trimmed;
    }
    return '${trimmed.substring(0, 180)}...';
  }
}
