import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/core/server_api/reports_api.dart';
import 'package:flowplanv2/features/reports/presentation/report_center_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('report page generate action uses stable control', (
    tester,
  ) async {
    final fakeReportsApi = FakeReportsApi();

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );
    await _pumpReportReady(tester);

    expect(find.byType(ReportCenterPage), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.reportGenerateButton));
    await _pumpFrames(tester);

    expect(fakeReportsApi.generatedReports, 1);
  });

  testWidgets('report page refresh reloads the report snapshot', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi(reports: [_reportFixture()]);

    await _pumpReportPage(tester, fakeReportsApi);
    final initialReportsCalls = fakeReportsApi.reportsCallCount;

    await tester.tap(find.byIcon(Icons.refresh).first);
    await _pumpUntil(
      tester,
      () => fakeReportsApi.reportsCallCount > initialReportsCalls,
    );

    expect(fakeReportsApi.diaryCallCount, greaterThanOrEqualTo(2));
    expect(fakeReportsApi.weatherLocationsCallCount, greaterThanOrEqualTo(2));
    expect(fakeReportsApi.pushDeliveriesCallCount, greaterThanOrEqualTo(2));
  });

  testWidgets('report page generates a diary draft from the toolbar', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi();

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    await _tapToolbarIconAction(tester, Icons.edit_note_outlined);
    await _pumpUntil(tester, () => fakeReportsApi.generatedDiaries.isNotEmpty);

    expect(fakeReportsApi.generatedDiaries.single['autoConfirm'], isFalse);
    expect(fakeReportsApi.generatedDiaries.single['useLlm'], isFalse);
    expect(fakeReportsApi.diaryList.single['status'], 'draft');
  });

  testWidgets('report page configures weather location and refreshes it', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi();

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    await _tapToolbarIconAction(tester, Icons.cloud_outlined);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'Shanghai office');
    await tester.enterText(fields.at(1), '31.2304');
    await tester.enterText(fields.at(2), '121.4737');
    await tester.enterText(fields.at(3), 'Asia/Shanghai');
    await _tapDialogFilledButton(tester);
    await _pumpUntil(
      tester,
      () => fakeReportsApi.upsertedWeatherLocations.isNotEmpty,
    );

    expect(fakeReportsApi.upsertedWeatherLocations.single, <String, Object?>{
      'name': 'Shanghai office',
      'latitude': 31.2304,
      'longitude': 121.4737,
      'timezone': 'Asia/Shanghai',
      'isDefault': true,
    });
    expect(fakeReportsApi.refreshedWeatherLocationIds, <String>[
      'weather-location-1',
    ]);
  });

  testWidgets('report page configures a push channel from the toolbar', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi();

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    await _tapToolbarIconAction(tester, Icons.send_outlined);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(0), 'webhook');
    await tester.enterText(fields.at(1), 'Report webhook');
    await tester.enterText(fields.at(2), 'https://hooks.example.test/report');
    await _tapDialogFilledButton(tester);
    await _pumpUntil(
      tester,
      () => fakeReportsApi.upsertedPushChannels.isNotEmpty,
    );

    expect(fakeReportsApi.upsertedPushChannels.single, <String, Object?>{
      'channelType': 'webhook',
      'name': 'Report webhook',
      'status': 'enabled',
      'config': <String, Object?>{
        'url': 'https://hooks.example.test/report',
      },
    });
  });

  testWidgets('report page opens report detail with entries and evidence', (
    tester,
  ) async {
    final fakeReportsApi = FakeReportsApi(reports: [_reportFixture()]);

    await _pumpReportPage(tester, fakeReportsApi);

    await _tapReportAction(tester, 0);

    expect(fakeReportsApi.openedReportIds, <String>['report-1']);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Completed deep work.'), findsOneWidget);
    expect(find.textContaining('2h focus session'), findsOneWidget);
    expect(find.textContaining('Timer log'), findsOneWidget);
  });

  testWidgets('report page edit action saves title, markdown, and note', (
    tester,
  ) async {
    final fakeReportsApi = FakeReportsApi(reports: [_reportFixture()]);

    await _pumpReportPage(tester, fakeReportsApi);

    await _tapReportAction(tester, 1);
    await tester.enterText(find.byType(TextField).at(0), 'Daily report edited');
    await tester.enterText(find.byType(TextField).at(1), 'Updated markdown');
    await tester.enterText(find.byType(TextField).at(2), 'Keep tone concise');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await _pumpFrames(tester);

    expect(fakeReportsApi.updatedReports, hasLength(1));
    expect(fakeReportsApi.updatedReports.single, <String, Object?>{
      'reportId': 'report-1',
      'title': 'Daily report edited',
      'contentMarkdown': 'Updated markdown',
      'userNote': 'Keep tone concise',
    });
  });

  testWidgets('report page confirms and pushes a draft report', (tester) async {
    final fakeReportsApi = _ReportWorkflowApi(
      reports: [_reportFixture(status: 'draft')],
    );

    await _pumpReportPage(tester, fakeReportsApi);

    await _tapReportAction(tester, 2);
    await _pumpUntil(
        tester, () => fakeReportsApi.confirmedReportIds.isNotEmpty);
    expect(fakeReportsApi.confirmedReportIds, <String>['report-1']);
    expect(fakeReportsApi.reportsList.single['status'], 'confirmed');

    await _tapReportAction(tester, 3);
    await _pumpUntil(tester, () => fakeReportsApi.pushedReportIds.isNotEmpty);
    expect(fakeReportsApi.pushedReportIds, <String>['report-1']);
  });

  testWidgets('report page AI polish action calls fake API', (tester) async {
    final fakeReportsApi = FakeReportsApi(reports: [_reportFixture()]);

    await _pumpReportPage(tester, fakeReportsApi);

    await _tapReportAction(tester, 2);

    expect(fakeReportsApi.polishedReportIds, <String>['report-1']);
  });

  testWidgets(
      'report page shows template fallback when report polish skips LLM',
      (tester) async {
    final fakeReportsApi = FakeReportsApi(
      reports: [_reportFixture()],
      polishReportAppliesLlm: false,
    );

    await _pumpReportPage(tester, fakeReportsApi);

    await _tapReportAction(tester, 2);

    expect(fakeReportsApi.polishedReportIds, <String>['report-1']);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('AI'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('report page retries failed push delivery', (tester) async {
    final fakeReportsApi = _ReportWorkflowApi(
      deliveries: [
        <String, dynamic>{
          'id': 'delivery-1',
          'channel': 'Report webhook',
          'status': 'failed',
          'lastError': 'network timeout',
          'target': 'https://hooks.example.test/report',
        },
      ],
    );

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    final deliveryTile = find
        .ancestor(
          of: find.text('network timeout'),
          matching: find.byType(ListTile),
        )
        .first;
    final retryButton = find.descendant(
      of: deliveryTile,
      matching: find.byType(TextButton),
    );
    await tester.tap(retryButton);
    await _pumpUntil(
        tester, () => fakeReportsApi.retriedDeliveryIds.isNotEmpty);

    expect(fakeReportsApi.retriedDeliveryIds, <String>['delivery-1']);
    expect(fakeReportsApi.deliveries.single['status'], 'sent');
  });

  testWidgets('report page reports failed retry result without marking sent',
      (tester) async {
    final fakeReportsApi = _RetryFailureWorkflowApi(
      deliveries: [
        <String, dynamic>{
          'id': 'delivery-1',
          'channel': 'Report webhook',
          'status': 'failed',
          'lastError': 'network timeout',
          'target': 'https://hooks.example.test/report',
        },
      ],
    );

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    final deliveryTile = find
        .ancestor(
          of: find.text('network timeout'),
          matching: find.byType(ListTile),
        )
        .first;
    await tester.tap(
      find.descendant(
        of: deliveryTile,
        matching: find.byType(TextButton),
      ),
    );
    await _pumpUntil(
        tester, () => fakeReportsApi.retriedDeliveryIds.isNotEmpty);
    await _pumpFrames(tester);

    expect(fakeReportsApi.retriedDeliveryIds, <String>['delivery-1']);
    expect(fakeReportsApi.deliveries.single['status'], 'failed');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('report page edits, confirms, and polishes a diary', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi(
      diary: [_diaryFixture(status: 'draft')],
    );

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    await _tapDiaryAction(tester, 'Diary draft', 0);
    final editFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(editFields, findsNWidgets(3));
    await tester.enterText(editFields.at(0), 'Diary edited');
    await tester.enterText(editFields.at(1), 'Updated diary markdown');
    await tester.enterText(editFields.at(2), 'Keep this private');
    await _tapDialogFilledButton(tester);
    await _pumpUntil(tester, () => fakeReportsApi.updatedDiaries.isNotEmpty);

    expect(fakeReportsApi.updatedDiaries.single, <String, Object?>{
      'diaryId': 'diary-1',
      'title': 'Diary edited',
      'contentMarkdown': 'Updated diary markdown',
    });

    await _tapDiaryAction(tester, 'Diary edited', 1);
    await _pumpUntil(tester, () => fakeReportsApi.confirmedDiaryIds.isNotEmpty);
    expect(fakeReportsApi.confirmedDiaryIds, <String>['diary-1']);
    expect(fakeReportsApi.diaryList.single['status'], 'confirmed');

    await _tapDiaryAction(tester, 'Diary edited', 1);
    await _pumpUntil(tester, () => fakeReportsApi.polishedDiaryIds.isNotEmpty);
    expect(fakeReportsApi.polishedDiaryIds, <String>['diary-1']);
    expect(
      fakeReportsApi.diaryList.single['contentMarkdown'],
      contains('Polished by AI.'),
    );
  });

  testWidgets('report page shows template fallback when diary polish skips LLM',
      (tester) async {
    final fakeReportsApi = _ReportWorkflowApi(
      diary: [_diaryFixture(status: 'confirmed')],
      polishDiaryAppliesLlm: false,
    );

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    await _tapDiaryAction(tester, 'Diary draft', 1);
    await _pumpUntil(tester, () => fakeReportsApi.polishedDiaryIds.isNotEmpty);

    expect(fakeReportsApi.polishedDiaryIds, <String>['diary-1']);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('AI'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('report page empty state keeps generation controls available', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi();

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    expect(find.byKey(AppKeys.reportGenerateButton), findsOneWidget);
    expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.byIcon(Icons.send_outlined), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(5));
    expect(find.byType(ListTile), findsNothing);
    expect(fakeReportsApi.reportsCallCount, 1);
    expect(fakeReportsApi.diaryCallCount, 1);
    expect(fakeReportsApi.pushDeliveriesCallCount, 1);
  });

  testWidgets('report page error state can retry and recover the snapshot', (
    tester,
  ) async {
    final fakeReportsApi = _FlakyReportWorkflowApi(
      reports: [_reportFixture()],
    );

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportsApiProvider.overrideWith((ref) async => fakeReportsApi),
        ],
        child: const MaterialApp(home: ReportCenterPage()),
      ),
    );
    await pumpUntilFound(
      tester,
      find.textContaining('snapshot unavailable'),
      maxPumps: 20,
    );

    expect(find.textContaining('snapshot unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await pumpUntilFound(
      tester,
      find.text('Daily report'),
      maxPumps: 20,
    );

    expect(find.text('Daily report'), findsOneWidget);
    expect(find.textContaining('snapshot unavailable'), findsNothing);
  });

  testWidgets('report page renders fallback rows and refreshes stored weather',
      (tester) async {
    final fakeReportsApi = _ReportWorkflowApi(
      weatherLocations: [
        <String, dynamic>{
          'id': 'weather-location-1',
          'latitude': 31.2,
          'longitude': 121.5,
        },
      ],
      weatherSummary: [
        <String, dynamic>{
          'summary': 'Fallback weather',
          'expiresAt': '2026-06-10T12:00:00.000Z',
        },
      ],
      channels: [
        <String, dynamic>{
          'channelType': 'telegram',
          'status': 'enabled',
        },
      ],
      deliveries: [
        <String, dynamic>{
          'id': 'delivery-sent',
          'status': 'sent',
          'target': 'chat-1',
        },
        <String, dynamic>{
          'id': 'delivery-pending',
          'channel': 'Webhook',
          'status': 'pending',
          'target': 'https://hooks.example.test/report',
        },
      ],
    );

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
      viewSize: const Size(1200, 1800),
    );

    expect(find.text('Fallback weather'), findsOneWidget);
    expect(find.text('2026-06-10T12:00:00.000Z'), findsOneWidget);
    expect(find.text('telegram'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.schedule_send_outlined), findsOneWidget);
    expect(find.text('31.2, 121.5'), findsOneWidget);

    final locationTile = find
        .ancestor(
          of: find.text('31.2, 121.5'),
          matching: find.byType(ListTile),
        )
        .first;
    await tester.tap(
      find.descendant(
        of: locationTile,
        matching: find.byType(TextButton),
      ),
    );
    await _pumpUntil(
      tester,
      () => fakeReportsApi.refreshedWeatherLocationIds.isNotEmpty,
    );

    expect(fakeReportsApi.refreshedWeatherLocationIds, <String>[
      'weather-location-1',
    ]);
  });

  testWidgets('report page cancelled dialogs do not call write APIs', (
    tester,
  ) async {
    final fakeReportsApi = _ReportWorkflowApi(
      reports: [_reportFixture(status: 'draft')],
      diary: [_diaryFixture(status: 'draft')],
    );

    await _pumpReportPage(tester, fakeReportsApi);

    await _tapReportAction(tester, 1);
    await _tapDialogCancelButton(tester);
    expect(fakeReportsApi.updatedReports, isEmpty);

    await _tapDiaryAction(tester, 'Diary draft', 0);
    await _tapDialogCancelButton(tester);
    expect(fakeReportsApi.updatedDiaries, isEmpty);

    await _tapToolbarIconAction(tester, Icons.cloud_outlined);
    await _tapDialogCancelButton(tester);
    expect(fakeReportsApi.upsertedWeatherLocations, isEmpty);

    await _tapToolbarIconAction(tester, Icons.send_outlined);
    await _tapDialogCancelButton(tester);
    expect(fakeReportsApi.upsertedPushChannels, isEmpty);
  });

  testWidgets('report page shows snackbar when an action fails',
      (tester) async {
    final fakeReportsApi = FakeReportsApi(failGenerateReport: true);

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    await tester.tap(find.byKey(AppKeys.reportGenerateButton));
    await _pumpFrames(tester);

    expect(fakeReportsApi.generatedReports, 0);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('report generation unavailable'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders legacy dynamic report items without crashing',
      (tester) async {
    final fakeReportsApi = _LegacyDynamicReportsApi();

    await _pumpReportPage(
      tester,
      fakeReportsApi,
      expectReportFixture: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Legacy report'), findsOneWidget);
    expect(find.text('Daily report'), findsNothing);
    expect(find.textContaining('draft'), findsOneWidget);
    expect(find.textContaining('String key report'), findsNothing);
  });
}

Future<void> _pumpReportPage(
  WidgetTester tester,
  FakeReportsApi fakeReportsApi, {
  bool expectReportFixture = true,
  Size viewSize = const Size(1200, 900),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reportsApiProvider.overrideWith((ref) async => fakeReportsApi),
      ],
      child: const MaterialApp(home: ReportCenterPage()),
    ),
  );
  await tester.pump();
  await _pumpReportReady(tester);

  expect(find.byType(ReportCenterPage), findsOneWidget);
  if (expectReportFixture) {
    expect(find.text('Daily report'), findsOneWidget);
  }
}

Future<void> _tapReportAction(WidgetTester tester, int actionIndex) async {
  final reportTile = find
      .ancestor(
        of: find.text('Daily report'),
        matching: find.byType(ListTile),
      )
      .first;
  final action = find
      .descendant(
        of: reportTile,
        matching: find.byType(TextButton),
      )
      .at(actionIndex);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await _pumpFrames(tester);
}

Future<void> _tapDiaryAction(
  WidgetTester tester,
  String title,
  int actionIndex,
) async {
  final diaryTile = find
      .ancestor(
        of: find.text(title),
        matching: find.byType(ListTile),
      )
      .first;
  final action = find
      .descendant(
        of: diaryTile,
        matching: find.byType(TextButton),
      )
      .at(actionIndex);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await _pumpFrames(tester);
}

Future<void> _tapToolbarIconAction(
  WidgetTester tester,
  IconData iconData,
) async {
  final action = find
      .ancestor(
        of: find.byIcon(iconData),
        matching: find.byType(OutlinedButton),
      )
      .first;
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await _pumpFrames(tester);
}

Future<void> _tapDialogFilledButton(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _tapDialogCancelButton(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        )
        .first,
  );
  await _pumpFrames(tester);
}

Future<void> _pumpReportReady(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byType(ReportCenterPage), maxPumps: 20);
  await _pumpFrames(tester);
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 10,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    finder,
    findsWidgets,
    reason: 'Expected finder to appear within $maxPumps bounded pumps.',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (done()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'Expected condition within $maxPumps pumps.');
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _reportFixture({String status = 'confirmed'}) {
  return <String, dynamic>{
    'id': 'report-1',
    'title': 'Daily report',
    'reportType': 'daily',
    'status': status,
    'contentMarkdown': 'Completed deep work.',
    'createdAt': '2026-06-09T00:00:00.000Z',
    'updatedAt': '2026-06-09T08:00:00.000Z',
  };
}

Map<String, dynamic> _diaryFixture({String status = 'draft'}) {
  return <String, dynamic>{
    'id': 'diary-1',
    'title': 'Diary draft',
    'date': '2026-06-09',
    'status': status,
    'contentMarkdown': 'Initial diary markdown',
    'createdAt': '2026-06-09T00:00:00.000Z',
    'updatedAt': '2026-06-09T08:00:00.000Z',
  };
}

class FakeReportsApi implements ReportsApi {
  FakeReportsApi({
    List<Map<String, dynamic>> reports = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> diary = const <Map<String, dynamic>>[],
    this.polishReportAppliesLlm = true,
    this.failGenerateReport = false,
  })  : reportsList = [
          for (final report in reports) Map<String, dynamic>.from(report),
        ],
        diaryList = [
          for (final entry in diary) Map<String, dynamic>.from(entry),
        ];

  final List<Map<String, dynamic>> reportsList;
  final List<Map<String, dynamic>> diaryList;
  final bool polishReportAppliesLlm;
  final bool failGenerateReport;
  var generatedReports = 0;
  final openedReportIds = <String>[];
  final updatedReports = <Map<String, Object?>>[];
  final polishedReportIds = <String>[];
  final pushedReportIds = <String>[];

  @override
  Future<Map<String, dynamic>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items': _pagedItems(
        reportsList,
        status: status,
        limit: limit,
        offset: offset,
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> report(String reportId) async {
    openedReportIds.add(reportId);
    final report = Map<String, dynamic>.from(_findReport(reportId));
    report.putIfAbsent('contentMarkdown', () => 'Completed deep work.');
    return <String, dynamic>{
      'report': report,
      'entries': <Map<String, Object?>>[
        <String, Object?>{
          'claimType': 'summary',
          'title': 'Focus block',
          'body': '2h focus session',
        },
      ],
      'evidence': <Map<String, Object?>>[
        <String, Object?>{
          'evidenceType': 'activity',
          'sourceType': 'tracker',
          'sourceId': 'segment-1',
          'summary': 'Timer log',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> generateReport({
    String reportType = 'daily',
    required DateTime periodStart,
    required DateTime periodEnd,
    bool autoConfirm = false,
  }) async {
    if (failGenerateReport) {
      throw StateError('report generation unavailable');
    }
    generatedReports++;
    final report = <String, dynamic>{
      'id': 'generated-report-$generatedReports',
      'title': 'Daily report',
      'reportType': reportType,
      'status': autoConfirm ? 'confirmed' : 'draft',
      'contentMarkdown': 'Generated report draft',
      'createdAt': periodStart.toIso8601String(),
      'updatedAt': periodEnd.toIso8601String(),
    };
    reportsList.insert(0, report);
    return <String, dynamic>{'report': Map<String, dynamic>.from(report)};
  }

  @override
  Future<Map<String, dynamic>> updateReport({
    required String reportId,
    String? title,
    String? contentMarkdown,
    String? userNote,
  }) async {
    updatedReports.add(<String, Object?>{
      'reportId': reportId,
      'title': title,
      'contentMarkdown': contentMarkdown,
      'userNote': userNote,
    });
    final report = _findReport(reportId);
    if (title != null) {
      report['title'] = title;
    }
    if (contentMarkdown != null) {
      report['contentMarkdown'] = contentMarkdown;
    }
    return <String, dynamic>{'report': Map<String, dynamic>.from(report)};
  }

  @override
  Future<Map<String, dynamic>> polishReport(String reportId) async {
    polishedReportIds.add(reportId);
    final report = _findReport(reportId);
    report['contentMarkdown'] =
        '${report['contentMarkdown'] ?? ''}\n\nPolished by AI.';
    return <String, dynamic>{
      'llmApplied': polishReportAppliesLlm,
      'report': Map<String, dynamic>.from(report),
    };
  }

  @override
  Future<Map<String, dynamic>> pushReport({
    required String reportId,
    String? channelId,
  }) async {
    pushedReportIds.add(reportId);
    return <String, dynamic>{
      'delivery': <String, Object?>{'id': 'delivery-1', 'status': 'sent'},
    };
  }

  @override
  Future<Map<String, dynamic>> diary({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items': _pagedItems(
        diaryList,
        status: status,
        limit: limit,
        offset: offset,
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> weatherLocations() async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> weatherSummary() async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> pushChannels() async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> pushDeliveries({
    String? status,
    int limit = 50,
  }) async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  Map<String, dynamic> _findReport(String reportId) {
    return reportsList.firstWhere(
      (report) => '${report['id']}' == reportId,
      orElse: () {
        final report = <String, dynamic>{
          'id': reportId,
          'title': 'Daily report',
          'reportType': 'daily',
          'status': 'draft',
          'contentMarkdown': 'Generated report draft',
        };
        reportsList.add(report);
        return report;
      },
    );
  }

  List<Map<String, dynamic>> _pagedItems(
    List<Map<String, dynamic>> source, {
    required String? status,
    required int limit,
    required int offset,
  }) {
    final items = status == null
        ? source
        : source.where((item) => '${item['status']}' == status).toList();
    return [
      for (final item in items.skip(offset).take(limit))
        Map<String, dynamic>.from(item),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LegacyDynamicReportsApi extends FakeReportsApi {
  @override
  Future<Map<String, dynamic>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items': <Object?>[
        <Object?, Object?>{
          'id': 'legacy-report',
          'title': 'Legacy report',
          'reportType': 'daily',
          'status': 'draft',
          'updatedAt': '2026-06-09T08:00:00.000Z',
        },
        'String key report',
      ],
    };
  }
}

class _ReportWorkflowApi extends FakeReportsApi {
  _ReportWorkflowApi({
    super.reports,
    super.diary,
    List<Map<String, dynamic>> weatherLocations =
        const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> weatherSummary = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> channels = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> deliveries = const <Map<String, dynamic>>[],
    this.polishDiaryAppliesLlm = true,
  })  : _weatherLocations = _copyItems(weatherLocations),
        _weatherSummary = _copyItems(weatherSummary),
        channels = _copyItems(channels),
        deliveries = _copyItems(deliveries);

  final List<Map<String, dynamic>> _weatherLocations;
  final List<Map<String, dynamic>> _weatherSummary;
  final List<Map<String, dynamic>> channels;
  final List<Map<String, dynamic>> deliveries;
  final bool polishDiaryAppliesLlm;

  var reportsCallCount = 0;
  var diaryCallCount = 0;
  var weatherLocationsCallCount = 0;
  var weatherSummaryCallCount = 0;
  var pushChannelsCallCount = 0;
  var pushDeliveriesCallCount = 0;
  final generatedDiaries = <Map<String, Object?>>[];
  final updatedDiaries = <Map<String, Object?>>[];
  final confirmedReportIds = <String>[];
  final confirmedDiaryIds = <String>[];
  final polishedDiaryIds = <String>[];
  final upsertedWeatherLocations = <Map<String, Object?>>[];
  final refreshedWeatherLocationIds = <String>[];
  final upsertedPushChannels = <Map<String, Object?>>[];
  final retriedDeliveryIds = <String>[];

  @override
  Future<Map<String, dynamic>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) {
    reportsCallCount++;
    return super.reports(status: status, limit: limit, offset: offset);
  }

  @override
  Future<Map<String, dynamic>> diary({
    String? status,
    int limit = 50,
    int offset = 0,
  }) {
    diaryCallCount++;
    return super.diary(status: status, limit: limit, offset: offset);
  }

  @override
  Future<Map<String, dynamic>> generateDiary({
    required DateTime date,
    bool autoConfirm = false,
    bool useLlm = false,
  }) async {
    generatedDiaries.add(<String, Object?>{
      'date': date,
      'autoConfirm': autoConfirm,
      'useLlm': useLlm,
    });
    final diary = <String, dynamic>{
      'id': 'generated-diary-${generatedDiaries.length}',
      'title': 'Generated diary',
      'date': date.toIso8601String(),
      'status': autoConfirm ? 'confirmed' : 'draft',
      'contentMarkdown': 'Generated diary draft',
      'createdAt': date.toIso8601String(),
      'updatedAt': date.toIso8601String(),
    };
    diaryList.insert(0, diary);
    return <String, dynamic>{'diary': Map<String, dynamic>.from(diary)};
  }

  @override
  Future<Map<String, dynamic>> updateDiary({
    required String diaryId,
    String? title,
    String? contentMarkdown,
  }) async {
    updatedDiaries.add(<String, Object?>{
      'diaryId': diaryId,
      'title': title,
      'contentMarkdown': contentMarkdown,
    });
    final diary = _findDiary(diaryId);
    if (title != null) {
      diary['title'] = title;
    }
    if (contentMarkdown != null) {
      diary['contentMarkdown'] = contentMarkdown;
    }
    return <String, dynamic>{'diary': Map<String, dynamic>.from(diary)};
  }

  @override
  Future<Map<String, dynamic>> confirmReport(String reportId) async {
    confirmedReportIds.add(reportId);
    final report = _findReport(reportId);
    report['status'] = 'confirmed';
    return <String, dynamic>{'report': Map<String, dynamic>.from(report)};
  }

  @override
  Future<Map<String, dynamic>> confirmDiary(String diaryId) async {
    confirmedDiaryIds.add(diaryId);
    final diary = _findDiary(diaryId);
    diary['status'] = 'confirmed';
    return <String, dynamic>{'diary': Map<String, dynamic>.from(diary)};
  }

  @override
  Future<Map<String, dynamic>> polishDiary(String diaryId) async {
    polishedDiaryIds.add(diaryId);
    final diary = _findDiary(diaryId);
    diary['contentMarkdown'] =
        '${diary['contentMarkdown'] ?? ''}\n\nPolished by AI.';
    return <String, dynamic>{
      'llmApplied': polishDiaryAppliesLlm,
      'diary': Map<String, dynamic>.from(diary),
    };
  }

  @override
  Future<Map<String, dynamic>> weatherLocations() async {
    weatherLocationsCallCount++;
    return <String, dynamic>{'items': _copyItems(_weatherLocations)};
  }

  @override
  Future<Map<String, dynamic>> weatherSummary() async {
    weatherSummaryCallCount++;
    return <String, dynamic>{'items': _copyItems(_weatherSummary)};
  }

  @override
  Future<Map<String, dynamic>> upsertWeatherLocation({
    required String name,
    required double latitude,
    required double longitude,
    String timezone = 'auto',
    bool isDefault = true,
  }) async {
    final request = <String, Object?>{
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'timezone': timezone,
      'isDefault': isDefault,
    };
    upsertedWeatherLocations.add(request);
    final location = <String, dynamic>{
      'id': 'weather-location-${upsertedWeatherLocations.length}',
      ...request,
    };
    _weatherLocations.add(location);
    return <String, dynamic>{'location': Map<String, dynamic>.from(location)};
  }

  @override
  Future<Map<String, dynamic>> refreshWeather(String locationId) async {
    refreshedWeatherLocationIds.add(locationId);
    final location = _weatherLocations.firstWhere(
      (item) => '${item['id']}' == locationId,
      orElse: () => <String, dynamic>{'name': 'Unknown'},
    );
    final weather = <String, dynamic>{
      'id': 'weather-${refreshedWeatherLocationIds.length}',
      'locationId': locationId,
      'locationName': location['name'],
      'summary': 'Sunny',
      'expiresAt': '2026-06-09T12:00:00.000Z',
    };
    _weatherSummary.add(weather);
    return <String, dynamic>{'weather': Map<String, dynamic>.from(weather)};
  }

  @override
  Future<Map<String, dynamic>> pushChannels() async {
    pushChannelsCallCount++;
    return <String, dynamic>{'items': _copyItems(channels)};
  }

  @override
  Future<Map<String, dynamic>> upsertPushChannel({
    required String channelType,
    required String name,
    String status = 'enabled',
    Map<String, Object?> config = const <String, Object?>{},
  }) async {
    final request = <String, Object?>{
      'channelType': channelType,
      'name': name,
      'status': status,
      'config': Map<String, Object?>.from(config),
    };
    upsertedPushChannels.add(request);
    final channel = <String, dynamic>{
      'id': 'channel-${upsertedPushChannels.length}',
      ...request,
    };
    channels.add(channel);
    return <String, dynamic>{'channel': Map<String, dynamic>.from(channel)};
  }

  @override
  Future<Map<String, dynamic>> pushDeliveries({
    String? status,
    int limit = 50,
  }) async {
    pushDeliveriesCallCount++;
    final items = status == null
        ? deliveries
        : deliveries.where((item) => '${item['status']}' == status).toList();
    return <String, dynamic>{
      'items': _copyItems(items.take(limit).toList()),
    };
  }

  @override
  Future<Map<String, dynamic>> retryDelivery(String deliveryId) async {
    retriedDeliveryIds.add(deliveryId);
    final delivery = deliveries.firstWhere(
      (item) => '${item['id']}' == deliveryId,
      orElse: () {
        final item = <String, dynamic>{
          'id': deliveryId,
          'channel': 'Report webhook',
          'status': 'failed',
        };
        deliveries.add(item);
        return item;
      },
    );
    delivery['status'] = 'sent';
    delivery['lastError'] = '';
    return <String, dynamic>{
      'ok': true,
      'delivery': Map<String, dynamic>.from(delivery),
    };
  }

  @override
  Map<String, dynamic> _findReport(String reportId) {
    return reportsList.firstWhere(
      (report) => '${report['id']}' == reportId,
      orElse: () {
        final report = <String, dynamic>{
          'id': reportId,
          'title': 'Daily report',
          'reportType': 'daily',
          'status': 'draft',
          'contentMarkdown': 'Generated report draft',
        };
        reportsList.add(report);
        return report;
      },
    );
  }

  Map<String, dynamic> _findDiary(String diaryId) {
    return diaryList.firstWhere(
      (diary) => '${diary['id']}' == diaryId,
      orElse: () {
        final diary = <String, dynamic>{
          'id': diaryId,
          'title': 'Diary draft',
          'date': '2026-06-09',
          'status': 'draft',
          'contentMarkdown': 'Initial diary markdown',
        };
        diaryList.add(diary);
        return diary;
      },
    );
  }
}

class _FlakyReportWorkflowApi extends _ReportWorkflowApi {
  _FlakyReportWorkflowApi({super.reports});

  @override
  Future<Map<String, dynamic>> weatherLocations() async {
    weatherLocationsCallCount++;
    if (weatherLocationsCallCount == 1) {
      throw StateError('snapshot unavailable');
    }
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }
}

class _RetryFailureWorkflowApi extends _ReportWorkflowApi {
  _RetryFailureWorkflowApi({super.deliveries});

  @override
  Future<Map<String, dynamic>> retryDelivery(String deliveryId) async {
    retriedDeliveryIds.add(deliveryId);
    return <String, dynamic>{'ok': false};
  }
}

List<Map<String, dynamic>> _copyItems(Iterable<Map<String, dynamic>> items) {
  return [
    for (final item in items) Map<String, dynamic>.from(item),
  ];
}
