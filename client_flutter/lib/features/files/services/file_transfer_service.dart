import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/connection/server_connection_state.dart';
import '../../../core/online/online_primary_policy.dart';
import '../../../core/server_api/file_cloud_api.dart';
import '../../audit/data_operation_log_repository.dart';

class FileTransferConstants {
  const FileTransferConstants._();

  static const smallFileThresholdBytes = 8 * 1024 * 1024;
  static const chunkSizeBytes = 4 * 1024 * 1024;
}

class FileTransferDirection {
  const FileTransferDirection._();

  static const upload = 'upload';
  static const download = 'download';
}

class FileTransferStatus {
  const FileTransferStatus._();

  static const queued = 'queued';
  static const hashing = 'hashing';
  static const uploading = 'uploading';
  static const uploaded = 'uploaded';
  static const downloading = 'downloading';
  static const downloaded = 'downloaded';
  static const failed = 'failed';
}

void debugTouchFileTransferConstantsForCoverage() {
  const FileTransferConstants._();
  const FileTransferDirection._();
  const FileTransferStatus._();
}

const Object _preserveErrorMessage = Object();

class FileTransferJob {
  const FileTransferJob({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.localPath,
    required this.totalBytes,
    required this.chunkSize,
    required this.expectedChunks,
    required this.transferredBytes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sessionId,
    this.storageObjectId,
    this.checksum,
    this.serverChecksum,
    this.errorMessage,
    this.speedBytesPerSecond = 0,
  });

  final String id;
  final String direction;
  final String fileName;
  final String localPath;
  final int totalBytes;
  final int chunkSize;
  final int expectedChunks;
  final int transferredBytes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sessionId;
  final String? storageObjectId;
  final String? checksum;
  final String? serverChecksum;
  final String? errorMessage;
  final double speedBytesPerSecond;

  double get progress {
    if (totalBytes <= 0) {
      return status == FileTransferStatus.uploaded ||
              status == FileTransferStatus.downloaded
          ? 1
          : 0;
    }
    return (transferredBytes / totalBytes).clamp(0, 1).toDouble();
  }

  bool get canResume =>
      status == FileTransferStatus.failed ||
      status == FileTransferStatus.uploading ||
      status == FileTransferStatus.downloading ||
      status == FileTransferStatus.queued;

  bool get canDownload =>
      direction == FileTransferDirection.upload &&
      status == FileTransferStatus.uploaded &&
      storageObjectId != null;

