import 'dart:convert';

import 'package:flowplanv2/core/server_api/activity_understanding_api.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('activity understanding API forwards segment commands and payloads',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <_CapturedRequest>[];
    final api = ActivityUnderstandingApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(_CapturedRequest.from(request));
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );
    final start = DateTime.utc(2026, 6, 10, 1);
    final end = DateTime.utc(2026, 6, 10, 12);
    final splitAt = DateTime.utc(2026, 6, 10, 8, 30);

    await api.buildSegments(
      date: DateTime(2026, 6, 10, 15),
      includeTrackedInputEvents: false,
      includeRawActivityLogs: true,
      includeActivityRecords: false,
    );
    await api.segments(
      startAt: start,
      endAt: end,
      status: 'pending',
      limit: 12,
      offset: 4,
    );
    await api.segments();
    await api.confirmSegment(
      segmentId: 'segment 1',
      title: 'Deep work',
      taskId: 'task 1',
      note: 'Looks right',
    );
    await api.rejectSegment(segmentId: 'segment 1', reason: 'bad window');
    await api.splitSegment(segmentId: 'segment 1', splitAt: splitAt);
    await api
        .mergeSegments(segmentIds: const <String>['segment 1', 'segment 2']);
    await api.sendFeedback(
      segmentId: 'segment 1',
      feedbackType: 'accepted',
      outcome: 'better',
      payload: const <String, Object?>{'score': 0.9},
    );
    await api.sendFeedback(segmentId: 'segment 1');

    expect(
      requests.map((request) => '${request.method} ${request.path}').toList(),
      <String>[
        'POST /api/activity-understanding/build-segments',
        'GET /api/activity-understanding/segments',
        'GET /api/activity-understanding/segments',
        'POST /api/activity-understanding/segments/segment%201/confirm',
        'POST /api/activity-understanding/segments/segment%201/reject',
        'POST /api/activity-understanding/segments/segment%201/split',
        'POST /api/activity-understanding/segments/merge',
        'POST /api/activity-understanding/segments/segment%201/feedback',
        'POST /api/activity-understanding/segments/segment%201/feedback',
      ],
    );
    expect(requests[0].jsonBody, <String, Object?>{
      'date': '2026-06-10',
      'includeTrackedInputEvents': false,
      'includeRawActivityLogs': true,
      'includeActivityRecords': false,
    });
    expect(requests[1].query, <String, String>{
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'status': 'pending',
      'limit': '12',
      'offset': '4',
    });
    expect(requests[2].query, <String, String>{
      'limit': '100',
      'offset': '0',
    });
    expect(requests[3].jsonBody, <String, Object?>{
      'title': 'Deep work',
      'taskId': 'task 1',
      'note': 'Looks right',
      'notes': 'Looks right',
    });
    expect(requests[4].jsonBody, <String, Object?>{'reason': 'bad window'});
    expect(requests[5].jsonBody, <String, Object?>{
      'splitAt': splitAt.toIso8601String(),
    });
    expect(requests[6].jsonBody, <String, Object?>{
      'segmentIds': <String>['segment 1', 'segment 2'],
    });
    expect(requests[7].jsonBody, <String, Object?>{
      'feedbackType': 'accepted',
      'outcome': 'better',
      'feedbackPayload': <String, Object?>{'score': 0.9},
    });
    expect(requests[8].jsonBody, <String, Object?>{
      'feedbackType': 'modified',
      'feedbackPayload': <String, Object?>{},
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.jsonBody,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.queryParameters,
      jsonBody: request.body.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
    );
  }

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, Object?> jsonBody;
}
