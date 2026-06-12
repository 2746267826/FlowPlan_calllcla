import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/ical_import_export_harness.dart';

void main() {
  testWidgets('iCal actions are disabled when no local calendar is available', (
    tester,
  ) async {
    await ICalImportExportHarness.pump(tester);

    expect(find.text('当前没有可用的本地日历本。请先在日历本管理中创建一个本地日历本。'), findsOneWidget);
    expect(_elevatedButtonEnabled(tester, '选择文件'), isFalse);
    expect(_elevatedButtonEnabled(tester, '导出当前日历本'), isFalse);
    expect(_elevatedButtonEnabled(tester, '导出结构化归档'), isFalse);
  });

  testWidgets('iCal export writes selected and merged local calendar scopes', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final workCalendarId = await harness.createCalendar(
      name: 'Work',
      colorHex: '#123456',
      isDefault: true,
    );
    final personalCalendarId = await harness.createCalendar(
      name: 'Personal',
      colorHex: '#654321',
    );
    final outlookCalendarId = await harness.createCalendar(
      name: 'Outlook read only',
      source: 'outlook',
      syncUrl: 'remote-calendar',
    );
    await harness.createEvent(
      calendarId: workCalendarId,
      uid: 'work-export',
      summary: 'Work export event',
    );
    await harness.createEvent(
      calendarId: personalCalendarId,
      uid: 'personal-export',
      summary: 'Personal export event',
    );
    await harness.createEvent(
      calendarId: outlookCalendarId,
      uid: 'remote-export',
      summary: 'Remote should not export',
    );
    await pumpIcalFrames(tester);

    expect(find.text('Work'), findsWidgets);
    expect(find.text('Personal'), findsWidgets);
    expect(find.text('Outlook read only'), findsNothing);
    expect(_elevatedButtonEnabled(tester, '导出当前日历本'), isTrue);

    final selectedOutput = harness.tempFile('selected.ics');
    harness.filePicker.queueSavePath(selectedOutput.path);
    await _tapChoiceChip(tester, 'Personal');
    await _tapIcalButtonWithRealAsync(tester, '导出当前日历本');
    await pumpIcalFrames(tester);

    expect(harness.filePicker.saveRequests.last.allowedExtensions, ['ics']);
    expect(
      harness.filePicker.saveRequests.last.fileName,
      'Personal_flowplanv2_export.ics',
    );
    final selectedContent = await _waitForFileContaining(
      tester,
      selectedOutput,
      'X-WR-CALNAME:FlowPlanV2 - Personal',
    );
    expect(selectedContent, contains('SUMMARY:Personal export event'));
    expect(selectedContent, isNot(contains('SUMMARY:Work export event')));
    expect(selectedContent, isNot(contains('Remote should not export')));
    expect(
      find.textContaining('成功从「Personal」导出 1 条日程到 ${selectedOutput.path}'),
      findsOneWidget,
    );

    final mergedOutput = harness.tempFile('merged.ics');
    harness.filePicker.queueSavePath(mergedOutput.path);
    await _tapChoiceChip(tester, '全部本地日历本');
    await _tapIcalButtonWithRealAsync(tester, '合并导出全部本地日历本');
    await pumpIcalFrames(tester);

    final mergedContent = await _waitForFileContaining(
      tester,
      mergedOutput,
      'X-WR-CALNAME:FlowPlanV2 - 全部本地日历本',
    );
    expect(mergedContent, contains('SUMMARY:Work export event'));
    expect(mergedContent, contains('SUMMARY:Personal export event'));
    expect(mergedContent, isNot(contains('Remote should not export')));
    expect(
      find.textContaining('成功合并导出 2 个本地日历本中的 2 条日程到 ${mergedOutput.path}'),
      findsOneWidget,
    );

    harness.filePicker.queueSavePath(null);
    await _tapIcalButtonWithRealAsync(tester, '合并导出全部本地日历本');
    await pumpIcalFrames(tester);

    expect(find.text('未选择保存位置'), findsOneWidget);
  });

  testWidgets('iCal smart merge updates matching uid and skips duplicates', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      colorHex: '#ABCDEF',
      isDefault: true,
    );
    await harness.setCalendarDefaultIsBlock(
      calendarId: calendarId,
      value: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'same-uid',
      summary: 'Original summary',
      start: DateTime(2026, 6, 9, 9),
      end: DateTime(2026, 6, 9, 10),
      isBlock: false,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'duplicate-existing',
      summary: 'Signature Duplicate',
      start: DateTime(2026, 6, 9, 11),
      end: DateTime(2026, 6, 9, 12),
    );
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickText(
      name: 'smart.ics',
      content: _ics([
        _vevent(
          uid: 'same-uid',
          summary: 'Updated by smart merge',
          start: '20260609T090000',
          end: '20260609T100000',
        ),
        _vevent(
          uid: 'smart-new',
          summary: 'Created by smart merge',
          start: '20260610T090000',
          end: '20260610T100000',
        ),
        _vevent(
          uid: 'duplicate-new-uid',
          summary: 'Signature Duplicate',
          start: '20260609T110000',
          end: '20260609T120000',
        ),
      ]),
    );

    await tapIcalButtonText(tester, '选择文件');
    await pumpIcalFrames(tester);

    final events = await harness.eventsInCalendar(calendarId);
    expect(events, hasLength(3));
    final updated = events.singleWhere((event) => event.uid == 'same-uid');
    expect(updated.summary, 'Updated by smart merge');
    expect(updated.colorHex, '#ABCDEF');
    expect(updated.isBlock, isTrue);
    expect(
      events.singleWhere((event) => event.uid == 'smart-new').summary,
      'Created by smart merge',
    );
    expect(
      events.where((event) => event.summary == 'Signature Duplicate'),
      hasLength(1),
    );
    expect(
      find.textContaining('新建 1 条，更新 1 条，跳过 1 条重复日程'),
      findsOneWidget,
    );
  });

  testWidgets('iCal append only creates new events without modifying matches', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'same-uid',
      summary: 'Keep this summary',
      start: DateTime(2026, 6, 9, 9),
      end: DateTime(2026, 6, 9, 10),
    );
    await pumpIcalFrames(tester);

    await _tapChoiceChip(tester, '仅追加');
    harness.filePicker.queuePickText(
      name: 'append.ics',
      content: _ics([
        _vevent(
          uid: 'same-uid',
          summary: 'Should be skipped',
          start: '20260609T090000',
          end: '20260609T100000',
        ),
        _vevent(
          uid: 'append-new',
          summary: 'Append new event',
          start: '20260611T090000',
          end: '20260611T100000',
        ),
      ]),
    );

    await tapIcalButtonText(tester, '选择文件');
    await pumpIcalFrames(tester);

    final events = await harness.eventsInCalendar(calendarId);
    expect(events, hasLength(2));
    expect(
      events.singleWhere((event) => event.uid == 'same-uid').summary,
      'Keep this summary',
    );
    expect(
      events.singleWhere((event) => event.uid == 'append-new').summary,
      'Append new event',
    );
    expect(
      find.textContaining('新增 1 条，跳过 1 条已存在的日程'),
      findsOneWidget,
    );
  });

  testWidgets('iCal replace mode confirms before clearing a calendar', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'old-1',
      summary: 'Old one',
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'old-2',
      summary: 'Old two',
      start: DateTime(2026, 6, 9, 11),
      end: DateTime(2026, 6, 9, 12),
    );
    await pumpIcalFrames(tester);

    await _tapChoiceChip(tester, '清空后导入');
    harness.filePicker.queuePickText(
      name: 'replace.ics',
      content: _ics([
        _vevent(
          uid: 'new-after-cancel',
          summary: 'New after cancel',
          start: '20260612T090000',
          end: '20260612T100000',
        ),
      ]),
    );
    await tapIcalButtonText(tester, '选择文件');
    await pumpUntilIcalFound(tester, find.byType(AlertDialog));
    expect(find.text('确认清空后导入'), findsOneWidget);
    await _tapDialogButton(tester, '取消');
    await pumpIcalFrames(tester);

    var events = await harness.eventsInCalendar(calendarId);
    expect(events.map((event) => event.uid), containsAll(['old-1', 'old-2']));
    expect(
      find.textContaining('已取消对「Work」的清空后导入'),
      findsOneWidget,
    );

    harness.filePicker.queuePickText(
      name: 'replace.ics',
      content: _ics([
        _vevent(
          uid: 'replacement',
          summary: 'Replacement event',
          start: '20260612T090000',
          end: '20260612T100000',
        ),
      ]),
    );
    await tapIcalButtonText(tester, '选择文件');
    await pumpUntilIcalFound(tester, find.byType(AlertDialog));
    await _tapDialogButton(tester, '继续');
    await pumpIcalFrames(tester);

    events = await harness.eventsInCalendar(calendarId);
    expect(events, hasLength(1));
    expect(events.single.uid, 'replacement');
    expect(events.single.summary, 'Replacement event');
    expect(
      find.textContaining('已先清空「Work」中的 2 条原有日程，再导入 1 条新日程'),
      findsOneWidget,
    );
  });

  testWidgets('iCal import reports cancel unreadable and empty file states', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Work', isDefault: true);
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickCancel();
    await tapIcalButtonText(tester, '选择文件');
    await pumpIcalFrames(tester);
    expect(find.text('未选择文件'), findsOneWidget);

    harness.filePicker.queueUnreadableFile();
    await tapIcalButtonText(tester, '选择文件');
    await pumpIcalFrames(tester);
    expect(find.text('无法读取文件内容'), findsOneWidget);

    harness.filePicker.queuePickText(name: 'empty.ics', content: '');
    await tapIcalButtonText(tester, '选择文件');
    await pumpIcalFrames(tester);
    expect(find.text('文件中未找到有效日程 (VEVENT)'), findsOneWidget);

    harness.filePicker.queuePickText(
      name: 'bad.ics',
      content: _ics([
        '''
BEGIN:VEVENT
UID:bad-date
SUMMARY:Bad date
DTSTART:not-a-date
END:VEVENT
''',
      ]),
    );
    await tapIcalButtonText(tester, '选择文件');
    await pumpIcalFrames(tester);
    expect(find.text('文件中未找到有效日程 (VEVENT)'), findsOneWidget);
  });

  testWidgets('structured archive export writes only selected containers', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final workCalendarId = await harness.createCalendar(
      name: 'Work',
      colorHex: '#112233',
      isDefault: true,
    );
    final personalCalendarId = await harness.createCalendar(
      name: 'Personal',
      colorHex: '#445566',
    );
    await harness.setCalendarDefaultIsBlock(
      calendarId: workCalendarId,
      value: true,
    );
    await harness.createEvent(
      calendarId: workCalendarId,
      uid: 'work-archive-event',
      summary: 'Work archive event',
      isBlock: true,
    );
    await harness.createEvent(
      calendarId: personalCalendarId,
      uid: 'personal-archive-event',
      summary: 'Personal archive event',
    );
    final inboxTaskListId = await harness.createTaskList(
      name: 'Inbox',
      isDefault: true,
    );
    final somedayTaskListId = await harness.createTaskList(name: 'Someday');
    await harness.books.saveTaskListDefaults(
      id: inboxTaskListId,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 45,
      audit: false,
    );
    await harness.createTask(
      taskListId: inboxTaskListId,
      uid: 'inbox-archive-task',
      summary: 'Inbox archive task',
    );
    await harness.createTask(
      taskListId: somedayTaskListId,
      uid: 'someday-archive-task',
      summary: 'Someday archive task',
    );
    await pumpIcalFrames(tester);

    expect(find.text('已选择 2 个日历本、2 个任务本。'), findsOneWidget);
    await _tapFilterChip(tester, 'Personal');
    await _tapFilterChip(tester, 'Someday');
    await pumpIcalFrames(tester);
    expect(find.text('已选择 1 个日历本、1 个任务本。'), findsOneWidget);

    final output = harness.tempFile('selected-containers.flowplanv2.json');
    harness.filePicker.queueSavePath(output.path);
    await _tapIcalButtonWithRealAsync(tester, '导出结构化归档');
    await pumpIcalFrames(tester);

    expect(harness.filePicker.saveRequests.last.allowedExtensions, ['json']);
    expect(
      harness.filePicker.saveRequests.last.fileName,
      allOf(
        startsWith('flowplanv2-containers-'),
        endsWith('.flowplanv2.json'),
      ),
    );

    final content = await _waitForFileContaining(
      tester,
      output,
      '"schema": "flowplanv2.container_archive.v1"',
    );
    final json = jsonDecode(content) as Map<String, dynamic>;
    final calendars = json['calendars'] as List<dynamic>;
    final taskLists = json['task_lists'] as List<dynamic>;

    expect(calendars, hasLength(1));
    expect(calendars.single, containsPair('name', 'Work'));
    expect(calendars.single, containsPair('default_is_block', true));
    expect(
      calendars.single,
      containsPair(
        'events',
        [
          containsPair('summary', 'Work archive event'),
        ],
      ),
    );
    expect(content, isNot(contains('Personal archive event')));

    expect(taskLists, hasLength(1));
    expect(taskLists.single, containsPair('name', 'Inbox'));
    expect(
      taskLists.single,
      containsPair('default_is_auto_scheduled', false),
    );
    expect(
      taskLists.single,
      containsPair('default_reminder_minutes_before', 45),
    );
    expect(
      taskLists.single,
      containsPair(
        'tasks',
        [
          containsPair('summary', 'Inbox archive task'),
        ],
      ),
    );
    expect(content, isNot(contains('Someday archive task')));
    expect(
      find.textContaining('已导出结构化归档到 ${output.path}，包含 1 个日历本、1 个任务本'),
      findsOneWidget,
    );
  });

  testWidgets('structured archive export includes archived task lists', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createTaskList(
      name: 'Archived backlog',
      colorHex: '#778899',
      isArchived: true,
    );
    await pumpIcalFrames(tester);

    expect(find.text('Archived backlog'), findsOneWidget);
    expect(find.text('已选择 0 个日历本、1 个任务本。'), findsOneWidget);
    expect(_elevatedButtonEnabled(tester, '导出结构化归档'), isTrue);

    final output = harness.tempFile('archived-task-list.flowplanv2.json');
    harness.filePicker.queueSavePath(output.path);
    await _tapIcalButtonWithRealAsync(tester, '导出结构化归档');
    await pumpIcalFrames(tester);

    final content = await _waitForFileContaining(
      tester,
      output,
      '"name": "Archived backlog"',
    );
    final json = jsonDecode(content) as Map<String, dynamic>;
    expect(json['calendars'], isEmpty);
    expect(
      json['task_lists'],
      [
        containsPair('is_archived', true),
      ],
    );
  });

  testWidgets(
      'structured archive selection controls gate export and cancel save', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Work', isDefault: true);
    await harness.createCalendar(name: 'Personal');
    await harness.createTaskList(name: 'Inbox', isDefault: true);
    await harness.createTaskList(name: 'Someday');
    await pumpIcalFrames(tester);

    expect(find.text('已选择 2 个日历本、2 个任务本。'), findsOneWidget);

    await _tapSelectorTextButton(tester, '选择日历本', '清空');
    await pumpIcalFrames(tester);
    expect(find.text('已选择 0 个日历本、2 个任务本。'), findsOneWidget);
    expect(_elevatedButtonEnabled(tester, '导出结构化归档'), isTrue);

    await _tapSelectorTextButton(tester, '选择任务本', '清空');
    await pumpIcalFrames(tester);
    expect(find.text('请至少选择一个日历本或任务本。'), findsOneWidget);
    expect(_elevatedButtonEnabled(tester, '导出结构化归档'), isFalse);

    await _tapSelectorTextButton(tester, '选择日历本', '全选');
    await _tapSelectorTextButton(tester, '选择任务本', '全选');
    await pumpIcalFrames(tester);
    expect(find.text('已选择 2 个日历本、2 个任务本。'), findsOneWidget);

    harness.filePicker.queueSavePath(null);
    await _tapIcalButtonWithRealAsync(tester, '导出结构化归档');
    await pumpIcalFrames(tester);

    expect(find.text('已取消导出结构化归档。'), findsOneWidget);
    expect(harness.filePicker.saveRequests.last.allowedExtensions, ['json']);
  });

  testWidgets(
      'structured archive import reports cancel unreadable invalid and mode cancel states',
      (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);

    harness.filePicker.queuePickCancel();
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpIcalFrames(tester);
    expect(find.text('未选择结构化归档文件。'), findsOneWidget);

    harness.filePicker.queueUnreadableFile(name: 'unreadable.flowplanv2.json');
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpIcalFrames(tester);
    expect(find.text('无法读取结构化归档文件内容。'), findsOneWidget);

    harness.filePicker.queuePickText(
      name: 'invalid.flowplanv2.json',
      content: '{"schema":"not-flowplan"}',
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpIcalFrames(tester);
    expect(find.textContaining('导入结构化归档失败'), findsOneWidget);

    harness.filePicker.queuePickText(
      name: 'containers.flowplanv2.json',
      content: _archiveJson(),
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogButtonWithRealAsync(tester, '取消');
    await pumpIcalFrames(tester);

    expect(find.text('已取消结构化归档导入。'), findsOneWidget);
    expect(await harness.books.getEventCalendarsBySource('local'), isEmpty);
    expect(await harness.books.getAllTaskLists(), isEmpty);
  });

  testWidgets('structured archive append mode skips existing items', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'archive-event-1',
      summary: 'Keep old archive event',
    );
    final taskListId = await harness.createTaskList(
      name: 'Inbox',
      isDefault: true,
    );
    await harness.createTask(
      taskListId: taskListId,
      uid: 'archive-task-1',
      summary: 'Keep old archive task',
    );
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickText(
      name: 'containers.flowplanv2.json',
      content: _archiveJson(),
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogRadio(tester, '仅追加');
    await _tapDialogButtonWithRealAsync(tester, '查看导入预览');
    await pumpUntilIcalFound(tester, find.text('确认结构化导入预览'));

    expect(find.text('导入策略：仅追加'), findsOneWidget);
    expect(
      find.text('将新建 0 个容器，合并 2 个同名容器；新增 2 项，更新 0 项，跳过 2 项。'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('新增 1，更新 0，跳过 1'),
      ),
      findsNWidgets(2),
    );

    await _tapDialogButtonWithRealAsync(tester, '生成备份并导入');
    await pumpUntilIcalFound(tester, find.textContaining('结构化归档导入完成'));

    final events = await harness.eventsInCalendar(calendarId);
    expect(events, hasLength(2));
    expect(
      events.singleWhere((event) => event.uid == 'archive-event-1').summary,
      'Keep old archive event',
    );
    expect(
      events.singleWhere((event) => event.uid == 'archive-event-2').summary,
      'New archive event',
    );

    final tasks = await harness.tasksInTaskList(taskListId);
    expect(tasks, hasLength(2));
    expect(
      tasks.singleWhere((task) => task.uid == 'archive-task-1').summary,
      'Keep old archive task',
    );
    expect(
      tasks.singleWhere((task) => task.uid == 'archive-task-2').summary,
      'New archive task',
    );
    expect(
      find.textContaining('日程新增 1 条、更新 0 条、跳过 1 条、移除 0 条'),
      findsOneWidget,
    );
    expect(
      find.textContaining('任务新增 1 条、更新 0 条、跳过 1 条、移除 0 条'),
      findsOneWidget,
    );
  });

  testWidgets('structured archive import previews counts before writing', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'archive-event-1',
      summary: 'Old archive event',
    );
    final taskListId = await harness.createTaskList(
      name: 'Inbox',
      isDefault: true,
    );
    await harness.createTask(
      taskListId: taskListId,
      uid: 'archive-task-1',
      summary: 'Old archive task',
    );
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickText(
      name: 'containers.flowplanv2.json',
      content: _archiveJson(),
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogButtonWithRealAsync(tester, '查看导入预览');
    await pumpUntilIcalFound(tester, find.text('确认结构化导入预览'));

    expect(find.text('导入策略：智能合并'), findsOneWidget);
    expect(
      find.text('将新建 0 个容器，合并 2 个同名容器；新增 2 项，更新 2 项，跳过 0 项。'),
      findsOneWidget,
    );
    final previewDialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: previewDialog,
        matching: find.text('日历本：Work'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: previewDialog,
        matching: find.text('任务本：Inbox'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: previewDialog,
        matching: find.textContaining('新增 1，更新 1，跳过 0'),
      ),
      findsNWidgets(2),
    );

    await _tapDialogButtonWithRealAsync(tester, '生成备份并导入');
    await pumpUntilIcalFound(tester, find.textContaining('结构化归档导入完成'));

    final events = await harness.eventsInCalendar(calendarId);
    expect(events, hasLength(2));
    expect(
      events.singleWhere((event) => event.uid == 'archive-event-1').summary,
      'Updated archive event',
    );
    expect(
      events.singleWhere((event) => event.uid == 'archive-event-2').summary,
      'New archive event',
    );

    final tasks = await harness.tasksInTaskList(taskListId);
    expect(tasks, hasLength(2));
    expect(
      tasks.singleWhere((task) => task.uid == 'archive-task-1').summary,
      'Updated archive task',
    );
    expect(
      tasks.singleWhere((task) => task.uid == 'archive-task-2').summary,
      'New archive task',
    );
    expect(find.textContaining('结构化归档导入完成'), findsOneWidget);
    expect(find.textContaining('导入前数据库回滚备份'), findsOneWidget);
  });

  testWidgets(
      'structured archive replace mode previews cancel and removes old items', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    final calendarId = await harness.createCalendar(
      name: 'Work',
      isDefault: true,
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'archive-event-1',
      summary: 'Old archive event',
    );
    await harness.createEvent(
      calendarId: calendarId,
      uid: 'remove-event',
      summary: 'Remove this event',
      start: DateTime(2026, 6, 9, 13),
      end: DateTime(2026, 6, 9, 14),
    );
    final taskListId = await harness.createTaskList(
      name: 'Inbox',
      isDefault: true,
    );
    await harness.createTask(
      taskListId: taskListId,
      uid: 'archive-task-1',
      summary: 'Old archive task',
    );
    await harness.createTask(
      taskListId: taskListId,
      uid: 'remove-task',
      summary: 'Remove this task',
    );
    await pumpIcalFrames(tester);

    harness.filePicker.queuePickText(
      name: 'replace.flowplanv2.json',
      content: _archiveJson(),
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogRadio(tester, '替换同名容器内容');
    await _tapDialogButtonWithRealAsync(tester, '查看导入预览');
    await pumpUntilIcalFound(tester, find.text('确认结构化导入预览'));

    expect(find.text('导入策略：替换同名容器内容'), findsOneWidget);
    expect(
      find.text('将新建 0 个容器，合并 2 个同名容器；新增 4 项，更新 0 项，跳过 0 项。'),
      findsOneWidget,
    );
    expect(
      find.text('替换导入会先移除 4 个同名容器内的旧项目。导入前会自动生成数据库回滚备份。'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('导入前移除 2'),
      ),
      findsNWidgets(2),
    );

    await _tapDialogButtonWithRealAsync(tester, '取消');
    await pumpIcalFrames(tester);

    var events = await harness.eventsInCalendar(calendarId);
    expect(
        events.map((event) => event.uid),
        containsAll([
          'archive-event-1',
          'remove-event',
        ]));
    var tasks = await harness.tasksInTaskList(taskListId);
    expect(
        tasks.map((task) => task.uid),
        containsAll([
          'archive-task-1',
          'remove-task',
        ]));
    expect(find.text('已取消结构化归档导入。'), findsOneWidget);

    harness.filePicker.queuePickText(
      name: 'replace.flowplanv2.json',
      content: _archiveJson(),
    );
    await _tapIcalButtonWithRealAsync(tester, '导入结构化归档');
    await pumpUntilIcalFound(tester, find.text('选择结构化导入策略'));
    await _tapDialogRadio(tester, '替换同名容器内容');
    await _tapDialogButtonWithRealAsync(tester, '查看导入预览');
    await pumpUntilIcalFound(tester, find.text('确认结构化导入预览'));
    await _tapDialogButtonWithRealAsync(tester, '生成备份并导入');
    await pumpUntilIcalFound(tester, find.textContaining('结构化归档导入完成'));

    events = await harness.eventsInCalendar(calendarId);
    expect(events.map((event) => event.uid), [
      'archive-event-1',
      'archive-event-2',
    ]);
    expect(
      events.singleWhere((event) => event.uid == 'archive-event-1').summary,
      'Updated archive event',
    );
    tasks = await harness.tasksInTaskList(taskListId);
    expect(tasks.map((task) => task.uid), [
      'archive-task-1',
      'archive-task-2',
    ]);
    expect(
      tasks.singleWhere((task) => task.uid == 'archive-task-1').summary,
      'Updated archive task',
    );
    expect(
      find.textContaining('日程新增 2 条、更新 0 条、跳过 0 条、移除 2 条'),
      findsOneWidget,
    );
    expect(
      find.textContaining('任务新增 2 条、更新 0 条、跳过 0 条、移除 2 条'),
      findsOneWidget,
    );
  });

  testWidgets('database export writes backup and reports canceled save', (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);
    await harness.createCalendar(name: 'Work', isDefault: true);
    await pumpIcalFrames(tester);

    harness.filePicker.queueSavePath(null);
    await _tapIcalButtonWithRealAsync(tester, '导出数据库');
    await pumpIcalFrames(tester);

    expect(find.text('已取消导出数据库'), findsOneWidget);
    expect(
      harness.filePicker.saveRequests.last.allowedExtensions,
      ['db', 'sqlite', 'sqlite3'],
    );
    expect(
      harness.filePicker.saveRequests.last.fileName,
      allOf(startsWith('flowplanv2-'), endsWith('.db')),
    );

    final output = harness.tempFile('full-backup.db');
    harness.filePicker.queueSavePath(output.path);
    await _tapIcalButtonWithRealAsync(tester, '导出数据库');
    await pumpIcalFrames(tester);

    await _waitForFileHeader(tester, output, ascii.encode('SQLite format 3'));
    expect(find.text('完整数据库已导出到 ${output.path}'), findsOneWidget);
  });

  testWidgets('database restore handles cancel invalid stage and clear pending',
      (
    tester,
  ) async {
    final harness = await ICalImportExportHarness.pump(tester);

    harness.filePicker.queuePickCancel();
    await _tapIcalButtonWithRealAsync(tester, '选择副本');
    await pumpIcalFrames(tester);
    expect(find.text('已取消选择恢复副本'), findsOneWidget);
    expect(
      harness.filePicker.pickRequests.last.allowedExtensions,
      ['db', 'sqlite', 'sqlite3'],
    );

    harness.filePicker.queueUnreadableFile(name: 'missing-path.db');
    await _tapIcalButtonWithRealAsync(tester, '选择副本');
    await pumpIcalFrames(tester);
    expect(find.text('无法读取所选恢复副本路径'), findsOneWidget);

    final invalidBackup = harness.tempFile('invalid-backup.db')
      ..writeAsStringSync('not sqlite');
    harness.filePicker.queuePickPath(invalidBackup);
    await _tapIcalButtonWithRealAsync(tester, '选择副本');
    await pumpIcalFrames(tester);
    expect(find.textContaining('准备恢复副本失败'), findsOneWidget);
    expect(find.textContaining('不是有效的 SQLite 数据库副本'), findsOneWidget);

    final validBackup = harness.tempFile('valid-backup.db')
      ..writeAsBytesSync(ascii.encode('SQLite format 3\x00fake backup'));
    harness.filePicker.queuePickPath(validBackup);
    await _tapIcalButtonWithRealAsync(tester, '选择副本');
    await pumpIcalFrames(tester);

    expect(find.text('已暂存待恢复副本'), findsOneWidget);
    expect(find.text('原始副本：${validBackup.path}'), findsOneWidget);
    expect(find.textContaining('已准备好恢复副本：${validBackup.path}'), findsOneWidget);

    await _tapIcalButtonWithRealAsync(tester, '取消恢复');
    await pumpUntilIcalFound(
      tester,
      find.text('已取消待应用的数据库恢复副本。'),
    );
    expect(find.text('已取消待应用的数据库恢复副本。'), findsOneWidget);
    expect(find.text('已暂存待恢复副本'), findsNothing);
  });
}

