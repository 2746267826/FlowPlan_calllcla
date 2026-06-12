import 'dart:convert';

import '../database/app_database.dart';
import 'client_api.dart';

class RemoteSettingsRepository {
  RemoteSettingsRepository({
    required AppDatabase database,
    required ClientApi clientApi,
  })  : _database = database,
        _clientApi = clientApi;

  static const cachedSettingsKey = 'server.remote_settings.cache_json';
  static const cachedPolicyKey = 'server.remote_settings.policy_json';
  static const versionKey = 'server.remote_settings.version';
  static const updatedAtKey = 'server.remote_settings.updated_at';

  final AppDatabase _database;
  final ClientApi _clientApi;

  Future<RemoteSettingsSnapshot> refresh() async {
    final response = await _clientApi.settings();
    final encoded = jsonEncode(response);
    await _database.setSetting(cachedSettingsKey, encoded);
    await _database.setSetting(
      versionKey,
      (response['version'] ?? 0).toString(),
    );
    final updatedAt = response['updatedAt']?.toString();
    if (updatedAt != null && updatedAt.isNotEmpty) {
      await _database.setSetting(updatedAtKey, updatedAt);
    }
    final policy = response['policy'];
    if (policy != null) {
      await _database.setSetting(cachedPolicyKey, jsonEncode(policy));
    }
    return RemoteSettingsSnapshot.fromJson(response);
  }

  Future<RemoteSettingsSnapshot?> readCached() async {
    final raw = await _database.getSetting(cachedSettingsKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return RemoteSettingsSnapshot.fromJson(Map<String, dynamic>.from(decoded));
  }
}

class RemoteSettingsSnapshot {
  const RemoteSettingsSnapshot({
    required this.version,
    required this.settings,
    this.updatedAt,
  });

  final int version;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> settings;

  factory RemoteSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    return RemoteSettingsSnapshot(
      version: _readInt(json['version']),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      settings: rawSettings is List
          ? rawSettings
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