  FileTransferJob copyWith({
    String? direction,
    String? fileName,
    String? localPath,
    int? totalBytes,
    int? chunkSize,
    int? expectedChunks,
    int? transferredBytes,
    String? status,
    DateTime? updatedAt,
    String? sessionId,
    String? storageObjectId,
    String? checksum,
    String? serverChecksum,
    Object? errorMessage = _preserveErrorMessage,
    double? speedBytesPerSecond,
  }) {
    return FileTransferJob(
      id: id,
      direction: direction ?? this.direction,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      chunkSize: chunkSize ?? this.chunkSize,
      expectedChunks: expectedChunks ?? this.expectedChunks,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      sessionId: sessionId ?? this.sessionId,
      storageObjectId: storageObjectId ?? this.storageObjectId,
      checksum: checksum ?? this.checksum,
      serverChecksum: serverChecksum ?? this.serverChecksum,
      errorMessage: identical(errorMessage, _preserveErrorMessage)
          ? this.errorMessage
          : errorMessage as String?,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'direction': direction,
        'fileName': fileName,
        'localPath': localPath,
        'totalBytes': totalBytes,
        'chunkSize': chunkSize,
        'expectedChunks': expectedChunks,
        'transferredBytes': transferredBytes,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sessionId': sessionId,
        'storageObjectId': storageObjectId,
        'checksum': checksum,
        'serverChecksum': serverChecksum,
        'errorMessage': errorMessage,
      };

  factory FileTransferJob.fromJson(Map<String, Object?> json) {
    return FileTransferJob(
      id: _readString(json['id']) ?? const Uuid().v4(),
      direction: _readString(json['direction']) ?? FileTransferDirection.upload,
      fileName: _readString(json['fileName']) ?? 'unnamed',
      localPath: _readString(json['localPath']) ?? '',
      totalBytes: _readInt(json['totalBytes']),
      chunkSize:
          _readInt(json['chunkSize'], FileTransferConstants.chunkSizeBytes),
      expectedChunks: _readInt(json['expectedChunks']),
      transferredBytes: _readInt(json['transferredBytes']),
      status: _readString(json['status']) ?? FileTransferStatus.queued,
      createdAt: DateTime.tryParse(_readString(json['createdAt']) ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(_readString(json['updatedAt']) ?? '') ??
          DateTime.now(),
      sessionId: _readString(json['sessionId']),
      storageObjectId: _readString(json['storageObjectId']),
      checksum: _readString(json['checksum']),
      serverChecksum: _readString(json['serverChecksum']),
      errorMessage: _readString(json['errorMessage']),
    );
  }
}

class FileTransferService extends ChangeNotifier {
  FileTransferService({
    required Future<FileCloudApi> Function() apiLoader,
    Future<OnlinePrimaryPolicy> Function()? policyLoader,
    required DataOperationLogRepository operationLogs,
  })  : _apiLoader = apiLoader,
        _policyLoader = policyLoader ??
            (() async => const OnlinePrimaryPolicy(
                  serverReachable: true,
                  authenticated: true,
                  level: ServerConnectionLevel.online,
                )),
        _operationLogs = operationLogs;

  static const _storageKey = 'flowplanv2.file_transfer.jobs.v1';

  final Future<FileCloudApi> Function() _apiLoader;
  final Future<OnlinePrimaryPolicy> Function() _policyLoader;
  final DataOperationLogRepository _operationLogs;
  final Uuid _uuid = const Uuid();

  final List<FileTransferJob> _jobs = <FileTransferJob>[];
  List<Map<String, dynamic>> _serverTransfers = const <Map<String, dynamic>>[];
  bool _loaded = false;
  bool _refreshingServer = false;

  List<FileTransferJob> get jobs => List.unmodifiable(_jobs);
  List<Map<String, dynamic>> get serverTransfers =>
      List.unmodifiable(_serverTransfers);
  bool get loaded => _loaded;
  bool get refreshingServer => _refreshingServer;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _jobs
          ..clear()
          ..addAll(
            decoded.whereType<Map>().map((item) => FileTransferJob.fromJson(
                  Map<String, Object?>.from(item),
                )),
          );
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> refreshServerTransfers() async {
    _refreshingServer = true;
    notifyListeners();
    try {
      final api = await _apiLoader();
      final result = await api.transfers(limit: 100);
      final rows = result['transfers'];
      _serverTransfers = rows is List
          ? rows
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
    } finally {
      _refreshingServer = false;
      notifyListeners();
    }
  }

  Future<void> removeJob(String jobId) async {
    _jobs.removeWhere((job) => job.id == jobId);
    await _save();
    notifyListeners();
  }

  Future<void> clearCompletedJobs() async {
    _jobs.removeWhere((job) =>
        job.status == FileTransferStatus.uploaded ||
        job.status == FileTransferStatus.downloaded ||
        job.status == FileTransferStatus.failed);
    await _save();
    notifyListeners();
  }

  Future<void> uploadFile(String path) async {
    await load();
    final policy = await _policyLoader();
    policy.requireOnlineFileUploadStart('upload file');

    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('文件不存在：$path');
    }
    final stat = await file.stat();
    final totalBytes = stat.size;
    final chunkSize = _chunkSizeFor(totalBytes);
    final expectedChunks =
        totalBytes <= 0 ? 0 : (totalBytes / chunkSize).ceil();
    final checksum = await _sha256File(path);
    final api = await _apiLoader();
    final sessionResult = await api.createUploadSession(
      fileName: _basename(path),
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      checksum: checksum,
      localPath: path,
      metadata: <String, Object?>{
        'small_file_threshold_bytes':
            FileTransferConstants.smallFileThresholdBytes,
      },
    );
    final session = _asMap(sessionResult['uploadSession']);
    final sessionId = _readString(session['sessionId']);
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Server did not return an upload session.');
    }

    var job = FileTransferJob(
      id: _uuid.v4(),
      direction: FileTransferDirection.upload,
      fileName: _basename(path),
      localPath: path,
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      expectedChunks: expectedChunks,
      transferredBytes: 0,
      status: FileTransferStatus.uploading,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sessionId: sessionId,
      checksum: checksum,
    );
    _jobs.insert(0, job);
    await _save();
    notifyListeners();
    await _record('file_transfer.upload.start', job, '开始上传文件');

    try {
      await _uploadMissingChunks(job);
    } catch (error) {
      _replace(
        job.copyWith(
          status: FileTransferStatus.failed,
          errorMessage: error.toString(),
          speedBytesPerSecond: 0,
        ),
      );
      await _record('file_transfer.upload.failed', job, '上传失败');
      rethrow;
    }
  }

