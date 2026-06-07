typedef FakeJsonHandler = Future<Map<String, dynamic>> Function(
  Map<String, Object?> request,
);

class FakeJsonApi {
  FakeJsonApi([Map<String, FakeJsonHandler>? handlers])
      : _handlers = handlers ?? <String, FakeJsonHandler>{};

  final Map<String, FakeJsonHandler> _handlers;
  final requests = <Map<String, Object?>>[];

  void when(String key, FakeJsonHandler handler) {
    _handlers[key] = handler;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final key = '$method $path';
    final request = <String, Object?>{
      'method': method,
      'path': path,
      if (query != null) 'query': query,
      if (body != null) 'body': body,
    };
    requests.add(request);
    final handler = _handlers[key];
    if (handler == null) {
      throw StateError('No fake API handler registered for $key');
    }
    return handler(request);
  }
}
