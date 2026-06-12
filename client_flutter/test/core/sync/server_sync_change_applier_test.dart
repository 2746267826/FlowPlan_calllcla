import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('applies user setting changes and records sync state', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);
    final applier = ServerSyncChangeApplier(db, stateStore);

    final result = await applier.applyPullResponse(<String, dynamic>{
      'changes': <Object?>[
        <String, Object?>{
          'changeId': 'change-1',
          'objectType': 'user_setting',
          'serverId': 'setting-server-1',
          'uid': 'client.theme',
          'action': 'upsert',
          'serverVersion': 2,
          'payload': <String, Object?>{
            'settingKey': 'client.theme',
            'settingValue': 'dark',
          },
        },
      ],
    });

    expect(result.applied, 1);
    expect(result.failed, 0);
    expect(await db.getSetting('client.theme'), 'dark');
    final state = await stateStore.getState(
      objectType: 'user_setting',
      localId: 'client.theme',
    );
    expect(state?.serverId, 'setting-server-1');
    expect(state?.serverVersion, 2);
  });

  test('skips malformed pull responses without mutating local data', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final applier = ServerSyncChangeApplier(db, SyncObjectStateStore(db));

    final result = await applier.applyPullResponse(<String, dynamic>{
      'changes': 'not-a-list',
    });

    expect(result.received, 0);
    expect(result.applied, 0);
    expect(result.skipped, 0);
  });

  test(
    'applies calendar books before events and cascades calendar deletes',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final stateStore = SyncObjectStateStore(db);

      final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'calendar-event-change',
          objectType: 'calendar_event',
          serverId: 'event-server-1',
          uid: 'outlook_event:remote-calendar-1:event-1',
          serverVersion: 3,
          payload: <String, Object?>{
            'summary': 'Design review',
            'description': 'Review the synced design',
            'startAt': '2026-06-10T09:00:00Z',
            'endAt': '2026-06-10T10:00:00Z',
            'remoteCalendarId': 'remote-calendar-1',
            'source': 'outlook',
            'location': <String, Object?>{'displayName': 'Room 9'},
          },
        ),
        _change(
          changeId: 'calendar-book-change',
          objectType: 'calendar_book',
          serverId: 'calendar-server-1',
          serverVersion: 2,
          payload: <String, Object?>{
            'name': 'Team Calendar',
            'remoteCalendarId': 'remote-calendar-1',
            'source': 'outlook',
            'colorHex': '#123456',
            'description': 'Remote team calendar',
          },
        ),
      ]);

      expect(result.applied, 2);
      expect(result.failed, 0);
      expect(
        result.appliedChangeIds,
        <String>['calendar-book-change', 'calendar-event-change'],
      );

      final calendar = _singleWhere(
        await _tableRows(db, 'event_calendars'),
        (row) => row['name'] == 'Team Calendar',
      );
      expect(calendar['source'], 'outlook');
      expect(calendar['sync_url'], 'remote-calendar-1');
      expect(calendar['color_hex'], '#123456');

      final event = _singleWhere(
        await _tableRows(db, 'calendar_events'),
        (row) => row['uid'] == 'outlook_event:remote-calendar-1:event-1',
      );
      expect(event['summary'], 'Design review');
      expect(event['location'], 'Room 9');
      expect(event['event_calendar_id'], calendar['id']);

      final eventState = await stateStore.getStateByServerId(
        objectType: 'calendar_event',
        serverId: 'event-server-1',
      );
      expect(eventState?.serverVersion, 3);

      final deleteResult = await _applyChanges(
        db,
        stateStore,
        <Map<String, Object?>>[
          _change(
            changeId: 'calendar-delete-change',
            objectType: 'calendar_book',
            serverId: 'calendar-server-1',
            action: 'delete',
            serverVersion: 4,
          ),
        ],
      );

      expect(deleteResult.applied, 1);
      expect(deleteResult.failed, 0);
      expect(await _rowById(db, 'event_calendars', calendar['id'] as int), isNull);
      expect(await _rowById(db, 'calendar_events', event['id'] as int), isNull);
      expect(
        await stateStore.getStateByServerId(
          objectType: 'calendar_book',
          serverId: 'calendar-server-1',
        ),
        isNull,
      );
      expect(
        await stateStore.getStateByServerId(
          objectType: 'calendar_event',
          serverId: 'event-server-1',
        ),
        isNull,
      );
    },
  );

  test('stale calendar book payload does not refresh local calendar names',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final freshResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'fresh-calendar-book',
          objectType: 'calendar_book',
          serverId: 'calendar-server-stale',
          serverVersion: 5,
          payload: <String, Object?>{
            'name': 'Fresh Calendar',
            'remoteCalendarId': 'remote-calendar-stale',
            'source': 'outlook',
            'colorHex': '#00AA00',
            'description': 'Fresh server name',
          },
        ),
      ],
    );
    expect(freshResult.applied, 1);

    final staleResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'stale-calendar-book',
          objectType: 'calendar_book',
          serverId: 'calendar-server-stale',
          serverVersion: 3,
          payload: <String, Object?>{
            'name': 'Stale Calendar',
            'remoteCalendarId': 'remote-calendar-stale',
            'source': 'outlook',
            'colorHex': '#FF0000',
            'description': 'Stale server name',
          },
        ),
      ],
    );

    expect(staleResult.applied, 0);
    expect(staleResult.skipped, 1);
    expect(staleResult.failed, 0);
    final calendar = _singleWhere(
      await _tableRows(db, 'event_calendars'),
      (row) => row['sync_url'] == 'remote-calendar-stale',
    );
    expect(calendar['name'], 'Fresh Calendar');
    expect(calendar['color_hex'], '#00AA00');
    expect(calendar['description'], 'Fresh server name');
    final state = await stateStore.getStateByServerId(
      objectType: 'calendar_book',
      serverId: 'calendar-server-stale',
    );
    expect(state?.serverVersion, 5);
  });

  test('upserts and deletes task lists and task items', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final listResult = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'task-list-change',
        objectType: 'task_list',
        serverId: 'task-list-server-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'name': 'Server Tasks',
          'colorHex': '#00AAFF',
          'emoji': 'S',
          'isArchived': false,
        },
      ),
    ]);
    expect(listResult.applied, 1);
    expect(listResult.failed, 0);

    final taskList = _singleWhere(
      await _tableRows(db, 'task_lists'),
      (row) => row['name'] == 'Server Tasks',
    );

    final itemResult = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'task-item-change',
        objectType: 'task_item',
        serverId: 'task-item-server-1',
        uid: 'task-item-uid-1',
        serverVersion: 3,
        payload: <String, Object?>{
          'summary': 'Write sync tests',
          'description': 'Cover server applier branches',
          'dueAt': '2026-06-11T12:00:00Z',
          'status': 'NEEDS-ACTION',
          'percentComplete': 20,
          'taskListId': taskList['id'],
          'durationMinutes': 45,
          'isLocked': true,
        },
      ),
    ]);
    expect(itemResult.applied, 1);
    expect(itemResult.failed, 0);

    final createdTask = _singleWhere(
      await _tableRows(db, 'task_items'),
      (row) => row['uid'] == 'task-item-uid-1',
    );
    expect(createdTask['summary'], 'Write sync tests');
    expect(createdTask['task_list_id'], taskList['id']);
    expect(createdTask['percent_complete'], 20);

    final updateResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'task-item-update-change',
          objectType: 'task_item',
          serverId: 'task-item-server-1',
          uid: 'task-item-uid-1',
          serverVersion: 7,
          payload: <String, Object?>{
            'summary': 'Ship sync tests',
            'status': 'COMPLETED',
            'percentComplete': 100,
            'completed': '2026-06-11T13:00:00Z',
            'taskListId': taskList['id'],
            'durationMinutes': 30,
          },
        ),
      ],
    );
    expect(updateResult.applied, 1);
    final updatedTask = await _rowById(
      db,
      'task_items',
      createdTask['id'] as int,
    );
    expect(updatedTask?['summary'], 'Ship sync tests');
    expect(updatedTask?['status'], 'COMPLETED');
    expect(updatedTask?['percent_complete'], 100);
    final updatedState = await stateStore.getStateByServerId(
      objectType: 'task_item',
      serverId: 'task-item-server-1',
    );
    expect(updatedState?.serverVersion, 7);

    final deleteResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'task-item-delete-change',
          objectType: 'task_item',
          serverId: 'task-item-server-1',
          action: 'delete',
        ),
        _change(
          changeId: 'task-list-delete-change',
          objectType: 'task_list',
          serverId: 'task-list-server-1',
          action: 'delete',
        ),
      ],
    );

    expect(deleteResult.applied, 2);
    expect(deleteResult.failed, 0);
    expect(await _rowById(db, 'task_items', createdTask['id'] as int), isNull);
    expect(await _rowById(db, 'task_lists', taskList['id'] as int), isNull);
    expect(
      await stateStore.getStateByServerId(
        objectType: 'task_item',
        serverId: 'task-item-server-1',
      ),
      isNull,
    );
  });

  test('skips stale server versions without overwriting newer local state',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'task-list-change',
        objectType: 'task_list',
        serverId: 'task-list-server-stale',
        serverVersion: 1,
        payload: <String, Object?>{
          'name': 'Server Tasks',
        },
      ),
    ]);
    final taskList = _singleWhere(
      await _tableRows(db, 'task_lists'),
      (row) => row['name'] == 'Server Tasks',
    );

    final freshResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'fresh-task-change',
          objectType: 'task_item',
          serverId: 'task-item-server-stale',
          uid: 'task-item-uid-stale',
          serverVersion: 5,
          payload: <String, Object?>{
            'summary': 'Fresh remote title',
            'status': 'COMPLETED',
            'percentComplete': 100,
            'taskListId': taskList['id'],
          },
        ),
      ],
    );
    expect(freshResult.applied, 1);
    final createdTask = _singleWhere(
      await _tableRows(db, 'task_items'),
      (row) => row['uid'] == 'task-item-uid-stale',
    );

    final staleResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'stale-task-change',
          objectType: 'task_item',
          serverId: 'task-item-server-stale',
          uid: 'task-item-uid-stale',
          serverVersion: 3,
          payload: <String, Object?>{
            'summary': 'Stale remote title',
            'status': 'NEEDS-ACTION',
            'percentComplete': 0,
            'taskListId': taskList['id'],
          },
        ),
      ],
    );

    expect(staleResult.applied, 0);
    expect(staleResult.skipped, 1);
    expect(staleResult.failed, 0);
    expect(staleResult.appliedChangeIds, isEmpty);
    final taskAfterStale = await _rowById(
      db,
      'task_items',
      createdTask['id'] as int,
    );
    expect(taskAfterStale?['summary'], 'Fresh remote title');
    expect(taskAfterStale?['status'], 'COMPLETED');
    expect(taskAfterStale?['percent_complete'], 100);
    final stateAfterStale = await stateStore.getStateByServerId(
      objectType: 'task_item',
      serverId: 'task-item-server-stale',
    );
    expect(stateAfterStale?.serverVersion, 5);
  });

  test('upserts, updates, and deletes report objects', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final reportResult = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'report-change',
        objectType: 'report_document',
        serverId: 'report-server-1',
        uid: 'report-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'reportType': 'weekly',
          'periodStart': '2026-06-01T00:00:00Z',
          'periodEnd': '2026-06-07T23:59:59Z',
          'title': 'Weekly sync report',
          'summaryMarkdown': 'Initial report',
          'metricsJson': '{"tasks":4}',
          'status': 'draft',
        },
      ),
    ]);
    expect(reportResult.applied, 1);
    expect(reportResult.failed, 0);

    final report = _singleWhere(
      await _tableRows(db, 'report_documents'),
      (row) => row['report_uid'] == 'report-uid-1',
    );
    expect(report['title'], 'Weekly sync report');
    expect(report['metrics_json'], '{"tasks":4}');

    final updateResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'report-update-change',
          objectType: 'report_document',
          serverId: 'report-server-1',
          uid: 'report-uid-1',
          serverVersion: 5,
          payload: <String, Object?>{
            'reportType': 'weekly',
            'periodStart': '2026-06-01T00:00:00Z',
            'periodEnd': '2026-06-07T23:59:59Z',
            'title': 'Weekly sync report confirmed',
            'summaryMarkdown': 'Updated report',
            'metricsJson': '{"tasks":5}',
            'status': 'confirmed',
          },
        ),
      ],
    );
    expect(updateResult.applied, 1);
    final updatedReport = await _rowById(
      db,
      'report_documents',
      report['id'] as int,
    );
    expect(updatedReport?['title'], 'Weekly sync report confirmed');
    expect(updatedReport?['status'], 'confirmed');

    final diaryResult = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'diary-change',
        objectType: 'diary_entry',
        serverId: 'diary-server-1',
        uid: 'diary-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'entryDate': '2026-06-08T08:00:00Z',
          'title': 'Synced diary',
          'bodyMarkdown': 'Report notes',
          'sourceReportId': report['id'],
          'linkedTaskIdsJson': '["task-item-uid-1"]',
          'status': 'draft',
        },
      ),
    ]);
    expect(diaryResult.applied, 1);
    final diary = _singleWhere(
      await _tableRows(db, 'diary_entries'),
      (row) => row['diary_uid'] == 'diary-uid-1',
    );
    expect(diary['entry_date'], '2026-06-08');
    expect(diary['source_report_id'], report['id']);

    final deliveryResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'delivery-change',
          objectType: 'report_push_delivery',
          serverId: 'delivery-server-1',
          uid: 'delivery-uid-1',
          serverVersion: 2,
          payload: <String, Object?>{
            'reportId': report['id'],
            'diaryId': diary['id'],
            'channel': 'email',
            'target': 'ops@example.test',
            'payloadJson': '{"ok":true}',
            'status': 'pending',
            'scheduledAt': '2026-06-09T01:00:00Z',
          },
        ),
      ],
    );
    expect(deliveryResult.applied, 1);
    final delivery = _singleWhere(
      await _tableRows(db, 'report_push_deliveries'),
      (row) => row['delivery_uid'] == 'delivery-uid-1',
    );
    expect(delivery['channel'], 'email');
    expect(delivery['report_id'], report['id']);
    expect(delivery['diary_id'], diary['id']);

    final deleteResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'delete-delivery-change',
          objectType: 'report_push_delivery',
          serverId: 'delivery-server-1',
          action: 'delete',
        ),
        _change(
          changeId: 'delete-diary-change',
          objectType: 'diary_entry',
          serverId: 'diary-server-1',
          action: 'delete',
        ),
        _change(
          changeId: 'delete-report-change',
          objectType: 'report_document',
          serverId: 'report-server-1',
          action: 'delete',
        ),
      ],
    );
    expect(deleteResult.applied, 3);
    expect(deleteResult.failed, 0);
    expect(await _rowById(db, 'report_documents', report['id'] as int), isNull);
    expect(await _rowById(db, 'diary_entries', diary['id'] as int), isNull);
    expect(
      await _rowById(db, 'report_push_deliveries', delivery['id'] as int),
      isNull,
    );
  });

  test('upserts and deletes file management objects', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'file-folder-change',
        objectType: 'file_folder',
        serverId: 'folder-server-1',
        uid: 'folder-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'provider': 'onedrive',
          'displayName': 'Specs',
          'localPath': 'C:/remote/specs',
          'remoteId': 'drive-folder-1',
          'pinned': true,
          'availability': 'available',
          'useCount': 3,
        },
      ),
    ]);
    final folder = _singleWhere(
      await _tableRows(db, 'file_folders'),
      (row) => row['folder_uid'] == 'folder-uid-1',
    );
    expect(folder['display_name'], 'Specs');
    expect(folder['provider'], 'onedrive');

    await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'file-item-change',
        objectType: 'file_item',
        serverId: 'file-server-1',
        uid: 'file-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'provider': 'onedrive',
          'displayName': 'Spec.md',
          'folderId': folder['id'],
          'localPath': 'C:/remote/specs/Spec.md',
          'remoteId': 'drive-file-1',
          'mimeType': 'text/markdown',
          'sizeBytes': '2048',
          'modifiedAt': '2026-06-09T03:00:00Z',
          'availability': 'available',
          'previewMode': 'markdown',
        },
      ),
    ]);
    final file = _singleWhere(
      await _tableRows(db, 'file_items'),
      (row) => row['file_uid'] == 'file-uid-1',
    );
    expect(file['display_name'], 'Spec.md');
    expect(file['folder_id'], folder['id']);
    expect(file['size_bytes'], 2048);

    await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'file-link-change',
        objectType: 'file_context_link',
        serverId: 'link-server-1',
        uid: 'link-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'entityType': 'task',
          'entityId': 'task-42',
          'targetType': 'file',
          'targetId': file['id'],
          'relationType': 'evidence',
          'confidence': '0.75',
          'reason': 'Initial match',
          'status': 'confirmed',
        },
      ),
      _change(
        changeId: 'folder-usage-change',
        objectType: 'file_folder_usage',
        serverId: 'usage-server-1',
        uid: 'usage-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'folderId': folder['id'],
          'entityType': 'report',
          'entityId': 'report-uid-1',
          'action': 'open',
          'source': 'sync',
          'usedAt': '2026-06-09T04:00:00Z',
          'metadataJson': '{"surface":"server"}',
        },
      ),
      _change(
        changeId: 'file-version-change',
        objectType: 'file_version_record',
        serverId: 'version-server-1',
        uid: 'version-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'fileId': file['id'],
          'provider': 'kopia',
          'versionRef': 'snapshot-1',
          'displayName': 'Spec v1',
          'sizeBytes': 2048,
          'checksum': 'abc123',
        },
      ),
    ]);

    final link = _singleWhere(
      await _tableRows(db, 'file_context_links'),
      (row) => row['link_uid'] == 'link-uid-1',
    );
    expect(link['target_id'], file['id']);
    expect(link['confidence'], 0.75);
    final usage = _singleWhere(
      await _tableRows(db, 'file_folder_usages'),
      (row) => row['usage_uid'] == 'usage-uid-1',
    );
    expect(usage['folder_id'], folder['id']);
    final version = _singleWhere(
      await _tableRows(db, 'file_version_records'),
      (row) => row['version_uid'] == 'version-uid-1',
    );
    expect(version['version_ref'], 'snapshot-1');

    await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'file-link-natural-key-change',
        objectType: 'file_context_link',
        serverId: 'link-server-2',
        uid: 'link-uid-2',
        serverVersion: 4,
        payload: <String, Object?>{
          'entityType': 'task',
          'entityId': 'task-42',
          'targetType': 'file',
          'targetId': file['id'],
          'relationType': 'evidence',
          'confidence': 0.9,
          'reason': 'Updated natural key match',
          'status': 'confirmed',
        },
      ),
    ]);
    final dedupedLinks = await _tableRows(db, 'file_context_links');
    expect(dedupedLinks, hasLength(1));
    expect(dedupedLinks.single['id'], link['id']);
    expect(dedupedLinks.single['link_uid'], 'link-uid-2');
    expect(dedupedLinks.single['reason'], 'Updated natural key match');

    final deleteResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'delete-file-version-change',
          objectType: 'file_version_record',
          serverId: 'version-server-1',
          action: 'delete',
        ),
        _change(
          changeId: 'delete-file-usage-change',
          objectType: 'file_folder_usage',
          serverId: 'usage-server-1',
          action: 'delete',
        ),
        _change(
          changeId: 'delete-file-link-change',
          objectType: 'file_context_link',
          serverId: 'link-server-2',
          action: 'delete',
        ),
        _change(
          changeId: 'delete-file-item-change',
          objectType: 'file_item',
          serverId: 'file-server-1',
          action: 'delete',
        ),
        _change(
          changeId: 'delete-file-folder-change',
          objectType: 'file_folder',
          serverId: 'folder-server-1',
          action: 'delete',
        ),
      ],
    );
    expect(deleteResult.applied, 5);
    expect(deleteResult.failed, 0);
    expect(await _rowById(db, 'file_folders', folder['id'] as int), isNull);
    expect(await _rowById(db, 'file_items', file['id'] as int), isNull);
    expect(await _rowById(db, 'file_context_links', link['id'] as int), isNull);
    expect(await _rowById(db, 'file_folder_usages', usage['id'] as int), isNull);
    expect(
      await _rowById(db, 'file_version_records', version['id'] as int),
      isNull,
    );
  });

  test('applies audit logs idempotently and tolerates audit deletes', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'audit-change',
        objectType: 'audit_log',
        serverId: 'audit-server-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'occurredAt': '2026-06-09T05:00:00Z',
          'actor': 'server',
          'action': 'upsert',
          'entityType': 'task_item',
          'entityId': 'task-item-server-1',
          'summary': 'Remote task changed',
          'metadataJson': '{"source":"sync"}',
        },
      ),
    ]);
    expect(result.applied, 1);
    expect(result.failed, 0);

    final log = _singleWhere(
      await _tableRows(db, 'data_operation_logs'),
      (row) => row['summary'] == 'Remote task changed',
    );
    expect(log['actor'], 'server');
    expect(log['entity_type'], 'task_item');

    final updateResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'audit-repeat-change',
          objectType: 'audit_log',
          serverId: 'audit-server-1',
          serverVersion: 5,
          payload: <String, Object?>{
            'summary': 'Should not insert a second log',
          },
        ),
      ],
    );
    expect(updateResult.applied, 1);
    expect(await _tableRows(db, 'data_operation_logs'), hasLength(1));
    final state = await stateStore.getStateByServerId(
      objectType: 'audit_log',
      serverId: 'audit-server-1',
    );
    expect(state?.localId, (log['id'] as int).toString());
    expect(state?.serverVersion, 5);

    final deleteResult = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'audit-delete-change',
          objectType: 'audit_log',
          serverId: 'audit-server-1',
          action: 'delete',
          serverVersion: 6,
        ),
      ],
    );
    expect(deleteResult.applied, 1);
    expect(deleteResult.failed, 0);
    expect(await _tableRows(db, 'data_operation_logs'), hasLength(1));
    expect(
      await stateStore.getStateByServerId(
        objectType: 'audit_log',
        serverId: 'audit-server-1',
      ),
      isNull,
    );
  });
}

