import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';

class TrackingIngestApi {
  TrackingIngestApi(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> createBatch({
    required String batchUid,
    required String dataKind,
    DateTime? startAt,
    DateTime? endAt,
    String compression = 'none',
    List<Map<String, dynamic>> records = const [],
    Map<String, dynamic> metadata = const {},
  }) {
    return _apiClient.postJson(
      '/tracking/ingest/batches',
      body: {
        'batchUid': batchUid,
        'dataKind': dataKind,
        'compression': compression,
        if (startAt != null) 'startAt': _utcIso(startAt),
        if (endAt != null) 'endAt': _utcIso(endAt),
        if (records.isNotEmpty) 'records': records,
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> uploadChunk({
    required String batchId,
    required int chunkIndex,
    List<Map<String, dynamic>> records = const [],
    Uint8List? compressedJsonBytes,
    String? checksum,
  }) {
    return _apiClient.postJson(
      '/tracking/ingest/batches/$batchId/chunks',
      body: {
        'chunkIndex': chunkIndex,
        if (records.isNotEmpty) 'payload': {'records': records},
        if (compressedJsonBytes != null)
          'payloadBase64': base64Encode(compressedJsonBytes),
        if (checksum != null && checksum.isNotEmpty) 'checksum': checksum,
      },
    );
  }

  Future<Map<String, dynamic>> completeBatch({
    required String batchId,
    List<Map<String, dynamic>> records = const [],
  }) {
    return _apiClient.postJson(
      '/tracking/ingest/batches/$batchId/complete',
      body: {
        if (records.isNotEmpty) 'records': records,
      },
    );
  }

  Future<Map<String, dynamic>> summary({DateTime? start, DateTime? end}) {
    return _apiClient.getJson(
      '/tracking/summary',
      query: {
        if (start != null) 'start': _utcIso(start),
        if (end != null) 'end': _utcIso(end),
      },
    );
  }

  static String _utcIso(DateTime value) {
    return value.toUtc().toIso8601String();
  }
}