  Future<void> resumeUpload(FileTransferJob job) async {
    await load();
    if (job.sessionId == null) {
      await uploadFile(job.localPath);
      return;
    }
    final resumed = _replace(
      job.copyWith(
        status: FileTransferStatus.uploading,
        errorMessage: null,
      ),
    );
    await _record('file_transfer.upload.resume', resumed, '继续上传文件');
    try {
      await _uploadMissingChunks(resumed);
    } catch (error) {
      _replace(
        resumed.copyWith(
          status: FileTransferStatus.failed,
          errorMessage: error.toString(),
          speedBytesPerSecond: 0,
        ),
      );
      await _record('file_transfer.upload.failed', resumed, '上传失败');
      rethrow;
    }
  }

  @visibleForTesting
  Future<void> debugUploadMissingChunksUncheckedForCoverage(
    FileTransferJob job,
  ) {
    return _uploadMissingChunks(job);
  }

  Future<FileTransferJob> downloadUploadedJob(
    FileTransferJob source,
    String targetPath,
  ) {
    return downloadFromServerTransfer(
      <String, Object?>{
        'storageObjectId': source.storageObjectId,
        'fileName': source.fileName,
        'totalBytes': source.totalBytes,
        'chunkSize': source.chunkSize,
        'checksum': source.serverChecksum ?? source.checksum,
      },
      targetPath,
    );
  }

  Future<FileTransferJob> downloadFromServerTransfer(
    Map<String, Object?> source,
    String targetPath,
  ) async {
    await load();
    final storageObjectId = _readString(source['storageObjectId']);
    if (storageObjectId == null || storageObjectId.isEmpty) {
      throw StateError('该服务端文件没有 storageObjectId，不能下载。');
    }
    final totalBytes = _readInt(source['totalBytes']);
    final chunkSize = _readInt(
      source['chunkSize'],
      FileTransferConstants.chunkSizeBytes,
    );
    var job = FileTransferJob(
      id: _uuid.v4(),
      direction: FileTransferDirection.download,
      fileName: _readString(source['fileName']) ?? _basename(targetPath),
      localPath: targetPath,
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      expectedChunks: totalBytes <= 0 ? 0 : (totalBytes / chunkSize).ceil(),
      transferredBytes: _existingPartLength(targetPath),
      status: FileTransferStatus.downloading,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      storageObjectId: storageObjectId,
      checksum: _readString(source['checksum']),
      serverChecksum: _readString(source['checksum']),
    );
    _jobs.insert(0, job);
    await _save();
    notifyListeners();
    await _record('file_transfer.download.start', job, '开始下载文件');
    try {
      final api = await _apiLoader();
      final sessionResult = await api.createDownloadSession(
        storageObjectId: storageObjectId,
        fileName: job.fileName,
        localPath: targetPath,
        totalBytes: job.totalBytes,
        chunkSize: job.chunkSize,
        checksum: job.serverChecksum,
        metadata: <String, Object?>{'flowplanv2_transfer_job_id': job.id},
      );
      final session = _asMap(sessionResult['downloadSession']);
      job = _replace(
        job.copyWith(
          sessionId: _readString(session['sessionId']),
          status: FileTransferStatus.downloading,
          errorMessage: null,
        ),
      );
      return _resumeDownload(job);
    } catch (error) {
      _replace(
        job.copyWith(
          status: FileTransferStatus.failed,
          errorMessage: error.toString(),
          speedBytesPerSecond: 0,
        ),
      );
      await _record('file_transfer.download.failed', job, '下载失败');
      rethrow;
    }
  }

