import { describe, expect, it } from 'vitest';
import { normalizeEventPayload } from './event.schema';

describe('normalizeEventPayload', () => {
  it('maps legacy event fields into the canonical payload shape', () => {
    expect(
      normalizeEventPayload({
        name: '  Planning block  ',
        dtstart: '2026-02-03T09:00:00.000Z',
        dtend: '2026-02-03T10:00:00.000Z',
        status: 'canceled',
        blocking: 'true',
        place: 'Office',
        note: 'Prep schedule',
        color_hex: '#336699',
        eventCalendarId: 'cal-1',
        calendarName: 'Work',
        updatedFrom: 'outlook',
      }),
    ).toMatchObject({
      title: 'Planning block',
      startAt: '2026-02-03T09:00:00.000Z',
      endAt: '2026-02-03T10:00:00.000Z',
      status: 'cancelled',
      isBlock: true,
      location: 'Office',
      notes: 'Prep schedule',
      colorHex: '#336699',
      calendarBookId: 'cal-1',
      calendarBookName: 'Work',
      source: 'outlook',
    });
  });

  it('defaults unknown status and missing dates safely', () => {
    expect(
      normalizeEventPayload({
        title: 'Focus',
        status: 'unknown',
        kind: 'blocking',
      }),
    ).toMatchObject({
      title: 'Focus',
      startAt: '',
      endAt: '',
      status: 'confirmed',
      isBlock: true,
    });
  });

  it('falls back to canonical defaults and handles numeric blocking flags', () => {
    const defaultTitle = normalizeEventPayload({}).title;
    const event = normalizeEventPayload({
      title: '   ',
      summary: '',
      startTime: '2026-03-04T08:00:00.000Z',
      endTime: '2026-03-04T09:00:00.000Z',
      isBlocking: 1,
      created_at: '2026-03-01T00:00:00.000Z',
      updated_at: '2026-03-02T00:00:00.000Z',
    });

    expect(event.title).toBe(defaultTitle);
    expect(event.startAt).toBe('2026-03-04T08:00:00.000Z');
    expect(event.endAt).toBe('2026-03-04T09:00:00.000Z');
    expect(event.isBlock).toBe(true);
    expect(event.createdAt).toBe('2026-03-01T00:00:00.000Z');
    expect(event.updatedAt).toBe('2026-03-02T00:00:00.000Z');
  });

  it('treats false string and zero numeric blocking values as non-blocking', () => {
    expect(normalizeEventPayload({ title: 'Open', isBlock: 'false' }).isBlock).toBe(
      false,
    );
    expect(normalizeEventPayload({ title: 'Open', blocking: 0 }).isBlock).toBe(false);
    expect(normalizeEventPayload({ title: 'Open', isBlock: true }).isBlock).toBe(true);
  });
});
