// Outlook 同步设置页面：配置 OAuth2 凭据 + 同步操作
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import 'outlook_auth_service.dart';
import 'sync_engine.dart';

class OutlookSettingsPage extends ConsumerStatefulWidget {
  const OutlookSettingsPage({super.key});

  @override
  ConsumerState<OutlookSettingsPage> createState() =>
      _OutlookSettingsPageState();
}

class _OutlookSettingsPageState extends ConsumerState<OutlookSettingsPage> {
  final _clientIdController = TextEditingController();
  final _tenantIdController = TextEditingController();
  final _authCodeController = TextEditingController();

  bool _isAuthenticated = false;
  bool _syncing = false;
  String? _status;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final config = await OutlookAuthService.loadConfig();
    final authed = await OutlookAuthService.isAuthenticated();
    final lastSync = await SyncEngine.getLastSyncTime();

    if (mounted) {
      setState(() {
        if (config != null) {
          _clientIdController.text = config.clientId;
          _tenantIdController.text = config.tenantId;
        }
        _isAuthenticated = authed;
        _lastSync = lastSync;
      });
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _tenantIdController.dispose();
    _authCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outlook 同步设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 状态卡片 ──────────────────────────────────────────────
            _buildStatusCard(context),
            const SizedBox(height: 24),

            // ── OAuth 配置 ─────────────────────────────────────────────
            _sectionTitle('Azure AD 应用配置'),
            const SizedBox(height: 8),
            _buildConfigSection(context),
            const SizedBox(height: 24),

            // ── 认证操作 ─────────────────────────────────────────────
            _sectionTitle('账号认证'),
            const SizedBox(height: 8),
            _buildAuthSection(context),
            const SizedBox(height: 24),

            // ── 同步操作 ─────────────────────────────────────────────
            if (_isAuthenticated) ...[
              _sectionTitle('同步操作'),
              const SizedBox(height: 8),
              _buildSyncSection(context),
              const SizedBox(height: 24),
            ],

            // ── 操作提示 ──────────────────────────────────────────────
            if (_status != null)
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

            const SizedBox(height: 32),

            // ── 帮助信息 ──────────────────────────────────────────────
            _buildHelpCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isAuthenticated
            ? const Color(0xFF43A047).withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isAuthenticated
              ? const Color(0xFF43A047).withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isAuthenticated ? Icons.cloud_done : Icons.cloud_off,
            color: _isAuthenticated ? const Color(0xFF43A047) : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAuthenticated ? '已连接 Outlook' : '未连接',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
                if (_lastSync != null)
                  Text(
                    '上次同步: ${_lastSync!.month}/${_lastSync!.day} ${_lastSync!.hour}:${_lastSync!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: _clientIdController,
            decoration: const InputDecoration(
              labelText: 'Client ID',
              hintText: 'Azure AD 应用的 Client ID',
              prefixIcon: Icon(Icons.key_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tenantIdController,
            decoration: const InputDecoration(
              labelText: 'Tenant ID',
              hintText: 'Azure AD 的 Tenant ID（或 common）',
              prefixIcon: Icon(Icons.business_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存配置'),
              onPressed: _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isAuthenticated) ...[
            const Text(
              '步骤1: 点击下方按钮打开浏览器完成 Microsoft 账户登录',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('打开浏览器授权'),
                onPressed: _startAuth,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '步骤2: 登录完成后，将回调中的 code 参数粘贴到下方',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _authCodeController,
              decoration: const InputDecoration(
                labelText: '授权码 (code)',
                hintText: '粘贴回调 URL 中的 code 参数',
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login, size: 18),
                label: const Text('完成认证'),
                onPressed: _exchangeCode,
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
              title: const Text('已认证成功'),
              trailing: TextButton(
                onPressed: _logout,
                child: const Text('退出登录',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, size: 18),
              label: Text(_syncing ? '同步中...' : '立即同步'),
              onPressed: _syncing ? null : _performSync,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重置同步状态'),
              onPressed: _resetSync,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('使用说明', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _helpRow('1.', '前往 Azure Portal 注册应用，获取 Client ID 和 Tenant ID'),
          _helpRow('2.', '在「重定向 URI」中添加: http://localhost:8400/callback'),
          _helpRow('3.', '在「API 权限」中添加: Calendars.ReadWrite, User.Read'),
          _helpRow('4.', '填写上方配置并完成认证即可开始同步'),
        ],
      ),
    );
  }

  Widget _helpRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(num,
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── 操作方法 ─────────────────────────────────────────────────────────

  Future<void> _saveConfig() async {
    final clientId = _clientIdController.text.trim();
    final tenantId = _tenantIdController.text.trim();
    if (clientId.isEmpty || tenantId.isEmpty) {
      setState(() => _status = '请填写完整的 Client ID 和 Tenant ID');
      return;
    }
    await OutlookAuthService.saveConfig(clientId, tenantId);
    setState(() => _status = '配置已保存 ✓');
  }

  Future<void> _startAuth() async {
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '请先保存 OAuth 配置');
      return;
    }
    final launched = await OutlookAuthService.launchAuth(config);
    if (!launched) {
      setState(() => _status = '无法打开浏览器');
    }
  }

  Future<void> _exchangeCode() async {
    final code = _authCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _status = '请输入授权码');
      return;
    }
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '请先保存 OAuth 配置');
      return;
    }
    final token = await OutlookAuthService.exchangeCode(config, code);
    if (token != null) {
      setState(() {
        _isAuthenticated = true;
        _status = '认证成功！可以开始同步了';
      });
    } else {
      setState(() => _status = '认证失败，请检查授权码是否正确');
    }
  }

  Future<void> _logout() async {
    await OutlookAuthService.logout();
    setState(() {
      _isAuthenticated = false;
      _status = '已退出登录';
    });
  }

  Future<void> _performSync() async {
    final config = await OutlookAuthService.loadConfig();
    if (config == null) {
      setState(() => _status = '请先配置 OAuth 凭据');
      return;
    }

    setState(() {
      _syncing = true;
      _status = '正在同步...';
    });

    try {
      final eventRepo = ref.read(eventRepositoryProvider);
      final engine = SyncEngine(eventRepo, config);
      final result = await engine.sync();
      final lastSync = await SyncEngine.getLastSyncTime();

      setState(() {
        _syncing = false;
        _lastSync = lastSync;
        _status = '同步完成！上传 ${result.uploaded} 条，下载 ${result.downloaded} 条';
      });
    } catch (e) {
      setState(() {
        _syncing = false;
        _status = '同步失败: $e';
      });
    }
  }

  Future<void> _resetSync() async {
    await SyncEngine.resetSync();
    setState(() {
      _lastSync = null;
      _status = '同步状态已重置';
    });
  }
}
