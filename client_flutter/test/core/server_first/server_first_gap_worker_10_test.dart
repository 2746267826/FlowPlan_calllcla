import 'dart:convert';

import 'package:flowplanv2/core/server_api/activity_understanding_api.dart';
import 'package:flowplanv2/core/server_api/analytics_api.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/file_context_api.dart';
import 'package:flowplanv2/core/server_api/scheduler_api.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/core/server_first/activity_understanding_server_first_store.dart';
import 'package:flowplanv2/core/server_first/cloud_drive_server_first_store.dart';
import 'package:flowplanv2/core/server_first/scheduler_server_first_store.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test(
      'tracking server-first store delegates analytics and understanding calls',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final store = TrackingServerFirstStore(
      analytics: AnalyticsApi(harness.client),
      tracking: TrackingIngestApi(harness.client),
      activityUnderstanding: ActivityUnderstandingApi(harness.client),
    );

    await store.trackingSummary(
      start: DateTime.utc(2026, 6, 9),
      end: DateTime.utc(2026, 6, 10),
    );
    await store.activityHeatmap(
      start: DateTime.utc(2026, 6, 9),
      end: DateTime.utc(2026, 6, 10),
      bucket: 'hour',
      processName: ' Code ',
      category: ' work ',
      taskId: 42,
    );
    await store.trackerHome(date: DateTime.utc(2026, 6, 10, 14));
    await store.activityDaySummary(date: DateTime.utc(2026, 6, 10, 14));
    await store.rangeAnalysis(
      start: DateTime.utc(2026, 6, 1),
      end: DateTime.utc(2026, 6, 10),
      bucket: 'week',
    );
    await store.filterOptions(start: DateTime.utc(2026, 6, 1));
    await store.inputHeatmap(
      bucket: 'minute',
      processName: ' Terminal ',
      category: ' dev ',
      eventKind: ' keyboard ',
    );
    await store.activityRecords(
      processName: 'Code',
      category: 'work',
      taskId: 7,
      limit: 5,
      offset: 10,
    );
    await store.inputEvents(
      processName: 'Terminal',
      category: 'dev',
      eventKind: 'mouse',
      limit: 6,
      offset: 12,
    );
    await store.buildSegments(
      date: DateTime.utc(2026, 6, 10, 3),
      includeTrackedInputEvents: false,
      includeRawActivityLogs: false,
      includeActivityRecords: true,
    );
    await store.segments(
      startAt: DateTime.utc(2026, 6, 10),
      endAt: DateTime.utc(2026, 6, 11),
      status: 'pending',
      limit: 9,
      offset: 3,
    );
    await store.confirmSegment(
      segmentId: 'segment 1',
      title: 'Focus',
      taskId: 'task-1',
      note: 'looks right',
    );
    await store.rejectSegment(segmentId: 'segment 1', reason: 'wrong app');

    expect(harness.requestLines, <String>[
      'GET /api/tracking/summary',
      'GET /api/analytics/activity-heatmap',
      'GET /api/analytics/tracker-home',
      'GET /api/analytics/activity-day-summary',
      'GET /api/analytics/range-analysis',
      'GET /api/analytics/filter-options',
      'GET /api/analytics/input-heatmap',
      'GET /api/analytics/activity-records',
      'GET /api/analytics/input-events',
      'POST /api/activity-understanding/build-segments',
      'GET /api/activity-understanding/segments',
      'POST /api/activity-understanding/segments/segment%201/confirm',
      'POST /api/activity-understanding/segments/segment%201/reject',
    ]);
    expect(harness.requests[1].url.queryParameters,
        containsPair('bucket', 'hour'));
    expect(harness.requests[1].url.queryParameters,
        containsPair('processName', 'Code'));
    expect(harness.requests[1].url.queryParameters,
        containsPair('category', 'work'));
    expect(
        harness.requests[1].url.queryParameters, containsPair('taskId', '42'));
    expect(harness.requests[2].url.queryParameters, <String, String>{
      'date': '2026-06-10',
    });
    expect(jsonDecode(harness.requests[9].body), <String, Object?>{
      'date': '2026-06-10',
      'includeTrackedInputEvents': false,
      'includeRawActivityLogs': false,
      'includeActivityRecords': true,
    });
    expect(harness.requests[10].url.queryParameters, <String, String>{
      'start': '2026-06-10T00:00:00.000Z',
      'end': '2026-06-11T00:00:00.000Z',
      'status': 'pending',
      'limit': '9',
      'offset': '3',
    });
    expect(jsonDecode(harness.requests[11].body), <String, Object?>{
      'title': 'Focus',
      'taskId': 'task-1',
      'note': 'looks right',
      'notes': 'looks right',
    });
    expect(jsonDecode(harness.requests[12].body), <String, Object?>{
      'reason': 'wrong app',
    });
  });

  test('cloud drive store preserves drive query and operation payloads',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final store = CloudDriveServerFirstStore(FileContextApi(harness.client));

    await store.roots(query: ' docs ');
    await store.nodes(
      rootId: 'root-1',
      parentId: 'parent-1',
      query: ' report ',
      limit: 25,
      offset: 5,
    );
    await store.node('node 1');
    await store.openPlan(
      nodeId: 'node 1',
      localIdentity: const <String, Object?>{'inode': 'abc'},
    );
    await store.registerDeviceLocation(
      nodeId: 'node 1',
      localPath: r'C:\Docs\a.md',
      availability: 'offline',
      metadata: const <String, Object?>{'device': 'laptop'},
    );
    await store.requestDownload(nodeId: 'node 1', targetPath: r'D:\a.md');
    await store.relink(
      nodeId: 'node 1',
      localPath: r'E:\a.md',
      reason: 'moved',
      identity: const <String, Object?>{'sha256': 'abc'},
    );
    await store.logOperation(
      nodeId: 'node 1',
      operation: 'copy',
      status: 'failed',
      sourcePath: r'C:\a.md',
      targetPath: r'D:\a.md',
      errorMessage: 'denied',
      metadata: const <String, Object?>{'attempt': 2},
    );

    expect(harness.requestLines, <String>[
      'GET /api/files/drive/roots',
      'GET /api/files/drive/nodes',
      'GET /api/files/drive/nodes/node%201',
      'POST /api/files/drive/nodes/node%201/open-plan',
      'POST /api/files/drive/nodes/node%201/device-location',
      'POST /api/files/drive/nodes/node%201/download-request',
      'POST /api/files/drive/nodes/node%201/relink',
      'POST /api/files/nodes/node%201/log',
    ]);
    expect(harness.requests[0].url.queryParameters, <String, String>{
      'q': 'docs',
    });
    expect(harness.requests[1].url.queryParameters, <String, String>{
      'rootId': 'root-1',
      'parentId': 'parent-1',
      'q': 'report',
      'limit': '25',
      'offset': '5',
    });
    expect(jsonDecode(harness.requests[3].body), <String, Object?>{
      'localIdentity': <String, Object?>{'inode': 'abc'},
    });
    expect(jsonDecode(harness.requests[4].body), <String, Object?>{
      'localPath': r'C:\Docs\a.md',
      'availability': 'offline',
      'metadata': <String, Object?>{'device': 'laptop'},
    });
    expect(jsonDecode(harness.requests[5].body), <String, Object?>{
      'targetPath': r'D:\a.md',
    });
    expect(jsonDecode(harness.requests[6].body), <String, Object?>{
      'localPath': r'E:\a.md',
      'reason': 'moved',
      'identity': <String, Object?>{'sha256': 'abc'},
    });
    expect(jsonDecode(harness.requests[7].body), <String, Object?>{
      'operation': 'copy',
      'status': 'failed',
      'sourcePath': r'C:\a.md',
      'targetPath': r'D:\a.md',
      'errorMessage': 'denied',
      'metadata': <String, Object?>{'attempt': 2},
    });
  });

  test('activity understanding store delegates feedback operations', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final store = ActivityUnderstandingServerFirstStore(
      ActivityUnderstandingApi(harness.client),
    );

    await store.buildSegments(date: DateTime.utc(2026, 6, 10));
    await store.segments();
    await store.confirmSegment(segmentId: 'segment-2');
    await store.rejectSegment(segmentId: 'segment-2');
    await store.sendFeedback(
      segmentId: 'segment-2',
      feedbackType: 'corrected',
      outcome: 'accepted',
      payload: const <String, Object?>{'title': 'Deep work'},
    );

    expect(harness.requestLines, <String>[
      'POST /api/activity-understanding/build-segments',
      'GET /api/activity-understanding/segments',
      'POST /api/activity-understanding/segments/segment-2/confirm',
      'POST /api/activity-understanding/segments/segment-2/reject',
      'POST /api/activity-understanding/segments/segment-2/feedback',
    ]);
    expect(harness.requests[1].url.queryParameters, <String, String>{
      'limit': '100',
      'offset': '0',
    });
    expect(jsonDecode(harness.requests[2].body), <String, Object?>{
      'title': null,
      'taskId': null,
      'note': null,
      'notes': null,
    });
    expect(jsonDecode(harness.requests[3].body), <String, Object?>{
      'reason': null,
    });
    expect(jsonDecode(harness.requests[4].body), <String, Object?>{
      'feedbackType': 'corrected',
      'outcome': 'accepted',
      'feedbackPayload': <String, Object?>{'title': 'Deep work'},
    });
  });

  test('scheduler store delegates draft, accept, reject, and deviation calls',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final store = SchedulerServerFirstStore(SchedulerApi(harness.client));

    await store.createDraftRun(
      startAt: DateTime.utc(2026, 6, 10, 8),
      endAt: DateTime.utc(2026, 6, 10, 18),
    );
    await store.run('run-2');
    await store.acceptRun(runId: 'run-2');
    await store.rejectRun(runId: 'run-2', reason: 'too packed');
    await store.detectDeviations();

    expect(harness.requestLines, <String>[
      'POST /api/scheduler/runs',
      'GET /api/scheduler/runs/run-2',
      'POST /api/scheduler/runs/run-2/accept',
      'POST /api/scheduler/runs/run-2/reject',
      'POST /api/scheduler/deviations/detect',
    ]);
    expect(jsonDecode(harness.requests[0].body), <String, Object?>{
      'rangeStart': '2026-06-10T08:00:00.000Z',
      'rangeEnd': '2026-06-10T18:00:00.000Z',
      'defaultTaskMinutes': 60,
      'strategy': 'balanced',
    });
    expect(jsonDecode(harness.requests[2].body), <String, Object?>{
      'note': null,
    });
    expect(jsonDecode(harness.requests[3].body), <String, Object?>{
      'reason': 'too packed',
    });
    expect(jsonDecode(harness.requests[4].body), <String, Object?>{});
  });
}

class _Harness {
  _Harness() {
    client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 200);
      }),
    );
  }

  final db = createTestDatabase();
  final requests = <http.Request>[];
  late final ApiClient client;

  List<String> get requestLines => requests
      .map((request) => '${request.method} ${request.url.path}')
      .toList(growable: false);

  Future<void> dispose() => db.close();
}