Map<String, Object?> _change({
  required String changeId,
  required String objectType,
  required String serverId,
  String action = 'upsert',
  int serverVersion = 1,
  String? uid,
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return <String, Object?>{
    'changeId': changeId,
    'objectType': objectType,
    'serverId': serverId,
    if (uid != null) 'uid': uid,
    'action': action,
    'serverVersion': serverVersion,
    'payload': payload,
  };
}

Future<ServerSyncApplyResult> _applyChanges(
  AppDatabase db,
  SyncObjectStateStore stateStore,
  List<Map<String, Object?>> changes,
) {
  final applier = ServerSyncChangeApplier(db, stateStore);
  return applier.applyPullResponse(<String, Object?>{
    'changes': changes,
  });
}

Future<List<Map<String, dynamic>>> _tableRows(
  AppDatabase db,
  String tableName,
) async {
  final rows = await db.customSelect('SELECT * FROM $tableName ORDER BY id').get();
  return rows
      .map((row) => Map<String, dynamic>.from(row.data))
      .toList(growable: false);
}

Map<String, dynamic> _singleWhere(
  List<Map<String, dynamic>> rows,
  bool Function(Map<String, dynamic> row) matches,
) {
  final found = rows.where(matches).toList(growable: false);
  expect(found, hasLength(1));
  return found.single;
}

Future<Map<String, dynamic>?> _rowById(
  AppDatabase db,
  String tableName,
  int id,
) async {
  final matches = (await _tableRows(db, tableName))
      .where((row) => row['id'] == id)
      .toList(growable: false);
  if (matches.isEmpty) {
    return null;
  }
  return matches.single;
}
