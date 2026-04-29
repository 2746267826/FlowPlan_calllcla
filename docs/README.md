# FlowPlan 文档入口

你要看的计划文件只看这一份：

- [FlowPlan 用户版完整开发计划](FlowPlan_用户版完整开发计划_260426.md)

其他文件是给开发执行、架构追溯和 Codex 内部参考用的，不需要日常阅读。

## 内部参考

- `planning/`：拆分版计划、近期清单和历史来源映射。
- `architecture/`：P0 架构、完成报告和 P1 交接契约。
- `architecture/p3_client_modularization_report_260427.md`：P3 客户端模块化拆分完成报告。
- `archive/legacy-root-plans/`：从仓库根目录归档进来的历史计划来源文件。
- `update.txt`：日常开发更新记录。
- `development_constraints_260426.md`：开发约束，尤其是禁止 Codex 运行 `flutter` / `dart` 指令。

## 当前仓库结构

- `../client_flutter/`：Flutter Windows / Android 主客户端。
- `../server/`：服务端。
- `../web_admin/`：Web 管理端。
- `../docs/`：计划、架构和更新记录。
