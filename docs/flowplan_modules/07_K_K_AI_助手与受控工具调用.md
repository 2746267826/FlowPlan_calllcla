<!--
Codex 阅读说明：
1. 本文件是实现规格参考。
2. 本次只处理用户明确指定的模块和任务。
3. 文中的“给 Codex 的提示词”只是可复制模板，不要自动执行。
4. 严禁运行 flutter / dart 命令。
-->

# FlowPlan 01：详细实现方式讨论稿 v2

> 用途：这份文档负责讨论每个模块到底怎么做。  
> `00_progress_plan.md` 负责看进度；本文件负责写实现细节。  
> 建议每次只细化一个模块，确认后再进入下一个模块。

## Codex 阅读说明

本文档正文是“实现规格”，不是要求 Codex 自动一次性执行所有内容。

每个模块末尾的“给 Codex 的提示词”应视为可复制的任务模板。让 Codex 自主读取本文档时，应该明确告诉它：

```text
请把本文档作为实现规格参考，不要自动执行所有提示词。
本次只处理我指定的一个模块和一个任务。
模块末尾的 Codex 提示词只是可复制模板，除非我明确指定，否则不要逐条执行。
```

建议长期做法：

- `00_progress_plan.md`：给 Codex 作为进度和状态规则参考。
- `01_detailed_implementation_spec.md`：给 Codex 作为实现规格参考。
- 每次单独发一条明确提示词：指定模块、目标状态、是否允许改代码、是否允许运行命令。

---

## 0. 每个模块固定讨论格式

后续每一部分都按这个结构讨论，避免变成泛泛而谈。

```md
## 模块名称

### 1. 目标
这个模块最终要解决什么问题，给用户什么能力。

### 2. 用户流程
用户具体怎么点、怎么输入、怎么看到结果，失败时怎么处理。

### 3. 数据模型
本地数据库、服务端数据库、关键字段、状态枚举、同步标记。

### 4. 服务端实现
NestJS 模块、Controller、Service、Repository、后台任务、审计日志。

### 5. Flutter 客户端实现
页面、Provider、Repository、本地数据库、离线队列、状态展示。

### 6. Web 管理端实现
管理端能看什么、查什么、修什么、审计什么。

### 7. 同步、离线与冲突
断网如何处理，多端如何同步，冲突如何产生和解决。

### 8. 异常与边界情况
网络错误、数据损坏、重复提交、权限失败、服务端不可用等。

### 9. 安全与隐私
哪些数据敏感，哪些操作必须确认，哪些内容不能发给第三方 AI。

### 10. 验收标准
从骨架到 MVP、验证可用、稳定可用的标准。

### 11. 给 Codex 的提示词
拆成可执行的小任务，让 Codex 不要乱做。
```

---
---

## 建议给 Codex 的使用方式

每次只发一个模块文件，并额外附上一条明确任务，例如：

```text
请只阅读 docs/flowplan_modules/03_G_智能排程.md。
本次只复核当前代码真实状态，不要开发新功能，不要运行 flutter 或 dart 指令。
请按文档末尾的“复核当前智能排程真实状态”格式输出。
```

推荐文件职责：

- `00_README_FOR_CODEX.md`：长期公共说明、阅读规则、固定模块格式。
- `01_D_离线同步与冲突处理.md` 等：每次只给 Codex 当前要处理的模块。
- 原始总文档可以保留，但不要每次都喂给 Codex。

---

# 第七部分：K AI 助手与受控工具调用

## 1. 目标

K 模块的目标是让 AI 成为 FlowPlan 的智能入口，但不能让 AI 绕过用户确认、权限边界和审计。

你理解的 AI 功能可以分成两个大模块：

```text
K1：LLM 辅助判断
  软件自己的规则、模型或算法在复杂场景下无法完全分辨时，询问 LLM 获得更准确的解释、分类、总结和建议。

K2：OpenClaw 式受控操作 FlowPlan
  用户通过自然语言让 AI 操作 FlowPlan，但 AI 只能生成操作草案，不能直接无确认写库或操作外部系统。
```

K 模块的核心目标：

