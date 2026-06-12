import { act, renderHook, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { safeRandomId, useAsyncAction } from './hooks';

describe('safeRandomId', () => {
  it('uses crypto randomUUID when available', () => {
    const randomUUID = vi.fn().mockReturnValue('uuid-1');
    vi.stubGlobal('crypto', { randomUUID });

    expect(safeRandomId()).toBe('uuid-1');
  });

  it('falls back to a web admin timestamp id', () => {
    vi.stubGlobal('crypto', {});
    vi.spyOn(Date, 'now').mockReturnValue(12345);
    vi.spyOn(Math, 'random').mockReturnValue(0.5);

    expect(safeRandomId()).toBe('web-admin-12345-8');
  });
});

describe('useAsyncAction', () => {
  it('sets loading while an async action is running and returns the result', async () => {
    const { result } = renderHook(() => useAsyncAction());
    let resolveAction: (value: string) => void = () => {};
    const action = vi.fn(
      () =>
        new Promise<string>((resolve) => {
          resolveAction = resolve;
        }),
    );

    let runResult!: Promise<string | undefined>;
    await act(async () => {
      runResult = result.current.run(action);
    });

    expect(result.current.loading).toBe(true);

    await act(async () => {
      resolveAction('ok');
      await expect(runResult).resolves.toBe('ok');
    });

    await waitFor(() => expect(result.current.loading).toBe(false));
  });

  it('clears loading when an async action rejects', async () => {
    const { result } = renderHook(() => useAsyncAction());
    let rejectAction: (error: Error) => void = () => {};
    const error = new Error('action failed');
    const action = vi.fn(
      () =>
        new Promise<string>((_, reject) => {
          rejectAction = reject;
        }),
    );

    let runResult!: Promise<string | undefined>;
    await act(async () => {
      runResult = result.current.run(action);
    });

    expect(result.current.loading).toBe(true);

    await act(async () => {
      rejectAction(error);
      await expect(runResult).rejects.toThrow(error);
    });

    await waitFor(() => expect(result.current.loading).toBe(false));
  });
});
