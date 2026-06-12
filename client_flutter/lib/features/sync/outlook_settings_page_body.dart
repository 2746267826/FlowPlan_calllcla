import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../reminders/reminder_service.dart';
import '../calendar/presentation/calendar_books_page.dart';
import 'outlook_calendar_service.dart';
import 'ms_graph_service.dart';
import 'outlook_auth_service.dart';
import 'outlook_oauth_config.dart';
import 'outlook_diagnostics_service.dart';
import 'outlook_managed_container_service.dart';
import 'outlook_sync_policy.dart';
import 'outlook_sync_bindings_repository.dart';
import 'outlook_task_list_binding.dart';
import 'outlook_task_mirror_binding.dart';
import 'outlook_task_mirror_sync_service.dart';
import 'sync_engine.dart';

part 'outlook_settings_widgets.dart';

typedef OutlookDiagnosticsReportWriter = Future<void> Function(
  String outputPath,
  String report,
);

final outlookDiagnosticsReportWriterProvider =
    Provider<OutlookDiagnosticsReportWriter>(
  (ref) => (outputPath, report) => File(outputPath).writeAsString(report),
);

typedef OutlookCalendarServiceFactory = OutlookCalendarService Function(
  OutlookConfig config,
);

final outlookCalendarServiceFactoryProvider =
    Provider<OutlookCalendarServiceFactory>(
  (ref) => (config) => OutlookCalendarService(config),
);

typedef OutlookManagedContainerServiceFactory
    = OutlookManagedContainerService Function({
  required OutlookConfig config,
  required OutlookSyncBindingsRepository bindingsRepository,
});

final outlookManagedContainerServiceFactoryProvider =
    Provider<OutlookManagedContainerServiceFactory>(
  (ref) => ({
    required config,
    required bindingsRepository,
  }) =>
      OutlookManagedContainerService(
    config: config,
    bindingsRepository: bindingsRepository,
  ),
);

class OutlookSettingsPage extends ConsumerStatefulWidget {
  const OutlookSettingsPage({
    super.key,
    this.serverManaged = true,
  });

  final bool serverManaged;

  @override
  ConsumerState<OutlookSettingsPage> createState() =>
      _OutlookSettingsPageState();
}

class _OutlookSettingsPageState extends ConsumerState<OutlookSettingsPage> {
  final _clientIdController = TextEditingController();
  final _authCodeController = TextEditingController();

  bool _isAuthenticated = false;
  bool _hasRequiredPermission = false;
  bool _refreshingToken = false;
  bool _authSubmitting = false;
  bool _syncing = false;
  bool _exportingDiagnostics = false;
  String? _status;
  DateTime? _lastSync;
  OutlookSyncReport? _lastSyncReport;
  OutlookSyncMode _syncMode = OutlookSyncMode.readOnly;
  OutlookSyncMode _grantedMode = OutlookSyncMode.readOnly;
  late Future<Map<String, dynamic>> _serverManagedDiagnosticsFuture;

