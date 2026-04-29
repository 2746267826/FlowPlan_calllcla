import 'api_client.dart';

class ReportsApi {
  ReportsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/reports',
      query: <String, String>{
        if (status != null) 'status': status,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> report(String reportId) {
    return _apiClient.getJson('/reports/$reportId');
  }

  Future<Map<String, dynamic>> generateReport({
    String reportType = 'daily',
    required DateTime periodStart,
    required DateTime periodEnd,
    bool autoConfirm = false,
  }) {
    return _apiClient.postJson(
      '/reports/generate',
      body: <String, Object?>{
        'reportType': reportType,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'autoConfirm': autoConfirm,
      },
    );
  }

  Future<Map<String, dynamic>> confirmReport(String reportId) {
    return _apiClient.postJson('/reports/$reportId/confirm');
  }

  Future<Map<String, dynamic>> updateReport({
    required String reportId,
    String? title,
    String? contentMarkdown,
    String? userNote,
  }) {
    return _apiClient.patchJson(
      '/reports/$reportId',
      body: <String, Object?>{
        if (title != null) 'title': title,
        if (contentMarkdown != null) 'contentMarkdown': contentMarkdown,
        if (userNote != null && userNote.trim().isNotEmpty)
          'userNote': userNote.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> polishReport(String reportId) {
    return _apiClient.postJson('/reports/$reportId/polish');
  }

  Future<Map<String, dynamic>> pushReport({
    required String reportId,
    String? channelId,
  }) {
    return _apiClient.postJson(
      '/reports/$reportId/push',
      body: <String, Object?>{
        'channelId': channelId,
      },
    );
  }

  Future<Map<String, dynamic>> pushDeliveries({
    String? status,
    int limit = 50,
  }) {
    return _apiClient.getJson(
      '/push/deliveries',
      query: <String, String>{
        if (status != null) 'status': status,
        'limit': limit.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> retryDelivery(String deliveryId) {
    return _apiClient.postJson('/push/deliveries/$deliveryId/retry');
  }

  Future<Map<String, dynamic>> diary({
    String? status,
    int limit = 50,
    int offset = 0,
  }) {
    return _apiClient.getJson(
      '/diary',
      query: <String, String>{
        if (status != null) 'status': status,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> generateDiary({
    required DateTime date,
    bool autoConfirm = false,
    bool useLlm = false,
  }) {
    return _apiClient.postJson(
      '/diary/generate',
      body: <String, Object?>{
        'date': date.toIso8601String(),
        'autoConfirm': autoConfirm,
        'useLlm': useLlm,
      },
    );
  }

  Future<Map<String, dynamic>> updateDiary({
    required String diaryId,
    String? title,
    String? contentMarkdown,
  }) {
    return _apiClient.patchJson(
      '/diary/$diaryId',
      body: <String, Object?>{
        if (title != null) 'title': title,
        if (contentMarkdown != null) 'contentMarkdown': contentMarkdown,
      },
    );
  }

  Future<Map<String, dynamic>> confirmDiary(String diaryId) {
    return _apiClient.postJson('/diary/$diaryId/confirm');
  }

  Future<Map<String, dynamic>> polishDiary(String diaryId) {
    return _apiClient.postJson('/diary/$diaryId/polish');
  }

  Future<Map<String, dynamic>> pushChannels() {
    return _apiClient.getJson('/push/channels');
  }

  Future<Map<String, dynamic>> upsertPushChannel({
    required String channelType,
    required String name,
    String status = 'enabled',
    Map<String, Object?> config = const <String, Object?>{},
  }) {
    return _apiClient.postJson(
      '/push/channels',
      body: <String, Object?>{
        'channelType': channelType,
        'name': name,
        'status': status,
        'config': config,
      },
    );
  }

  Future<Map<String, dynamic>> weatherSummary() {
    return _apiClient.getJson('/weather/summary');
  }

  Future<Map<String, dynamic>> weatherLocations() {
    return _apiClient.getJson('/weather/locations');
  }

  Future<Map<String, dynamic>> upsertWeatherLocation({
    required String name,
    required double latitude,
    required double longitude,
    String timezone = 'auto',
    bool isDefault = true,
  }) {
    return _apiClient.postJson(
      '/weather/locations',
      body: <String, Object?>{
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
        'isDefault': isDefault,
      },
    );
  }

  Future<Map<String, dynamic>> refreshWeather(String locationId) {
    return _apiClient.postJson('/weather/locations/$locationId/refresh');
  }
}
