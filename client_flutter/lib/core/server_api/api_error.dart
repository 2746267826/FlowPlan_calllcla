class ApiError implements Exception {
  const ApiError({
    required this.message,
    this.statusCode,
    this.body,
  });

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'ApiError$status: $message';
  }
}
