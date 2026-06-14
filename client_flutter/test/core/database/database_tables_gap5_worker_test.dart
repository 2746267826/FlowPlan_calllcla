import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/database/app_database_connection_io.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/storage/app_storage_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_support/test_database.dart';

void main() {
  test('io database connection creates storage path and export replaces target',
      () async {
    final previousPathProvider = PathProviderPlatform.instance;
    final documentsDirectory =
        await Directory.systemTemp.createTemp('flowplan-gap5-storage-');
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      documentsDirectory.path,
    );
    final db = AppDatabase.forTesting(openAppDatabaseConnection());

    try {
      final databasePath = await resolveAppDatabasePathForDisplay();
      expect(
        databasePath,
        p.join(
          documentsDirectory.path,
          appStorageDirectoryName,
          appDatabaseFileName,
        ),
      );

      expect(await db.getSetting('gap5.missing'), isNull);
      expect(await File(databasePath).exists(), isTrue);
      final busyTimeoutRow =
          await db.customSelect('PRAGMA busy_timeout').getSingle();
      final journalModeRow =
          await db.customSelect('PRAGMA journal_mode').getSingle();

      expect(
        int.parse(busyTimeoutRow.data.values.single.toString()),
        greaterThanOrEqualTo(5000),
      );
      expect(
        journalModeRow.data.values.single.toString().toLowerCase(),
        'wal',
      );

      final targetFile = File(
        p.join(documentsDirectory.path, 'existing-export.sqlite'),
      );
      await targetFile.writeAsString('stale export');

      await exportAppDatabase(db, targetFile.path);

      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.length(), greaterThan(0));
    } finally {
      await db.close();
      PathProviderPlatform.instance = previousPathProvider;
      if (await documentsDirectory.exists()) {
        await documentsDirectory.delete(recursive: true);
      }
    }
  });

  test('generated tables expose remaining Drift declaration columns', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    expect(
      db.appUsageRules.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'process_name',
        'window_title_pattern',
        'category',
        'custom_label',
        'hit_count',
      ]),
    );
    expect(
      db.eventCalendars.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'name',
        'color_hex',
        'description',
        'is_visible',
        'is_default',
        'source',
        'sync_url',
        'created_at',
      ]),
    );
    expect(
      db.projects.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'name',
        'color_hex',
        'description',
        'deadline',
        'is_archived',
        'created_at',
      ]),
    );
    expect(
      db.tags.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'name',
        'color_hex',
        'icon_name',
      ]),
    );
    expect(
      db.taskLists.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'name',
        'color_hex',
        'emoji',
        'is_visible',
        'is_default',
        'is_archived',
        'created_at',
      ]),
    );
  });

  test('generated companions apply defaults for remaining table declarations',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 11, 12);

    final ruleId = await db.into(db.appUsageRules).insert(
          AppUsageRulesCompanion.insert(
            processName: 'Code.exe',
            category: 'coding',
          ),
        );
    final calendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Gap5 calendar',
            createdAt: now,
          ),
        );
    final projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            name: 'Gap5 project',
            colorHex: '#123456',
            createdAt: now,
          ),
        );
    final tagId = await db.into(db.tags).insert(
          TagsCompanion.insert(
            name: 'Gap5 tag',
            colorHex: '#654321',
          ),
        );
    final listId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Gap5 list',
            createdAt: now,
          ),
        );

    final rule = await (db.select(db.appUsageRules)
          ..where((table) => table.id.equals(ruleId)))
        .getSingle();
    expect(rule.windowTitlePattern, isNull);
    expect(rule.customLabel, isNull);
    expect(rule.hitCount, 0);

    final calendar = await (db.select(db.eventCalendars)
          ..where((table) => table.id.equals(calendarId)))
        .getSingle();
    expect(calendar.colorHex, '#6B5EE4');
    expect(calendar.description, isNull);
    expect(calendar.isVisible, isTrue);
    expect(calendar.isDefault, isFalse);
    expect(calendar.source, 'local');
    expect(calendar.syncUrl, isNull);

    final project = await (db.select(db.projects)
          ..where((table) => table.id.equals(projectId)))
        .getSingle();
    expect(project.description, isNull);
    expect(project.deadline, isNull);
    expect(project.isArchived, isFalse);

    final tag = await (db.select(db.tags)
          ..where((table) => table.id.equals(tagId)))
        .getSingle();
    expect(tag.iconName, isNull);

    final list = await (db.select(db.taskLists)
          ..where((table) => table.id.equals(listId)))
        .getSingle();
    expect(list.colorHex, '#0EA8A0');
    expect(list.emoji, isNull);
    expect(list.isVisible, isTrue);
    expect(list.isDefault, isFalse);
    expect(list.isArchived, isFalse);
  });

  test('remote settings refresh caches metadata policy and numeric versions',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = _FakeClientApi(db)
      ..settingsResponse = <String, dynamic>{
        'version': 2.75,
        'updatedAt': '2026-06-11T12:00:00Z',
        'policy': <String, Object?>{
          'allowRemoteOverride': true,
          'scope': 'device',
        },
        'settings': <Object?>[
          <String, Object?>{
            'key': 'theme.mode',
            'value': 'dark',
          },
          'ignored non-map entry',
        ],
      };
    final repository = RemoteSettingsRepository(
      database: db,
      clientApi: api,
    );

    final snapshot = await repository.refresh();

    expect(snapshot.version, 2);
    expect(snapshot.updatedAt, DateTime.utc(2026, 6, 11, 12));
    expect(snapshot.settings, hasLength(1));
    expect(snapshot.settings.single['key'], 'theme.mode');
    expect(
      await db.getSetting(RemoteSettingsRepository.versionKey),
      '2.75',
    );
    expect(
      await db.getSetting(RemoteSettingsRepository.updatedAtKey),
      '2026-06-11T12:00:00Z',
    );
    expect(
      await db.getSetting(RemoteSettingsRepository.cachedPolicyKey),
      '{"allowRemoteOverride":true,"scope":"device"}',
    );
  });

  test('remote settings cache reads missing blank object and non-object states',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = RemoteSettingsRepository(
      database: db,
      clientApi: _FakeClientApi(db),
    );

    expect(await repository.readCached(), isNull);

    await db.setSetting(RemoteSettingsRepository.cachedSettingsKey, '   ');
    expect(await repository.readCached(), isNull);

    await db.setSetting(
      RemoteSettingsRepository.cachedSettingsKey,
      '{"version":"7","updatedAt":"2026-06-11T13:00:00Z",'
      '"settings":[{"key":"sync.enabled","value":true},42]}',
    );
    final cached = await repository.readCached();
    expect(cached, isNotNull);
    expect(cached!.version, 7);
    expect(cached.updatedAt, DateTime.utc(2026, 6, 11, 13));
    expect(cached.settings, hasLength(1));
    expect(cached.settings.single['key'], 'sync.enabled');

    await db.setSetting(
      RemoteSettingsRepository.cachedSettingsKey,
      '["not","an","object"]',
    );
    expect(await repository.readCached(), isNull);
  });
}

class _FakeClientApi extends ClientApi {
  _FakeClientApi(AppDatabase db)
      : super(
          ApiClient(
            baseUri: Uri.parse('http://unused.invalid'),
            tokenStore: AuthTokenStore(db),
          ),
        );

  Map<String, dynamic> settingsResponse = const <String, dynamic>{
    'version': 1,
    'settings': <Object?>[],
  };

  @override
  Future<Map<String, dynamic>> settings() async {
    return settingsResponse;
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationCachePath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;
}
