import { describe, expect, it } from 'vitest';
import { flattenHealth } from './pageFormat';

describe('flattenHealth', () => {
  it('normalizes known health sections into status rows', () => {
    const rows = flattenHealth({
      database: { status: 'ok', message: 'ready' },
      sync: { available: false, error: 'lagging' },
    });

    expect(rows.find((row) => row.key === 'database')).toMatchObject({
      value: 'ok',
      detail: 'ready',
    });
    expect(rows.find((row) => row.key === 'sync')).toMatchObject({
      value: false,
      detail: 'lagging',
    });
  });

  it('falls back to arbitrary health keys when known sections are absent', () => {
    expect(flattenHealth({ custom: { nested: true } })).toEqual([
      {
        key: 'custom',
        label: 'custom',
        value: '{"nested":true}',
      },
    ]);
  });
});
