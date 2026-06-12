import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'web_local_store.dart';

class WebApiException implements Exception {
  const WebApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'WebApiException($statusCode): $message';
}

class WebApiClient {
  WebApiClient(this.store, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final WebLocalStore store;
  final http.Client _httpClient;

  String get baseUrl =>
      (store.baseUrl ?? 'http://localhost:3202/api').replaceFirst(
        RegExp(r'/+$'),
        '',
      );

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    final response =
        await _httpClient.get(_uri(path, query), headers: _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    final response = await _httpClient.patch(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    final response = await _httpClient.put(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Uri _uri(String path, [Map<String, String?> query = const {}]) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final base = Uri.parse('$baseUrl/$normalizedPath');
    final cleanQuery = <String, String>{};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value != null && value.isNotEmpty) {
        cleanQuery[entry.key] = value;
      }
    }
    return base.replace(
      queryParameters: cleanQuery.isEmpty ? null : cleanQuery,
    );
  }

  Map<String, String> _headers() {
    final token = store.accessToken;
    return {
      'content-type': 'application/json',
      'x-flowplanv2-platform': 'web',
      'x-flowplanv2-user-id':
          store.userId ?? '00000000-0000-4000-8000-000000000001',
      'x-flowplanv2-device-id':
          store.deviceId ?? '00000000-0000-4000-8000-000000000101',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    final raw = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebApiException(
        '请求失败',
        statusCode: response.statusCode,
        body: raw,
      );
    }
    if (raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }
}

String encodeBytes(Uint8List bytes) => base64Encode(bytes);

Uint8List decodeBytes(String value) => base64Decode(value);
