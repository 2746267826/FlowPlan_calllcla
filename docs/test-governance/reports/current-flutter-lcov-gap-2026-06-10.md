# 当前 Flutter LCOV gap 摘要

更新时间：2026-06-10 19:46:08 +08:00
仓库：`C:\Users\a2746\Desktop\calll260426`

## 口径

- 最新 full Flutter coverage 已通过：`client_flutter/build/codex_logs/flutter-coverage-20260610-192417.out.log` 尾部为 `07:30 +857: All tests passed!`。
- 本文未重跑 full coverage，仅基于 `client_flutter/coverage/lcov.info` 做短命令复算。
- 复算口径对齐 `scripts/test-flowplanv2.ps1` 的 `Get-DartLcovSummary` / `Assert-DartLcovCoverage`：`SF:` 先经 `ConvertTo-RepoRelativePath` 转 repo-relative path；优先按 `DA:` line hits 统计；只排除 `docs/test-governance/coverage-exclusions.csv` 中 `owner_or_module=client_flutter` 且 `status=reviewed` 的匹配记录。
- 当前门禁真实口径：91.66% = 27731/30255，missed 2524；excluded 4 records/3582 lines。
- `client_flutter/**.g.dart` 和 `client_flutter/lib/core/database/app_database.g.dart` 已按 reviewed exclusions 排除；生成 `.g.dart` 不应进入下一轮 included gap 分派。

## Top Included Gaps

| Rank | File | Total | Covered | Missed |
| ---: | --- | ---: | ---: | ---: |
| 1 | `client_flutter/lib/web_app/flowplanv2_web_app.dart` | 2002 | 1836 | 166 |
| 2 | `client_flutter/lib/features/sync/outlook_settings_page_body.dart` | 1001 | 909 | 92 |
| 3 | `client_flutter/lib/features/tracker/presentation/tracker_page.dart` | 466 | 378 | 88 |
| 4 | `client_flutter/lib/features/sync/sync_engine.dart` | 263 | 193 | 70 |
| 5 | `client_flutter/lib/features/tracker/services/tracker_service.dart` | 312 | 249 | 63 |
| 6 | `client_flutter/lib/features/settings/presentation/settings_widgets.dart` | 222 | 161 | 61 |
| 7 | `client_flutter/lib/core/database/app_database.dart` | 248 | 191 | 57 |
| 8 | `client_flutter/lib/features/tracker/presentation/input_heatmap_page.dart` | 640 | 585 | 55 |
| 9 | `client_flutter/lib/features/sync/outlook_auth_service.dart` | 336 | 282 | 54 |
| 10 | `client_flutter/lib/features/ical/ical_import_export_page_body.dart` | 744 | 690 | 54 |
| 11 | `client_flutter/lib/features/tracker/presentation/tracker_input_history_page.dart` | 364 | 310 | 54 |
| 12 | `client_flutter/lib/features/tracker/data/activity_record_repository.dart` | 129 | 76 | 53 |
| 13 | `client_flutter/lib/features/files/data/file_context_repository.dart` | 970 | 923 | 47 |
| 14 | `client_flutter/lib/features/task/data/task_repository.dart` | 222 | 176 | 46 |
| 15 | `client_flutter/lib/features/calendar/presentation/calendar_books_page.dart` | 290 | 245 | 45 |
| 16 | `client_flutter/lib/features/tracker/presentation/tracker_page_panels.dart` | 204 | 162 | 42 |
| 17 | `client_flutter/lib/features/sync/server_sync_status_page.dart` | 364 | 324 | 40 |
| 18 | `client_flutter/lib/features/tracker/presentation/tracker_history_filter_panel.dart` | 171 | 131 | 40 |
| 19 | `client_flutter/lib/features/sync/outlook_task_mirror_sync_service.dart` | 538 | 499 | 39 |
| 20 | `client_flutter/lib/shared/providers/app_providers.dart` | 534 | 498 | 36 |
| 21 | `client_flutter/lib/features/tracker/services/input_activity_event_service.dart` | 533 | 499 | 34 |
| 22 | `client_flutter/lib/features/tracker/presentation/activity_review_page.dart` | 364 | 331 | 33 |
| 23 | `client_flutter/lib/features/files/presentation/file_context_page.dart` | 710 | 678 | 32 |
| 24 | `client_flutter/lib/features/tracker/data/activity_fusion_repository.dart` | 371 | 340 | 31 |
| 25 | `client_flutter/lib/features/sync/outlook_settings_widgets.dart` | 201 | 171 | 30 |
| 26 | `client_flutter/lib/features/reminders/reminder_service.dart` | 509 | 480 | 29 |
| 27 | `client_flutter/lib/features/tracker/presentation/tracker_page_helpers.dart` | 366 | 337 | 29 |
| 28 | `client_flutter/lib/features/scheduler/scheduler_engine.dart` | 472 | 445 | 27 |
| 29 | `client_flutter/lib/features/calendar/presentation/event_detail_page.dart` | 348 | 323 | 25 |
| 30 | `client_flutter/lib/core/database/tables/task_items_table.dart` | 25 | 0 | 25 |
| 31 | `client_flutter/lib/core/server_first/tracking_server_first_store.dart` | 27 | 3 | 24 |
| 32 | `client_flutter/lib/features/settings/presentation/settings_page.dart` | 122 | 98 | 24 |
| 33 | `client_flutter/lib/features/tracker/models/work_session.dart` | 252 | 228 | 24 |
| 34 | `client_flutter/lib/core/server_api/tracking_ingest_api.dart` | 31 | 7 | 24 |
| 35 | `client_flutter/lib/features/files/services/file_transfer_service.dart` | 423 | 399 | 24 |
| 36 | `client_flutter/lib/features/tracker/services/android_usage_import_service.dart` | 160 | 137 | 23 |
| 37 | `client_flutter/lib/core/server_api/models_api.dart` | 25 | 2 | 23 |
| 38 | `client_flutter/lib/core/sync/server_sync_change_applier.dart` | 785 | 763 | 22 |
| 39 | `client_flutter/lib/features/sync/sync_status_badge.dart` | 60 | 38 | 22 |
| 40 | `client_flutter/lib/features/task/presentation/unscheduled_task_panel.dart` | 131 | 110 | 21 |