```text
自然语言 / 系统不确定场景
  -> 读取受限上下文
  -> LLM 解释或生成建议
  -> 如果只是解释，直接展示
  -> 如果涉及写操作，生成 OperationDraft
  -> 用户确认
  -> FlowPlan 执行器执行
  -> 写入审计
```

一句话目标：

```text
AI 可以帮忙判断、总结、建议和起草操作，但最终写入必须由 FlowPlan 受控执行器完成，并且由用户确认。
```

---

## 2. 两类 AI 能力

### 2.1 K1：LLM 辅助判断

这类能力用于“软件自身难以准确判断”的场景。

典型场景：

```text
活动理解不确定
  -> 这段 VS Code + 浏览器 + 文件夹活动到底是不是某个作业？

任务匹配不确定
  -> 这个文件夹更像属于哪个任务？

日报总结不自然
  -> 如何把一天活动整理成自然语言？

排程解释需要更友好
  -> 为什么建议今晚先写数据库作业？

冲突说明需要解释
  -> 本地版本和云端版本有什么差异？
```

特点：

- 主要是读上下文、生成解释。
- 默认不直接写库。
- 输出是建议、分类、摘要、理由、置信度。
- 可以用于提高 F/G/H/J/L 等模块的体验。

### 2.2 K2：OpenClaw 式受控操作 FlowPlan

这类能力类似 OpenClaw 的“AI 能实际做事”，但必须比通用 agent 更安全。

用户可以说：

```text
帮我把明天晚上的时间安排给数据库作业。
帮我创建一个下周三截止的英语阅读任务。
帮我把今天上午的活动整理成实际记录。
帮我找数据库作业相关文件。
帮我生成今天的日报。
```

AI 不能直接执行，而是：

```text
用户自然语言
  -> AI 解析意图
  -> 查询只读上下文
  -> 生成操作草案
  -> 用户看到将要创建/修改/删除什么
  -> 用户确认
  -> FlowPlan 受控执行器执行
  -> 写入审计
```

OpenClaw 式能力的重点不是“AI 自由控制一切”，而是：

```text
自然语言入口 + 工具调用能力 + 权限边界 + 人工确认 + 审计追踪
```

---

## 3. 用户流程

### 3.1 AI 辅助判断活动片段

```text
系统生成活动片段，但置信度只有 58%
  -> 规则无法确定属于哪个任务
  -> 系统把脱敏后的片段摘要发给 LLM
  -> LLM 返回：更可能是“数据库课程作业”，理由是 VS Code 项目路径和任务标题匹配
  -> FlowPlan 显示建议和理由
  -> 用户确认或修正
```

用户看到：

```text
AI 建议：这段活动可能属于“数据库课程作业”
理由：
- 主要应用是 VS Code 和浏览器
- 项目路径包含 database/homework
- 任务“数据库课程作业”明天截止
置信度：76%
操作：确认 / 改为其他任务 / 忽略
```

### 3.2 AI 创建任务草案

```text
用户：帮我加一个下周五截止的数据库实验报告任务，预计 3 小时。
  -> AI 解析
  -> 生成 create_task 草案
  -> 用户看到字段
  -> 用户确认
  -> FlowPlan 创建任务
  -> 写入审计
```

草案展示：

```text
将创建任务：
标题：数据库实验报告
截止时间：下周五 23:59
预计耗时：3 小时
任务本：课程任务
优先级：普通

操作：确认创建 / 修改草案 / 取消
```

### 3.3 AI 重排计划草案

```text
用户：我今天没写作业，帮我重新排一下。
  -> AI 查询今天计划和实际活动摘要
  -> AI 调用排程上下文
  -> 生成 reschedule 草案
  -> 用户查看新旧对比
  -> 用户确认部分或全部
```

注意：真正写入排程片段的是 G 模块的排程执行器，不是 LLM 自己。

### 3.4 AI 查找文件

```text
用户：帮我找数据库作业相关资料。
  -> AI 查询 H 文件中心索引
  -> 读取文件名、路径摘要、任务关联、最近使用
  -> 返回候选文件和理由
```

