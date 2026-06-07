import { afterEach, beforeAll, vi } from 'vitest';
import { assertTestDatabaseUrl } from './common/test/db-test-harness';

if (!process.env.FLOWPLANV2_DATABASE_URL && !process.env.DATABASE_URL) {
  process.env.DATABASE_URL =
    'postgres://postgres:060331@localhost:5432/flowplantest';
}

beforeAll(() => {
  assertTestDatabaseUrl();
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});
