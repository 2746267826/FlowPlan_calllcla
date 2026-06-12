import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/platform/desktop_shell_service.dart';
import '../data/report_repository.dart';

class TelegramPushResult {
  const TelegramPushResult({
    required this.sent,
    required this.failed,
  });

  final int sent;
  final int failed;
}

class ReportPushService {
  ReportPushService({
    required AppDatabase database,
    required ReportRepository reportRepository,
    DesktopShellService shellService = const DesktopShellService(),
    http.Client? httpClient,
  })  : _db = database,
        _reports = reportRepository,
        _shellService = shellService,
        _httpClient = httpClient ?? http.Client();

  static const telegramBotTokenKey = 'integrations.telegram.bot_token';
  static const telegramChatIdKey = 'integrations.telegram.chat_id';
  static const reportWebhookUrlKey = 'integrations.report_webhook.url';
  static const reportEmailTargetKey = 'integrations.report_email.target';
  static const reportDetailBaseUrlKey = 'reports.detail_base_url';

  final AppDatabase _db;
  final ReportRepository _reports;
  final DesktopShellService _shellService;
  final http.Client _httpClient;

  Future<ReportPushDelivery> queueTelegramReport(
    ReportDocument report, {
    String? chatId,
  }) async {
    final target = chatId ?? await _db.getSetting(telegramChatIdKey);
    final detailBaseUrl = await _db.getSetting(reportDetailBaseUrlKey);
    final detailUrl = detailBaseUrl == null || detailBaseUrl.trim().isEmpty
        ? null
        : '${detailBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/reports/${report.reportUid}';
    return _reports.queueDelivery(
      reportId: report.id,
      channel: 'telegram',
      target: target,
      payload: <String, Object?>{
        'text': _buildTelegramSummary(report, detailUrl: detailUrl),
        'report_uid': report.reportUid,
        'report_type': report.reportType,
        'detail_url': detailUrl,
      },
    );
  }

  Future<ReportPushDelivery> queueSystemNotification(ReportDocument report) {
    return _reports.queueDelivery(
      reportId: report.id,
      channel: 'system_notification',
      payload: <String, Object?>{
        'title': report.title,
        'body': _firstLines(report.summaryMarkdown, 4),
        'report_uid': report.reportUid,
      },
    );
  }

  Future<ReportPushDelivery> queueWebhookReport(
    ReportDocument report, {
    String? webhookUrl,
  }) async {
    final target = webhookUrl ?? await _db.getSetting(reportWebhookUrlKey);
    return _reports.queueDelivery(
      reportId: report.id,
      channel: 'webhook',
      target: target,
      payload: <String, Object?>{
        'report_uid': report.reportUid,
        'report_type': report.reportType,
        'title': report.title,
        'summary_markdown': report.summaryMarkdown,
        'metrics_json': report.metricsJson,
      },
    );
  }

  Future<ReportPushDelivery> queueEmailReport(
    ReportDocument report, {
    String? targetEmail,
  }) async {
    final target = targetEmail ?? await _db.getSetting(reportEmailTargetKey);
    return _reports.queueDelivery(
      reportId: report.id,
      channel: 'email',
      target: target,
      payload: <String, Object?>{
        'subject': report.title,
        'body_markdown': report.summaryMarkdown,
        'report_uid': report.reportUid,
      },
    );
  }

  Future<TelegramPushResult> sendPendingTelegram({int limit = 10}) async {
    final token = await _db.getSetting(telegramBotTokenKey);
    if (token == null || token.trim().isEmpty) {
      throw StateError('Telegram bot token is not configured.');
    }

    final deliveries = await _reports.listPendingDeliveries(
      channel: 'telegram',
      limit: limit,
    );
    var sent = 0;
    var failed = 0;
    for (final delivery in deliveries) {
      try {
        await _reports.markDeliverySending(delivery.id);
        final payload = _decodePayload(delivery.payloadJson);
        final chatId =
            delivery.target ?? await _db.getSetting(telegramChatIdKey);
        if (chatId == null || chatId.trim().isEmpty) {
          throw StateError('Telegram chat id is not configured.');
        }
        final response = await _httpClient.post(
          Uri.https('api.telegram.org', '/bot${token.trim()}/sendMessage'),
          headers: const <String, String>{
            'content-type': 'application/json',
          },
          body: jsonEncode(<String, Object?>{
            'chat_id': chatId.trim(),
            'text': payload['text']?.toString() ?? '',
            'disable_web_page_preview': true,
          }),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError(
              'Telegram returned ${response.statusCode}: ${response.body}');
        }
        await _reports.markDeliverySent(delivery.id);
        sent++;
      } catch (error) {
        await _reports.markDeliveryFailed(delivery.id, error);
        failed++;
      }
    }
    return TelegramPushResult(sent: sent, failed: failed);
  }

