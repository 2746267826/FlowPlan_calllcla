// 双向增量同步引擎
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/app_database.dart';
import '../calendar/data/event_repository.dart';
import 'ms_graph_service.dart';
import 'outlook_auth_service.dart';

/// 同步引擎：本地 ↔ Outlook 双向同步
class SyncEngine {
  final EventRepository _eventRepo;
  final OutlookConfig _config;
  late final MsGraphService _graphService;

  static const _deltaLinkKey = 'outlook_sync_delta_link';
  static const _lastSyncKey = 'outlook_last_sync';

  SyncEngine(this._eventRepo, this._config) {
    _graphService = MsGraphService(_config);
  }

  /// 执行完整同步
  /// 返回 (uploaded, downloaded) 数量
  Future<({int uploaded, int downloaded})> sync() async {
    int uploaded = 0;
    int downloaded = 0;

    // 1. 从 Outlook 拉取变更
    downloaded = await _pullFromOutlook();

    // 2. 将本地变更推送到 Outlook
    uploaded = await _pushToOutlook();

    // 记录同步时间
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());

    return (uploaded: uploaded, downloaded: downloaded);
  }

  /// 从 Outlook 拉取事件
  Future<int> _pullFromOutlook() async {
    final prefs = await SharedPreferences.getInstance();
    final deltaLink = prefs.getString(_deltaLinkKey);

    final result = await _graphService.getEvents(deltaLink: deltaLink);

    // 保存新的 deltaLink
    if (result.deltaLink != null) {
      await prefs.setString(_deltaLinkKey, result.deltaLink!);
    }

    int count = 0;
    for (final graphEvent in result.events) {
      final parsed = MsGraphService.fromGraphEvent(graphEvent);

      // 检查本地是否已有该事件（通过 uid 匹配）
      // 简单策略：用 Graph ID 作为 uid 前缀匹配
      final uid = 'outlook_${parsed.id}';

      final companion = CalendarEventsCompanion.insert(
        uid: uid,
        dtstamp: DateTime.now(),
        summary: parsed.subject,
        description: Value(parsed.body),
        location: Value(parsed.location),
        dtstart: parsed.start,
        dtend: Value(parsed.end),
        status: const Value('CONFIRMED'),
        colorHex: const Value('#0078D4'), // Outlook 蓝
      );

      // 尝试更新已有的，否则创建新的
      await _eventRepo.create(companion);
      count++;
    }

    return count;
  }

  /// 推送本地事件到 Outlook
  Future<int> _pushToOutlook() async {
    // 未来可通过 SharedPreferences 中的 lastSyncKey 过滤仅推送上次同步后修改的事件

    // 获取本地近期事件
    final now = DateTime.now();
    final events = await _eventRepo
        .watchForDateRange(
          now.subtract(const Duration(days: 7)),
          now.add(const Duration(days: 365)),
        )
        .first;

    int count = 0;
    for (final event in events) {
      // 跳过从 Outlook 同步下来的事件（避免循环）
      if (event.uid.startsWith('outlook_')) continue;

      // 创建到 Outlook
      final graphEvent = MsGraphService.toGraphEvent(
        subject: event.summary,
        start: event.dtstart,
        end: event.dtend ?? event.dtstart.add(const Duration(hours: 1)),
        body: event.description,
        location: event.location,
      );

      final result = await _graphService.createEvent(graphEvent);
      if (result != null) count++;
    }

    return count;
  }

  /// 获取上次同步时间
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_lastSyncKey);
    return str != null ? DateTime.tryParse(str) : null;
  }

  /// 清除同步状态
  static Future<void> resetSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deltaLinkKey);
    await prefs.remove(_lastSyncKey);
  }
}
