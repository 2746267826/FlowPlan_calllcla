import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DatabaseService } from '../../database/database.service';
import { assertTestDatabaseUrl, resetTestDatabase } from './db-test-harness';
import { cleanDatabase } from './test-utils';

const ORIGINAL_FLOWPLANV2_DATABASE_URL = process.env.FLOWPLANV2_DATABASE_URL;
const ORIGINAL_DATABASE_URL = process.env.DATABASE_URL;

function createDatabaseMock(activeDatabaseName: string) {
  const db = {
    query: vi.fn(async (sql: string) => {
      if (sql === 'SELECT current_database() AS name') {
        return { rows: [{ name: activeDatabaseName }] };
      }
      return { rows: [] };
    }),
  };

  return db as unknown as DatabaseService & { query: typeof db.query };
}

function issuedTruncate(db: ReturnType<typeof createDatabaseMock>): boolean {
  return db.query.mock.calls.some(([sql]) => /^TRUNCATE\b/i.test(String(sql)));
}

describe('assertTestDatabaseUrl', () => {
  beforeEach(() => {
    delete process.env.FLOWPLANV2_DATABASE_URL;
    delete process.env.DATABASE_URL;
  });

  afterEach(() => {
    process.env.FLOWPLANV2_DATABASE_URL = ORIGINAL_FLOWPLANV2_DATABASE_URL;
    process.env.DATABASE_URL = ORIGINAL_DATABASE_URL;
  });

  it('rejects production-looking database URLs', () => {
    expect(() =>
      assertTestDatabaseUrl('postgres://user:pass@localhost:5432/flowplanv2'),
    ).toThrow(/Refusing to use non-test database/);
  });

  it('accepts flowplantest database URLs', () => {
    expect(() =>
      assertTestDatabaseUrl('postgres://user:pass@localhost:5432/flowplantest'),
    ).not.toThrow();
  });

  it('refuses to reset when the active database is not a test database', async () => {
    process.env.DATABASE_URL =
      'postgres://user:pass@localhost:5432/flowplantest';
    const db = createDatabaseMock('flowplanv2');

    await expect(resetTestDatabase(db)).rejects.toThrow(
      /Refusing to clean non-test database/,
    );

    expect(issuedTruncate(db)).toBe(false);
  });

  it('resets only after the configured URL and active database are test databases', async () => {
    process.env.DATABASE_URL =
      'postgres://user:pass@localhost:5432/flowplantest';
    const db = createDatabaseMock('flowplantest');

    await resetTestDatabase(db);

    expect(db.query).toHaveBeenCalledWith('SELECT current_database() AS name');
    expect(db.query).toHaveBeenCalledWith(
      'TRUNCATE TABLE users RESTART IDENTITY CASCADE',
    );
  });

  it('keeps cleanDatabase behind the guarded reset helper', async () => {
    process.env.DATABASE_URL =
      'postgres://user:pass@localhost:5432/flowplantest';
    const db = createDatabaseMock('flowplanv2');

    await expect(cleanDatabase(db)).rejects.toThrow(
      /Refusing to clean non-test database/,
    );

    expect(issuedTruncate(db)).toBe(false);
  });
});
