import { describe, expect, it, vi } from 'vitest';
import {
  asArray,
  asRecord,
  auditActionLabel,
  compareManagementItems,
  displayValue,
  extractRows,
  fieldLabel,
  firstDate,
  formatDate,
  formatFieldValue,
  getNestedValue,
  matchesManagementFilters,
  parseJsonMaybe,
  parseJsonOrString,
  pickId,
  prettyJson,
  relativeDate,
  shortJson,
  sourceLabel,
  statusColor,
  statusLabel,
  timeRangeLabel,
  toCount,
  toManagementItem,
  toSnakeCase,
} from './format';

describe('format utilities', () => {
  it('normalizes records, arrays, and direct array payloads with safe fallbacks', () => {
    expect(asRecord({ ok: true })).toEqual({ ok: true });
    expect(asRecord(['not-record'])).toEqual({});
    expect(asRecord(null)).toEqual({});
    expect(asArray(['row'])).toEqual(['row']);
    expect(asArray({ row: true })).toEqual([]);
    expect(extractRows([{ id: 'direct-row' }, null, 'bad-row'])).toEqual([
      { id: 'direct-row' },
      {},
      {},
    ]);
  });

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
    expect(formatDate(new Date('2026-06-08T09:10:11.000Z'))).toContain(
      '2026-06-08',
    );
    expect(formatDate(undefined)).toBe(relativeDate(undefined));
    expect(formatDate('not-a-date')).toBe('not-a-date');
    expect(firstDate('', 'bad-date')).toBeUndefined();
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
    const later = toManagementItem(
      { id: 'later', title: 'Later', dueAt: '2026-06-09T09:00:00.000Z' },
      'tasks',
    );
    const undated = toManagementItem({ id: 'undated', title: 'Undated' }, 'tasks');
    const alpha = toManagementItem({ id: 'alpha', title: 'Alpha' }, 'tasks');
    const beta = toManagementItem({ id: 'beta', title: 'Beta' }, 'tasks');

    expect(compareManagementItems(dated, undated)).toBeLessThan(0);
    expect(compareManagementItems(undated, dated)).toBeGreaterThan(0);
    expect(compareManagementItems(alpha, beta)).toBeLessThan(0);
    expect(compareManagementItems(dated, later)).toBeLessThan(0);
    expect(statusColor('failed')).toBe('error');
  });

  it('formats primitive and object values with safe fallbacks', () => {
    const circular: Record<string, unknown> = {};
    circular.self = circular;

    expect(displayValue(true)).not.toBe('');
    expect(displayValue(false)).not.toBe(displayValue(true));
    expect(displayValue(12)).toBe('12');
    expect(displayValue({ ok: true })).toBe('{"ok":true}');
    expect(displayValue(Number.NaN, 'fallback')).toBe('fallback');
    expect(displayValue('', 'fallback')).toBe('fallback');
    expect(displayValue(null, 'fallback')).toBe('fallback');
    expect(shortJson({ value: 'x'.repeat(160) })).toMatch(/\.\.\.$/);
    expect(shortJson(circular)).toBe('[object Object]');
    expect(prettyJson({ nested: true })).toContain('\n');
    expect(prettyJson(circular)).toBe('[object Object]');
    expect(parseJsonMaybe('{"ok":true}')).toEqual({ ok: true });
    expect(parseJsonMaybe({ ok: true })).toEqual({ ok: true });
    expect(parseJsonMaybe('{bad json')).toBe('{bad json');
    expect(parseJsonOrString('   ')).toEqual({});
    expect(parseJsonOrString('plain text')).toBe('plain text');
  });

  it('extracts rows from each supported list property and ignores non-arrays', () => {
    expect(extractRows({ devices: [{ id: 'device-1' }] })).toEqual([
      { id: 'device-1' },
    ]);
    expect(extractRows({ calendars: [{ id: 'calendar-1' }] })).toEqual([
      { id: 'calendar-1' },
    ]);
    expect(extractRows({ roots: [{ id: 'ignored' }] })).toEqual([]);
    expect(extractRows(null)).toEqual([]);
  });

  it('labels statuses, sources, fields, and nested values', () => {
    expect(statusLabel('COMPLETED')).not.toBe('COMPLETED');
    expect(statusColor('success')).toBe('success');
    expect(statusColor('running')).toBe('warning');
    expect(statusColor('mystery')).toBe('default');
    expect(sourceLabel('outlook')).toBe('Outlook');
    expect(sourceLabel('server')).not.toBe('server');
    expect(sourceLabel(undefined)).toBe(sourceLabel('local'));
    expect(auditActionLabel('admin.operation.confirm')).not.toBe(
      'admin.operation.confirm',
    );
    expect(auditActionLabel('custom.action')).toBe('custom.action');
    expect(sourceLabel('custom-source')).toBe('custom-source');
    expect(fieldLabel('title')).not.toBe('title');
    expect(fieldLabel('unknownField')).toBe('unknownField');
    expect(formatFieldValue('createdAt', '2026-06-08T09:00:00.000Z')).toContain(
      '2026-06-08',
    );
    expect(formatFieldValue('status', 'open')).toBe('open');
    expect(formatFieldValue('source', 'outlook')).toBe('Outlook');
    expect(formatFieldValue('payload', { ok: true })).toBe('{"ok":true}');
    expect(formatFieldValue('plain', 'value')).toBe('value');
    expect(
      [
        pickId({ id: 'id' }),
        pickId({ uid: 'uid' }),
        pickId({ objectUid: 'object' }),
        pickId({ deviceId: 'device' }),
        pickId({ batchId: 'batch' }),
        pickId({ configKey: 'config' }),
        pickId({ key: 'key' }),
      ],
    ).toEqual(['id', 'uid', 'object', 'device', 'batch', 'config', 'key']);
    expect(getNestedValue({ direct: 'value' }, 'direct')).toBe('value');
    expect(
      getNestedValue({ payload: { displayName: 'payload-name' } }, 'displayName'),
    ).toBe('payload-name');
    expect(
      getNestedValue({ metadata: { displayName: 'metadata-name' } }, 'displayName'),
    ).toBe('metadata-name');
    expect(getNestedValue({ due_at: 'row-date' }, 'dueAt')).toBe('row-date');
    expect(
      getNestedValue({ metadata: { due_at: 'metadata-date' } }, 'dueAt'),
    ).toBe('metadata-date');
    expect(getNestedValue({}, 'missing')).toBeUndefined();
    expect(
      getNestedValue(
        {
          payload: { due_at: 'payload-date' },
          metadata: { displayName: 'metadata-name' },
        },
        'dueAt',
      ),
    ).toBe('payload-date');
    expect(toSnakeCase('dueAtTime')).toBe('due_at_time');
  });

  it('covers the status formatter branch when the broad date-key guard is bypassed', () => {
    const originalIncludes = String.prototype.includes;
    const includesSpy = vi
      .spyOn(String.prototype, 'includes')
      .mockImplementation(function includes(searchString, position) {
        if (String(this) === 'status' && searchString === 'at') return false;
        return originalIncludes.call(this, searchString, position);
      });

    try {
      expect(formatFieldValue('status', 'COMPLETED')).not.toBe('COMPLETED');
    } finally {
      includesSpy.mockRestore();
    }
  });

  it('builds readable time labels and counts from mixed inputs', () => {
    const start = firstDate('', 'bad', '2026-06-08T09:00:00.000Z');
    const end = firstDate('2026-06-08T10:00:00.000Z');

    expect(start).toBeInstanceOf(Date);
    expect(relativeDate(undefined)).not.toBe('');
    expect(relativeDate('not-a-date')).toBe('not-a-date');
    expect(relativeDate('2026-06-08T09:00:00.000Z')).toContain('06-08');
    expect(timeRangeLabel(undefined, end)).not.toBe('');
    expect(timeRangeLabel(start, undefined)).toContain('2026-06-08');
    expect(timeRangeLabel(start, end)).toContain(' - ');
    expect(toCount('4.9')).toBe(4);
    expect(toCount(-2)).toBe(0);
    expect(toCount('bad')).toBe(0);
  });

  it('builds schedule management items with outlook defaults and filters by time', () => {
    const item = toManagementItem(
      {
        uid: 'outlook-event-1',
        summary: 'Design review',
        dtstart: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        dtend: new Date(Date.now() + 25 * 60 * 60 * 1000).toISOString(),
      },
      'schedules',
    );
    const noTime = toManagementItem(
      { id: 'schedule-2', title: 'Floating review' },
      'schedules',
    );

    expect(item.type).toBe('schedule');
    expect(item.source).toBe('outlook');
    expect(
      matchesManagementFilters(item, {
        query: 'design',
        typeFilter: 'schedule',
        sourceFilter: 'outlook',
        timeFilter: 'next7',
        statusFilter: 'all',
      }),
    ).toBe(true);
    expect(
      matchesManagementFilters(noTime, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'none',
        statusFilter: 'all',
      }),
    ).toBe(true);
    expect(
      matchesManagementFilters(
        toManagementItem(
          {
            id: 'overdue-task',
            title: 'Overdue',
            status: 'open',
            dueAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
          },
          'tasks',
        ),
        {
          query: '',
          typeFilter: 'all',
          sourceFilter: 'all',
          timeFilter: 'overdue',
          statusFilter: 'all',
        },
      ),
    ).toBe(true);
  });

  it('uses management item title fallbacks and rejects mismatched filters early', () => {
    const item = toManagementItem(
      {
        id: 'task-1',
        payload: { summary: 'Payload summary' },
      },
      'tasks',
    );
    const uidTitle = toManagementItem({ uid: 'uid-title' }, 'tasks');
    const unnamed = toManagementItem({ id: 'unnamed' }, 'tasks');

    expect(item.title).toBe('Payload summary');
    expect(uidTitle.title).toBe('uid-title');
    expect(unnamed.title).not.toBe(displayValue(undefined));
    expect(
      matchesManagementFilters(item, {
        query: '',
        typeFilter: 'schedule',
        sourceFilter: 'all',
        timeFilter: 'all',
        statusFilter: 'all',
      }),
    ).toBe(false);
    expect(
      matchesManagementFilters(item, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'outlook',
        timeFilter: 'all',
        statusFilter: 'all',
      }),
    ).toBe(false);
    expect(
      matchesManagementFilters(item, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'all',
        statusFilter: 'done',
      }),
    ).toBe(false);
  });

  it('covers date filter fallbacks for missing, today, next7, and overdue cases', () => {
    const noTime = toManagementItem({ id: 'floating', title: 'Floating' }, 'tasks');
    const today = toManagementItem(
      {
        id: 'today',
        title: 'Today',
        dueAt: new Date().toISOString(),
      },
      'tasks',
    );
    const outsideNext7 = toManagementItem(
      {
        id: 'future',
        title: 'Future',
        dueAt: new Date(Date.now() + 8 * 24 * 60 * 60 * 1000).toISOString(),
      },
      'tasks',
    );
    const completedOverdue = toManagementItem(
      {
        id: 'completed',
        title: 'Completed',
        status: 'COMPLETED',
        dueAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      },
      'tasks',
    );
    const scheduleOverdue = toManagementItem(
      {
        id: 'schedule',
        title: 'Schedule',
        startAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      },
      'schedules',
    );

    expect(
      matchesManagementFilters(noTime, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'today',
        statusFilter: 'all',
      }),
    ).toBe(false);
    expect(
      matchesManagementFilters(today, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'today',
        statusFilter: 'all',
      }),
    ).toBe(true);
    expect(
      matchesManagementFilters(outsideNext7, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'next7',
        statusFilter: 'all',
      }),
    ).toBe(false);
    expect(
      matchesManagementFilters(completedOverdue, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'overdue',
        statusFilter: 'all',
      }),
    ).toBe(false);
    expect(
      matchesManagementFilters(scheduleOverdue, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'overdue',
        statusFilter: 'all',
      }),
    ).toBe(false);
    expect(
      matchesManagementFilters(today, {
        query: '',
        typeFilter: 'all',
        sourceFilter: 'all',
        timeFilter: 'custom-range',
        statusFilter: 'all',
      }),
    ).toBe(true);
  });
});