默认不读取文件正文。

如果用户要求：

```text
帮我总结这个 PDF
```

必须提示：

```text
需要读取该文件内容并可能发送给第三方 AI，是否允许？
```

### 3.5 AI 高风险操作

高风险操作必须二次确认。

例如：

```text
用户：把旧版本恢复回来。
  -> AI 只能生成 restore_version 草案
  -> FlowPlan 显示当前版本、旧版本、影响范围
  -> 用户二次确认
  -> J 模块执行恢复
  -> 写入审计
```

---

## 4. AI 权限分级

### 4.1 只读能力

AI 可以直接读取摘要级上下文：

| 能力 | 是否需要确认 |
|---|---|
| 查询今天日程摘要 | 不需要 |
| 查询任务列表摘要 | 不需要 |
| 查询已确认实际记录摘要 | 不需要 |
| 查询活动片段摘要 | 不需要，但敏感字段脱敏 |
| 查询文件名和路径摘要 | 不需要 |
| 查询日报/周报 | 不需要 |

### 4.2 草案能力

AI 可以生成草案，但不能直接执行：

| 能力 | 执行方式 |
|---|---|
| 创建任务 | OperationDraft -> 用户确认 |
| 修改任务 | OperationDraft -> 用户确认 |
| 创建日程 | OperationDraft -> 用户确认 |
| 修改日程 | OperationDraft -> 用户确认 |
| 生成实际记录 | OperationDraft -> 用户确认 |
| 生成排程草案 | 调 G 模块，用户确认 |
| 绑定文件到任务 | OperationDraft -> 用户确认 |
| 生成日报草稿 | 用户确认保存 |

### 4.3 高风险能力

必须二次确认，必要时还要输入确认文本。

| 能力 | 要求 |
|---|---|
| 删除任务/日程 | 二次确认 |
| 批量修改排程 | 二次确认 |
| 移动/删除文件 | 二次确认 |
| 恢复历史版本覆盖当前文件 | 二次确认，恢复前备份当前版本 |
| 写入 Outlook | 显示写入对象和字段 |
| 写入 OneDrive | 显示路径、版本、影响范围 |
| 执行服务器任务 | 显示命令/任务类型/影响范围 |
| 读取完整敏感文件内容给第三方 AI | 明确授权 |

### 4.4 禁止能力

首版禁止：

```text
AI 直接执行 shell 命令
AI 直接读写数据库
AI 直接删除文件
AI 直接覆盖历史版本
AI 直接把完整键盘输入发给第三方
AI 直接绕过确认写入外部系统
AI 安装第三方 skill 后自动获得权限
```

---

## 5. 数据模型

### 5.1 AI Provider 配置：`ai_providers`

```text
id
user_id
name
provider_type           openai_compatible / local / custom
base_url
model_name
api_key_encrypted
temperature
max_tokens
status                  disabled / enabled / error
test_status             not_tested / success / failed
last_test_at
last_error
created_at
updated_at
```

### 5.2 AI 会话：`ai_conversations`

```text
id
user_id
title
source                  app / web_admin / telegram / webhook / system
status                  active / archived
created_at
updated_at
```

### 5.3 AI 消息：`ai_messages`

```text
id
conversation_id
role                    user / assistant / system / tool
content
content_redacted        true / false
context_snapshot_id
created_at
```

### 5.4 AI 上下文快照：`ai_context_snapshots`

```text
id
user_id
conversation_id
context_type            task_summary / schedule_summary / activity_summary / file_summary / report_summary / mixed
payload_json
sensitive_policy_json
redaction_summary
created_at
```

### 5.5 操作草案：`ai_operation_drafts`

```text
id
user_id
conversation_id
operation_type          create_task / update_task / create_event / update_event / create_actual_log / reschedule / link_file / generate_report / restore_file_version
risk_level              low / medium / high / critical
status                  pending / approved / rejected / executed / expired / failed
summary
payload_json
preview_diff_json
requires_confirmation   true / false
requires_second_confirm true / false
expires_at
created_at
approved_at
executed_at
rejected_at
```

