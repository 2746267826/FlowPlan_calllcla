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

  it('falls back to canonical defaults and normalizes numeric flags and legacy fields', () => {
    const defaultTitle = normalizeTaskPayload({}).title;
    const task = normalizeTaskPayload({
      name: '   ',
      deadline: '2026-04-05T12:00:00.000Z',
      startTime: '2026-04-05T10:00:00.000Z',
      estimatedMinutes: 'bad',
      durationMinutes: 90,
      taskListName: 'Projects',
      where: 'Library',
      rrule: 'FREQ=WEEKLY',
      isLocked: 2,
      reminderMinutesBefore: '15',
      source: 'manual',
      created_at: '2026-04-01T00:00:00.000Z',
      updated_at: '2026-04-02T00:00:00.000Z',
    });

    expect(task).toMatchObject({
      title: defaultTitle,
      dueAt: '2026-04-05T12:00:00.000Z',
      startAt: '2026-04-05T10:00:00.000Z',
      estimatedMinutes: 90,
      taskListName: 'Projects',
      location: 'Library',
      rrule: 'FREQ=WEEKLY',
      isLocked: true,
      reminderMinutesBefore: 15,
      source: 'manual',
      createdAt: '2026-04-01T00:00:00.000Z',
      updatedAt: '2026-04-02T00:00:00.000Z',
    });
  });

  it('treats false string and zero numeric lock flags as unlocked', () => {
    expect(normalizeTaskPayload({ title: 'Task', isLocked: 'false' }).isLocked).toBe(
      false,
    );
    expect(normalizeTaskPayload({ title: 'Task', is_locked: 0 }).isLocked).toBe(false);
    expect(
      normalizeTaskPayload({
        title: 'Task',
        isLocked: true,
        allowAutoSchedule: true,
        canSplit: true,
      }),
    ).toMatchObject({
      isLocked: true,
      isAutoScheduled: true,
      isSplittable: true,
    });
  });
});
