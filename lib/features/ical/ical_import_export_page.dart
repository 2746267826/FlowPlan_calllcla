// iCalendar 导入导出页面
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import 'ical_parser.dart';
import 'ical_exporter.dart';

class ICalImportExportPage extends ConsumerStatefulWidget {
  const ICalImportExportPage({super.key});

  @override
  ConsumerState<ICalImportExportPage> createState() =>
      _ICalImportExportPageState();
}

class _ICalImportExportPageState extends ConsumerState<ICalImportExportPage> {
  bool _importing = false;
  bool _exporting = false;
  String? _lastMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('日程导入 / 导出')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 导入卡片 ──────────────────────────────────────────────
            _buildCard(
              context,
              icon: Icons.file_download_outlined,
              title: '导入 .ics 文件',
              subtitle: '从标准 iCalendar 文件导入日程到本地数据库',
              actionLabel: _importing ? '导入中...' : '选择文件',
              onAction: _importing ? null : _importIcs,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),

            // ── 导出卡片 ──────────────────────────────────────────────
            _buildCard(
              context,
              icon: Icons.file_upload_outlined,
              title: '导出 .ics 文件',
              subtitle: '将本地所有日程导出为标准 iCalendar 格式',
              actionLabel: _exporting ? '导出中...' : '导出全部',
              onAction: _exporting ? null : _exportIcs,
              color: const Color(0xFF43A047),
            ),
            const SizedBox(height: 24),

            // ── 操作结果 ──────────────────────────────────────────────
            if (_lastMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_lastMessage!,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // ── 格式说明 ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('支持的格式',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _infoRow('📄', 'iCalendar (.ics) — RFC 5545 标准'),
                  _infoRow(
                      '📅', '支持 Outlook、Google Calendar、Apple Calendar 导出的文件'),
                  _infoRow('🔄', '导入时自动解析时区、重复规则、地点等属性'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required String actionLabel,
      required VoidCallback? onAction,
      required Color color}) {
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
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(actionLabel, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── 导入 ─────────────────────────────────────────────────────────────
  Future<void> _importIcs() async {
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
          _lastMessage = '未选择文件';
        });
        return;
      }

      final file = result.files.single;
      String content;
      if (file.bytes != null) {
        try {
          content = utf8.decode(file.bytes!);
        } catch (_) {
          // 降级使用普通字符码转化（备用）
          content = String.fromCharCodes(file.bytes!);
        }
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() {
          _importing = false;
          _lastMessage = '无法读取文件内容';
        });
        return;
      }

      final parser = const ICalParser();
      final companions = parser.parse(content);

      if (companions.isEmpty) {
        setState(() {
          _importing = false;
          _lastMessage = '文件中未找到有效日程 (VEVENT)';
        });
        return;
      }

      // 逐条写入数据库
      final repo = ref.read(eventRepositoryProvider);
      int count = 0;
      for (final companion in companions) {
        await repo.create(companion);
        count++;
      }

      setState(() {
        _importing = false;
        _lastMessage = '成功导入 $count 条日程';
      });
    } catch (e) {
      setState(() {
        _importing = false;
        _lastMessage = '导入失败: $e';
      });
    }
  }

  // ── 导出 ─────────────────────────────────────────────────────────────
  Future<void> _exportIcs() async {
    setState(() => _exporting = true);

    try {
      // 获取所有事件（用日期范围覆盖足够大的范围）
      final repo = ref.read(eventRepositoryProvider);
      final start = DateTime(2020);
      final end = DateTime(2030);
      // 使用 watchForDateRange 的 first 来获取当前快照
      final events = await repo.watchForDateRange(start, end).first;

      if (events.isEmpty) {
        setState(() {
          _exporting = false;
          _lastMessage = '没有可导出的日程';
        });
        return;
      }

      final exporter = const ICalExporter();
      final icsContent = exporter.export(events);

      // 选择保存位置
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存 .ics 文件',
        fileName: 'flowplan_export.ics',
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );

      if (outputPath == null) {
        setState(() {
          _exporting = false;
          _lastMessage = '未选择保存位置';
        });
        return;
      }

      final file = File(outputPath);
      await file.writeAsString(icsContent);

      setState(() {
        _exporting = false;
        _lastMessage = '成功导出 ${events.length} 条日程到: ${file.path}';
      });
    } catch (e) {
      setState(() {
        _exporting = false;
        _lastMessage = '导出失败: $e';
      });
    }
  }
}
