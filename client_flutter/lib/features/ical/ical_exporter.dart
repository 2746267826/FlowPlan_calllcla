// iCalendar RFC 5545 导出器：将数据库 CalendarEvent 列表格式化为 .ics 文本
import '../../../core/database/app_database.dart';

class ICalExporter {
  const ICalExporter();

  /// 将日程事件列表导出为标准 .ics 格式文本
  String export(List<CalendarEvent> events,
      {String calendarName = 'FlowPlan'}) {
    final buffer = StringBuffer();

    // VCALENDAR 头
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//FlowPlan//FlowPlan Calendar//CN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:$calendarName');

    for (final event in events) {
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${event.uid}');
      buffer.writeln('DTSTAMP:${_formatDateTime(event.dtstamp)}');
      buffer.writeln('DTSTART:${_formatDateTime(event.dtstart)}');

      if (event.dtend != null) {
        buffer.writeln('DTEND:${_formatDateTime(event.dtend!)}');
      }

      buffer.writeln('SUMMARY:${_escapeText(event.summary)}');

      if (event.description != null && event.description!.isNotEmpty) {
        buffer.writeln('DESCRIPTION:${_escapeText(event.description!)}');
      }

      if (event.location != null && event.location!.isNotEmpty) {
        buffer.writeln('LOCATION:${_escapeText(event.location!)}');
      }

      buffer.writeln('STATUS:${event.status}');

      if (event.rrule != null && event.rrule!.isNotEmpty) {
        buffer.writeln('RRULE:${event.rrule}');
      }

      // 颜色扩展属性（非标准，但 Outlook/Apple 支持）
      if (event.colorHex.isNotEmpty) {
        buffer.writeln('X-APPLE-CALENDAR-COLOR:${event.colorHex}');
      }

      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// 格式化为 iCalendar 日期时间 (UTC)
  String _formatDateTime(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}'
        'T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}'
        'Z';
  }

  /// 转义 iCal 文本
  String _escapeText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
  }
}
