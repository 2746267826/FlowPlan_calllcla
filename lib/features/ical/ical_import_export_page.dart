import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import 'ical_exporter.dart';
import 'ical_parser.dart';

class ICalImportExportPage extends ConsumerStatefulWidget {
  const ICalImportExportPage({super.key});

  @override
  ConsumerState<ICalImportExportPage> createState() => _ICalImportExportPageState();
}

class _ICalImportExportPageState extends ConsumerState<ICalImportExportPage> {
  bool _importing = false;
  bool _exporting = false;
  String? _lastMessage;
  int? _selectedCalendarId;

  @override
  Widget build(BuildContext context) {
    final calendarsAsync = ref.watch(allEventCalendarsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u65e5\u7a0b\u5bfc\u5165 / \u5bfc\u51fa'),
      ),
      body: calendarsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('\u52a0\u8f7d\u65e5\u5386\u672c\u5931\u8d25\uff1a$error'),
          ),
        ),
        data: (allCalendars) {
          final localCalendars = allCalendars
              .where((calendar) => calendar.source == 'local')
              .toList(growable: false);
          _ensureSelectedCalendar(localCalendars);

          final selectedCalendar = _findSelectedCalendar(localCalendars);
          final selectedCalendarName =
              selectedCalendar?.name ?? '\u672a\u9009\u62e9\u65e5\u5386\u672c';

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u64cd\u4f5c\u5bf9\u8c61',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '\u5bfc\u5165\u548c\u5bfc\u51fa\u53ea\u4f1a\u9488\u5bf9\u672c\u5730\u65e5\u5386\u672c\u3002Outlook \u540c\u6b65\u65e5\u5386\u4e3a\u53ea\u8bfb\uff0c\u4e0d\u4f1a\u5728\u8fd9\u91cc\u88ab\u6539\u5199\u6216\u5bfc\u51fa\u56de\u5199\u3002',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      if (localCalendars.isEmpty)
                        const Text(
                          '\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c\u3002\u8bf7\u5148\u5728\u65e5\u5386\u672c\u7ba1\u7406\u4e2d\u521b\u5efa\u4e00\u4e2a\u672c\u5730\u65e5\u5386\u672c\u3002',
                          style: TextStyle(fontSize: 13),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: localCalendars.map((calendar) {
                            final selected = calendar.id == _selectedCalendarId;
                            return ChoiceChip(
                              label: Text(calendar.name),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _selectedCalendarId = calendar.id);
                              },
                              selectedColor: _parseColor(calendar.colorHex),
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : null,
                              ),
                            );
                          }).toList(growable: false),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.file_download_outlined,
                  title: '\u5bfc\u5165 .ics \u6587\u4ef6',
                  subtitle: localCalendars.isEmpty
                      ? '\u65e0\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c'
                      : '\u5c06 iCalendar \u6587\u4ef6\u5bfc\u5165\u5230\u300c$selectedCalendarName\u300d',
                  actionLabel: _importing ? '\u5bfc\u5165\u4e2d...' : '\u9009\u62e9\u6587\u4ef6',
                  onAction: _importing || localCalendars.isEmpty
                      ? null
                      : () => _importIcs(selectedCalendar!),
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.file_upload_outlined,
                  title: '\u5bfc\u51fa .ics \u6587\u4ef6',
                  subtitle: localCalendars.isEmpty
                      ? '\u65e0\u53ef\u7528\u7684\u672c\u5730\u65e5\u5386\u672c'
                      : '\u53ea\u5bfc\u51fa\u300c$selectedCalendarName\u300d\u4e2d\u7684\u672c\u5730\u65e5\u7a0b',
                  actionLabel: _exporting ? '\u5bfc\u51fa\u4e2d...' : '\u5bfc\u51fa\u5f53\u524d\u65e5\u5386\u672c',
                  onAction: _exporting || localCalendars.isEmpty
                      ? null
                      : () => _exportIcs(selectedCalendar!),
                  color: const Color(0xFF43A047),
                ),
                const SizedBox(height: 24),
                if (_lastMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastMessage!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\u89c4\u5219\u8bf4\u660e',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.description_outlined,
                        text: 'iCalendar (.ics) \u00b7 RFC 5545 \u6807\u51c6',
                      ),
                      _InfoRow(
                        icon: Icons.calendar_month_outlined,
                        text: '\u652f\u6301 Outlook\u3001Google Calendar\u3001Apple Calendar \u5bfc\u51fa\u7684 .ics \u6587\u4ef6',
                      ),
                      _InfoRow(
                        icon: Icons.shield_outlined,
                        text: '\u53ea\u5904\u7406\u672c\u5730\u65e5\u5386\u672c\uff0c\u4e0d\u4f1a\u6539\u5199 Outlook \u53ea\u8bfb\u540c\u6b65\u65e5\u5386',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _ensureSelectedCalendar(List<EventCalendar> localCalendars) {
    if (localCalendars.isEmpty) {
      if (_selectedCalendarId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedCalendarId = null);
          }
        });
      }
      return;
    }

    final exists = localCalendars.any((calendar) => calendar.id == _selectedCalendarId);
    if (_selectedCalendarId == null || !exists) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedCalendarId = localCalendars.first.id);
        }
      });
    }
  }

  EventCalendar? _findSelectedCalendar(List<EventCalendar> localCalendars) {
    for (final calendar in localCalendars) {
      if (calendar.id == _selectedCalendarId) {
        return calendar;
      }
    }
    return localCalendars.isEmpty ? null : localCalendars.first;
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  String _safeFileNameSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'flowplan_export' : sanitized;
  }

  Future<void> _importIcs(EventCalendar calendar) async {
    setState(() => _importing = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _importing = false;
          _lastMessage = '\u672a\u9009\u62e9\u6587\u4ef6';
        });
        return;
      }

      final file = result.files.single;
      String content;
      if (file.bytes != null) {
        try {
          content = utf8.decode(file.bytes!);
        } catch (_) {
          content = String.fromCharCodes(file.bytes!);
        }
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() {
          _importing = false;
          _lastMessage = '\u65e0\u6cd5\u8bfb\u53d6\u6587\u4ef6\u5185\u5bb9';
        });
        return;
      }

      final companions = const ICalParser().parse(content);
      if (companions.isEmpty) {
        setState(() {
          _importing = false;
          _lastMessage = '\u6587\u4ef6\u4e2d\u672a\u627e\u5230\u6709\u6548\u65e5\u7a0b (VEVENT)';
        });
        return;
      }

      final repo = ref.read(eventRepositoryProvider);
      var count = 0;
      for (final companion in companions) {
        await repo.create(
          companion.copyWith(eventCalendarId: Value(calendar.id)),
        );
        count++;
      }

      setState(() {
        _importing = false;
        _lastMessage =
            '\u6210\u529f\u5bfc\u5165 $count \u6761\u65e5\u7a0b\u5230\u300c${calendar.name}\u300d';
      });
    } catch (error) {
      setState(() {
        _importing = false;
        _lastMessage = '\u5bfc\u5165\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _exportIcs(EventCalendar calendar) async {
    setState(() => _exporting = true);

    try {
      final events = await ref
          .read(eventRepositoryProvider)
          .watchForDateRange(DateTime(2020), DateTime(2035))
          .first;

      final exportable = events
          .where((event) => event.eventCalendarId == calendar.id)
          .toList(growable: false);

      if (exportable.isEmpty) {
        setState(() {
          _exporting = false;
          _lastMessage = '\u300c${calendar.name}\u300d\u4e2d\u6ca1\u6709\u53ef\u5bfc\u51fa\u7684\u65e5\u7a0b';
        });
        return;
      }

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '\u4fdd\u5b58 .ics \u6587\u4ef6',
        fileName: '${_safeFileNameSegment(calendar.name)}_flowplan_export.ics',
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );

      if (outputPath == null) {
        setState(() {
          _exporting = false;
          _lastMessage = '\u672a\u9009\u62e9\u4fdd\u5b58\u4f4d\u7f6e';
        });
        return;
      }

      final file = File(outputPath);
      await file.writeAsString(
        const ICalExporter().export(
          exportable,
          calendarName: 'FlowPlan - ${calendar.name}',
        ),
      );

      setState(() {
        _exporting = false;
        _lastMessage =
            '\u6210\u529f\u5bfc\u51fa ${exportable.length} \u6761\u65e5\u7a0b\u5230 ${file.path}';
      });
    } catch (error) {
      setState(() {
        _exporting = false;
        _lastMessage = '\u5bfc\u51fa\u5931\u8d25\uff1a$error';
      });
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