  Future<TelegramPushResult> sendPendingWebhooks({int limit = 10}) async {
    final deliveries = await _reports.listPendingDeliveries(
      channel: 'webhook',
      limit: limit,
    );
    var sent = 0;
    var failed = 0;
    for (final delivery in deliveries) {
      try {
        await _reports.markDeliverySending(delivery.id);
        final target =
            delivery.target ?? await _db.getSetting(reportWebhookUrlKey);
        if (target == null || target.trim().isEmpty) {
          throw StateError('Webhook url is not configured.');
        }
        final response = await _httpClient.post(
          Uri.parse(target.trim()),
          headers: const <String, String>{
            'content-type': 'application/json',
          },
          body: delivery.payloadJson,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError(
              'Webhook returned ${response.statusCode}: ${response.body}');
        }
        await _reports.markDeliverySent(delivery.id);
        sent++;
      } catch (error) {
        await _reports.markDeliveryFailed(delivery.id, error);
        failed++;
      }
    }
    return TelegramPushResult(sent: sent, failed: failed);
  }

  Future<TelegramPushResult> sendPendingSystemNotifications({
    int limit = 10,
  }) async {
    final deliveries = await _reports.listPendingDeliveries(
      channel: 'system_notification',
      limit: limit,
    );
    var sent = 0;
    var failed = 0;
    for (final delivery in deliveries) {
      try {
        await _reports.markDeliverySending(delivery.id);
        final payload = _decodePayload(delivery.payloadJson);
        await _shellService.showReminder(
          title: payload['title']?.toString() ?? 'FlowPlanV2 报告',
          body: payload['body']?.toString() ?? '',
        );
        await _reports.markDeliverySent(delivery.id);
        sent++;
      } catch (error) {
        await _reports.markDeliveryFailed(delivery.id, error);
        failed++;
      }
    }
    return TelegramPushResult(sent: sent, failed: failed);
  }

  Future<TelegramPushResult> sendPendingEmails({int limit = 10}) async {
    final deliveries = await _reports.listPendingDeliveries(
      channel: 'email',
      limit: limit,
    );
    var sent = 0;
    var failed = 0;
    for (final delivery in deliveries) {
      try {
        await _reports.markDeliverySending(delivery.id);
        final payload = _decodePayload(delivery.payloadJson);
        final target =
            delivery.target ?? await _db.getSetting(reportEmailTargetKey);
        if (target == null || target.trim().isEmpty) {
          throw StateError('Email target is not configured.');
        }
        final uri = Uri(
          scheme: 'mailto',
          path: target.trim(),
          queryParameters: <String, String>{
            'subject': payload['subject']?.toString() ?? 'FlowPlanV2 报告',
            'body': payload['body_markdown']?.toString() ?? '',
          },
        );
        final launched = await launchUrl(uri);
        if (!launched) {
          throw StateError('Could not open email client.');
        }
        await _reports.markDeliverySent(delivery.id);
        sent++;
      } catch (error) {
        await _reports.markDeliveryFailed(delivery.id, error);
        failed++;
      }
    }
    return TelegramPushResult(sent: sent, failed: failed);
  }

  @visibleForTesting
  static Map<String, dynamic> decodePayloadForTesting(Object? decoded) {
    return _normalizePayload(decoded);
  }

  String _buildTelegramSummary(
    ReportDocument report, {
    String? detailUrl,
  }) {
    final excerpt = report.summaryMarkdown
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(10)
        .join('\n');
    return [
      report.title,
      '',
      excerpt,
      if (detailUrl != null) ...[
        '',
        '详情：$detailUrl',
      ],
    ].join('\n');
  }

  String _firstLines(String text, int count) {
    return text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(count)
        .join('\n');
  }

  Map<String, dynamic> _decodePayload(String raw) {
    return _normalizePayload(jsonDecode(raw));
  }

  static Map<String, dynamic> _normalizePayload(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const <String, dynamic>{};
  }
}
