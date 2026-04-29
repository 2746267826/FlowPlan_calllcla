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
      'x-flowplan-device-id': deviceId,
      'x-flowplan-platform': platform,
      if (userId != null && userId!.isNotEmpty) 'x-flowplan-user-id': userId!,
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
