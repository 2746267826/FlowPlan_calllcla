# Manual Acceptance Runbook - 2026-06-12

本清单用于替代“继续用自动化硬顶”的收口方式：以下 14 项需要真实设备、真实账号、系统权限、外部服务或长时间运行证据，因此保持 `docs/test-governance/manual-acceptance.csv` 中的 `pending-user` 状态，直到人工执行并补齐 dated evidence。

## 使用规则

1. 每条验收都必须在真实环境执行，不能用 mock、单元测试或截图占位替代。
2. 每条 passing 证据必须包含日期、执行人或设备标识、关键截图/日志/ID，以及失败路径或限制说明。
3. 完成后更新 `docs/test-governance/manual-acceptance.csv` 的 `evidence` 和 `status`，再回填关联的 `docs/test-governance/feature-test-matrix.csv`。
4. 如果环境不可用，保持 `pending-user`，不要改成 `passing`。

## 通用证据格式

建议每条人工验收都保存一个小包，命名为：

`docs/test-governance/reports/manual-evidence/<manual_id>-YYYYMMDD/`

包内建议包含：

- `notes.md`：日期、执行人、设备、系统版本、账号类型、服务地址、结果。
- `screenshots/`：关键按钮、状态、错误、成功结果截图。
- `logs/`：客户端、服务端、Web Admin、命令输出。
- `ids.md`：task id、event id、audit row id、sync mutation id、diagnostic run id、transfer session id 等。

## 待人工验收项

### MANUAL-WIN-001 - Windows task create complete sync audit

环境：
Windows 桌面，标准非管理员用户，本地 server，本地测试数据库，Web Admin 可访问。

操作步骤：
1. 用标准非管理员用户登录 Windows，记录 `whoami` 输出。
2. 启动本地 server、Web Admin 和 Windows Flutter 客户端。
3. 在客户端创建一个新任务，点击保存。
4. 勾选完成该任务。
5. 打开 Web Admin 的 task/audit 页面，找到该任务。
6. 验证任务状态已同步，且存在对应 audit row。

必须覆盖：
保存按钮、完成 checkbox、Web Admin 审计导航；draft、saved、completed、synced、audit-visible 状态；validation failure、sync failure、duplicate completion 风险。

证据：
`whoami` 输出、manifest asInvoker 确认、创建/完成截图、sync mutation id、audit row id。

### MANUAL-WIN-002 - Windows reminder flow and notification handling

环境：
Windows 桌面，本地 server，通知权限已开启。

操作步骤：
1. 创建一个带日期的任务。
2. 使用日期选择器设置 due date。
3. 点击 reminder schedule 按钮创建提醒。
4. 等待系统通知出现。
5. 分别验证 snooze 或 dismiss 动作。
6. 在数据库或诊断视图中确认 schedule row、notification id、audit row。

必须覆盖：
date picker、reminder schedule、notification snooze/dismiss；scheduled、notified、snoozed、dismissed 状态；permission denied、missing due date、notification delivery failure。

证据：
桌面通知截图、schedule row id、notification id、audit row id、失败路径说明。

### MANUAL-WIN-003 - Windows credential validation and redaction

环境：
Windows 桌面，可丢弃测试账号或凭据，本地 server。

操作步骤：
1. 使用测试凭据登录。
2. 验证受保护页面可访问。
3. 执行 rotate credential 或 clear credential。
4. 再次访问受保护页面，确认需要重新认证或处于 credential-cleared 状态。
5. 检查日志、诊断输出和截图，确认没有泄漏 secret。
6. 使用无效或过期凭据验证错误路径。

必须覆盖：
sign-in form、rotate credential、clear credential、protected view navigation；authenticated、unauthenticated、credential-cleared、redacted 状态；invalid credential、expired credential、protected route without auth。

证据：
测试账号说明、脱敏截图、redacted logs、diagnostics id。

### MANUAL-ANDROID-001 - Android usage stats import

环境：
Android 真机，Usage Access 权限可操作，本地 server 可连通。

操作步骤：
1. 安装并启动 Android 客户端。
2. 打开系统 Usage Access 权限页，为应用授权。
3. 返回应用，点击 usage import action。
4. 打开 tracker timeline，确认导入记录出现。
5. 如配置上传，确认 upload payload 或同步记录。
6. 关闭权限后重试，确认 permission denied 状态。

