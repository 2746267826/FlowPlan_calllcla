import { describe, expect, it } from 'vitest';
import {
  compareManagementItems,
  extractRows,
  formatDate,
  matchesManagementFilters,
  statusColor,
  toManagementItem,
} from './format';

describe('format utilities', () => {
  it('extracts array-like payload rows and drops primitive values safely', () => {
    expect(
      extractRows({
        items: [{ id: 'task-1' }, null, 'bad-row'],
      }),
    ).toEqual([{ id: 'task-1' }, {}, {}]);
  });

  it('formats valid dates and leaves invalid dates readable', () => {
    expect(formatDate('2026-06-08T09:10:11.000Z')).toContain(
      '2026-06-08',
    );
    expect(formatDate('not-a-date')).toBe('not-a-date');
  });

  it('builds management items from nested task payload fields', () => {
    const item = toManagementItem(
      {
        uid: 'task-1',
        payload: {
          title: 'Plan review',
          source: 'local',
          dueAt: '2026-06-08T09:00:00.000Z',
        },
      },
      'tasks',
    );

    expect(item.id).toBe('task-1');
    expect(item.title).toBe('Plan review');
    expect(item.source).toBe('local');
    expect(item.timeLabel).toContain('2026-06-08');
  });

  it('filters management rows by user query, source, and status', () => {
    const item = toManagementItem(
      {
        id: 'task-1',
        title: 'Plan review',
        source: 'local',
        status: 'open',
      },
      'tasks',
    );

    expect(
      matchesManagementFilters(item, {
        query: 'plan',
        typeFilter: 'all',
        sourceFilter: 'local',
        timeFilter: 'all',
        statusFilter: 'open',
      }),
    ).toBe(true);
    expect(
      matchesManagementFilters(item, {
        query: 'daily',
        typeFilter: 'all',
        sourceFilter: 'local',
        timeFilter: 'all',
        statusFilter: 'open',
      }),
    ).toBe(false);
  });

  it('sorts undated management rows after dated rows', () => {
    const dated = toManagementItem(
      { id: 'dated', title: 'Dated', dueAt: '2026-06-08T09:00:00.000Z' },
      'tasks',
    );
    const undated = toManagementItem({ id: 'undated', title: 'Undated' }, 'tasks');

    expect(compareManagementItems(dated, undated)).toBeLessThan(0);
    expect(statusColor('failed')).toBe('error');
  });
});