bool _elevatedButtonEnabled(
  WidgetTester tester,
  String text,
) {
  final buttonFinder = find.ancestor(
    of: find.text(text),
    matching: find.byType(ElevatedButton),
  );
  expect(buttonFinder, findsWidgets);
  return tester.widget<ElevatedButton>(buttonFinder.last).onPressed != null;
}

Future<void> _tapChoiceChip(
  WidgetTester tester,
  String label,
) async {
  final chip = find.ancestor(
    of: find.text(label),
    matching: find.byType(ChoiceChip),
  );
  expect(chip, findsWidgets);
  await tester.ensureVisible(chip.last);
  await tester.tap(chip.last);
  await tester.pump();
}

Future<void> _tapFilterChip(
  WidgetTester tester,
  String label,
) async {
  final chip = find.ancestor(
    of: find.text(label),
    matching: find.byType(FilterChip),
  );
  expect(chip, findsWidgets);
  await tester.ensureVisible(chip.last);
  await tester.tap(chip.last);
  await tester.pump();
}

Future<void> _tapSelectorTextButton(
  WidgetTester tester,
  String selectorTitle,
  String buttonLabel,
) async {
  final selector = find.ancestor(
    of: find.text(selectorTitle),
    matching: find.byType(Column),
  );
  expect(selector, findsWidgets);
  final button = find.descendant(
    of: selector.first,
    matching: find.widgetWithText(TextButton, buttonLabel),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _tapDialogRadio(
  WidgetTester tester,
  String label,
) async {
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  final radioLabel = find.descendant(
    of: dialog,
    matching: find.text(label),
  );
  expect(radioLabel, findsOneWidget);
  await tester.tap(radioLabel);
  await tester.pump();
}

Future<void> _tapDialogButton(
  WidgetTester tester,
  String label,
) async {
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  final buttonLabel = find.descendant(
    of: dialog,
    matching: find.text(label),
  );
  expect(buttonLabel, findsOneWidget);
  await tester.tap(buttonLabel);
  await tester.pump();
}

Future<void> _tapDialogButtonWithRealAsync(
  WidgetTester tester,
  String label,
) async {
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  final buttonLabel = find.descendant(
    of: dialog,
    matching: find.text(label),
  );
  expect(buttonLabel, findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(buttonLabel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

Future<void> _tapIcalButtonWithRealAsync(
  WidgetTester tester,
  String text,
) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.runAsync(() async {
    await tester.tap(finder.last);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

Future<String> _waitForFileContaining(
  WidgetTester tester,
  File file,
  String marker, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  var content = '';
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) {
        content = file.readAsStringSync();
        if (content.contains(marker)) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  if (!content.contains(marker) && file.existsSync()) {
    content = file.readAsStringSync();
  }
  expect(content, contains(marker));
  return content;
}

Future<void> _waitForFileHeader(
  WidgetTester tester,
  File file,
  List<int> expectedHeader, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  List<int> bytes = const [];
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync() && file.lengthSync() >= expectedHeader.length) {
        bytes = file.readAsBytesSync().take(expectedHeader.length).toList();
        if (_listEquals(bytes, expectedHeader)) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  if (!_listEquals(bytes, expectedHeader) &&
      file.existsSync() &&
      file.lengthSync() >= expectedHeader.length) {
    bytes = file.readAsBytesSync().take(expectedHeader.length).toList();
  }
  expect(bytes, expectedHeader);
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

String _ics(List<String> events) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    ...events.map((event) => event.trim()),
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

String _vevent({
  required String uid,
  required String summary,
  required String start,
  required String end,
}) {
  return '''
BEGIN:VEVENT
UID:$uid
SUMMARY:$summary
DTSTART:$start
DTEND:$end
STATUS:CONFIRMED
END:VEVENT
''';
}

String _archiveJson() {
  return const JsonEncoder.withIndent('  ').convert({
    'schema': 'flowplanv2.container_archive.v1',
    'version': 1,
    'exported_at': '2026-06-08T09:00:00.000Z',
    'calendars': [
      {
        'name': 'Work',
        'color_hex': '#6B5EE4',
        'description': null,
        'is_visible': true,
        'is_default': true,
        'default_is_block': false,
        'events': [
          {
            'uid': 'archive-event-1',
            'dtstamp': '2026-06-08T09:00:00.000Z',
            'summary': 'Updated archive event',
            'description': null,
            'location': null,
            'dtstart': '2026-06-09T09:00:00.000Z',
            'dtend': '2026-06-09T10:00:00.000Z',
            'rrule': null,
            'status': 'CONFIRMED',
            'transp': 'OPAQUE',
            'source': 'local',
            'color_hex': '#6B5EE4',
            'is_block': false,
          },
          {
            'uid': 'archive-event-2',
            'dtstamp': '2026-06-08T09:00:00.000Z',
            'summary': 'New archive event',
            'description': null,
            'location': null,
            'dtstart': '2026-06-10T09:00:00.000Z',
            'dtend': '2026-06-10T10:00:00.000Z',
            'rrule': null,
            'status': 'CONFIRMED',
            'transp': 'OPAQUE',
            'source': 'local',
            'color_hex': '#6B5EE4',
            'is_block': false,
          },
        ],
      },
    ],
    'task_lists': [
      {
        'name': 'Inbox',
        'color_hex': '#0EA8A0',
        'emoji': null,
        'is_visible': true,
        'is_default': true,
        'is_archived': false,
        'default_is_auto_scheduled': true,
        'default_reminder_minutes_before': 15,
        'tasks': [
          {
            'uid': 'archive-task-1',
            'dtstamp': '2026-06-08T09:00:00.000Z',
            'summary': 'Updated archive task',
            'description': null,
            'location': null,
            'dtstart': '2026-06-09T09:00:00.000Z',
            'due': '2026-06-09T10:00:00.000Z',
            'completed': null,
            'priority': 0,
            'status': 'NEEDS-ACTION',
            'percent_complete': 0,
            'categories': [],
            'rrule': null,
            'duration_minutes': 60,
            'is_splittable': false,
            'priority_local': 2,
            'is_auto_scheduled': true,
            'tag_id': null,
            'is_locked': false,
            'reminder_minutes_before': 15,
          },
          {
            'uid': 'archive-task-2',
            'dtstamp': '2026-06-08T09:00:00.000Z',
            'summary': 'New archive task',
            'description': null,
            'location': null,
            'dtstart': '2026-06-10T09:00:00.000Z',
            'due': '2026-06-10T10:00:00.000Z',
            'completed': null,
            'priority': 0,
            'status': 'NEEDS-ACTION',
            'percent_complete': 0,
            'categories': [],
            'rrule': null,
            'duration_minutes': 60,
            'is_splittable': false,
            'priority_local': 2,
            'is_auto_scheduled': true,
            'tag_id': null,
            'is_locked': false,
            'reminder_minutes_before': 15,
          },
        ],
      },
    ],
  });
}