必须覆盖：
usage access permission switch、import action、tracker timeline navigation；permission-granted、importing、imported、uploaded；permission denied、empty usage data、upload failure。

证据：
设备型号/系统版本、权限截图、timeline 截图、upload payload id 或测试说明。

### MANUAL-ANDROID-002 - Android usage reminders and permission recovery

环境：
Android 真机，Usage Access 和 notification 权限均可切换。

操作步骤：
1. 授权 Usage Access 和通知权限。
2. 创建 usage-based reminder。
3. 撤销 Usage Access，确认应用显示 blocked 或 permission recovery 状态。
4. 通过 permission recovery action 恢复权限。
5. 等待或触发通知，执行 notification action。
6. 验证 reminder schedule、notification payload、upload payload。

必须覆盖：
usage reminder create、permission recovery、notification action；blocked、permission-restored、scheduled、notified、uploaded；usage access revoked、notification denied、recovery failure。

证据：
权限切换截图、通知截图、reminder schedule id、upload payload id、恢复过程说明。

### MANUAL-OUTLOOK-001 - Outlook OAuth and sync

环境：
Microsoft 测试账号，测试日历，可授权 Outlook OAuth，本地 server/Web Admin。

操作步骤：
1. 点击 authorize button，完成 OAuth 授权。
2. 记录授权 scope 截图。
3. 点击 read-only sync button。
4. 查看 diagnostics，确认 sync run 成功。
5. 验证本地创建了事件或镜像记录。
6. 确认 read-only scope 下没有远端写操作。
7. 点击 reset connection，确认 reset audit。

必须覆盖：
authorize、read-only sync、reset connection；authorized、syncing、diagnostics-visible、reset；OAuth denial、token refresh failure、sync API failure。

证据：
OAuth scope 截图、diagnostics response、sync run id、本地 event id、无远端写入说明、reset audit id。

### MANUAL-OUTLOOK-002 - Outlook credential revocation and reconnect

环境：
Microsoft 测试账号，允许撤销应用 consent。

操作步骤：
1. 完成 Outlook 授权并运行一次 read-only sync。
2. 到 Microsoft 账号安全/应用授权页撤销 consent。
3. 返回应用触发 sync，确认 revoked 或 failure diagnostics。
4. 点击 reconnect button 重新授权。
5. 再次运行 read-only sync，确认恢复。
6. 点击 reset connection 验证 cleanup 状态。

必须覆盖：
authorize、reconnect、reset connection；authorized、revoked、failure-diagnostics、reconnected；revoked consent、reconnect failure、stale token。

证据：
撤销授权截图、失败 diagnostics、reconnect run id、cleanup notes。

### MANUAL-AI-001 - Real AI provider draft approval

环境：
OpenAI-compatible 测试 key，本地 server，任务创建可用。

操作步骤：
1. 打开 provider 设置页，保存测试 provider。
2. 点击 test connection，确认 connection-ok。
3. 发起 task draft request。
4. 检查 draft-ready 内容。
5. 点击 approve draft。
6. 验证任务被创建，且存在 audit row。
7. 使用 provider error 或 malformed draft 路径验证错误显示。

必须覆盖：
provider save、test connection、draft request、approve draft；provider-saved、connection-ok、draft-ready、approved、audited；provider error、malformed draft、approval failure。

证据：
provider test id、draft 截图、task id、audit row id、错误路径截图。

### MANUAL-AI-002 - AI provider credential failure handling

环境：
OpenAI-compatible 无效 key 和有效测试 key。

操作步骤：
1. 保存无效 provider key。
2. 点击 test connection，确认 invalid-key 错误可见。
3. 检查诊断、日志和截图，确认 key 已脱敏。
4. 用有效测试 key 替换。
5. 再次 test connection，确认 recovered/connection succeeds。
6. 如可模拟网络失败，记录 network failure 状态。

必须覆盖：
provider save、test connection、replace key；invalid-key、error-visible、redacted、recovered；invalid key、network failure、redaction failure。

证据：
脱敏错误截图、provider validation record、provider test id、恢复说明。

### MANUAL-FILE-001 - Real file transfer interruption recovery

环境：
Windows 文件系统，本地 server，准备 10MB 测试文件。