### 5.6 工具调用日志：`ai_tool_calls`

```text
id
conversation_id
draft_id
tool_name
input_json
output_json
status                  success / failed / blocked / requires_confirmation
error_message
created_at
```

### 5.7 权限策略：`ai_tool_policies`

```text
id
user_id
tool_name
permission_level        disabled / read_only / draft_only / confirm_required / second_confirm_required
allowed_scopes_json
denied_scopes_json
created_at
updated_at
```

### 5.8 AI 审计：`ai_audit_logs`

也可以复用全局 audit_logs。

```text
id
user_id
conversation_id
draft_id
event_type              provider_updated / message_sent / context_built / draft_created / draft_approved / draft_executed / draft_rejected / tool_blocked
summary
payload_json
created_at
```

---

## 6. 服务端实现

建议 NestJS 模块：

```text
server/src/modules/ai/
  ai.module.ts
  ai.controller.ts
  ai.service.ts
  ai-provider.service.ts
  ai-context.service.ts
  ai-redaction.service.ts
  ai-tool-router.service.ts
  ai-draft.service.ts
  ai-draft-executor.service.ts
  ai-policy.service.ts
  ai-audit.service.ts
  ai.repository.ts
  ai.types.ts
```

### 6.1 API 设计

#### Provider 设置

```text
GET /ai/providers
POST /ai/providers
PATCH /ai/providers/:id
POST /ai/providers/:id/test
```

#### 会话和消息

```text
GET /ai/conversations
POST /ai/conversations
GET /ai/conversations/:id/messages
POST /ai/conversations/:id/messages
```

#### 上下文

```text
GET /ai/context/summary
POST /ai/context/build
```

#### 草案

```text
GET /ai/drafts
GET /ai/drafts/:id
POST /ai/drafts/:id/approve
POST /ai/drafts/:id/reject
POST /ai/drafts/:id/execute
```

#### 权限策略

```text
GET /ai/tool-policies
PATCH /ai/tool-policies/:toolName
```

### 6.2 AI 请求处理流程

```text
用户消息
  -> 识别意图
  -> 构建只读上下文
  -> 脱敏
  -> 调用 LLM
  -> 解析 LLM 输出
  -> 如果是普通回答，保存 assistant message
  -> 如果包含操作，生成 ai_operation_drafts
  -> 返回自然语言说明 + 草案列表
```

### 6.3 工具路由器

`AiToolRouterService` 不直接执行高风险操作。

它只允许：

```text
read_tasks
read_events
read_activity_summary
read_file_summary
read_reports
create_operation_draft
```

真正写操作交给：

```text
AiDraftExecutorService
```

执行器再调用 C/D/F/G/H/J/L 各模块的受控 API。

---

## 7. K1：LLM 辅助判断实现

### 7.1 活动理解辅助

输入给 LLM：

```text
时间范围
主要应用
脱敏窗口标题
文件夹摘要
任务候选
日程上下文
输入强度
规则模型的初步判断
```

LLM 输出：

```json
{
  "title": "完成数据库课程作业",
  "activityType": "study",
  "matchedTaskId": "...",
  "confidence": 76,
  "reason": "项目路径和任务标题匹配，且截止时间接近"
}
```

FlowPlan 处理：

```text
写入 activity_interpretations
标记 model_used = llm
status = candidate
等待用户确认或修正
```

### 7.2 文件推荐辅助

LLM 可以帮助解释文件和任务关系，但默认只能看文件名、路径摘要和任务摘要。

```text
输入：任务标题、描述、候选文件名、候选路径摘要
输出：推荐排序和理由
```

不默认读取文件正文。

### 7.3 日报和日记辅助

LLM 可以把事实摘要转成自然语言。

```text
输入：已确认实际记录、任务推进、活动摘要、偏离情况
输出：日报草稿、日记草稿、复盘建议
```

必须区分：

```text
确定事实
系统推断
AI 总结
```

### 7.4 排程解释辅助

排程本身由 G 模块规则生成，LLM 只负责把原因说得更自然。

不要让 LLM 自己决定最终排程。

---

