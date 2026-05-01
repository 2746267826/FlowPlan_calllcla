# FlowPlanV2 发布检查清单

本文件对应根目录 `plan260424.md` 的 P0：发布稳定与回归验证。

当前发布候选版本：`v1.4.4+144`

说明：Codex 在本项目中不主动运行 `dart` / `flutter` 命令。以下命令需要由开发者在本机执行，并把结果反馈回来。

## 1. 版本链路

- [x] `pubspec.yaml` 版本号已更新为 `1.4.4+144`。
- [x] `msix_config.msix_version` 已更新为 `1.4.4.144`。
- [x] `lib/core/app/app_release.dart` 已更新为 `v1.4.4`。
- [x] `windows/runner/Runner.rc` 默认版本号已更新为 `1.4.4`。
- [x] `README.md` 已同步当前版本与发布验证入口。
- [x] `version.txt` 已同步当前版本更新说明。
- [x] `update.txt` 已建立日常更新记录。

## 2. 本地命令验证

请在项目根目录执行：

```powershell
flutter analyze
```

期望结果：

- [ ] 0 issues。

请在 Windows 上执行：

```powershell
flutter build windows --release
```

期望结果：

- [ ] 构建成功。
- [ ] Release 应用可启动。
- [ ] 应用图标、窗口标题、设置页版本号正确。

请在 Android 设备或模拟器上执行：

```powershell
flutter build apk --release
```

期望结果：

- [ ] 构建成功。
- [ ] 应用可安装并启动。
- [ ] Android 网络权限、Usage Stats 权限入口可用。

如准备发布到应用商店或长期安装包，请再执行：

```powershell
flutter build appbundle --release
```

期望结果：

- [ ] App Bundle 构建成功。

## 3. Windows 手工回归

- [ ] Debug 与 Release 存储目录互不污染。
- [ ] Windows 版本以管理员权限启动。
- [ ] 开机自启动可开启、可关闭，实际行为一致。
- [ ] 最小化到托盘后可重新唤起。
- [ ] 托盘右键菜单可退出。
- [ ] 日程 / 任务提醒只使用托盘或系统通知，不再弹出 FlowPlanV2 软件置顶窗口。
- [ ] 数据库路径可见，数据库可导出。
- [ ] 审计日志页面可查看高风险数据操作记录。

## 4. Android 手工回归

- [ ] 设置页不显示 Windows 托盘和开机自启动项。
- [ ] 追踪页不会出现红色 overflow 文本。
- [ ] 追踪页显示应用名，避免只显示包名。
- [ ] Outlook 提交授权码前的网络诊断能区分 DNS / 网络问题和 OAuth 授权码问题。
- [ ] 手机宽度和平板宽度下主导航、设置页、Outlook 设置页均不溢出。

## 5. Outlook 回归

- [ ] 使用 `consumers + PKCE + nativeclient` 登录个人 Outlook 账号。
- [ ] 授权码回填后能成功换取 token。
- [ ] access token 过期后能通过 refresh token 自动刷新。
- [ ] 手动同步 Outlook 日历成功。
- [ ] Outlook 来源日程的标题、地点、备注能正常导入。
- [ ] 含 HTML 正文的 Outlook 备注能转换为可读纯文本。
- [ ] Outlook 日程时间没有整体偏移一小时。
- [ ] “完全重置已同步的 Outlook 日历本”只清理本地 Outlook 日历本和日程缓存，不删除远端 Outlook 数据。
- [ ] 重置后重新同步能恢复 Outlook 日程。
- [ ] 普通 Outlook 日历默认只读，不静默写回远端。
- [ ] 只有 FlowPlanV2 托管的任务镜像容器允许受控写回，并且写回必须有审计记录。

## 6. 日历 / 任务 / 管理页回归

- [ ] 新建日程必须绑定日历本。
- [ ] 新建任务必须绑定任务本。
- [ ] 日程详情可删除。
- [ ] 任务详情可删除。
- [ ] 左侧导航高亮跟随当前页面变化。
- [ ] “全部任务与日程管理”页可统一查看任务和日程。
- [ ] 管理页搜索、类型筛选、完成状态筛选正常。
- [ ] 管理页多选、批量删除、批量完成任务前会要求人工确认。
- [ ] 批量操作写入数据操作审计日志。

## 7. 追踪回归

- [ ] 追踪页进入后不会自动高频刷新。
- [ ] 右上角手动刷新可更新摘要数据。
- [ ] 键鼠监听不会在主线程高频调用 `ProcessInfo.currentRss`。
- [ ] 鼠标移动已在原生层合并后再传给 Dart，避免逐条移动写入导致数据爆炸。
- [ ] 主追踪页只保留摘要和入口，详细日志、输入历史、热力图等保留在二级页面。
- [ ] 键鼠输入事件按顺序写入数据库和 JSONL 日志。

## 8. 发布阻断项

以下任意一项失败，建议不要发布：

- `flutter analyze` 出现 error 或 warning 级别问题。
- Windows 或 Android Release 构建失败。
- Outlook 登录或手动同步不可用。
- Outlook 同步会误修改普通日历数据。
- 数据库迁移导致旧数据不可读。
- 托盘无法退出或无法唤起。
- 追踪页再次出现明显卡死。
- 批量删除 / 批量修改绕过人工确认或审计日志。

## 9. 发布记录要求

- 每次发布前更新 `version.txt`。
- 每次重要开发后更新 `update.txt`。
- 如果用户可见能力、权限、同步边界、构建方式或数据安全说明变化，同步修缮 `README.md`。
- 如果 P0 验证发现新问题，将问题回写到 `plan260424.md` 的对应阶段。
