class RequestContext {
  const RequestContext({
    required this.deviceId,
    required this.platform,
    this.userId,
  });

  final String deviceId;
  final String platform;
  final String? userId;

  Map<String, String> toHeaders() {
    return {
      'x-flowplanv2-device-id': deviceId,
      'x-flowplanv2-platform': platform,
      if (userId != null && userId!.isNotEmpty) 'x-flowplanv2-user-id': userId!,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'deviceId': deviceId,
      'platform': platform,
      if (userId != null && userId!.isNotEmpty) 'userId': userId,
    };
  }
}