## 8. K2：OpenClaw 式受控操作实现

### 8.1 FlowPlan 内部工具定义

工具分为只读工具、草案工具和执行器。

#### 只读工具

```text
get_today_schedule
get_task_summary
get_actual_activity_summary
get_file_recommendations
get_report_summary
get_sync_status
```

#### 草案工具

```text
draft_create_task
draft_update_task
draft_create_event
draft_update_event
draft_create_actual_log
draft_reschedule
draft_link_file
draft_generate_report
draft_restore_file_version
```

#### 执行器

```text
execute_task_draft
execute_event_draft
execute_actual_log_draft
execute_schedule_draft
execute_file_link_draft
execute_report_draft
execute_restore_version_draft
```

LLM 不能直接调用执行器，只能生成 draft。

### 8.2 草案预览

每个草案都必须有用户可读 preview。

创建任务：

```text
将创建任务：数据库实验报告
截止时间：2026-05-01 23:59
预计耗时：3 小时
任务本：课程任务
```

修改任务：

```text
将修改任务：数据库作业
标题：数据库作业 -> 数据库实验报告
预计耗时：2 小时 -> 3 小时
```

恢复文件版本：

```text
将恢复旧版本：report.md
当前版本：2026-04-27 22:30
恢复版本：2026-04-26 19:15
风险：会覆盖当前文件。系统会先保存当前版本。
```

### 8.3 执行前校验

执行草案前必须检查：

```text
草案是否过期
目标对象是否还存在
目标对象版本是否变化
用户是否有权限
是否需要二次确认
是否涉及外部系统写入
是否会删除或覆盖数据
```

### 8.4 执行后审计

审计记录必须包括：

```text
用户原始请求
AI 生成的草案
用户确认时间
执行器
实际写入对象
旧值和新值
执行结果
失败原因
```

---

## 9. Flutter 客户端实现

建议目录：

```text
client_flutter/lib/features/ai/
  data/
    ai_provider_repository.dart
    ai_conversation_repository.dart
    ai_draft_repository.dart
  services/
    ai_api.dart
    ai_context_preview_service.dart
    ai_draft_preview_service.dart
  presentation/
    ai_chat_page.dart
    ai_message_bubble.dart
    ai_draft_card.dart
    ai_draft_detail_page.dart
    ai_confirm_dialog.dart
    ai_tool_settings_page.dart
```

### 9.1 AI 聊天页

显示：

- 用户消息。
- AI 回复。
- 相关草案卡片。
- 上下文来源。
- 敏感数据提示。

### 9.2 草案卡片

必须显示：

```text
操作类型
影响对象
主要字段变化
风险等级
是否需要二次确认
按钮：查看详情 / 确认 / 拒绝
```

### 9.3 AI 权限设置页

允许用户配置：

```text
是否启用 AI
Provider
模型
只读上下文范围
是否允许生成草案
哪些工具启用
哪些工具禁用
是否允许读取文件正文
是否允许读取活动原始数据
```

---

## 10. Web 管理端实现

建议页面：

```text
/admin/ai/providers
/admin/ai/conversations
/admin/ai/drafts
/admin/ai/tool-policies
/admin/ai/audit-logs
```

管理端可以：

- 配置 AI Provider。
- 测试连接。
- 查看会话。
- 查看草案。
- 审核/拒绝/执行草案。
- 查看工具权限。
- 查看审计日志。

管理端不应默认授予比客户端更高的 AI 自主权限。

---

## 11. 同步、离线与冲突

### 11.1 哪些数据同步

| 数据 | 同步策略 |
|---|---|
| AI Provider 配置 | 同步摘要，密钥服务端加密保存 |
| AI 会话 | 可同步 |
| AI 消息 | 可同步，敏感内容按策略处理 |
| 上下文快照 | 同步摘要，不同步高敏感原文 |
| 操作草案 | 必须同步 |
| 草案执行结果 | 必须同步 |
| AI 审计日志 | 必须同步 |
| 工具权限策略 | 必须同步 |

### 11.2 离线规则

