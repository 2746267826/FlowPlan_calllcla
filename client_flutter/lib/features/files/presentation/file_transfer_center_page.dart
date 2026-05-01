import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/app_providers.dart';
import '../services/file_transfer_service.dart';

class FileTransferCenterPage extends ConsumerWidget {
  const FileTransferCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(fileTransferServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件传输中心'),
        actions: [
          IconButton(
            tooltip: '刷新服务端会话',
            icon: service.refreshingServer
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed:
                service.refreshingServer ? null : service.refreshServerTransfers,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _pickAndUpload(context, service),
                icon: const Icon(Icons.upload_file),
                label: const Text('上传本地文件'),
              ),
              OutlinedButton.icon(
                onPressed: service.refreshServerTransfers,
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('加载服务端传输'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TransferPolicyNote(),
          const SizedBox(height: 16),
          Text(
            '本机传输任务',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (service.jobs.isEmpty)
            const _EmptyNotice(message: '还没有传输任务。可以先上传一个本地文件。')
          else
            ...service.jobs.map(
              (job) => _TransferJobTile(
                job: job,
                onResume: () => _resume(context, service, job),
                onDownload: job.canDownload
                    ? () => _downloadUploadedJob(context, service, job)
                    : null,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '服务端传输会话',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (service.serverTransfers.isEmpty)
            const _EmptyNotice(message: '尚未加载服务端传输会话，或服务端暂无记录。')
          else
            ...service.serverTransfers.map(
              (row) => _ServerTransferTile(
                row: row,
                onDownload: _canDownload(row)
                    ? () => _downloadServerRow(context, service, row)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    FileTransferService service,
  ) async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      await service.uploadFile(path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上传完成并已校验 hash')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$error')),
      );
    }
  }

  Future<void> _resume(
    BuildContext context,
    FileTransferService service,
    FileTransferJob job,
  ) async {
    try {
      if (job.direction == FileTransferDirection.upload) {
        await service.resumeUpload(job);
      } else {
        await service.resumeDownload(job);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('传输已继续并完成当前校验')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('继续传输失败：$error')),
      );
    }
  }

  Future<void> _downloadUploadedJob(
    BuildContext context,
    FileTransferService service,
    FileTransferJob job,
  ) async {
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '保存服务端文件',
      fileName: job.fileName,
    );
    if (targetPath == null || targetPath.trim().isEmpty) {
      return;
    }
    try {
      await service.downloadUploadedJob(job, targetPath);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成并已校验 hash')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$error')),
      );
    }
  }

  Future<void> _downloadServerRow(
    BuildContext context,
    FileTransferService service,
    Map<String, dynamic> row,
  ) async {
    final fileName = row['fileName']?.toString() ?? 'download';
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '保存服务端文件',
      fileName: fileName,
    );
    if (targetPath == null || targetPath.trim().isEmpty) {
      return;
    }
    try {
      await service.downloadFromServerTransfer(row, targetPath);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成并已校验 hash')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$error')),
      );
    }
  }

  bool _canDownload(Map<String, dynamic> row) {
    return row['direction'] == FileTransferDirection.upload &&
        row['status'] == 'completed' &&
        row['storageObjectId'] != null;
  }
}

class _TransferPolicyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '当前 MVP 仅使用服务端中转：小文件不超过 8MB 时按单个 chunk 上传，大文件按 4MB chunk 上传。'
        '失败后可通过缺失 chunk 查询继续上传；下载会写入 .flowplanv2.part 临时文件并支持继续下载。',
      ),
    );
  }
}

class _TransferJobTile extends StatelessWidget {
  const _TransferJobTile({
    required this.job,
    required this.onResume,
    required this.onDownload,
  });

  final FileTransferJob job;
  final VoidCallback onResume;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(job.direction == FileTransferDirection.upload
                    ? Icons.upload_file
                    : Icons.download_for_offline_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusChip(status: job.status),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: job.progress),
            const SizedBox(height: 6),
            Text(
              '${_formatBytes(job.transferredBytes)} / ${_formatBytes(job.totalBytes)}'
              ' · ${_formatSpeed(job.speedBytesPerSecond)}'
              ' · ${job.expectedChunks} chunks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (job.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                '失败原因：${job.errorMessage}',
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (job.canResume)
                  OutlinedButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续'),
                  ),
                if (onDownload != null)
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('下载'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTransferTile extends StatelessWidget {
  const _ServerTransferTile({
    required this.row,
    required this.onDownload,
  });

  final Map<String, dynamic> row;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final total = _readInt(row['totalBytes']);
    final done = _readInt(row['receivedBytes']);
    final progress = total <= 0 ? null : (done / total).clamp(0, 1).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(row['direction'] == FileTransferDirection.upload
            ? Icons.cloud_upload_outlined
            : Icons.cloud_download_outlined),
        title: Text(row['fileName']?.toString() ?? '未命名文件'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              '${row['direction']} · ${row['status']} · '
              '${_formatBytes(done)} / ${_formatBytes(total)} · '
              '${row['receivedChunks'] ?? 0}/${row['expectedChunks'] ?? 0} chunks',
            ),
            if (row['errorMessage'] != null)
              Text(
                '失败原因：${row['errorMessage']}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        trailing: onDownload == null
            ? null
            : FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('下载'),
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == FileTransferStatus.uploaded ||
            status == FileTransferStatus.downloaded
        ? Colors.green
        : status == FileTransferStatus.failed
            ? Colors.red
            : status == FileTransferStatus.uploading ||
                    status == FileTransferStatus.downloading
                ? Colors.blue
                : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status, style: TextStyle(color: color)),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String _formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) {
    return '等待中';
  }
  return '${_formatBytes(bytesPerSecond.round())}/s';
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