## 下一轮 Worker 分配建议

| Worker lane | 领域 | 建议范围 | 目标 |
| --- | --- | --- | --- |
| Flutter UI shell | Web app / settings / app providers | `flowplanv2_web_app.dart`、`settings_widgets.dart`、`settings_page.dart`、`app_providers.dart` | 覆盖主 shell、设置区状态、provider 分支、空/错误/权限状态。 |
| Sync & Outlook | Outlook auth/settings/task mirror/server sync | `outlook_settings_page_body.dart`、`sync_engine.dart`、`outlook_auth_service.dart`、`server_sync_status_page.dart`、`outlook_task_mirror_sync_service.dart`、`outlook_settings_widgets.dart`、`sync_status_badge.dart` | 覆盖 OAuth 失败/取消/刷新、mirror 冲突、server sync 状态、重试与禁用状态。 |
| Tracker UI | Tracker pages and panels | `tracker_page.dart`、`input_heatmap_page.dart`、`tracker_input_history_page.dart`、`tracker_page_panels.dart`、`tracker_history_filter_panel.dart`、`activity_review_page.dart`、`tracker_page_helpers.dart` | 覆盖筛选、日期范围、空状态、错误状态、面板切换、用户操作流。 |
| Tracker services/data | Tracker service/repository/model/API | `tracker_service.dart`、`activity_record_repository.dart`、`input_activity_event_service.dart`、`activity_fusion_repository.dart`、`work_session.dart`、`tracking_ingest_api.dart`、`android_usage_import_service.dart` | 覆盖数据合并、导入、上传、边界时间、异常、空记录、平台能力缺失。 |
| Database & server-first | Hand-written database tables and sync stores | `app_database.dart`、`task_items_table.dart`、`tracking_server_first_store.dart`、`models_api.dart`、`server_sync_change_applier.dart` | 覆盖手写 schema helpers、表定义访问、server-first 分支、change applier 冲突/跳过路径。 |
| Files / iCal / Calendar / Task | File, iCal, calendar and task flows | `ical_import_export_page_body.dart`、`file_context_repository.dart`、`task_repository.dart`、`calendar_books_page.dart`、`file_context_page.dart`、`file_transfer_service.dart`、`scheduler_engine.dart`、`event_detail_page.dart`、`unscheduled_task_panel.dart` | 覆盖导入导出、文件上下文、传输失败、日历详情、未排程任务、scheduler 边界。 |
| Reminders | Reminder service | `reminder_service.dart` | 覆盖权限、取消、重复计划、平台失败和无通知能力分支。 |

## 当前状态结论

Flutter full coverage 测试命令已通过，但 LCOV 仍未达到 root gate 的 100% threshold。server/web_admin 仍只能引用先前 100% 记录，最终交付前需要 fresh gate。整体测试治理任务当前仍未完成。