| 场景 | 处理 |
|---|---|
| 离线使用云端 LLM | 不可用，提示稍后重试 |
| 离线使用本地模型 | 可用，但只能基于本地数据 |
| 离线生成草案 | 可以，但标记为基于本地上下文 |
| 离线执行草案 | 只允许本地安全操作，写入离线队列 |
| 联网后对象已变化 | 草案过期或进入冲突 |

### 11.3 冲突场景

| 场景 | 处理 |
|---|---|
| AI 草案生成后任务被用户修改 | 草案过期，需重新确认 |
| 两端生成不同草案 | 两个草案并存 |
| 一端确认，一端拒绝同一草案 | 以先确认的执行结果为准，另一端显示已处理 |
| AI 草案涉及已删除对象 | 执行前阻止 |
| AI 草案涉及文件旧版本，但版本缺失 | 执行前阻止 |

---

## 12. 异常与边界情况

必须考虑：

1. AI API Key 错误。
2. AI API 超时。
3. AI API 限流或余额不足。
4. 模型返回非 JSON。
5. 模型幻觉生成不存在的任务 ID。
6. 模型要求越权工具调用。
7. 草案过期。
8. 用户确认时目标对象已变化。
9. AI 输出包含危险建议。
10. Prompt injection 出现在网页、文件、邮件、聊天内容中。
11. 第三方 skill 或工具描述被污染。
12. AI 读取了不该读取的敏感上下文。
13. 用户误确认高风险操作。
14. 执行器执行一半失败。
15. 审计日志写入失败。

处理原则：

- 解析失败不执行。
- 越权工具调用直接阻止。
- 高风险草案必须二次确认。
- 草案执行前重新校验对象版本。
- 审计失败时，高风险执行应中止。
- AI 输出只作为建议，不作为事实。

---

## 13. 安全与隐私

OpenClaw 式 agent 的风险很高，因此 FlowPlan 不能照搬“AI 可以自己做所有事”的模式。

规则：

- 默认关闭高风险工具。
- 默认不允许 shell 命令。
- 默认不允许直接数据库写入。
- 默认不允许读取完整文件内容。
- 默认不把原始键鼠输入发给第三方 AI。
- 默认不把完整聊天内容发给第三方 AI。
- 工具权限必须白名单。
- 第三方 skill 必须审查和签名，首版不支持用户随意安装 skill。
- 外部系统写入必须显示影响范围。
- 所有 AI 写操作必须审计。
- 管理端暴露到公网时必须有真实认证，不能用开发 token。

### 13.1 Prompt Injection 防护

当 AI 读取文件、网页、邮件、聊天内容时，必须把这些内容视为“不可信数据”。

规则：

```text
不可信内容不能覆盖系统指令
不可信内容不能要求调用工具
不可信内容不能要求泄露数据
不可信内容中的命令只作为文本，不作为指令
```

### 13.2 工具调用白名单

每个工具要有：

```text
tool_name
permission_level
input_schema
output_schema
risk_level
requires_confirmation
requires_second_confirmation
allowed_context_types
```

没有注册的工具不能调用。

---

## 14. 验收标准

### `[B] 骨架完成`

满足：

- 有 AI Provider 设置。
- 有 AI 会话和消息。
- 有只读上下文。
- 有操作草案表。
- 有草案审核/确认基础。
- 有审计日志。

### `[M] MVP 可用`

必须实测：

- 配置真实 OpenAI-compatible API。
- 发送自然语言创建任务请求。
- AI 生成任务草案，而不是直接写库。
- 用户能查看草案字段。
- 用户拒绝草案时不写库。
- 用户确认草案后创建任务。
- 审计日志记录完整过程。
- AI 能对一个低置信度活动片段给出解释建议，但不直接写事实。

### `[V] 已验证可用`

必须实测：

- AI 能生成日程草案。
- AI 能生成实际记录候选。
- AI 能生成排程草案并调用 G 模块。
- 草案过期能被检测。
- 高风险操作必须二次确认。
- Prompt injection 测试不会越权调用工具。
- 敏感数据不会默认发给第三方 AI。
- Flutter 客户端和 Web 管理端都能处理草案。