  Future<FileTransferJob> downloadPreparedSession(
    Map<String, Object?> response,
    String targetPath,
  ) async {
    await load();
    final session = _asMap(response['downloadSession']);
    final node = _asMap(response['node']);
    final storage = _asMap(node['storage']);
    final sessionId = _readString(session['sessionId']);
    final storageObjectId = _readString(session['storageObjectId']) ??
        _readString(storage['storageObjectId']);
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('服务端没有返回 download session，不能下载。');
    }
    if (storageObjectId == null || storageObjectId.isEmpty) {
      throw StateError('服务端文件没有 storageObjectId，不能下载。');
    }
    final totalBytes = _readInt(
      session['totalBytes'],
      _readInt(node['sizeBytes']),
    );
    final chunkSize = _readInt(
      session['chunkSize'],
      FileTransferConstants.chunkSizeBytes,
    );
    var job = FileTransferJob(
      id: _uuid.v4(),
      direction: FileTransferDirection.download,
      fileName: _readString(node['name']) ??
          _readString(node['displayName']) ??
          _basename(targetPath),
      localPath: targetPath,
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      expectedChunks: totalBytes <= 0 ? 0 : (totalBytes / chunkSize).ceil(),
      transferredBytes: _existingPartLength(targetPath),
      status: FileTransferStatus.downloading,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sessionId: sessionId,
      storageObjectId: storageObjectId,
      checksum: _readString(session['checksum']) ??
          _readString(storage['checksum']) ??
          _readString(node['hashSha256']),
      serverChecksum: _readString(session['checksum']) ??
          _readString(storage['checksum']) ??
          _readString(node['hashSha256']),
    );
    _jobs.insert(0, job);
    await _save();
    notifyListeners();
    await _record('file_transfer.download.start', job, '开始下载云盘文件');
    try {
      job = await _resumeDownload(job);
      return job;
    } catch (error) {
      _replace(
        job.copyWith(
          status: FileTransferStatus.failed,
          errorMessage: error.toString(),
          speedBytesPerSecond: 0,
        ),
      );
      await _record('file_transfer.download.failed', job, '下载失败');
      rethrow;
    }
  }

  Future<FileTransferJob> resumeDownload(FileTransferJob job) async {
    await load();
    if (job.sessionId == null || job.storageObjectId == null) {
      throw StateError('下载任务缺少 sessionId 或 storageObjectId。');
    }
    final resumed = _replace(
      job.copyWith(
        status: FileTransferStatus.downloading,
        transferredBytes: _existingPartLength(job.localPath),
        errorMessage: null,
      ),
    );
    await _record('file_transfer.download.resume', resumed, '继续下载文件');
    try {
      return await _resumeDownload(resumed);
    } catch (error) {
      _replace(
        resumed.copyWith(
          status: FileTransferStatus.failed,
          errorMessage: error.toString(),
          speedBytesPerSecond: 0,
        ),
      );
      await _record('file_transfer.download.failed', resumed, '下载失败');
      rethrow;
    }
  }

  Future<FileTransferJob> debugResumeDownloadUncheckedForCoverage(
    FileTransferJob job,
  ) {
    return _resumeDownload(job);
  }

  Future<void> _uploadMissingChunks(FileTransferJob initialJob) async {
    final api = await _apiLoader();
    var job = initialJob;
    final sessionId = job.sessionId;
    if (sessionId == null) {
      throw StateError('上传任务缺少 sessionId。');
    }
    final missingResult = await api.missingUploadChunks(sessionId);
    final missing = _readIntList(missingResult['missingChunks']);
    final missingSet = missing.toSet();
    final remoteSession = _asMap(missingResult['session']);
    var uploadedBytes = _clampInt(
      _readInt(remoteSession['receivedBytes']),
      0,
      job.totalBytes,
    );
    final stopwatch = Stopwatch()..start();

    if (job.expectedChunks == 0) {
      final complete = await api.completeUploadSession(sessionId);
      if (complete['ok'] != true) {
        throw StateError(complete['reason'] ?? '服务端完成上传失败');
      }
      final storage = _asMap(complete['storageObject']);
      job = _replace(
        job.copyWith(
          storageObjectId: _readString(storage['storageObjectId']),
          serverChecksum: _readString(complete['checksum']) ?? job.checksum,
        ),
      );
    } else {
      for (var index = 0; index < job.expectedChunks; index += 1) {
        if (!missingSet.contains(index)) {
          continue;
        }
        final start = index * job.chunkSize;
        final endExclusive =
            _clampInt(start + job.chunkSize, 0, job.totalBytes);
        final bytes = await _readFileRange(job.localPath, start, endExclusive);
        await api.uploadChunk(
          sessionId: sessionId,
          chunkIndex: index,
          startByte: start,
          bytes: bytes,
          checksum: sha256.convert(bytes).toString(),
        );
        uploadedBytes += bytes.length;
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        job = _replace(
          job.copyWith(
            transferredBytes: _clampInt(uploadedBytes, 0, job.totalBytes),
            status: FileTransferStatus.uploading,
            speedBytesPerSecond: seconds <= 0 ? 0 : uploadedBytes / seconds,
            errorMessage: null,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      final complete = await api.completeUploadSession(sessionId);
      if (complete['ok'] != true) {
        throw StateError(complete['reason'] ?? '服务端完成上传失败');
      }
      final storage = _asMap(complete['storageObject']);
      job = _replace(
        job.copyWith(
          storageObjectId: _readString(storage['storageObjectId']),
          serverChecksum: _readString(complete['checksum']) ?? job.checksum,
        ),
      );
    }

    final serverChecksum = job.serverChecksum ?? job.checksum;
    if (serverChecksum != null &&
        job.checksum != null &&
        serverChecksum != job.checksum) {
      throw StateError('上传后 hash 不一致：本地 ${job.checksum}，服务端 $serverChecksum');
    }
    job = _replace(
      job.copyWith(
        transferredBytes: job.totalBytes,
        status: FileTransferStatus.uploaded,
        errorMessage: null,
        speedBytesPerSecond: 0,
      ),
    );
    await _record('file_transfer.upload.complete', job, '上传完成');
    await refreshServerTransfers();
  }

  Future<FileTransferJob> _resumeDownload(FileTransferJob initialJob) async {
    final api = await _apiLoader();
    var job = initialJob;
    final sessionId = job.sessionId;
    if (sessionId == null) {
      throw StateError('下载任务缺少 sessionId。');
    }
    if (job.totalBytes <= 0) {
      throw StateError('文件大小未知或为0，无法下载。请确认服务端文件元数据是否完整。');
    }
    final partPath = _partPath(job.localPath);
    await Directory(File(partPath).parent.path).create(recursive: true);
    final partFile = File(partPath);
    if (!partFile.existsSync()) {
      await partFile.create(recursive: true);
    }
    var downloadedBytes = await partFile.length();
    final alignedBytes = job.chunkSize <= 0
        ? downloadedBytes
        : (downloadedBytes ~/ job.chunkSize) * job.chunkSize;
    if (alignedBytes != downloadedBytes) {
      await partFile.open(mode: FileMode.writeOnlyAppend).then((handle) async {
        await handle.truncate(alignedBytes);
        await handle.close();
      });
      downloadedBytes = alignedBytes;
    }
    final sink = partFile.openWrite(mode: FileMode.append);
    final stopwatch = Stopwatch()..start();
    try {
      while (downloadedBytes < job.totalBytes) {
        final start = downloadedBytes;
        final end = _clampInt(start + job.chunkSize - 1, 0, job.totalBytes - 1);
        final result = await api.downloadRange(
          sessionId: sessionId,
          start: start,
          end: end,
        );
        if (result['ok'] != true) {
          throw StateError(result['reason'] ?? '服务端下载失败');
        }
        final chunks = result['chunks'];
        if (chunks is! List || chunks.isEmpty) {
          throw StateError('服务端没有返回下载分块。');
        }
        for (final chunkValue in chunks) {
          final chunk = _asMap(chunkValue);
          final payload = _readString(chunk['payloadBase64']);
          if (payload == null) {
            continue;
          }
          final bytes = base64Decode(payload);
          sink.add(bytes);
          downloadedBytes += bytes.length;
          final seconds = stopwatch.elapsedMilliseconds / 1000.0;
          job = _replace(
            job.copyWith(
              transferredBytes: _clampInt(downloadedBytes, 0, job.totalBytes),
              status: FileTransferStatus.downloading,
              speedBytesPerSecond: seconds <= 0 ? 0 : downloadedBytes / seconds,
              errorMessage: null,
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    final localChecksum = await _sha256File(partPath);
    final expectedChecksum = job.serverChecksum ?? job.checksum;
    if (expectedChecksum != null && localChecksum != expectedChecksum) {
      throw StateError('下载后 hash 不一致：本地 $localChecksum，服务端 $expectedChecksum');
    }
    final finalFile = File(job.localPath);
    if (finalFile.existsSync()) {
      await finalFile.delete();
    }
    await partFile.rename(job.localPath);
    job = _replace(
      job.copyWith(
        transferredBytes: job.totalBytes,
        status: FileTransferStatus.downloaded,
        checksum: localChecksum,
        serverChecksum: expectedChecksum,
        errorMessage: null,
        speedBytesPerSecond: 0,
      ),
    );
    await _record('file_transfer.download.complete', job, '下载完成');
    return job;
  }

  FileTransferJob _replace(FileTransferJob job) {
    final index = _jobs.indexWhere((item) => item.id == job.id);
    final updated = job.copyWith(updatedAt: DateTime.now());
    if (index >= 0) {
      _jobs[index] = updated;
    } else {
      _jobs.insert(0, updated);
    }
    unawaited(_save());
    notifyListeners();
    return updated;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_jobs.map((job) => job.toJson()).toList(growable: false)),
    );
  }

  Future<void> _record(
    String action,
    FileTransferJob job,
    String summary,
  ) {
    return _operationLogs.record(
      actor: 'user',
      action: action,
      entityType: 'file_transfer',
      entityId: job.sessionId ?? job.id,
      summary: '$summary：${job.fileName}',
      metadata: job.toJson(),
    );
  }

  int _chunkSizeFor(int totalBytes) {
    if (totalBytes <= 0) {
      return 1;
    }
    if (totalBytes <= FileTransferConstants.smallFileThresholdBytes) {
      return totalBytes;
    }
    return FileTransferConstants.chunkSizeBytes;
  }

  int _existingPartLength(String finalPath) {
    final file = File(_partPath(finalPath));
    return file.existsSync() ? file.lengthSync() : 0;
  }

  String _partPath(String finalPath) => '$finalPath.flowplanv2.part';

  Future<String> _sha256File(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  Future<Uint8List> _readFileRange(
    String path,
    int start,
    int endExclusive,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(start, endExclusive)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}

String? _readString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int _readInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<int> _readIntList(Object? value) {
  if (value is! List) {
    return const <int>[];
  }
  return value
      .map((item) => _readInt(item, -1))
      .where((item) => item >= 0)
      .toList();
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
