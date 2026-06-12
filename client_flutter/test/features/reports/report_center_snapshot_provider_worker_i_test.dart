import 'package:flowplanv2/core/server_api/reports_api.dart';
import 'package:flowplanv2/features/reports/presentation/report_center_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report center snapshot includes weather and channel configuration data',
      () async {
    final api = _SnapshotReportsApi();
    final container = ProviderContainer(
      overrides: [
        reportsApiProvider.overrideWith((ref) async => api),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(reportCenterSnapshotProvider.future);

    expect(api.reportsLimits, <int>[80]);
    expect(api.diaryLimits, <int>[80]);
    expect(api.deliveryLimits, <int>[30]);
    expect(snapshot['reports'], hasLength(1));
    expect(snapshot['diary'], hasLength(1));
    expect(snapshot['weatherLocations'], <Map<String, Object?>>[
      <String, Object?>{
        'id': 'weather-location-1',
        'name': 'Shanghai',
        'isDefault': true,
      },
    ]);
    expect(snapshot['weatherSummary'], <Map<String, Object?>>[
      <String, Object?>{
        'id': 'weather-1',
        'locationId': 'weather-location-1',
        'summary': 'Cloudy',
      },
    ]);
    expect(snapshot['channels'], <Map<String, Object?>>[
      <String, Object?>{
        'id': 'channel-1',
        'channelType': 'webhook',
        'name': 'Ops webhook',
        'status': 'enabled',
      },
    ]);
    expect(snapshot['deliveries'], <Map<String, Object?>>[
      <String, Object?>{
        'id': 'delivery-1',
        'channel': 'webhook',
        'status': 'failed',
      },
    ]);
  });

  test('report center snapshot surfaces API errors', () async {
    final container = ProviderContainer(
      overrides: [
        reportsApiProvider.overrideWith(
          (ref) async => _ThrowingReportsApi(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(reportCenterSnapshotProvider.future),
      throwsA(isA<StateError>()),
    );
  });
}

class _SnapshotReportsApi implements ReportsApi {
  final reportsLimits = <int>[];
  final diaryLimits = <int>[];
  final deliveryLimits = <int>[];

  @override
  Future<Map<String, dynamic>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    reportsLimits.add(limit);
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'report-1',
          'title': 'Daily report',
          'status': status ?? 'draft',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> diary({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    diaryLimits.add(limit);
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'diary-1',
          'title': 'Diary',
          'status': status ?? 'draft',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> weatherLocations() async {
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'weather-location-1',
          'name': 'Shanghai',
          'isDefault': true,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> weatherSummary() async {
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'weather-1',
          'locationId': 'weather-location-1',
          'summary': 'Cloudy',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> pushChannels() async {
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'channel-1',
          'channelType': 'webhook',
          'name': 'Ops webhook',
          'status': 'enabled',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> pushDeliveries({
    String? status,
    int limit = 50,
  }) async {
    deliveryLimits.add(limit);
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'delivery-1',
          'channel': 'webhook',
          'status': status ?? 'failed',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> confirmDiary(String diaryId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> confirmReport(String reportId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> generateDiary({
    required DateTime date,
    bool autoConfirm = false,
    bool useLlm = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> generateReport({
    String reportType = 'daily',
    required DateTime periodStart,
    required DateTime periodEnd,
    bool autoConfirm = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> polishDiary(String diaryId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> polishReport(String reportId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> pushReport({
    required String reportId,
    String? channelId,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> refreshWeather(String locationId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> report(String reportId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> retryDelivery(String deliveryId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updateDiary({
    required String diaryId,
    String? title,
    String? contentMarkdown,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updateReport({
    required String reportId,
    String? title,
    String? contentMarkdown,
    String? userNote,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> upsertPushChannel({
    required String channelType,
    required String name,
    String status = 'enabled',
    Map<String, Object?> config = const <String, Object?>{},
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> upsertWeatherLocation({
    required String name,
    required double latitude,
    required double longitude,
    String timezone = 'auto',
    bool isDefault = true,
  }) =>
      throw UnimplementedError();
}

class _ThrowingReportsApi extends _SnapshotReportsApi {
  @override
  Future<Map<String, dynamic>> weatherLocations() async {
    throw StateError('weather service unavailable');
  }
}
