import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import 'outlook_auth_service.dart';
import 'sync_engine.dart';

class OutlookSettingsPage extends ConsumerStatefulWidget {
  const OutlookSettingsPage({super.key});

  @override
  ConsumerState<OutlookSettingsPage> createState() => _OutlookSettingsPageState();
}

class _OutlookSettingsPageState extends ConsumerState<OutlookSettingsPage> {
  final _clientIdController = TextEditingController();
  final _tenantIdController = TextEditingController();
  final _authCodeController = TextEditingController();

  bool _isAuthenticated = false;
  bool _syncing = false;
  String? _status;
  DateTime? _lastSync;
  OutlookSyncMode _syncMode = OutlookSyncMode.importOnly;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _tenantIdController.dispose();
    _authCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final config = await OutlookAuthService.loadConfig();
    final authed = await OutlookAuthService.isAuthenticated();
    final lastSync = await SyncEngine.getLastSyncTime();
    final syncMode = await OutlookAuthService.loadSyncMode();
    if (!mounted) return;

    setState(() {
      if (config != null) {
        _clientIdController.text = config.clientId;
        _tenantIdController.text = config.tenantId;
      }
      _isAuthenticated = authed;
      _lastSync = lastSync;
      _syncMode = syncMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outlook \u540c\u6b65\u8bbe\u7f6e')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusCard(
              isAuthenticated: _isAuthenticated,
              syncMode: _syncMode,
              lastSync: _lastSync,
            ),
            const SizedBox(height: 24),
            _sectionTitle('\u914d\u7f6e'),
            const SizedBox(height: 8),
            _Panel(
              child: Column(
                children: [
                  TextField(
                    controller: _clientIdController,
                    decoration: const InputDecoration(
                      labelText: 'Client ID',
                      hintText: 'Azure AD \u5e94\u7528\u7684 Client ID',
                      prefixIcon: Icon(Icons.key_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tenantIdController,
                    decoration: const InputDecoration(
                      labelText: 'Tenant ID',
                      hintText: 'Azure AD \u7684 Tenant ID\uff0c\u6216 common',
                      prefixIcon: Icon(Icons.business_outlined, size: 20),
                    ),
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
                  const Text(
                    'FlowPlan \u5f53\u524d\u53ea\u7533\u8bf7 Outlook \u65e5\u5386\u53ea\u8bfb\u6743\u9650\uff0c\u4e0d\u4f1a\u5411\u4f60\u7684 Outlook \u65e5\u5386\u5199\u5165\u3001\u4fee\u6539\u6216\u5220\u9664\u4efb\u4f55\u4e8b\u4ef6\u3002',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (!_isAuthenticated) ...[
                    const Text(
                      '\u6b65\u9aa4 1\uff1a\u6253\u5f00\u6d4f\u89c8\u5668\u5b8c\u6210 Microsoft \u8d26\u53f7\u767b\u5f55\u4e0e\u6388\u6743\u3002',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _startAuth,
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: const Text('\u6253\u5f00\u6d4f\u89c8\u5668\u6388\u6743'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '\u6b65\u9aa4 2\uff1a\u767b\u5f55\u5b8c\u6210\u540e\uff0c\u628a\u56de\u8c03\u5730\u5740\u91cc\u7684 code \u53c2\u6570\u7c98\u8d34\u5230\u4e0b\u65b9\u3002',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _authCodeController,
                      decoration: const InputDecoration(
                        labelText: '\u6388\u6743\u7801\uff08code\uff09',
                        hintText: '\u7c98\u8d34\u56de\u8c03 URL \u4e2d\u7684 code \u53c2\u6570',
                        prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _exchangeCode,
                        icon: const Icon(Icons.login, size: 18),
                        label: const Text('\u5b8c\u6210\u8ba4\u8bc1'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0078D4),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle, color: Color(0xFF43A047)),
                      title: const Text('\u5f53\u524d\u8d26\u53f7\u5df2\u8ba4\u8bc1'),
                      subtitle: const Text('\u5982\u9700\u91cd\u65b0\u7533\u8bf7\u53ea\u8bfb\u6743\u9650\uff0c\u53ef\u9000\u51fa\u540e\u91cd\u65b0\u8ba4\u8bc1\u3002'),
                      trailing: TextButton(
                        onPressed: _logout,
                        child: const Text(
                          '\u9000\u51fa\u767b\u5f55',
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
                      labelText: '\u540c\u6b65\u65b9\u5411',
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
                    child: Text(_syncMode.description, style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _syncing || !_canSync ? null : _performSync,
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
                            : '\u7acb\u5373\u4ece Outlook \u8bfb\u53d6',
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
                      label: const Text('\u91cd\u7f6e\u540c\u6b65\u72b6\u6001'),
                    ),
                  ),
                ],
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
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(_status!, style: const TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 32),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('\u4f7f\u7528\u8bf4\u660e', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  _HelpRow(num: '1.', text: '\u5728 Azure Portal \u6ce8\u518c\u5e94\u7528\uff0c\u83b7\u53d6 Client ID \u548c Tenant ID\u3002'),
                  _HelpRow(num: '2.', text: '\u5728\u201c\u91cd\u5b9a\u5411 URI\u201d\u4e2d\u6dfb\u52a0\uff1ahttp://localhost:8400/callback'),
                  _HelpRow(num: '3.', text: '\u5728 API \u6743\u9650\u4e2d\u6dfb\u52a0\uff1aCalendars.Read\u3001User.Read\u3001offline_access\u3002'),
                  _HelpRow(num: '4.', text: '\u5982\u679c\u4f60\u4e4b\u524d\u7528\u8fc7\u65e7\u7248\u672c\u7684\u8bfb\u5199\u6743\u9650\uff0c\u5efa\u8bae\u9000\u51fa\u767b\u5f55\u540e\u91cd\u65b0\u8ba4\u8bc1\u4e00\u6b21\uff0c\u6539\u6210\u53ea\u8bfb\u6388\u6743\u3002'),
                  _HelpRow(num: '5.', text: 'Outlook \u65e5\u5386\u4f1a\u5148\u540c\u6b65\u6210 FlowPlan \u7684\u65e5\u5386\u672c\uff0c\u518d\u628a\u4e8b\u4ef6\u540c\u6b65\u5230\u5bf9\u5e94\u65e5\u5386\u672c\u4e0b\u3002'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSync => _isAuthenticated && _syncMode != OutlookSyncMode.disabled;

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

  Future<void> _saveConfig() async {
    final clientId = _clientIdController.text.trim();
    final tenantId = _tenantIdController.text.trim();
    if (clientId.isEmpty || tenantId.isEmpty) {
      setState(() => _status = '\u8bf7\u586b\u5199\u5b8c\u6574\u7684 Client ID \u548c Tenant ID\u3002');
      return;
    }

    await OutlookAuthService.saveConfig(clientId, tenantId);
    if (!mounted) return;
    setState(() {
      _status = '\u914d\u7f6e\u5df2\u4fdd\u5b58\u3002\u540e\u7eed\u8ba4\u8bc1\u5c06\u53ea\u7533\u8bf7 Outlook \u65e5\u5386\u53ea\u8bfb\u6743\u9650\u3002';
    });
  }

  Future<void> _updateSyncMode(OutlookSyncMode mode) async {
    await OutlookAuthService.saveSyncMode(mode);
    if (!mounted) return;
    setState(() {
      _syncMode = mode;
      _status = '\u540c\u6b65\u65b9\u5411\u5df2\u66f4\u65b0\u4e3a\u201c${mode.label}\u201d\u3002';
    });
  }

  Future<void> _startAuth() async {
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '\u8bf7\u5148\u4fdd\u5b58 OAuth \u914d\u7f6e\u3002');
      return;
    }

    final launched = await OutlookAuthService.launchAuth(config);
    if (!launched && mounted) {
      setState(() => _status = '\u65e0\u6cd5\u6253\u5f00\u6d4f\u89c8\u5668\uff0c\u8bf7\u68c0\u67e5\u7cfb\u7edf\u9ed8\u8ba4\u6d4f\u89c8\u5668\u8bbe\u7f6e\u3002');
    }
  }

  Future<void> _exchangeCode() async {
    final code = _authCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _status = '\u8bf7\u8f93\u5165\u6388\u6743\u7801\u3002');
      return;
    }

    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '\u8bf7\u5148\u4fdd\u5b58 OAuth \u914d\u7f6e\u3002');
      return;
    }

    final token = await OutlookAuthService.exchangeCode(config, code);
    if (!mounted) return;

    if (token != null) {
      setState(() {
        _isAuthenticated = true;
        _status = '\u8ba4\u8bc1\u6210\u529f\u3002FlowPlan \u73b0\u5728\u53ea\u4f1a\u4ece Outlook \u5355\u5411\u8bfb\u53d6\u65e5\u5386\u6570\u636e\u3002';
      });
      return;
    }

    setState(() => _status = '\u8ba4\u8bc1\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u6388\u6743\u7801\u662f\u5426\u6b63\u786e\u3002');
  }

  Future<void> _logout() async {
    await OutlookAuthService.logout();
    if (!mounted) return;
    setState(() {
      _isAuthenticated = false;
      _status = '\u5df2\u9000\u51fa\u767b\u5f55\u3002';
    });
  }

  Future<void> _performSync() async {
    if (_syncMode == OutlookSyncMode.disabled) {
      setState(() => _status = '\u5f53\u524d\u5df2\u5173\u95ed Outlook \u540c\u6b65\u3002');
      return;
    }

    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '\u8bf7\u5148\u914d\u7f6e OAuth \u51ed\u636e\u3002');
      return;
    }

    setState(() {
      _syncing = true;
      _status = '\u6b63\u5728\u4ece Outlook \u8bfb\u53d6\u65e5\u5386\u672c\u548c\u4e8b\u4ef6...';
    });

    try {
      final engine = SyncEngine(
        ref.read(eventRepositoryProvider),
        ref.read(calendarBooksRepositoryProvider),
        config,
      );
      final result = await engine.sync();
      final lastSync = await SyncEngine.getLastSyncTime();
      if (!mounted) return;

      setState(() {
        _syncing = false;
        _lastSync = lastSync;
        _status =
            '\u540c\u6b65\u5b8c\u6210\uff1a\u5df2\u540c\u6b65 ${result.calendarBooks} \u4e2a Outlook \u65e5\u5386\u672c\uff0c\u66f4\u65b0 ${result.downloaded} \u6761\u65e5\u7a0b\u3002FlowPlan \u6ca1\u6709\u5411 Outlook \u5199\u5165\u4efb\u4f55\u6570\u636e\u3002';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _status = '\u540c\u6b65\u5931\u8d25\uff1a$error';
      });
    }
  }

  Future<void> _resetSync() async {
    await SyncEngine.resetSync();
    if (!mounted) return;
    setState(() {
      _lastSync = null;
      _status = '\u540c\u6b65\u72b6\u6001\u5df2\u91cd\u7f6e\u3002\u4e0b\u6b21\u540c\u6b65\u4f1a\u91cd\u65b0\u62c9\u53d6 Outlook \u6570\u636e\u3002';
    });
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isAuthenticated,
    required this.syncMode,
    required this.lastSync,
  });

  final bool isAuthenticated;
  final OutlookSyncMode syncMode;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final enabled = syncMode != OutlookSyncMode.disabled;
    final color = isAuthenticated && enabled ? const Color(0xFF43A047) : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAuthenticated && enabled ? Icons.cloud_done : Icons.cloud_off,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAuthenticated
                      ? '\u5df2\u8fde\u63a5 Outlook\uff08\u53ea\u8bfb\uff09'
                      : '\u5c1a\u672a\u8fde\u63a5 Outlook',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u5f53\u524d\u6a21\u5f0f\uff1a${syncMode.label}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  syncMode.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (lastSync != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '\u4e0a\u6b21\u540c\u6b65\uff1a${_formatDateTime(lastSync!)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.num,
    required this.text,
  });

  final String num;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            num,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
