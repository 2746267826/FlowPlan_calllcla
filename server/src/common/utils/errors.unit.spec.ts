import { describe, expect, it } from 'vitest';
import { errorMessage } from './errors';

describe('errorMessage', () => {
  it('returns the message from Error instances', () => {
    expect(errorMessage(new Error('database unavailable'))).toBe(
      'database unavailable',
    );
  });

  it('stringifies non-Error thrown values', () => {
    expect(errorMessage('plain failure')).toBe('plain failure');
    expect(errorMessage(404)).toBe('404');
  });
});