  @override
  void initState() {
    super.initState();
    _serverManagedDiagnosticsFuture = widget.serverManaged
        ? _loadServerManagedOutlookDiagnostics()
        : Future.value(const <String, dynamic>{});
    _loadState();
    _status = 'Outlook 日程由服务端只读同步后下发。';
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _authCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final config = await OutlookAuthService.loadConfig();
    var token = await OutlookAuthService.loadToken();
    final lastSync = await SyncEngine.getLastSyncTime();
    final lastSyncReport = await SyncEngine.getLastSyncReport();
    final syncMode = await OutlookAuthService.loadSyncMode();
    String? statusMessage;

    if (config != null &&
        token != null &&
        token.isExpired &&
        (token.refreshToken?.trim().isNotEmpty ?? false)) {
      if (mounted) {
        setState(() {
          _refreshingToken = true;
          _status = 'Outlook token 已过期，正在刷新。';
        });
      }
      try {
        token = await OutlookAuthService.refreshAccessToken(config);
        statusMessage =
            token == null ? '未找到可刷新的 Outlook token。' : 'Outlook token 刷新成功。';
      } on OutlookAuthException catch (error) {
        token = await OutlookAuthService.loadToken();
        statusMessage = error.userMessage;
      } catch (error) {
        statusMessage = 'Outlook token 刷新失败：$error';
      }
    }

    final authed = token != null;
    final hasRequiredPermission = syncMode == OutlookSyncMode.paused ||
        (token?.supportsMode(syncMode) ?? false);
    if (!mounted) return;

    setState(() {
      if (config != null) {
        _clientIdController.text = config.clientId;
      }
      _isAuthenticated = authed;
      _hasRequiredPermission = hasRequiredPermission;
      _refreshingToken = false;
      _lastSync = lastSync;
      _lastSyncReport = lastSyncReport;
      _syncMode = syncMode;
      _grantedMode = token?.grantedMode ?? OutlookSyncMode.bidirectional;
      if (statusMessage != null) {
        _status = statusMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_outlookIsServerManaged) {
      return _buildServerManagedPage(context);
    }
    final eventCalendarsAsync = ref.watch(allEventCalendarsProvider);
    final taskListsAsync = ref.watch(allTaskListsProvider);
    final taskListBindingsAsync = ref.watch(outlookTaskListBindingsProvider);
    final taskMirrorDiagnosticsAsync =
        ref.watch(outlookTaskMirrorDiagnosticsProvider);
    final fieldConflictsAsync =
        ref.watch(outlookFieldConflictSummariesProvider);
    final pageWidth = MediaQuery.of(context).size.width;
    final pagePadding = pageWidth < 600 ? 16.0 : 24.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Outlook \u540c\u6b65\u8bbe\u7f6e')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusCard(
                  isAuthenticated: _isAuthenticated,
                  hasRequiredPermission: _hasRequiredPermission,
                  syncMode: _syncMode,
                  grantedMode: _grantedMode,
                  lastSync: _lastSync,
                  isRefreshingToken: _refreshingToken,
                  lastSyncFailed: _lastSyncReport?.success == false,
                ),
                const SizedBox(height: 24),
                _sectionTitle('\u914d\u7f6e'),
                const SizedBox(height: 8),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _clientIdController,
                        decoration: const InputDecoration(
                          labelText: '\u5ba2\u6237\u7aef ID',
                          hintText:
                              'Microsoft Entra \u5e94\u7528\u7684\u5ba2\u6237\u7aef ID',
                          prefixIcon: Icon(Icons.key_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StaticConfigTile(
                        icon: Icons.account_tree_outlined,
                        title: 'Authority',
                        value: OutlookOAuthPlatformConfig.authority,
                      ),
                      const SizedBox(height: 12),
                      _StaticConfigTile(
                        icon: Icons.link_outlined,
                        title: 'Redirect URI',
                        value: OutlookOAuthPlatformConfig.redirectUri,
                      ),
                      const SizedBox(height: 12),
                      _StaticConfigTile(
                        icon: Icons.shield_outlined,
                        title: 'Scope',
                        value: OutlookOAuthPlatformConfig.scopeString,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saveConfig,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('\u4fdd\u5b58\u914d\u7f6e'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('\u8ba4\u8bc1'),
                const SizedBox(height: 8),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _syncMode.authSummary,
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      if (!_isAuthenticated) ...[
                        Text(
                          '步骤 1：点击下方按钮后，FlowPlanV2 会按 Microsoft identity platform Authorization Code Flow + PKCE 打开浏览器登录个人 Outlook 账号。',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _authSubmitting ? null : _startAuth,
                            icon: const Icon(Icons.open_in_browser, size: 18),
                            label: const Text('连接 Outlook 日历'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '登录完成后，请复制浏览器地址栏中 code= 后面的授权码，粘贴回这里。',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '为了安全校验 state，推荐直接粘贴浏览器完整地址栏内容，系统会自动解析 code 和 state。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _authCodeController,
                          decoration: const InputDecoration(
                            labelText: '粘贴授权码',
                            hintText: '可粘贴完整回调地址，或包含 code 与 state 的查询串',
                            prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _authSubmitting ? null : _exchangeCode,
                            icon: _authSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login, size: 18),
                            label: Text(_authSubmitting ? '提交中...' : '提交授权码'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0078D4),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ] else ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.check_circle,
                              color: Color(0xFF43A047)),
                          title: Text(
                            _hasRequiredPermission
                                ? '当前 Outlook 已连接'
                                : '当前 Outlook 已连接，但建议重新认证',
                          ),
                          subtitle: Text(
                            _hasRequiredPermission
                                ? '当前授权：${_authorizationLabel(_grantedMode)}。是否写回 Outlook 取决于你选择的同步模式，而不是令牌本身。'
                                : '当前选择的同步模式为“${_syncMode.label}”，请重新完成一次 Microsoft 登录，确保新的浏览器会话与当前配置一致。',
                          ),
                          trailing: TextButton(
                            onPressed: _authSubmitting ? null : _logout,
                            child: const Text(
                              '断开 Outlook 连接',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('\u540c\u6b65'),
                const SizedBox(height: 8),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<OutlookSyncMode>(
                        initialValue: _syncMode,
                        decoration: const InputDecoration(
                          labelText: '\u540c\u6b65\u6a21\u5f0f',
                          prefixIcon: Icon(Icons.swap_horiz_outlined, size: 20),
                        ),
                        items: OutlookSyncMode.values
                            .map(
                              (mode) => DropdownMenuItem<OutlookSyncMode>(
                                value: mode,
                                child: Text(mode.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (mode) {
                          if (mode != null) {
                            _updateSyncMode(mode);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_syncMode.description,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (_isAuthenticated &&
                          _syncMode.requiresWritePermission &&
                          !_hasRequiredPermission) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '\u4f60\u5df2\u5207\u6362\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\uff0c\u4f46\u73b0\u6709 Outlook \u4ee4\u724c\u4ecd\u662f\u53ea\u8bfb\u6743\u9650\u3002\u8bf7\u91cd\u65b0\u8fdb\u884c\u4e00\u6b21\u6d4f\u89c8\u5668\u6388\u6743\uff0cFlowPlanV2 \u624d\u80fd\u5bf9\u81ea\u5df1\u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u65e5\u5386\u672c\u6267\u884c\u5199\u56de\u3002',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _syncing ? null : _startAuth,
                                icon: const Icon(
                                  Icons.lock_open_outlined,
                                  size: 18,
                                ),
                                label: const Text(
                                  '\u7acb\u5373\u91cd\u65b0\u8fdb\u884c\u8bfb\u5199\u6388\u6743',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _syncing || !_canSync ? null : _performSync,
                          icon: _syncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync, size: 18),
                          label: Text(
                            _syncing
                                ? '\u540c\u6b65\u4e2d...'
                                : '手动同步 Outlook 日历',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0078D4),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _resetSync,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text(
                              '\u91cd\u7f6e\u540c\u6b65\u72b6\u6001'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _syncing
                              ? null
                              : _resetSyncedOutlookEventCalendars,
                          icon:
                              const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: const Text('完全重置已同步的 Outlook 日历本'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('\u6700\u8fd1\u7ed3\u679c'),
                const SizedBox(height: 8),
                _buildLastSyncReportPanel(),
                const SizedBox(height: 24),
                _OutlookAdvancedSection(
                  title: '\u8bca\u65ad\u4e0e\u51b2\u7a81',
                  icon: Icons.troubleshoot_outlined,
                  child: _buildDiagnosticsPanel(
                    taskMirrorDiagnosticsAsync,
                    fieldConflictsAsync,
                  ),
                ),
                const SizedBox(height: 12),
                _OutlookAdvancedSection(
                  title: '\u5199\u56de\u8fb9\u754c',
                  icon: Icons.policy_outlined,
                  child: _buildControlledWriteScopePanel(),
                ),
                const SizedBox(height: 12),
                _OutlookAdvancedSection(
                  title: '\u540c\u6b65\u5bf9\u8c61',
                  icon: Icons.account_tree_outlined,
                  child: _buildSyncObjectsPanel(
                    eventCalendarsAsync: eventCalendarsAsync,
                    taskListsAsync: taskListsAsync,
                    taskListBindingsAsync: taskListBindingsAsync,
                    taskMirrorDiagnosticsAsync: taskMirrorDiagnosticsAsync,
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Text(_status!, style: const TextStyle(fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 32),
                _OutlookAdvancedSection(
                  title: '\u4f7f\u7528\u8bf4\u660e',
                  icon: Icons.help_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HelpRow(
                        num: '1.',
                        text:
                            '在 Microsoft Entra 中注册 Public Client 应用，记录客户端 ID，不要填写 client_secret。',
                      ),
                      const _HelpRow(
                        num: '2.',
                        text: '重定向 URI 由管理端统一配置。',
                      ),
                      _HelpRow(num: '3.', text: _permissionHelpText()),
                      const _HelpRow(
                        num: '4.',
                        text: 'Authority 由管理端统一配置。',
                      ),
                      const _HelpRow(
                        num: '5.',
                        text:
                            'Outlook 普通日历默认保持只读，FlowPlanV2 只会对自己托管的 Outlook 专属日历本执行写回。',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _outlookIsServerManaged => widget.serverManaged;

  Widget _buildServerManagedPage(BuildContext context) {
    final pageWidth = MediaQuery.of(context).size.width;
    final pagePadding = pageWidth < 600 ? 16.0 : 24.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outlook'),
      ),
      body: ListView(
        padding: EdgeInsets.all(pagePadding),
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_sync_outlined),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '由服务端管理',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '客户端不再保存 Outlook token，也不直接访问 Microsoft Graph。',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _syncing ? null : _refreshServerOutlook,
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_outlined, size: 18),
                    label: Text(_syncing ? '正在刷新 Outlook' : '手动刷新 Outlook'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '刷新会请求服务端只读拉取 Outlook，然后通过 FlowPlanV2 同步下发日历本和日程。',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '只读边界',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _serverManagedBullet('授权、Client ID 和 token 仅在管理端/服务端配置。'),
                _serverManagedBullet('客户端日历中的 Outlook 日程为只读来源。'),
                _serverManagedBullet('离线或服务端失败时不会回退到本地 Graph 同步。'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildServerManagedDiagnosticsPanel(),
          if (_status != null) ...[
            const SizedBox(height: 16),
            _Panel(
              child: Text(_status!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServerManagedDiagnosticsPanel() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _serverManagedDiagnosticsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Panel(
            child: _InlineStateHint(
              icon: Icons.hourglass_empty_outlined,
              message: '正在读取 Outlook 服务端诊断日志...',
            ),
          );
        }
        if (snapshot.hasError) {
          return _Panel(
            child: _InlineStateHint(
              icon: Icons.error_outline,
              iconColor: Colors.redAccent,
              message: 'Outlook 服务端诊断读取失败：${snapshot.error}',
            ),
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final runs = _listOfMaps(data['runs']);
        final diagnostics = _map(data['diagnostics']);
        final fieldCoverage = _map(diagnostics['fieldCoverage']);
        final recentRuns = _listOfMaps(diagnostics['recentRuns']);
        final visibleRuns = runs.isNotEmpty ? runs : recentRuns;
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Outlook 同步运行日志',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '字段覆盖：事件 ${fieldCoverage['eventCount'] ?? 0}，缺标题 ${fieldCoverage['missingTitle'] ?? 0}，缺地点 ${fieldCoverage['missingLocation'] ?? 0}，缺正文 ${fieldCoverage['missingBodyPreview'] ?? 0}，缺组织者 ${fieldCoverage['missingOrganizer'] ?? 0}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (visibleRuns.isEmpty)
                const _InlineStateHint(
                  icon: Icons.inbox_outlined,
                  message: '暂无 Outlook 服务端同步运行记录。',
                )
              else
                for (final run in visibleRuns.take(8))
                  _OutlookRunLogTile(run: run),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadServerManagedOutlookDiagnostics() async {
    final clientApi = await ref.read(clientApiProvider.future);
    final runs = await clientApi.adminOutlookRuns();
    final diagnostics = await clientApi.adminOutlookDiagnostics();
    return <String, dynamic>{
      'runs': runs['runs'],
      'diagnostics': diagnostics,
    };
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Widget _serverManagedBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  bool get _canSync => _isAuthenticated;

  String _authorizationLabel(OutlookSyncMode mode) {
    switch (mode) {
      case OutlookSyncMode.paused:
      case OutlookSyncMode.readOnly:
        return '只读授权';
      case OutlookSyncMode.bidirectional:
        return '读写授权';
    }
  }

  String _permissionHelpText() {
    return '当前 Outlook 授权已迁移到服务端，客户端只消费服务端下发的只读日程。';
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildLastSyncReportPanel() {
    final report = _lastSyncReport;
    if (report == null) {
      return const _Panel(
        child: _InlineStateHint(
          icon: Icons.history_outlined,
          message:
              '\u5f53\u524d\u8fd8\u6ca1\u6709\u6700\u8fd1\u540c\u6b65\u7ed3\u679c\u3002\u5b8c\u6210\u4e00\u6b21\u5b9e\u9645\u540c\u6b65\u540e\uff0c\u8fd9\u91cc\u4f1a\u4fdd\u7559\u6700\u8fd1\u4e00\u6b21\u6210\u529f\u6216\u5931\u8d25\u7684\u6458\u8981\uff0c\u65b9\u4fbf\u56de\u770b\u548c\u6392\u67e5\u3002',
        ),
      );
    }

    final accentColor =
        report.success ? const Color(0xFF43A047) : const Color(0xFFE53935);
    final detail = report.success
        ? report.mode == OutlookSyncMode.bidirectional
            ? '\u540c\u6b65\u65f6\u95f4\uff1a${_formatDateTime(report.attemptedAt)}\n\u540c\u6b65\u6a21\u5f0f\uff1a${report.mode.label}\n\u540c\u6b65\u65e5\u5386\u672c\uff1a${report.calendarBooks} \u4e2a\n\u66f4\u65b0\u65e5\u7a0b\uff1a${report.downloaded} \u6761\n\u4efb\u52a1\u955c\u50cf\uff1a\u65b0\u589e ${report.mirroredCreated} / \u66f4\u65b0 ${report.mirroredUpdated} / \u5220\u9664 ${report.mirroredDeleted} / \u51b2\u7a81 ${report.mirroredConflicted}'
            : '\u540c\u6b65\u65f6\u95f4\uff1a${_formatDateTime(report.attemptedAt)}\n\u540c\u6b65\u6a21\u5f0f\uff1a${report.mode.label}\n\u540c\u6b65\u65e5\u5386\u672c\uff1a${report.calendarBooks} \u4e2a\n\u66f4\u65b0\u65e5\u7a0b\uff1a${report.downloaded} \u6761\n\u672c\u6b21\u672a\u5411 Outlook \u5199\u5165\u4efb\u4f55\u6570\u636e\u3002'
        : '\u5c1d\u8bd5\u65f6\u95f4\uff1a${_formatDateTime(report.attemptedAt)}\n\u540c\u6b65\u6a21\u5f0f\uff1a${report.mode.label}\n\u9519\u8bef\u4fe1\u606f\uff1a${report.errorMessage ?? '\u672a\u77e5\u9519\u8bef'}';
    final actionPresentation = _buildLastSyncActionPresentation(report);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SyncScopeTile(
            icon: report.success
                ? Icons.check_circle_outline
                : Icons.error_outline,
            accentColor: accentColor,
            title: report.success
                ? '\u6700\u8fd1\u4e00\u6b21\u540c\u6b65\u5df2\u5b8c\u6210'
                : '\u6700\u8fd1\u4e00\u6b21\u540c\u6b65\u5931\u8d25',
            status: report.success
                ? '\u6700\u8fd1\u7ed3\u679c\u5df2\u5199\u5165\u672c\u5730\uff0c\u53ef\u968f\u65f6\u56de\u770b'
                : '\u6700\u8fd1\u4e00\u6b21\u5c1d\u8bd5\u672a\u5b8c\u6210\uff0c\u8bf7\u6839\u636e\u9519\u8bef\u4fe1\u606f\u7ee7\u7eed\u6392\u67e5',
            detail: detail,
            actionLabel: actionPresentation.label,
            actionIcon: actionPresentation.icon,
            onAction: actionPresentation.onAction,
          ),
          if (report.success) ...[
            const SizedBox(height: 12),
            _buildLastSyncCalendarBreakdown(report),
            if (report.mode == OutlookSyncMode.bidirectional) ...[
              const SizedBox(height: 12),
              _buildLastSyncTaskMirrorBreakdown(report),
            ],
          ],
          if (report.success &&
              report.mode == OutlookSyncMode.bidirectional) ...[
            const SizedBox(height: 12),
            const _InlineStateHint(
              icon: Icons.shield_outlined,
              iconColor: Color(0xFF43A047),
              message:
                  '\u5373\u4fbf\u5728\u53cc\u5411\u540c\u6b65\u4e0b\uff0cFlowPlanV2 \u4e5f\u53ea\u4f1a\u5199\u5165\u81ea\u5df1\u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668\uff0c\u666e\u901a Outlook \u65e5\u5386\u4ecd\u4fdd\u6301\u53ea\u8bfb\u3002',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLastSyncCalendarBreakdown(OutlookSyncReport report) {
    final changedDetails = report.calendarDetails
        .where((detail) => detail.downloaded > 0)
        .toList();
    changedDetails.sort((left, right) {
      final downloadedCompare = right.downloaded.compareTo(left.downloaded);
      if (downloadedCompare != 0) {
        return downloadedCompare;
      }
      return left.calendarName.compareTo(right.calendarName);
    });
    final visibleDetails = changedDetails.take(6).toList(growable: false);
    final unchangedCount =
        report.calendarDetails.length - changedDetails.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '\u65e5\u5386\u672c\u7ea7\u6458\u8981',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (report.calendarDetails.isEmpty)
          const _InlineStateHint(
            icon: Icons.event_busy_outlined,
            message:
                '\u672c\u6b21\u6ca1\u6709\u8bb0\u5f55\u5230 Outlook \u65e5\u5386\u672c\u660e\u7ec6\u3002',
          )
        else if (changedDetails.isEmpty)
          _InlineStateHint(
            icon: Icons.event_note_outlined,
            iconColor: Colors.blueGrey,
            message:
                '\u672c\u6b21\u5171\u68c0\u67e5 ${report.calendarDetails.length} \u4e2a Outlook \u65e5\u5386\uff0c\u4f46\u672c\u8f6e\u6ca1\u6709\u53d1\u73b0\u9700\u8981\u66f4\u65b0\u7684\u65e5\u7a0b\u3002',
          )
        else ...[
          ...visibleDetails.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SyncScopeTile(
                icon: Icons.event_note_outlined,
                accentColor: const Color(0xFF0078D4),
                title: detail.calendarName,
                status:
                    '\u5df2\u62c9\u53d6 ${detail.downloaded} \u6761\u65e5\u7a0b\u66f4\u65b0',
                detail:
                    '\u5df2\u540c\u6b65\u8fdb FlowPlanV2 \u672c\u5730\u65e5\u5386\u672c ID\uff1a${detail.localCalendarId}\u3002',
              ),
            ),
          ),
          if (changedDetails.length > visibleDetails.length)
            _InlineStateHint(
              icon: Icons.more_horiz,
              message:
                  '\u5176\u4f59 ${changedDetails.length - visibleDetails.length} \u4e2a\u6709\u66f4\u65b0\u7684 Outlook \u65e5\u5386\u4e5f\u5df2\u88ab\u8bb0\u5f55\u5230\u6700\u8fd1\u540c\u6b65\u7ed3\u679c\u4e2d\u3002',
            ),
          if (unchangedCount > 0)
            _InlineStateHint(
              icon: Icons.remove_red_eye_outlined,
              message:
                  '\u53e6\u6709 $unchangedCount \u4e2a Outlook \u65e5\u5386\u5df2\u5b8c\u6210\u68c0\u67e5\uff0c\u4f46\u672c\u6b21\u6ca1\u6709\u53d8\u66f4\u3002',
            ),
        ],
      ],
    );
  }

  Widget _buildLastSyncTaskMirrorBreakdown(OutlookSyncReport report) {
    final details = report.taskMirrorDetails
        .where((detail) => detail.changedCount > 0)
        .toList();
    details.sort((left, right) {
      final changedCompare = right.changedCount.compareTo(left.changedCount);
      if (changedCompare != 0) {
        return changedCompare;
      }
      return left.taskListName.compareTo(right.taskListName);
    });
    final visibleDetails = details.take(6).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '\u4efb\u52a1\u955c\u50cf\u7ea7\u6458\u8981',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (details.isEmpty)
          const _InlineStateHint(
            icon: Icons.task_alt_outlined,
            message:
                '\u672c\u6b21\u672a\u53d1\u751f\u4efb\u52a1\u955c\u50cf\u5199\u56de\u53d8\u66f4\u3002',
          )
        else ...[
          ...visibleDetails.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SyncScopeTile(
                icon: Icons.task_alt_outlined,
                accentColor: const Color(0xFF8E24AA),
                title: detail.taskListName,
                status:
                    '\u65b0\u589e ${detail.created} / \u66f4\u65b0 ${detail.updated} / \u5220\u9664 ${detail.deleted} / \u51b2\u7a81 ${detail.conflicted}',
                detail:
                    '\u955c\u50cf\u5199\u5165\u5bb9\u5668\uff1a${detail.remoteCalendarName}',
              ),
            ),
          ),
          if (details.length > visibleDetails.length)
            _InlineStateHint(
              icon: Icons.more_horiz,
              message:
                  '\u5176\u4f59 ${details.length - visibleDetails.length} \u4e2a\u53d1\u751f\u53d8\u66f4\u7684\u4efb\u52a1\u672c\u4e5f\u5df2\u88ab\u8bb0\u5f55\u5230\u6700\u8fd1\u540c\u6b65\u7ed3\u679c\u4e2d\u3002',
            ),
        ],
      ],
    );
  }

  Widget _buildDiagnosticsPanel(
    AsyncValue<OutlookTaskMirrorDiagnostics> taskMirrorDiagnosticsAsync,
    AsyncValue<List<OutlookFieldConflictSummary>> fieldConflictsAsync,
  ) {
    final diagnostics = taskMirrorDiagnosticsAsync.asData?.value;
    final pendingCleanup = diagnostics?.pendingCleanup ?? 0;
    final localChanged = diagnostics?.localChangedSinceLastMirror ?? 0;
    final conflictCount = fieldConflictsAsync.asData?.value.length ?? 0;
    final conflictHint = pendingCleanup > 0 || localChanged > 0
        ? '\u5df2\u53d1\u73b0 $pendingCleanup \u6761\u5f85\u6e05\u7406\u955c\u50cf\u7d22\u5f15\uff0c$localChanged \u6761\u672c\u5730\u5b57\u6bb5\u53d8\u66f4\u5f85\u5199\u56de\u3002\u51b2\u7a81\u9879\u4e0d\u4f1a\u88ab FlowPlanV2 \u9759\u9ed8\u8986\u76d6\uff0c\u8bf7\u4f18\u5148\u5bfc\u51fa\u62a5\u544a\u68c0\u67e5\u3002'
        : '\u5f53\u524d\u672a\u53d1\u73b0\u5f85\u6e05\u7406\u955c\u50cf\u7d22\u5f15\u6216\u672c\u5730\u5b57\u6bb5\u53d8\u66f4\u51b2\u7a81\u5019\u9009\u3002';

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SyncScopeTile(
            icon: pendingCleanup > 0 || localChanged > 0
                ? Icons.warning_amber_rounded
                : Icons.fact_check_outlined,
            accentColor: pendingCleanup > 0 || localChanged > 0
                ? const Color(0xFFFB8C00)
                : const Color(0xFF43A047),
            title: '\u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009',
            status: pendingCleanup > 0 || localChanged > 0
                ? '\u9700\u8981\u68c0\u67e5'
                : '\u6682\u65e0\u51b2\u7a81\u5019\u9009',
            detail:
                '$conflictHint\n\n\u5f53\u524d\u53ef\u89c1\u51b2\u7a81 / \u5019\u9009\u9879\uff1a$conflictCount \u6761\n\n\u5b89\u5168\u7b56\u7565\uff1a\u666e\u901a Outlook \u65e5\u5386\u59cb\u7ec8\u53ea\u8bfb\uff1b\u4efb\u52a1\u955c\u50cf\u5199\u56de\u5931\u8d25\u65f6\u8bb0\u4e3a\u51b2\u7a81\uff0c\u4e0d\u518d\u9759\u9ed8\u5220\u9664\u540e\u91cd\u5efa\u8fdc\u7aef\u4e8b\u4ef6\u3002',
          ),
          const SizedBox(height: 12),
          _buildFieldConflictList(fieldConflictsAsync),
          const SizedBox(height: 12),
          _buildConflictBatchActions(fieldConflictsAsync),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _exportingDiagnostics ? null : _exportDiagnosticsReport,
              icon: _exportingDiagnostics
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.description_outlined, size: 18),
              label: Text(
                _exportingDiagnostics
                    ? '\u6b63\u5728\u751f\u6210\u8bca\u65ad\u62a5\u544a...'
                    : '\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldConflictList(
    AsyncValue<List<OutlookFieldConflictSummary>> fieldConflictsAsync,
  ) {
    return fieldConflictsAsync.when(
      loading: () => const _InlineStateHint(
        icon: Icons.sync,
        message:
            '\u6b63\u5728\u68c0\u67e5\u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009...',
      ),
      error: (error, _) => _InlineStateHint(
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
        message:
            '\u68c0\u67e5\u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009\u5931\u8d25\uff1a$error',
      ),
      data: (conflicts) {
        if (conflicts.isEmpty) {
          return const _InlineStateHint(
            icon: Icons.check_circle_outline,
            iconColor: Color(0xFF43A047),
            message:
                '\u5f53\u524d\u6ca1\u6709\u9700\u8981\u4eba\u5de5\u68c0\u67e5\u7684\u5b57\u6bb5\u7ea7\u51b2\u7a81\u5019\u9009\u3002',
          );
        }

        final visibleConflicts = conflicts.take(5).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '\u5b57\u6bb5\u53d8\u66f4\u5019\u9009',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...visibleConflicts.map(
              (conflict) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SyncScopeTile(
                  icon: Icons.rule_folder_outlined,
                  accentColor: const Color(0xFFFB8C00),
                  title: conflict.taskSummary,
                  status: '待写回字段：${conflict.changedFields.join('、')}',
                  detail:
                      '\u4efb\u52a1\u672c\uff1a${conflict.taskListName}\nOutlook \u955c\u50cf\u5bb9\u5668\uff1a${conflict.remoteCalendarName}\nFlowPlanV2 \u4f1a\u5728\u53cc\u5411\u540c\u6b65\u65f6\u5c1d\u8bd5\u5199\u56de\u8fd9\u4e9b\u672c\u5730\u5b57\u6bb5\uff1b\u5982\u679c\u8fdc\u7aef\u62d2\u7edd\u6216\u5df2\u88ab\u5220\u9664\uff0c\u5c06\u8bb0\u4e3a\u51b2\u7a81\u800c\u4e0d\u9759\u9ed8\u8986\u76d6\u3002',
                ),
              ),
            ),
            if (conflicts.length > visibleConflicts.length)
              _InlineStateHint(
                icon: Icons.more_horiz,
                message:
                    '\u8fd8\u6709 ${conflicts.length - visibleConflicts.length} \u6761\u5b57\u6bb5\u53d8\u66f4\u5019\u9009\uff0c\u53ef\u5bfc\u51fa\u8bca\u65ad\u62a5\u544a\u67e5\u770b\u5b8c\u6574\u660e\u7ec6\u3002',
              ),
          ],
        );
      },
    );
  }

  Widget _buildConflictBatchActions(
    AsyncValue<List<OutlookFieldConflictSummary>> fieldConflictsAsync,
  ) {
    return fieldConflictsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (conflicts) {
        if (conflicts.isEmpty) {
          return const SizedBox.shrink();
        }

        final remoteDeletedCount = conflicts
            .where(
              (conflict) =>
                  conflict.conflictState ==
                  OutlookTaskMirrorConflictState.remoteDeleted,
            )
            .length;
        final pushableCount =
            conflicts.where((conflict) => conflict.canPushLocal).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pushableCount > 0 || remoteDeletedCount > 0)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (pushableCount > 0)
                    OutlinedButton.icon(
                      onPressed: _syncing
                          ? null
                          : () => _confirmAndRunBatchAction(
                                title:
                                    '\u6279\u91cf\u6309\u672c\u5730\u8986\u76d6\u8fdc\u7aef',
                                content:
                                    '\u8fd9\u4f1a\u628a\u5f53\u524d\u53ef\u5199\u56de\u7684\u672c\u5730\u4efb\u52a1\u5185\u5bb9\u6279\u91cf\u8986\u76d6\u5230 Outlook \u4e13\u5c5e\u955c\u50cf\u4e2d\uff0c\u662f\u5426\u7ee7\u7eed\uff1f',
                                busyText:
                                    '\u6b63\u5728\u6279\u91cf\u6309\u672c\u5730\u5185\u5bb9\u8986\u76d6\u8fdc\u7aef\u955c\u50cf...',
                                runner: (service) =>
                                    service.forcePushAllPendingLocalChanges(),
                              ),
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: Text(
                          '\u6279\u91cf\u6309\u672c\u5730\u8986\u76d6\u8fdc\u7aef\uff08$pushableCount\uff09'),
                    ),
                  if (remoteDeletedCount > 0)
                    OutlinedButton.icon(
                      onPressed: _syncing
                          ? null
                          : () => _confirmAndRunBatchAction(
                                title:
                                    '\u6279\u91cf\u91cd\u5efa\u8fdc\u7aef\u955c\u50cf',
                                content:
                                    '\u8fd9\u4f1a\u4e3a\u5df2\u5728 Outlook \u4fa7\u5220\u9664\u7684\u955c\u50cf\u6279\u91cf\u91cd\u65b0\u521b\u5efa\uff0c\u662f\u5426\u7ee7\u7eed\uff1f',
                                busyText:
                                    '\u6b63\u5728\u6279\u91cf\u91cd\u5efa\u8fdc\u7aef\u5df2\u5220\u9664\u955c\u50cf...',
                                runner: (service) =>
                                    service.recreateAllRemoteDeletedMirrors(),
                              ),
                      icon: const Icon(Icons.restore_outlined, size: 18),
                      label: Text(
                          '\u6279\u91cf\u91cd\u5efa\u5df2\u5220\u9664\u955c\u50cf\uff08$remoteDeletedCount\uff09'),
                    ),
                ],
              ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '\u9010\u6761\u5904\u7406',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...conflicts.take(3).map(
                    (conflict) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${conflict.taskSummary} \u00b7 ${conflict.conflictState.label}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conflict.detail,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          _buildConflictActionButtons(conflict),
                        ],
                      ),
                    ),
                  ),
              if (conflicts.length > 3)
                _InlineStateHint(
                  icon: Icons.more_horiz,
                  message:
                      '\u5176\u4f59 ${conflicts.length - 3} \u6761\u53ef\u7ee7\u7eed\u901a\u8fc7\u8bca\u65ad\u62a5\u544a\u67e5\u770b\u3002',
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildConflictActionButtons(OutlookFieldConflictSummary conflict) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (conflict.canPushLocal)
          OutlinedButton.icon(
            onPressed: _syncing
                ? null
                : () => _confirmAndRunConflictAction(
                      title: '\u4ee5 FlowPlanV2 \u4e3a\u51c6',
                      content:
                          '\u5c06\u201c${conflict.taskSummary}\u201d\u7684\u672c\u5730\u4efb\u52a1\u5185\u5bb9\u5199\u56de\u5230 Outlook \u955c\u50cf\uff0c\u662f\u5426\u7ee7\u7eed\uff1f',
                      busyText:
                          '\u6b63\u5728\u628a\u672c\u5730\u5185\u5bb9\u5199\u56de Outlook \u955c\u50cf...',
                      runner: (service) =>
                          service.forcePushLocalToRemote(conflict.taskId),
                    ),
            icon: const Icon(Icons.upload_outlined, size: 16),
            label: const Text('\u4ee5\u672c\u5730\u4e3a\u51c6'),
          ),
        if (conflict.canPullRemote)
          OutlinedButton.icon(
            onPressed: _syncing
                ? null
                : () => _confirmAndRunConflictAction(
                      title: '\u91c7\u7528 Outlook \u5185\u5bb9',
                      content:
                          '\u5c06 Outlook \u955c\u50cf\u5185\u5bb9\u56de\u586b\u5230\u672c\u5730\u4efb\u52a1\u201c${conflict.taskSummary}\u201d\uff0c\u662f\u5426\u7ee7\u7eed\uff1f',
                      busyText:
                          '\u6b63\u5728\u91c7\u7528 Outlook \u5185\u5bb9\u66f4\u65b0\u672c\u5730\u4efb\u52a1...',
                      runner: (service) =>
                          service.applyRemoteToLocal(conflict.taskId),
                    ),
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('\u91c7\u7528 Outlook \u5185\u5bb9'),
          ),
        if (conflict.canRecreateRemote)
          OutlinedButton.icon(
            onPressed: _syncing
                ? null
                : () => _confirmAndRunConflictAction(
                      title: '\u91cd\u5efa\u8fdc\u7aef\u955c\u50cf',
                      content:
                          '\u5728 Outlook \u4e13\u5c5e\u5bb9\u5668\u4e2d\u91cd\u65b0\u521b\u5efa\u201c${conflict.taskSummary}\u201d\u7684\u955c\u50cf\u4e8b\u4ef6\uff0c\u662f\u5426\u7ee7\u7eed\uff1f',
                      busyText:
                          '\u6b63\u5728\u91cd\u5efa\u8fdc\u7aef Outlook \u955c\u50cf...',
                      runner: (service) =>
                          service.recreateRemoteMirror(conflict.taskId),
                    ),
            icon: const Icon(Icons.restore_outlined, size: 16),
            label: const Text('\u91cd\u5efa\u8fdc\u7aef\u955c\u50cf'),
          ),
        if (conflict.canDetachMirror)
          OutlinedButton.icon(
            onPressed: _syncing
                ? null
                : () => _confirmAndRunConflictAction(
                      title: '\u89e3\u9664\u955c\u50cf\u7ed1\u5b9a',
                      content:
                          '\u53ea\u89e3\u9664\u201c${conflict.taskSummary}\u201d\u4e0e Outlook \u955c\u50cf\u7684\u5bf9\u5e94\u5173\u7cfb\uff0c\u662f\u5426\u7ee7\u7eed\uff1f',
                      busyText:
                          '\u6b63\u5728\u89e3\u9664 Outlook \u955c\u50cf\u7ed1\u5b9a...',
                      runner: (service) => service.detachMirror(
                        conflict.taskId,
                        reason:
                            '\u7528\u6237\u786e\u8ba4\u89e3\u9664 Outlook \u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a',
                      ),
                    ),
            icon: const Icon(Icons.link_off_outlined, size: 16),
            label: const Text('\u89e3\u9664\u955c\u50cf\u7ed1\u5b9a'),
          ),
      ],
    );
  }

  Future<void> _confirmAndRunConflictAction({
    required String title,
    required String content,
    required String busyText,
    required Future<OutlookTaskMirrorActionResult> Function(
      OutlookTaskMirrorSyncService service,
    ) runner,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('\u786e\u8ba4'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final service = await _createMirrorSyncService();
    if (service == null) {
      return;
    }

    setState(() {
      _syncing = true;
      _status = busyText;
    });

    try {
      final result = await runner(service);
      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = result.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = '操作失败：$error';
      });
    }
  }

  Future<void> _confirmAndRunBatchAction({
    required String title,
    required String content,
    required String busyText,
    required Future<OutlookTaskMirrorBatchActionResult> Function(
      OutlookTaskMirrorSyncService service,
    ) runner,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('\u786e\u8ba4'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final service = await _createMirrorSyncService();
    if (service == null) {
      return;
    }

    setState(() {
      _syncing = true;
      _status = busyText;
    });

    try {
      final result = await runner(service);
      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = result.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = '批量处理失败：$error';
      });
    }
  }

  Future<OutlookTaskMirrorSyncService?> _createMirrorSyncService() async {
    if (_syncMode != OutlookSyncMode.bidirectional) {
      setState(() => _status =
          '\u8bf7\u5148\u5207\u6362\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\u6a21\u5f0f\u3002');
      return null;
    }
    if (!_hasRequiredPermission) {
      setState(() => _status =
          '\u5f53\u524d\u6ca1\u6709 Outlook \u8bfb\u5199\u6388\u6743\uff0c\u8bf7\u5148\u91cd\u65b0\u5b8c\u6210\u8ba4\u8bc1\u3002');
      return null;
    }

    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      if (mounted) {
        setState(() =>
            _status = '\u8bf7\u5148\u914d\u7f6e OAuth \u51ed\u636e\u3002');
      }
      return null;
    }

    return OutlookTaskMirrorSyncService(
      graphService: MsGraphService(config, syncMode: _syncMode),
      taskRepository: ref.read(taskRepositoryProvider),
      calendarBooksRepository: ref.read(calendarBooksRepositoryProvider),
      taskListBindingsRepository:
          ref.read(outlookSyncBindingsRepositoryProvider),
      taskMirrorRepository: ref.read(outlookTaskMirrorRepositoryProvider),
      operationLogRepository: ref.read(dataOperationLogRepositoryProvider),
    );
  }

  Widget _buildControlledWriteScopePanel() {
    final managedContainerStatus = _syncMode == OutlookSyncMode.bidirectional &&
            _hasRequiredPermission
        ? '\u5df2\u6ee1\u8db3\u53cc\u5411\u5199\u56de\u524d\u7f6e\u6761\u4ef6'
        : '\u5f53\u524d\u5c1a\u672a\u6ee1\u8db3\u53cc\u5411\u5199\u56de\u524d\u7f6e\u6761\u4ef6';
    final currentModeHint = _buildControlledWriteModeHint();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FlowPlanV2 \u5bf9 Outlook \u7684\u5199\u56de\u59cb\u7ec8\u53d7\u5230\u53d7\u63a7\u8303\u56f4\u9650\u5236\uff0c\u4e0d\u4f1a\u76f4\u63a5\u6539\u52a8\u4f60\u7684\u666e\u901a Outlook \u65e5\u5386\u3002',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const _SyncScopeTile(
            icon: Icons.calendar_month_outlined,
            accentColor: Colors.blueGrey,
            title: '\u666e\u901a Outlook \u65e5\u5386',
            status: '\u59cb\u7ec8\u53ea\u8bfb',
            detail:
                '\u65e0\u8bba\u5f53\u524d\u540c\u6b65\u6a21\u5f0f\u5982\u4f55\uff0cFlowPlanV2 \u90fd\u53ea\u4f1a\u628a\u5b83\u4eec\u62c9\u53d6\u8fdb\u672c\u5730\u65e5\u5386\u672c\uff0c\u4e0d\u4f1a\u76f4\u63a5\u4fee\u6539\u3001\u8986\u76d6\u6216\u5220\u9664\u8fd9\u4e9b\u539f\u751f\u65e5\u5386\u6570\u636e\u3002',
          ),
          const SizedBox(height: 12),
          _SyncScopeTile(
            icon: Icons.shield_outlined,
            accentColor: const Color(0xFF0078D4),
            title: 'FlowPlanV2 \u6258\u7ba1\u65e5\u5386\u5bb9\u5668',
            status: managedContainerStatus,
            detail:
                '\u53ea\u6709\u5728\u540c\u6b65\u6a21\u5f0f\u4e3a\u201c\u53cc\u5411\u540c\u6b65\u201d\u4e14\u5f53\u524d\u4ee4\u724c\u5177\u5907\u8bfb\u5199\u6388\u6743\u65f6\uff0cFlowPlanV2 \u624d\u80fd\u5199\u56de\u81ea\u5df1\u521b\u5efa\u6216\u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u65e5\u5386\u672c\u3002',
          ),
          const SizedBox(height: 12),
          const _SyncScopeTile(
            icon: Icons.task_alt_outlined,
            accentColor: Color(0xFF8E24AA),
            title: '\u4efb\u52a1\u672c\u955c\u50cf\u5bb9\u5668',
            status: '\u4ec5\u9650\u5df2\u7ed1\u5b9a\u4efb\u52a1\u672c',
            detail:
                '\u4efb\u52a1\u4e0d\u4f1a\u76f4\u63a5\u6563\u843d\u5199\u5165 Outlook\u3002\u53ea\u6709\u660e\u786e\u7ed1\u5b9a\u5230 Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\u7684\u4efb\u52a1\u672c\uff0c\u624d\u4f1a\u5728\u53cc\u5411\u540c\u6b65\u65f6\u751f\u6210\u5bf9\u5e94\u955c\u50cf\u4e8b\u4ef6\u3002',
          ),
          const SizedBox(height: 12),
          _InlineStateHint(
            icon: Icons.info_outline,
            iconColor: AppColors.primary,
            message: currentModeHint,
          ),
        ],
      ),
    );
  }

  ({
    String? label,
    IconData? icon,
    Future<void> Function()? onAction,
  }) _buildLastSyncActionPresentation(OutlookSyncReport report) {
    if (_syncing) {
      return (
        label: null,
        icon: null,
        onAction: null,
      );
    }

    if (!report.success &&
        _syncMode == OutlookSyncMode.bidirectional &&
        !_hasRequiredPermission) {
      return (
        label: '\u91cd\u65b0\u8fdb\u884c\u8bfb\u5199\u6388\u6743',
        icon: Icons.lock_open_outlined,
        onAction: _startAuth,
      );
    }

    if (_canSync) {
      return (
        label: report.success
            ? '\u518d\u6b21\u540c\u6b65'
            : '\u91cd\u8bd5\u540c\u6b65',
        icon: Icons.sync,
        onAction: _performSync,
      );
    }

    return (
      label: null,
      icon: null,
      onAction: null,
    );
  }

  String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute';
  }

  String _formatReportFileDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year$month$day-$hour$minute';
  }

  String _buildControlledWriteModeHint() {
    if (_syncMode == OutlookSyncMode.paused) {
      return '\u5f53\u524d\u4e3a\u201c\u6682\u505c\u540c\u6b65\u201d\uff0cFlowPlanV2 \u4e0d\u4f1a\u4e0e Outlook \u53d1\u751f\u4efb\u4f55\u8bfb\u5199\u3002';
    }
    if (_syncMode == OutlookSyncMode.readOnly) {
      return '\u5f53\u524d\u4e3a\u201c\u53ea\u8bfb\u540c\u6b65\u201d\uff0cFlowPlanV2 \u53ea\u4f1a\u8bfb\u53d6 Outlook \u6570\u636e\uff0c\u4e0d\u4f1a\u5411\u8fdc\u7aef\u5199\u5165\u3002';
    }
    if (!_hasRequiredPermission) {
      return '\u5f53\u524d\u5df2\u5207\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\uff0c\u4f46\u4ecd\u7f3a\u5c11\u8bfb\u5199\u6388\u6743\uff0cFlowPlanV2 \u4f9d\u7136\u4e0d\u4f1a\u6267\u884c\u8fdc\u7aef\u5199\u56de\u3002';
    }
    return '\u5f53\u524d\u5df2\u6ee1\u8db3\u53cc\u5411\u540c\u6b65\u4e0e\u6388\u6743\u6761\u4ef6\uff0cFlowPlanV2 \u53ea\u4f1a\u5728\u53d7\u63a7\u5bb9\u5668\u5185\u6267\u884c\u5199\u56de\u3002';
  }

  Widget _buildSyncObjectsPanel({
    required AsyncValue<List<EventCalendar>> eventCalendarsAsync,
    required AsyncValue<List<TaskList>> taskListsAsync,
    required AsyncValue<Map<int, OutlookTaskListBinding>> taskListBindingsAsync,
    required AsyncValue<OutlookTaskMirrorDiagnostics>
        taskMirrorDiagnosticsAsync,
  }) {
    final summary = _buildSyncObjectsSummary(
      eventCalendarsAsync: eventCalendarsAsync,
      taskListsAsync: taskListsAsync,
      taskListBindingsAsync: taskListBindingsAsync,
    );

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openBooksManager,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text(
                    '\u7ba1\u7406\u65e5\u5386\u672c\u4e0e\u4efb\u52a1\u672c'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '\u5df2\u63a5\u5165\u7684 Outlook \u65e5\u5386\u672c',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildOutlookCalendarsList(eventCalendarsAsync),
          const SizedBox(height: 16),
          const Text(
            '\u4efb\u52a1\u672c\u955c\u50cf\u7ed1\u5b9a',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildTaskMirrorBindingsList(
            taskListsAsync: taskListsAsync,
            taskListBindingsAsync: taskListBindingsAsync,
          ),
          const SizedBox(height: 16),
          const Text(
            '\u955c\u50cf\u7d22\u5f15\u5065\u5eb7\u5ea6',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildMirrorDiagnosticsPanel(taskMirrorDiagnosticsAsync),
        ],
      ),
    );
  }

  Widget _buildMirrorDiagnosticsPanel(
    AsyncValue<OutlookTaskMirrorDiagnostics> taskMirrorDiagnosticsAsync,
  ) {
    return taskMirrorDiagnosticsAsync.when(
      loading: () => const _InlineStateHint(
        icon: Icons.sync,
        message:
            '\u6b63\u5728\u68c0\u67e5 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15...',
      ),
      error: (error, _) => _InlineStateHint(
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
        message:
            '\u68c0\u67e5 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u5931\u8d25\uff1a$error',
      ),
      data: (diagnostics) {
        if (diagnostics.totalBindings == 0) {
          return const _InlineStateHint(
            icon: Icons.inventory_2_outlined,
            message:
                '\u5f53\u524d\u8fd8\u6ca1\u6709\u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002\u7ed1\u5b9a\u4efb\u52a1\u672c\u5e76\u5b8c\u6210\u4e00\u6b21\u53cc\u5411\u540c\u6b65\u540e\uff0c\u8fd9\u91cc\u4f1a\u5f00\u59cb\u51fa\u73b0\u5065\u5eb7\u72b6\u6001\u3002',
          );
        }

        if (!diagnostics.hasPendingCleanup) {
          return _SyncScopeTile(
            icon: Icons.verified_outlined,
            accentColor: const Color(0xFF43A047),
            title: '\u955c\u50cf\u7d22\u5f15\u72b6\u6001\u826f\u597d',
            status:
                '\u5171 ${diagnostics.totalBindings} \u6761\u955c\u50cf\u7d22\u5f15\uff0c\u5168\u90e8\u5904\u4e8e\u6b63\u5e38\u53ef\u8ffd\u8e2a\u72b6\u6001',
            detail:
                '\u6b63\u5e38\u955c\u50cf\uff1a${diagnostics.activeBindings} \u6761\n\u5f53\u524d\u4e0d\u5b58\u5728\u5f85\u6e05\u7406\u6216\u5931\u914d\u7684 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002',
          );
        }

        final actionPresentation = _buildMirrorCleanupActionPresentation();
        return _SyncScopeTile(
          icon: Icons.warning_amber_rounded,
          accentColor: const Color(0xFFFB8C00),
          title:
              '\u6709\u90e8\u5206\u955c\u50cf\u7d22\u5f15\u7b49\u5f85\u6e05\u7406',
          status:
              '\u5171 ${diagnostics.totalBindings} \u6761\u955c\u50cf\u7d22\u5f15\uff0c\u5176\u4e2d ${diagnostics.pendingCleanup} \u6761\u4ecd\u5728\u7b49\u5f85\u4e0b\u6b21\u53cc\u5411\u540c\u6b65\u6536\u53e3',
          detail:
              '\u6b63\u5e38\u955c\u50cf\uff1a${diagnostics.activeBindings} \u6761\n\u672c\u5730\u4efb\u52a1\u5df2\u4e0d\u5b58\u5728\uff1a${diagnostics.missingTasks} \u6761\n\u4efb\u52a1\u672c\u5df2\u89e3\u9664\u7ed1\u5b9a\uff1a${diagnostics.unboundTaskLists} \u6761\n\u955c\u50cf\u76ee\u6807\u5df2\u53d1\u751f\u53d8\u66f4\uff1a${diagnostics.movedTargets} \u6761\n\u672c\u5730\u5b57\u6bb5\u53d8\u66f4\u5f85\u5199\u56de\uff1a${diagnostics.localChangedSinceLastMirror} \u6761\n${actionPresentation.hint}',
          actionLabel: actionPresentation.label,
          actionIcon: actionPresentation.icon,
          onAction: actionPresentation.onAction,
        );
      },
    );
  }

  ({
    String label,
    IconData icon,
    String hint,
    Future<void> Function()? onAction,
  }) _buildMirrorCleanupActionPresentation() {
    if (_syncing) {
      return (
        label: '\u6b63\u5728\u5904\u7406',
        icon: Icons.sync,
        hint:
            '\u5f53\u524d\u6b63\u5728\u6267\u884c Outlook \u7ef4\u62a4\u64cd\u4f5c\uff0c\u8fd9\u4e9b\u5f85\u6e05\u7406\u7684\u955c\u50cf\u7d22\u5f15\u4f1a\u5728\u64cd\u4f5c\u7ed3\u675f\u540e\u91cd\u65b0\u8bc4\u4f30\u3002',
        onAction: null,
      );
    }

    if (_syncMode != OutlookSyncMode.bidirectional) {
      return (
        label: '\u5207\u6362\u4e3a\u53cc\u5411\u540c\u6b65',
        icon: Icons.swap_horiz_outlined,
        hint:
            '\u8981\u8ba9 FlowPlanV2 \u628a\u8fd9\u4e9b\u65e7\u7684 Outlook \u955c\u50cf\u4e00\u5e76\u6536\u53e3\uff0c\u9700\u5148\u5207\u6362\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\u6a21\u5f0f\u3002',
        onAction: () async {
          await _performMirrorCleanup();
          await _updateSyncMode(OutlookSyncMode.bidirectional);
        },
      );
    }

    if (!_hasRequiredPermission) {
      return (
        label: '\u91cd\u65b0\u8fdb\u884c\u8bfb\u5199\u6388\u6743',
        icon: Icons.lock_open_outlined,
        hint:
            '\u5f53\u524d\u5df2\u5728\u53cc\u5411\u6a21\u5f0f\uff0c\u4f46 Outlook \u6388\u6743\u4ecd\u662f\u53ea\u8bfb\u3002\u8bf7\u5148\u5b8c\u6210\u8bfb\u5199\u6388\u6743\uff0c\u624d\u80fd\u7ee7\u7eed\u6536\u53e3\u8fd9\u4e9b\u955c\u50cf\u7d22\u5f15\u3002',
        onAction: _performMirrorCleanup,
      );
    }

    return (
      label: '\u7acb\u5373\u6e05\u7406\u5931\u6548\u955c\u50cf',
      icon: Icons.cleaning_services_outlined,
      hint:
          '\u5f53\u524d\u5df2\u6ee1\u8db3\u53cc\u5411\u540c\u6b65\u4e0e\u8bfb\u5199\u6388\u6743\u6761\u4ef6\uff0c\u53ef\u4ee5\u76f4\u63a5\u5220\u9664\u8fd9\u4e9b\u5df2\u5931\u6548\u7684 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15\uff0c\u800c\u4e0d\u5fc5\u5148\u6267\u884c\u4e00\u6574\u8f6e\u540c\u6b65\u3002',
      onAction: _performMirrorCleanup,
    );
  }

  String _buildSyncObjectsSummary({
    required AsyncValue<List<EventCalendar>> eventCalendarsAsync,
    required AsyncValue<List<TaskList>> taskListsAsync,
    required AsyncValue<Map<int, OutlookTaskListBinding>> taskListBindingsAsync,
  }) {
    final eventCalendars = eventCalendarsAsync.asData?.value;
    final taskLists = taskListsAsync.asData?.value;
    final taskBindings = taskListBindingsAsync.asData?.value;

    if (eventCalendars == null || taskLists == null || taskBindings == null) {
      return '\u8fd9\u91cc\u4f1a\u96c6\u4e2d\u5217\u51fa\u5f53\u524d\u53c2\u4e0e Outlook \u540c\u6b65\u7684\u65e5\u5386\u672c\uff0c\u4ee5\u53ca\u5df2\u7ed1\u5b9a Outlook \u4e13\u5c5e\u4efb\u52a1\u955c\u50cf\u5bb9\u5668\u7684\u4efb\u52a1\u672c\u3002';
    }

    final outlookCalendars = eventCalendars
        .where((calendar) => calendar.source == 'outlook')
        .toList();
    final managedCalendars = outlookCalendars
        .where(
          (calendar) =>
              OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(calendar.name),
        )
        .length;

    return '\u5f53\u524d\u5171\u63a5\u5165 ${outlookCalendars.length} \u4e2a Outlook \u65e5\u5386\u672c\uff0c\u5176\u4e2d $managedCalendars \u4e2a\u4e3a FlowPlanV2 \u6258\u7ba1\u5bb9\u5668\uff1b\u5df2\u7ed1\u5b9a ${taskBindings.length} / ${taskLists.length} \u4e2a\u4efb\u52a1\u672c\u5230 Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\u3002';
  }

  Widget _buildOutlookCalendarsList(
    AsyncValue<List<EventCalendar>> eventCalendarsAsync,
  ) {
    return eventCalendarsAsync.when(
      loading: () => const _InlineStateHint(
        icon: Icons.sync,
        message: '\u6b63\u5728\u8bfb\u53d6 Outlook \u65e5\u5386\u672c...',
      ),
      error: (error, _) => _InlineStateHint(
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
        message:
            '\u8bfb\u53d6 Outlook \u65e5\u5386\u672c\u5931\u8d25\uff1a$error',
      ),
      data: (eventCalendars) {
        final outlookCalendars = eventCalendars
            .where((calendar) => calendar.source == 'outlook')
            .toList(growable: false);
        if (outlookCalendars.isEmpty) {
          return const _InlineStateHint(
            icon: Icons.calendar_today_outlined,
            message:
                '\u5f53\u524d\u8fd8\u6ca1\u6709\u63a5\u5165\u4efb\u4f55 Outlook \u65e5\u5386\u672c\u3002\u5b8c\u6210\u4e00\u6b21\u624b\u52a8\u540c\u6b65\u540e\uff0c\u8fd9\u91cc\u4f1a\u51fa\u73b0\u5df2\u5bfc\u5165\u7684\u65e5\u5386\u672c\u3002',
          );
        }

        return Column(
          children: outlookCalendars.map((calendar) {
            final presentation = _describeOutlookCalendar(calendar);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SyncScopeTile(
                icon: presentation.icon,
                accentColor: presentation.color,
                title: calendar.name,
                status: presentation.status,
                detail:
                    '\u5728 FlowPlanV2 \u4e2d\uff1a${calendar.isVisible ? '\u5df2\u663e\u793a' : '\u5df2\u9690\u85cf'}\n${presentation.detail}',
                actionLabel:
                    calendar.isVisible ? '\u9690\u85cf' : '\u663e\u793a',
                actionIcon: calendar.isVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                onAction: () => _toggleOutlookCalendarVisibility(calendar),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }

  Widget _buildTaskMirrorBindingsList({
    required AsyncValue<List<TaskList>> taskListsAsync,
    required AsyncValue<Map<int, OutlookTaskListBinding>> taskListBindingsAsync,
  }) {
    if (taskListsAsync.isLoading || taskListBindingsAsync.isLoading) {
      return const _InlineStateHint(
        icon: Icons.sync,
        message:
            '\u6b63\u5728\u8bfb\u53d6\u4efb\u52a1\u672c\u955c\u50cf\u7ed1\u5b9a...',
      );
    }

    if (taskListsAsync.hasError) {
      return _InlineStateHint(
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
        message:
            '\u8bfb\u53d6\u4efb\u52a1\u672c\u5931\u8d25\uff1a${taskListsAsync.error}',
      );
    }

    if (taskListBindingsAsync.hasError) {
      return _InlineStateHint(
        icon: Icons.error_outline,
        iconColor: Colors.redAccent,
        message:
            '\u8bfb\u53d6 Outlook \u7ed1\u5b9a\u72b6\u6001\u5931\u8d25\uff1a${taskListBindingsAsync.error}',
      );
    }

    final taskLists = taskListsAsync.asData?.value ?? const <TaskList>[];
    final bindings = taskListBindingsAsync.asData?.value ??
        const <int, OutlookTaskListBinding>{};

    if (taskLists.isEmpty) {
      return const _InlineStateHint(
        icon: Icons.task_alt_outlined,
        message: '\u5f53\u524d\u8fd8\u6ca1\u6709\u4efb\u52a1\u672c\u3002',
      );
    }

    final sortedTaskLists = taskLists.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));

    return Column(
      children: sortedTaskLists.map((taskList) {
        final binding = bindings[taskList.id];
        final presentation = _describeTaskMirrorBinding(taskList, binding);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SyncScopeTile(
            icon: presentation.icon,
            accentColor: presentation.color,
            title: taskList.name,
            status: presentation.status,
            detail: presentation.detail,
            actionLabel: binding == null
                ? '\u7ed1\u5b9a\u955c\u50cf'
                : '\u89e3\u9664\u7ed1\u5b9a',
            actionIcon:
                binding == null ? Icons.link_outlined : Icons.link_off_outlined,
            onAction: () {
              if (binding == null) {
                return _bindTaskListToOutlook(taskList);
              }
              return _unbindTaskListFromOutlook(taskList, binding);
            },
          ),
        );
      }).toList(growable: false),
    );
  }

  ({
    IconData icon,
    Color color,
    String status,
    String detail,
  }) _describeOutlookCalendar(EventCalendar calendar) {
    final isManaged =
        OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(calendar.name);

    if (!isManaged) {
      return (
        icon: Icons.cloud_download_outlined,
        color: const Color(0xFF546E7A),
        status:
            '\u5916\u90e8 Outlook \u65e5\u5386\uff0c\u4ec5\u53ea\u8bfb\u5bfc\u5165',
        detail:
            '\u8fd9\u7c7b\u65e5\u5386\u672c\u4e0d\u4f1a\u88ab FlowPlanV2 \u5199\u56de\uff0c\u53ea\u4f1a\u4f5c\u4e3a\u5916\u90e8\u53c2\u8003\u6570\u636e\u540c\u6b65\u8fdb\u6765\u3002',
      );
    }

    if (_syncMode == OutlookSyncMode.paused) {
      return (
        icon: Icons.pause_circle_outline,
        color: Colors.orange,
        status:
            'FlowPlanV2 \u6258\u7ba1\u5bb9\u5668\uff0c\u5f53\u524d\u5df2\u6682\u505c\u540c\u6b65',
        detail:
            '\u6620\u5c04\u5173\u7cfb\u4ecd\u4f1a\u4fdd\u7559\uff0c\u4f46\u76ee\u524d\u4e0d\u4f1a\u7ee7\u7eed\u62c9\u53d6\u6216\u5199\u56de\u3002',
      );
    }

    if (_syncMode == OutlookSyncMode.bidirectional && _hasRequiredPermission) {
      return (
        icon: Icons.cloud_done_outlined,
        color: const Color(0xFF43A047),
        status:
            'FlowPlanV2 \u6258\u7ba1\u5bb9\u5668\uff0c\u53ef\u53d7\u63a7\u5199\u56de',
        detail:
            '\u53ea\u6709\u8fd9\u7c7b\u6807\u8bb0\u4e3a FlowPlanV2 \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668\uff0c\u624d\u5141\u8bb8\u5728\u53cc\u5411\u6a21\u5f0f\u4e0b\u88ab\u5199\u56de\u3002',
      );
    }

    if (_syncMode == OutlookSyncMode.bidirectional && !_hasRequiredPermission) {
      return (
        icon: Icons.lock_clock_outlined,
        color: const Color(0xFFFB8C00),
        status:
            'FlowPlanV2 \u6258\u7ba1\u5bb9\u5668\uff0c\u4f46\u5f53\u524d\u4ecd\u7f3a\u5c11\u8bfb\u5199\u6388\u6743',
        detail:
            '\u5728\u91cd\u65b0\u5b8c\u6210 Outlook \u8bfb\u5199\u6388\u6743\u524d\uff0c\u8fd9\u4e9b\u5bb9\u5668\u4ecd\u53ea\u4f1a\u6309\u53ea\u8bfb\u903b\u8f91\u5904\u7406\u3002',
      );
    }

    return (
      icon: Icons.shield_outlined,
      color: AppColors.primary,
      status:
          'FlowPlanV2 \u6258\u7ba1\u5bb9\u5668\uff0c\u5f53\u524d\u4ecd\u6309\u53ea\u8bfb\u5904\u7406',
      detail:
          '\u867d\u7136\u8fd9\u662f FlowPlanV2 \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668\uff0c\u4f46\u53ea\u8bfb\u6a21\u5f0f\u4e0b\u4f9d\u7136\u4e0d\u4f1a\u5bf9\u5b83\u5199\u56de\u3002',
    );
  }

  ({
    IconData icon,
    Color color,
    String status,
    String detail,
  }) _describeTaskMirrorBinding(
    TaskList taskList,
    OutlookTaskListBinding? binding,
  ) {
    final localVisibility =
        '\u5728 FlowPlanV2 \u4e2d\uff1a${taskList.isVisible ? '\u5df2\u663e\u793a' : '\u5df2\u9690\u85cf'}';

    if (binding == null) {
      return (
        icon: Icons.link_off_outlined,
        color: const Color(0xFF9E9E9E),
        status:
            '\u672a\u7ed1\u5b9a Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668',
        detail:
            '$localVisibility\n\u8fd9\u4e2a\u4efb\u52a1\u672c\u76ee\u524d\u53ea\u5728 FlowPlanV2 \u672c\u5730\u5de5\u4f5c\uff0c\u4e0d\u4f1a\u5411 Outlook \u5199\u5165\u4efb\u4f55\u4efb\u52a1\u955c\u50cf\u3002',
      );
    }

    final linkedAt = _formatBindingDateTime(binding.linkedAt);
    if (_syncMode == OutlookSyncMode.paused) {
      return (
        icon: Icons.pause_circle_outline,
        color: Colors.orange,
        status:
            '\u5df2\u7ed1\u5b9a\uff0c\u4f46\u5f53\u524d\u5904\u4e8e\u6682\u505c\u540c\u6b65',
        detail:
            '$localVisibility\n\u8fdc\u7aef\u5bb9\u5668\uff1a${binding.remoteCalendarName}\n\u7ed1\u5b9a\u65f6\u95f4\uff1a$linkedAt',
      );
    }

    if (_syncMode == OutlookSyncMode.bidirectional && _hasRequiredPermission) {
      return (
        icon: Icons.task_alt_outlined,
        color: const Color(0xFF43A047),
        status:
            '\u5df2\u7ed1\u5b9a\uff0c\u53ef\u5199\u56de Outlook \u955c\u50cf\u5bb9\u5668',
        detail:
            '$localVisibility\n\u8fdc\u7aef\u5bb9\u5668\uff1a${binding.remoteCalendarName}\n\u7ed1\u5b9a\u65f6\u95f4\uff1a$linkedAt',
      );
    }

    if (_syncMode == OutlookSyncMode.bidirectional && !_hasRequiredPermission) {
      return (
        icon: Icons.lock_clock_outlined,
        color: const Color(0xFFFB8C00),
        status:
            '\u5df2\u7ed1\u5b9a\uff0c\u4f46\u5f53\u524d\u8fd8\u6ca1\u6709\u8bfb\u5199\u6388\u6743',
        detail:
            '$localVisibility\n\u8fdc\u7aef\u5bb9\u5668\uff1a${binding.remoteCalendarName}\n\u8bf7\u91cd\u65b0\u5b8c\u6210 Outlook \u8ba4\u8bc1\u540e\u518d\u5199\u56de\uff0c\u7ed1\u5b9a\u65f6\u95f4\uff1a$linkedAt',
      );
    }

    return (
      icon: Icons.visibility_outlined,
      color: AppColors.primary,
      status:
          '\u5df2\u7ed1\u5b9a\uff0c\u4f46\u5f53\u524d\u4ecd\u662f\u53ea\u8bfb\u6a21\u5f0f',
      detail:
          '$localVisibility\n\u8fdc\u7aef\u5bb9\u5668\uff1a${binding.remoteCalendarName}\n\u6620\u5c04\u4f1a\u88ab\u4fdd\u7559\uff0c\u4f46 FlowPlanV2 \u6682\u4e0d\u4f1a\u5199\u56de\u8fd9\u4e2a\u4efb\u52a1\u955c\u50cf\u5bb9\u5668\u3002',
    );
  }

  String _formatBindingDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  Future<void> _openBooksManager() async {
    final width = MediaQuery.of(context).size.width;
    if (width >= 700) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          child: const SizedBox(
            width: 520,
            child: CalendarBooksPage(),
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CalendarBooksPage(),
      ),
    );
  }

  Future<void> _toggleOutlookCalendarVisibility(EventCalendar calendar) async {
    final nextValue = !calendar.isVisible;
    await ref
        .read(calendarBooksRepositoryProvider)
        .toggleEventCalendarVisible(calendar.id, nextValue);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextValue
              ? '\u5df2\u5728 FlowPlanV2 \u4e2d\u663e\u793a\u300c${calendar.name}\u300d'
              : '\u5df2\u5728 FlowPlanV2 \u4e2d\u9690\u85cf\u300c${calendar.name}\u300d',
        ),
      ),
    );
  }

  Future<void> _bindTaskListToOutlook(TaskList taskList) async {
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u8bf7\u5148\u5728 Outlook \u540c\u6b65\u8bbe\u7f6e\u4e2d\u4fdd\u5b58 OAuth \u914d\u7f6e\u5e76\u5b8c\u6210 Outlook \u767b\u5f55\u3002',
          ),
        ),
      );
      return;
    }

    final service = ref.read(outlookManagedContainerServiceFactoryProvider)(
      config: config,
      bindingsRepository: ref.read(outlookSyncBindingsRepositoryProvider),
    );

    try {
      final binding = await service.ensureTaskListMirrorBinding(taskList);
      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u7ed1\u5b9a Outlook \u4e13\u5c5e\u5bb9\u5668\uff1a${binding.remoteCalendarName}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('\u7ed1\u5b9a Outlook \u5bb9\u5668\u5931\u8d25\uff1a$error'),
        ),
      );
    }
  }

  Future<void> _unbindTaskListFromOutlook(
    TaskList taskList,
    OutlookTaskListBinding binding,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u89e3\u9664 Outlook \u7ed1\u5b9a'),
        content: Text(
          '\u786e\u5b9a\u8981\u89e3\u9664\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u4e0e\u300c${binding.remoteCalendarName}\u300d\u7684\u5bf9\u5e94\u5173\u7cfb\u5417\uff1f\u8fd9\u53ea\u4f1a\u89e3\u9664 FlowPlanV2 \u4e2d\u7684\u6620\u5c04\uff0c\u4e0d\u4f1a\u76f4\u63a5\u5220\u6389 Outlook \u8fdc\u7aef\u5bb9\u5668\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '\u89e3\u9664',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await ref
        .read(outlookSyncBindingsRepositoryProvider)
        .removeTaskListBinding(taskList.id);
    final refreshNotifier =
        ref.read(outlookBindingRefreshTickProvider.notifier);
    refreshNotifier.state = refreshNotifier.state + 1;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u89e3\u9664 Outlook \u7ed1\u5b9a',
        ),
      ),
    );
  }

