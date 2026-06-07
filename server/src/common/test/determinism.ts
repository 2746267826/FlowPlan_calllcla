import { vi } from 'vitest';

export const TEST_NOW = new Date('2026-01-02T03:04:05.000Z');

export function installDeterminism(): () => void {
  vi.useFakeTimers();
  vi.setSystemTime(TEST_NOW);
  const randomSpy = vi.spyOn(Math, 'random').mockReturnValue(0.42);

  return () => {
    randomSpy.mockRestore();
    vi.useRealTimers();
    vi.restoreAllMocks();
  };
}
