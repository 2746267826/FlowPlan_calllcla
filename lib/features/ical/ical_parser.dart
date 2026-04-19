// iCalendar RFC 5545 解析器：将 .ics 文件内容解析为 CalendarEvent Companion 列表
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';

/// 将标准 iCalendar 文本解析为 CalendarEventsCompanion 列表
class ICalParser {
  const ICalParser();

  /// 解析 .ics 文件字符串内容
  List<CalendarEventsCompanion> parse(String icsContent) {
    final results = <CalendarEventsCompanion>[];

    // 规范化行折叠 (RFC 5545 §3.1)
    final unfolded =
        icsContent.replaceAll('\r\n ', '').replaceAll('\r\n\t', '');
    final lines = unfolded.split(RegExp(r'\r?\n'));

    bool inEvent = false;
    Map<String, String> currentProps = {};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed == 'BEGIN:VEVENT') {
        inEvent = true;
        currentProps = {};
        continue;
      }

      if (trimmed == 'END:VEVENT') {
        inEvent = false;
        final companion = _buildCompanion(currentProps);
        if (companion != null) results.add(companion);
        continue;
      }

      if (inEvent) {
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx > 0) {
          final key = trimmed.substring(0, colonIdx).toUpperCase();
          final value = trimmed.substring(colonIdx + 1);
          // 处理带参数的属性名 (e.g. DTSTART;TZID=xxx:20210101T090000)
          final baseName = key.split(';').first;
          currentProps[baseName] = value;
        }
      }
    }

    return results;
  }

  CalendarEventsCompanion? _buildCompanion(Map<String, String> props) {
    final summary = props['SUMMARY'];
    if (summary == null || summary.isEmpty) return null;

    final dtstart = _parseDateTime(props['DTSTART']);
    if (dtstart == null) return null;

    final dtend = _parseDateTime(props['DTEND']);
    final uid = props['UID'] ?? const Uuid().v4();
    final description = props['DESCRIPTION'];
    final location = props['LOCATION'];
    final status = props['STATUS'] ?? 'CONFIRMED';
    final rrule = props['RRULE'];
    final now = DateTime.now();

    return CalendarEventsCompanion.insert(
      uid: uid,
      dtstamp: now,
      summary: _unescapeText(summary),
      description:
          Value(description != null ? _unescapeText(description) : null),
      location: Value(location != null ? _unescapeText(location) : null),
      dtstart: dtstart,
      dtend: Value(dtend),
      status: Value(status),
      rrule: Value(rrule),
      colorHex: const Value('#6B5EE4'),
    );
  }

  /// 解析 iCalendar 日期时间格式
  /// 支持: 20210315T090000Z, 20210315T090000, 20210315
  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;

    try {
      // 移除可能的 TZID 前缀值
      final clean = value.trim();

      if (clean.length == 8) {
        // 纯日期: 20210315
        return DateTime(
          int.parse(clean.substring(0, 4)),
          int.parse(clean.substring(4, 6)),
          int.parse(clean.substring(6, 8)),
        );
      }

      if (clean.length >= 15) {
        // 日期时间: 20210315T090000 or 20210315T090000Z
        final isUtc = clean.endsWith('Z');
        final dateStr = clean.replaceAll('Z', '').replaceAll('T', '');
        final year = int.parse(dateStr.substring(0, 4));
        final month = int.parse(dateStr.substring(4, 6));
        final day = int.parse(dateStr.substring(6, 8));
        final hour = int.parse(dateStr.substring(8, 10));
        final minute = int.parse(dateStr.substring(10, 12));
        final second = int.parse(dateStr.substring(12, 14));

        final dt = DateTime(year, month, day, hour, minute, second);
        return isUtc ? dt.toLocal() : dt;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// 反转义 iCal 文本
  String _unescapeText(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\N', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }
}