  Future<void> _saveConfig() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() => _status = '请填写完整的客户端 ID。');
      return;
    }

    await OutlookAuthService.saveConfig(clientId);
    if (!mounted) return;
    setState(() {
      _status =
          'OAuth 配置已保存。后续会固定使用 consumers + nativeclient + PKCE 方式连接个人 Outlook。';
    });
  }

  Future<void> _updateSyncMode(OutlookSyncMode mode) async {
    await OutlookAuthService.saveSyncMode(mode);
    final hasRequiredPermission =
        await OutlookAuthService.isAuthorizedForMode(mode);
    if (!mounted) return;
    setState(() {
      _syncMode = mode;
      _hasRequiredPermission = _isAuthenticated && hasRequiredPermission;
      _status = !_isAuthenticated
          ? '同步模式已切换为“${mode.label}”。连接 Outlook 后，FlowPlanV2 会按该模式决定是否写回。'
          : hasRequiredPermission
              ? '\u540c\u6b65\u6a21\u5f0f\u5df2\u66f4\u65b0\u4e3a\u201c${mode.label}\u201d\u3002'
              : '\u540c\u6b65\u6a21\u5f0f\u5df2\u5207\u6362\u4e3a\u201c${mode.label}\u201d\uff0c\u4f46\u5f53\u524d Outlook \u6388\u6743\u4ecd\u4e3a${_authorizationLabel(_grantedMode)}\uff0c\u8bf7\u91cd\u65b0\u8ba4\u8bc1\u4e00\u6b21\u3002';
    });
  }

  Future<void> _startAuth() async {
    await _connectOutlookCalendar();
  }

  Future<void> _exchangeCode() async {
    await _submitOutlookAuthorization();
  }

  Future<void> _logout() async {
    await _disconnectOutlookCalendar();
  }

  Future<void> _connectOutlookCalendar() async {
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '请先保存 OAuth 配置。');
      return;
    }

    final launched = await OutlookCalendarService(config).signInWithMicrosoft(
      requestedMode: _syncMode,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = launched
          ? '浏览器已打开。登录完成后，请复制浏览器地址栏中 code= 后面的授权码并粘贴回来；为了校验 state，推荐直接粘贴完整地址栏内容。'
          : '无法打开浏览器，请检查系统默认浏览器设置。';
    });
  }

  Future<void> _submitOutlookAuthorization() async {
    final rawInput = _authCodeController.text.trim();
    if (rawInput.isEmpty) {
      setState(() => _status = '请输入授权码或完整回调地址。');
      return;
    }

    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '请先保存 OAuth 配置。');
      return;
    }

    setState(() {
      _authSubmitting = true;
      _status = '正在向 Microsoft 提交授权码并换取 token...';
    });

    try {
      final token = await ref
          .read(outlookCalendarServiceFactoryProvider)(config)
          .exchangeCodeForToken(
        rawInput,
        requestedMode: _syncMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _authSubmitting = false;
        _isAuthenticated = true;
        _grantedMode = token.grantedMode;
        _hasRequiredPermission = _syncMode == OutlookSyncMode.paused ||
            token.supportsMode(_syncMode);
        _authCodeController.clear();
        _status =
            '认证成功。FlowPlanV2 已连接个人 Outlook 账号，并会在 access_token 过期后自动使用 refresh_token 刷新。';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Outlook 连接成功。'),
        ),
      );
    } on OutlookAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _authSubmitting = false;
        _status = error.userMessage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.userMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = '认证失败：$error';
      setState(() {
        _authSubmitting = false;
        _status = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _disconnectOutlookCalendar() async {
    await OutlookAuthService.logout();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAuthenticated = false;
      _hasRequiredPermission = false;
      _authSubmitting = false;
      _grantedMode = OutlookSyncMode.bidirectional;
      _authCodeController.clear();
      _status = '已断开 Outlook 连接，本地保存的令牌已清除。';
    });
  }

  Future<void> _refreshServerOutlook() async {
    setState(() {
      _syncing = true;
      _status = '正在请求服务端刷新 Outlook...';
    });

    try {
      final clientApi = await ref.read(clientApiProvider.future);
      final result = await clientApi.refreshOutlook();
      final serverSyncEngine = await ref.read(serverSyncEngineProvider.future);
      final pullResult = await serverSyncEngine.pullChanges();
      await ref.read(reminderServiceProvider).rebuildSystemSchedule();
      ref.invalidate(reminderSystemStatusProvider);
      ref.invalidate(allEventCalendarsProvider);
      ref.invalidate(eventsForSelectedDateProvider);
      ref.invalidate(managementEventsProvider);
      final diagnosticsFuture = _loadServerManagedOutlookDiagnostics();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _serverManagedDiagnosticsFuture = diagnosticsFuture;
        _lastSync = DateTime.now();
        final pulledChanges = pullResult['changes'] is List
            ? (pullResult['changes'] as List).length
            : 0;
        _status =
            'Outlook 已由服务端刷新：${result['status'] ?? 'completed'}，日历本 ${result['calendarCount'] ?? 0} 个，更新 ${result['eventUpserts'] ?? 0} 条，删除 ${result['eventDeletes'] ?? 0} 条；客户端已拉取 $pulledChanges 条服务端变更。';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = 'Outlook 服务端刷新失败：$error';
      });
    }
  }

  Future<void> _performSync() async {
    if (!_syncMode.allowsPull) {
      setState(() => _status =
          '\u5f53\u524d Outlook \u540c\u6b65\u5904\u4e8e\u6682\u505c\u72b6\u6001\u3002');
      return;
    }

    if (!_hasRequiredPermission) {
      setState(
        () => _status =
            '\u5f53\u524d\u6a21\u5f0f\u9700\u8981${_authorizationLabel(_syncMode)}\uff0c\u8bf7\u91cd\u65b0\u8fdb\u884c Outlook \u8ba4\u8bc1\u3002',
      );
      return;
    }

    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(
          () => _status = '\u8bf7\u5148\u914d\u7f6e OAuth \u51ed\u636e\u3002');
      return;
    }

    setState(() {
      _syncing = true;
      _status = _syncMode == OutlookSyncMode.bidirectional
          ? '\u6b63\u5728\u540c\u6b65 Outlook \u65e5\u5386\u672c\u548c\u4e8b\u4ef6...'
          : '\u6b63\u5728\u4ece Outlook \u8bfb\u53d6\u65e5\u5386\u672c\u548c\u4e8b\u4ef6...';
    });

    try {
      final engine = SyncEngine(
        ref.read(eventRepositoryProvider),
        ref.read(calendarBooksRepositoryProvider),
        ref.read(taskRepositoryProvider),
        ref.read(outlookSyncBindingsRepositoryProvider),
        ref.read(outlookTaskMirrorRepositoryProvider),
        config,
        ref.read(dataOperationLogRepositoryProvider),
      );
      final result = await engine.sync();
      await ref.read(reminderServiceProvider).rebuildSystemSchedule();
      ref.invalidate(reminderSystemStatusProvider);
      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;
      final lastSync = await SyncEngine.getLastSyncTime();
      final lastSyncReport = await SyncEngine.getLastSyncReport();
      if (!mounted) return;

      setState(() {
        _syncing = false;
        _lastSync = lastSync;
        _lastSyncReport = lastSyncReport;
        _status = _syncMode == OutlookSyncMode.bidirectional
            ? '\u540c\u6b65\u5b8c\u6210\uff1a\u5df2\u540c\u6b65 ${result.calendarBooks} \u4e2a Outlook \u65e5\u5386\u672c\uff0c\u66f4\u65b0 ${result.downloaded} \u6761\u65e5\u7a0b\uff0c\u4efb\u52a1\u955c\u50cf\u65b0\u5efa ${result.mirroredCreated} \u6761\uff0c\u66f4\u65b0 ${result.mirroredUpdated} \u6761\uff0c\u5220\u9664 ${result.mirroredDeleted} \u6761\uff0c\u51b2\u7a81 ${result.mirroredConflicted} \u6761\u3002\u8fd9\u4e9b\u5199\u56de\u4ecd\u53ea\u4f1a\u53d1\u751f\u5728 FlowPlanV2 \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u5bb9\u5668\u4e2d\uff1b\u51b2\u7a81\u9879\u4e0d\u4f1a\u88ab\u9759\u9ed8\u8986\u76d6\u3002'
            : '\u540c\u6b65\u5b8c\u6210\uff1a\u5df2\u540c\u6b65 ${result.calendarBooks} \u4e2a Outlook \u65e5\u5386\u672c\uff0c\u66f4\u65b0 ${result.downloaded} \u6761\u65e5\u7a0b\u3002FlowPlanV2 \u6ca1\u6709\u5411 Outlook \u5199\u5165\u4efb\u4f55\u6570\u636e\u3002';
      });
    } catch (error) {
      final lastSyncReport = await SyncEngine.getLastSyncReport();
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _lastSyncReport = lastSyncReport;
        _status = '\u540c\u6b65\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _performMirrorCleanup() async {
    if (_syncMode != OutlookSyncMode.bidirectional) {
      setState(() => _status =
          '\u8bf7\u5148\u5207\u6362\u5230\u201c\u53cc\u5411\u540c\u6b65\u201d\u6a21\u5f0f\u3002');
      return;
    }

    if (!_hasRequiredPermission) {
      setState(
        () => _status =
            '\u5f53\u524d\u8fd8\u6ca1\u6709 Outlook \u8bfb\u5199\u6388\u6743\uff0c\u8bf7\u5148\u91cd\u65b0\u5b8c\u6210\u8ba4\u8bc1\u3002',
      );
      return;
    }

    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(
          () => _status = '\u8bf7\u5148\u914d\u7f6e OAuth \u51ed\u636e\u3002');
      return;
    }

    setState(() {
      _syncing = true;
      _status =
          '\u6b63\u5728\u6e05\u7406\u5df2\u5931\u6548\u7684 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15...';
    });

    try {
      final result = await OutlookTaskMirrorSyncService(
        graphService: MsGraphService(config, syncMode: _syncMode),
        taskRepository: ref.read(taskRepositoryProvider),
        calendarBooksRepository: ref.read(calendarBooksRepositoryProvider),
        taskListBindingsRepository:
            ref.read(outlookSyncBindingsRepositoryProvider),
        taskMirrorRepository: ref.read(outlookTaskMirrorRepositoryProvider),
        operationLogRepository: ref.read(dataOperationLogRepositoryProvider),
      ).cleanupStaleTaskMirrors();

      final refreshNotifier =
          ref.read(outlookBindingRefreshTickProvider.notifier);
      refreshNotifier.state = refreshNotifier.state + 1;

      if (!mounted) {
        return;
      }

      final affectedTaskLists = result.taskListDetails.length;
      setState(() {
        _syncing = false;
        _status = result.affected > 0
            ? '\u955c\u50cf\u6e05\u7406\u5b8c\u6210\uff1a\u5df2\u5220\u9664 ${result.affected} \u6761\u5931\u6548 Outlook \u4efb\u52a1\u955c\u50cf\uff0c\u6d89\u53ca $affectedTaskLists \u4e2a\u4efb\u52a1\u672c\u3002'
            : '\u955c\u50cf\u6e05\u7406\u5b8c\u6210\uff1a\u5f53\u524d\u6ca1\u6709\u53ef\u5b89\u5168\u5220\u9664\u7684\u5931\u6548 Outlook \u4efb\u52a1\u955c\u50cf\u3002';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = '\u955c\u50cf\u6e05\u7406\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _exportDiagnosticsReport() async {
    setState(() {
      _exportingDiagnostics = true;
      _status =
          '\u6b63\u5728\u751f\u6210 Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a...';
    });

    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle:
            '\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a',
        fileName:
            'flowplanv2-outlook-diagnostics-${_formatReportFileDate(DateTime.now())}.md',
        type: FileType.custom,
        allowedExtensions: const ['md', 'txt'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _exportingDiagnostics = false;
          _status =
              '\u5df2\u53d6\u6d88\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a\u3002';
        });
        return;
      }

      final report = await OutlookDiagnosticsService(
        calendarBooksRepository: ref.read(calendarBooksRepositoryProvider),
        taskRepository: ref.read(taskRepositoryProvider),
        taskListBindingsRepository:
            ref.read(outlookSyncBindingsRepositoryProvider),
        taskMirrorRepository: ref.read(outlookTaskMirrorRepositoryProvider),
      ).buildMarkdownReport();

      await ref
          .read(outlookDiagnosticsReportWriterProvider)
          .call(outputPath, report);
      if (!mounted) {
        return;
      }
      setState(() {
        _exportingDiagnostics = false;
        _status =
            '\u5df2\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a\uff1a$outputPath';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _exportingDiagnostics = false;
        _status =
            '\u5bfc\u51fa Outlook \u540c\u6b65\u8bca\u65ad\u62a5\u544a\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _resetSync() async {
    await SyncEngine.resetSync();
    if (!mounted) return;
    setState(() {
      _lastSync = null;
      _lastSyncReport = null;
      _status =
          '\u540c\u6b65\u72b6\u6001\u5df2\u91cd\u7f6e\u3002\u4e0b\u6b21\u540c\u6b65\u4f1a\u91cd\u65b0\u62c9\u53d6 Outlook \u6570\u636e\u3002';
    });
  }

  Future<void> _resetSyncedOutlookEventCalendars() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('完全重置 Outlook 日历本'),
        content: const Text(
          '这会删除 FlowPlanV2 本地已经同步到的 Outlook 日历本和其中日程，不会删除任务本，也不会删除 Outlook 服务器中的任何数据。确认后下次同步会重新完整拉取 Outlook 日历。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _syncing = true;
      _status = '正在删除本地 Outlook 日历本并清空同步缓存...';
    });

    try {
      final calendarRepo = ref.read(calendarBooksRepositoryProvider);
      final eventRepo = ref.read(eventRepositoryProvider);
      final calendars = await calendarRepo.getEventCalendarsBySource('outlook');
      var deletedEvents = 0;
      var deletedCalendars = 0;

      for (final calendar in calendars) {
        deletedEvents += await eventRepo.deleteBySourceAndCalendarId(
          source: 'outlook',
          calendarId: calendar.id,
        );
        deletedCalendars += await calendarRepo.deleteEventCalendar(
          calendar.id,
          actor: 'user',
          action: 'reset_outlook_calendar',
          summary: '重置 Outlook 同步日历本「${calendar.name}」',
          metadata: <String, Object?>{
            'source': 'outlook',
            'remote_id': calendar.syncUrl,
          },
        );
      }

      await SyncEngine.resetSync();
      final lastSyncReport = await SyncEngine.getLastSyncReport();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _lastSync = null;
        _lastSyncReport = lastSyncReport;
        _status =
            '已重置 Outlook 日历本：删除 $deletedCalendars 个本地日历本、$deletedEvents 条本地日程。下次同步会重新完整拉取。';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _status = '重置 Outlook 日历本失败：$error';
      });
    }
  }
}
