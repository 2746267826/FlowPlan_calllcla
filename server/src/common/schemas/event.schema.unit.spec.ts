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
});