操作步骤：
1. 记录源文件 hash。
2. 点击 upload button 上传 10MB 文件。
3. 在上传过程中执行 cancel、断网、杀进程或其他明确 interrupt 动作。
4. 点击 resume button 恢复上传。
5. 下载文件。
6. 比对下载 hash 与源 hash。
7. 检查 transfer session 和 stored object。

必须覆盖：
upload、cancel/interrupt、resume、download；uploading、interrupted、resumed、downloaded、verified；interrupted transfer、missing chunk、hash mismatch。

证据：
源/目标 hash、transfer session id、interrupt 方式说明、下载验证截图。

### MANUAL-FILE-002 - File transfer credential and cleanup audit

环境：
Windows 文件系统，可丢弃 storage target，本地 server/Web Admin。

操作步骤：
1. 使用测试用户上传 disposable file。
2. 打开 owner verification view，确认 owner 信息。
3. 打开 audit view，确认 owner audit row。
4. 点击 delete button 删除文件。
5. 验证 storage object 和 transfer session cleanup。
6. 记录 cleanup audit row。
7. 如可模拟 unauthorized upload 或 delete failure，记录错误状态。

必须覆盖：
upload、owner verification、delete、audit view；uploaded、owner-visible、deleted、cleanup-confirmed；unauthorized upload、delete failure、stale storage object。

证据：
source hash、transfer session id、owner audit row id、cleanup audit row id、cleanup notes。

### MANUAL-LONGTRACK-001 - Long-running tracking continuity

环境：
Windows 桌面或 Android 真机，本地 server，可连续运行至少 2 小时。

操作步骤：
1. 启动客户端和本地 server。
2. 点击 start tracking button。
3. 记录开始时间。
4. 让 tracking 连续运行至少 2 小时。
5. 期间可记录中间 checkpoint。
6. 点击 stop tracking button。
7. 打开 timeline review，确认连续性。
8. 检查 sync checkpoints 和 audit query result，确认无重复 checkpoint。

必须覆盖：
start tracking、stop tracking、timeline review；tracking active、checkpointed、stopped、synced；session interruption、duplicate checkpoint、sync failure。

证据：
开始/结束时间、timeline 截图、sync checkpoint ids、audit query result。

### MANUAL-AUDIT-001 - Cross-end audit verification

环境：
Windows 桌面、Android 真机或 Web Admin，本地 server 和测试数据库。

操作步骤：
1. 在任一客户端执行一个用户可见动作，例如创建任务、完成任务或上传文件。
2. 记录客户端 mutation id 或实体 id。
3. 打开 Web Admin audit 页面，查找对应记录。
4. 调用 server API audit query，查找同一记录。
5. 直接查询测试数据库 audit row。
6. 比对 actor、entity、timestamp、event type 是否一致。

必须覆盖：
client action、Web Admin audit navigation、API audit query；client-updated、web-visible、api-visible、database-visible；missing audit row、mismatched actor、stale timestamp。

证据：
客户端截图、API response、database audit row id、字段比对说明。

### MANUAL-GEN-DRIFT-001 - Generated Drift churn audit

环境：
本地 checkout，存在 `client_flutter/lib/core/database/app_database.g.dart` diff。

操作步骤：
1. 查看 `git diff -- client_flutter/lib/core/database/app_database.dart client_flutter/lib/core/database/app_database.g.dart`。
2. 确认 generated diff 与 schema/source 变更一致。
3. 如需要，运行项目约定的 Drift generator 或 focused generator owner check。
4. 确认没有手工编辑 generated output。
5. 在证据中记录 schema/source 变更引用和 generator command transcript。

必须覆盖：
git diff review、generator owner check；generated-only、reviewed、source-linked；hand edit suspected、schema/source mismatch、generator unavailable。

证据：
git diff summary、generator command transcript 或 owner sign-off、schema/source change reference。

## 完成后的 CSV 更新规则

人工验收通过后，只更新对应行：

- `status` 改为 `passing`。
- `evidence` 增加日期和证据路径，例如：`2026-06-13: docs/test-governance/reports/manual-evidence/MANUAL-WIN-001-20260613/ contains screenshots, sync mutation id ..., audit row id ...`

不要删除原始要求。若只有部分证据，保持 `pending-user` 并在 evidence 中说明缺口。
