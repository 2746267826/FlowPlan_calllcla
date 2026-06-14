import { describe, expect, it } from 'vitest';
import { resolveInitialApiBase } from './apiBase';

describe('resolveInitialApiBase', () => {
  it('uses the development fallback when no stored or Vite value exists', () => {
    expect(resolveInitialApiBase({ storedValue: null, viteValue: undefined })).toBe(
      'http://localhost:3202',
    );
  });

  it('uses VITE_API_BASE_URL when local storage has no override', () => {
    expect(
      resolveInitialApiBase({
        storedValue: null,
        viteValue: 'https://flowplan.example.com/api',
      }),
    ).toBe('https://flowplan.example.com');
  });

  it('keeps local storage override ahead of VITE_API_BASE_URL', () => {
    expect(
      resolveInitialApiBase({
        storedValue: 'https://stored.example.com/api',
        viteValue: 'https://vite.example.com/api',
      }),
    ).toBe('https://stored.example.com');
  });

  it('supports same-origin reverse proxy configuration with /api', () => {
    expect(
      resolveInitialApiBase({
        storedValue: null,
        viteValue: '/api',
      }),
    ).toBe('');
  });
});