### `[S] 稳定可用`

必须具备：

- 工具 schema 测试。
- 草案执行器测试。
- 权限策略测试。
- Prompt injection 防护测试。
- AI API 失败 fallback。
- 审计完整性测试。
- 长期使用没有静默写错关键数据。

---

## 15. 给 Codex 的提示词：复核当前 AI 助手真实状态

```text
请阅读 docs/00_progress_plan.md ，并复核 K：AI 助手与受控工具调用。

本次任务只做复核，不要开发新功能，不要大范围修改代码。
不要运行 flutter 或 dart 指令。

请检查当前仓库中与 AI 相关的代码，包括但不限于：
- server/src/ai/ai.controller.ts
- server/src/ai/ai.service.ts
- server/src/database/p1_schema.sql 中的 AI Provider、会话、消息、草案和审计相关表
- server/src/admin/admin.service.ts 中的 AI 草案和管理端接口
- client_flutter/lib/core/server_api/ai_api.dart
- web_admin/src/main.tsx 中的 AI API 设置、聊天、草案审核和确认执行入口

请按以下格式输出：

1. 当前涉及的主要文件和目录。
2. 已经存在的能力。
3. 只是骨架、还不能算可用的能力。
4. K1：LLM 辅助判断是否真实接入活动理解、文件推荐、日报或排程解释。
5. K2：OpenClaw 式受控操作是否只生成草案，是否有确认和审计。
6. 是否接入真实 OpenAI-compatible API 验证。
7. 是否有工具权限白名单和高风险二次确认。
8. 是否存在直接写库、直接执行命令或越权风险。
9. 缺失的用户流程。
10. 缺失的异常处理。
11. 缺失的 UI 或管理端入口。
12. 建议当前状态标记：[ ] / [~] / [B] / [M] / [V] / [S]。
13. 如果要推进到下一级状态，需要做哪些最小任务。
14. 用户需要手动验证的步骤。

注意：
- 不要把“有 AI Provider 设置”说成“AI 功能完成”。
- 必须区分 K1 辅助判断和 K2 受控操作。
- AI 写操作必须是 OperationDraft -> 用户确认 -> 执行器执行 -> 审计。
- 如果发现 AI 可以直接执行高风险操作，请明确指出。
```

---

## 16. 给 Codex 的提示词：把 AI 助手从 B 推进到 M

只有完成复核后，才使用这个提示词。

```text
请基于刚才对 K：AI 助手与受控工具调用的复核结果 和 \docs\flowplan_modules\07_K_K_AI_助手与受控工具调用.md，只把该模块从 [B] 骨架完成推进到 [M] MVP 可用。

本次不要做 Telegram 入站，不要做 shell 命令，不要做第三方 skill 市场，不要做文件恢复覆盖，不要做 Outlook/OneDrive 写入。
只完成最小闭环：真实模型调用 + 只读上下文 + 创建任务草案 + 用户确认执行 + 审计，以及一个 LLM 辅助判断示例。

必须完成：

1. 用户能在管理端或客户端配置 OpenAI-compatible Base URL、模型名和 API Key。
2. 用户能测试连接。
3. 用户发送“帮我创建一个明天截止的数据库作业任务”。
4. AI 只能生成 create_task OperationDraft，不能直接写库。
5. 草案页显示任务标题、截止时间、预计耗时、任务本、风险等级。
6. 用户拒绝草案时不写库。
7. 用户确认草案后，由受控执行器创建任务。
8. 创建任务后进入同步队列或服务端事实库。
9. 审计日志记录用户请求、AI 草案、用户确认、执行结果。
10. 选择一个 F 模块的低置信度活动片段，LLM 只生成解释建议，不直接确认实际记录。
11. 高风险工具默认禁用。
12. 明确禁止 shell 命令和直接数据库写入。

输出必须包含：
- 修改文件列表。
- 每个文件改了什么。
- AI 工具权限边界。
- OperationDraft 的 schema。
- 草案确认流程。
- 审计记录内容。
- 用户需要手动配置 API Key 的步骤。
- 用户需要手动做的事情



---
