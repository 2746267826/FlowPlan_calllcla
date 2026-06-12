import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'api_error.dart';
import 'auth_token_store.dart';

class ApiClient {
  ApiClient({
    required Uri baseUri,
    required AuthTokenStore tokenStore,
    Map<String, String>? defaultHeaders,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _tokenStore = tokenStore,
        _defaultHeaders = defaultHeaders ?? const <String, String>{},
        _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final AuthTokenStore _tokenStore;
  final Map<String, String> _defaultHeaders;
  final http.Client _httpClient;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _send(
      'GET',
      path,
      query: query,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _send(
      'POST',
      path,
      query: query,
      body: body,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _send(
      'PATCH',
      path,
      query: query,
      body: body,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _send(
      'PUT',
      path,
      query: query,
      body: body,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _send(
      'DELETE',
      path,
      query: query,
    );
    return _decodeObject(response);
  }

  @visibleForTesting
  Future<http.Response> sendForTesting(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) {
    return _send(method, path, query: query, body: body);
  }

  @visibleForTesting
  static Map<String, dynamic> decodeObjectForTesting(
    Object? decoded, {
    int? statusCode,
    String? body,
  }) {
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw ApiError(
      message: 'Expected JSON object response',
      statusCode: statusCode,
      body: body,
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = await _tokenStore.readAccessToken();
    final headers = <String, String>{
      'accept': 'application/json',
      ..._defaultHeaders,
      if (body != null) 'content-type': 'application/json',
      if (token != null && token.trim().isNotEmpty)
        'authorization': 'Bearer ${token.trim()}',
    };
    final requestBody = body == null ? null : jsonEncode(body);
    final uri = _buildUri(path, query);

    late final http.Response response;
    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: requestBody,
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: headers,
          body: requestBody,
        );
        break;
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: headers,
          body: requestBody,
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(uri, headers: headers);
        break;
      default:
        throw ApiError(message: 'Unsupported HTTP method: $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        message: 'Request failed',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    return response;
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final basePath =
        _baseUri.path.endsWith('/') ? _baseUri.path : '${_baseUri.path}/';
    return _baseUri.replace(
      path: '$basePath$normalizedPath',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    return decodeObjectForTesting(
      decoded,
      statusCode: response.statusCode,
      body: response.body,
    );
  }
}
