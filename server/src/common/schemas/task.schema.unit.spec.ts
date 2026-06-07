import { describe, expect, it } from 'vitest';
import { normalizeTaskPayload } from './task.schema';

describe('normalizeTaskPayload', () => {
  it('maps legacy task fields into the canonical payload shape', () => {
    expect(
      normalizeTaskPayload({
        summary: '  Draft report  ',
        status: 'completed',
        priorityLocal: 'medium',
        due: '2026-02-03T10:00:00.000Z',
        dtstart: '2026-02-03T09:00:00.000Z',
        durationMinutes: '45',
        task_list_id: 'list-1',
        listName: 'Inbox',
        note: 'Bring evidence links',
        is_locked: '1',
        allowAutoSchedule: false,
        canSplit: false,
        updatedFrom: 'import',
      }),
    ).toMatchObject({
      title: 'Draft report',
      summary: 'Draft report',
      description: 'Bring evidence links',
      status: 'done',
      priority: 'normal',
      dueAt: '2026-02-03T10:00:00.000Z',
      startAt: '2026-02-03T09:00:00.000Z',
      estimatedMinutes: 45,
      taskListId: 'list-1',
      taskListName: 'Inbox',
      notes: 'Bring evidence links',
      isLocked: true,
      isAutoScheduled: false,
      isSplittable: false,
      source: 'import',
    });
  });

  it('defaults unknown status priority and scheduling flags predictably', () => {
    expect(
      normalizeTaskPayload({
        title: 'Task',
        status: 'surprise',
        priority: 'medium-ish',
      }),
    ).toMatchObject({
      title: 'Task',
      status: 'todo',
      priority: 'normal',
      isLocked: false,
      isAutoScheduled: true,
      isSplittable: true,
    });
  });
});
