import { afterEach, describe, expect, it, vi } from 'vitest';
import { dateRange, dayRange, iso, readDate, readIsoDate } from './dates';

describe('date utilities', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('parses valid date values and rejects invalid or blank inputs', () => {
    expect(readDate(' 2026-01-02T03:04:05.000Z ')?.toISOString()).toBe(
      '2026-01-02T03:04:05.000Z',
    );
    expect(readDate(new Date('2026-01-02T03:04:05.000Z'))?.toISOString()).toBe(
      '2026-01-02T03:04:05.000Z',
    );
    expect(readDate('')).toBeNull();
    expect(readDate('not-a-date')).toBeNull();
    expect(readDate(new Date('not-a-date'))).toBeNull();
  });

  it('requires strict ISO timestamps when requested', () => {
    expect(readIsoDate('2026-01-02T03:04:05Z')?.toISOString()).toBe(
      '2026-01-02T03:04:05.000Z',
    );
    expect(readIsoDate('2026-01-02')).toBeNull();
    expect(readIsoDate('2026-13-02T03:04:05Z')).toBeNull();
    expect(readIsoDate(new Date('2026-01-02T03:04:05Z'))).toBeNull();
  });

  it('normalizes dates to ISO strings while preserving unparseable strings', () => {
    expect(iso(new Date('2026-01-02T03:04:05.000Z'))).toBe(
      '2026-01-02T03:04:05.000Z',
    );
    expect(iso(new Date('not-a-date'))).toBeNull();
    expect(iso('2026-01-02T03:04:05.000Z')).toBe('2026-01-02T03:04:05.000Z');
    expect(iso('later-ish')).toBe('later-ish');
    expect(iso(null)).toBeNull();
  });

  it('returns explicit day ranges when start is before end', () => {
    expect(
      dayRange(
        '2026-02-03',
        '2026-02-03T09:00:00.000Z',
        '2026-02-03T17:00:00.000Z',
      ),
    ).toEqual({
      start: '2026-02-03T09:00:00.000Z',
      end: '2026-02-03T17:00:00.000Z',
    });
  });

  it('falls back to the requested calendar day when explicit ranges are invalid', () => {
    expect(dayRange('2026-02-03', 'bad', 'also-bad')).toEqual({
      start: '2026-02-03T00:00:00.000Z',
      end: '2026-02-04T00:00:00.000Z',
    });
  });

  it('uses the current UTC day when no day or explicit range is provided', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-04T12:00:00.000Z'));

    expect(dayRange(null, null, null)).toEqual({
      start: '2026-03-04T00:00:00.000Z',
      end: '2026-03-05T00:00:00.000Z',
    });
  });

  it('validates broader date ranges', () => {
    expect(
      dateRange('2026-02-01T00:00:00.000Z', '2026-02-08T00:00:00.000Z'),
    ).toEqual({
      start: '2026-02-01T00:00:00.000Z',
      end: '2026-02-08T00:00:00.000Z',
    });
    expect(() =>
      dateRange('2026-02-08T00:00:00.000Z', '2026-02-01T00:00:00.000Z'),
    ).toThrow('start must be earlier than end');
  });

  it('defaults broader ranges around the provided or current end date', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-04-30T00:00:00.000Z'));

    expect(dateRange(undefined, '2026-05-31T00:00:00.000Z')).toEqual({
      start: '2026-05-01T00:00:00.000Z',
      end: '2026-05-31T00:00:00.000Z',
    });
    expect(dateRange('2026-04-01T00:00:00.000Z', undefined)).toEqual({
      start: '2026-04-01T00:00:00.000Z',
      end: '2026-04-30T00:00:00.000Z',
    });
  });
});
