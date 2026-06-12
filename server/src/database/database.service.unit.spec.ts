import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DatabaseService, type TransactionClient } from './database.service';

type MockPool = {
  totalCount: number;
  idleCount: number;
  waitingCount: number;
  query: ReturnType<typeof vi.fn>;
  connect: ReturnType<typeof vi.fn>;
  end: ReturnType<typeof vi.fn>;
  on: ReturnType<typeof vi.fn>;
};

const { PoolMock, createdPools } = vi.hoisted(() => {
  const createdPools: MockPool[] = [];
  const PoolMock = vi.fn(function MockedPool() {
    const pool: MockPool = {
      totalCount: 4,
      idleCount: 2,
      waitingCount: 1,
      query: vi.fn(async () => ({ rows: [] })),
      connect: vi.fn(),
      end: vi.fn(async () => undefined),
      on: vi.fn(),
    };
    createdPools.push(pool);
    return pool;
  });

  return { PoolMock, createdPools };
});

vi.mock('pg', () => ({ Pool: PoolMock }));

const ENV_KEYS = [
  'FLOWPLANV2_DATABASE_URL',
  'DATABASE_URL',
  'DATABASE_POOL_MAX',
  'DATABASE_POOL_IDLE_TIMEOUT',
  'DATABASE_POOL_CONNECTION_TIMEOUT',
  'SLOW_QUERY_THRESHOLD_MS',
] as const;

const originalEnv = Object.fromEntries(
  ENV_KEYS.map((key) => [key, process.env[key]]),
);

function restoreEnv() {
  for (const key of ENV_KEYS) {
    const value = originalEnv[key];
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
}

function useDatabaseEnv(overrides: Partial<Record<(typeof ENV_KEYS)[number], string>> = {}) {
  for (const key of ENV_KEYS) {
    delete process.env[key];
  }
  process.env.DATABASE_URL = 'postgres://postgres:060331@localhost:5432/flowplantest';
  Object.assign(process.env, overrides);
}

function latestPool(): MockPool {
  const pool = createdPools.at(-1);
  if (!pool) {
    throw new Error('Expected DatabaseService to construct a Pool');
  }
  return pool;
}

describe('DatabaseService', () => {
  beforeEach(() => {
    createdPools.length = 0;
    PoolMock.mockClear();
    useDatabaseEnv();
  });

  afterEach(() => {
    restoreEnv();
  });

  it('requires a database URL before constructing the pg pool', () => {
    delete process.env.FLOWPLANV2_DATABASE_URL;
    delete process.env.DATABASE_URL;

    expect(() => new DatabaseService()).toThrow(
      /FLOWPLANV2_DATABASE_URL or DATABASE_URL is required/,
    );
    expect(PoolMock).not.toHaveBeenCalled();
  });

  it('configures pg Pool from FlowPlanV2 environment overrides and monitors pool events', () => {
    useDatabaseEnv({
      FLOWPLANV2_DATABASE_URL: 'postgres://flowplan-primary',
      DATABASE_URL: 'postgres://legacy',
      DATABASE_POOL_MAX: '25',
      DATABASE_POOL_IDLE_TIMEOUT: '1234',
      DATABASE_POOL_CONNECTION_TIMEOUT: '5678',
    });
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    new DatabaseService();

    expect(PoolMock).toHaveBeenCalledWith({
      connectionString: 'postgres://flowplan-primary',
      max: 25,
      idleTimeoutMillis: 1234,
      connectionTimeoutMillis: 5678,
    });

    const pool = latestPool();
    const connectHandler = pool.on.mock.calls.find(([event]) => event === 'connect')?.[1];
    const errorHandler = pool.on.mock.calls.find(([event]) => event === 'error')?.[1];

    expect(connectHandler).toEqual(expect.any(Function));
    expect(errorHandler).toEqual(expect.any(Function));
    expect(() => connectHandler()).not.toThrow();

    errorHandler(new Error('socket closed'));

    expect(consoleError).toHaveBeenCalledWith(
      '[DatabaseService] Pool error:',
      'socket closed',
    );
  });

  it('reports current pool statistics with the configured max size', () => {
    useDatabaseEnv({ DATABASE_POOL_MAX: '17' });
    const service = new DatabaseService();
    const pool = latestPool();
    pool.totalCount = 8;
    pool.idleCount = 3;
    pool.waitingCount = 2;

    expect(service.poolStats()).toEqual({
      totalCount: 8,
      idleCount: 3,
      waitingCount: 2,
      max: 17,
    });
  });

  it('reports the default pool max when no override is configured', () => {
    const service = new DatabaseService();

    expect(service.poolStats()).toEqual({
      totalCount: 4,
      idleCount: 2,
      waitingCount: 1,
      max: 10,
    });
  });

  it('checks connectivity on module init and wraps connection failures with setup guidance', async () => {
    const service = new DatabaseService();
    const pool = latestPool();

    await expect(service.onModuleInit()).resolves.toBeUndefined();
    expect(pool.query).toHaveBeenCalledWith('SELECT 1');

    pool.query.mockRejectedValueOnce(new Error('connection refused'));

    await expect(service.onModuleInit()).rejects.toThrow(
      /could not connect to PostgreSQL.*connection refused.*npm run db:schema/,
    );
  });

  it('delegates queries directly when slow query logging is disabled', async () => {
    useDatabaseEnv({ SLOW_QUERY_THRESHOLD_MS: '0' });
    const service = new DatabaseService();
    const pool = latestPool();
    const result = { rows: [{ ok: true }] };
    pool.query.mockResolvedValueOnce(result);
    const consoleWarn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    await expect(service.query('SELECT $1')).resolves.toBe(result);

    expect(pool.query).toHaveBeenCalledWith('SELECT $1', []);
    expect(consoleWarn).not.toHaveBeenCalled();
  });

  it('logs normalized slow queries when elapsed time reaches the configured threshold', async () => {
    useDatabaseEnv({ SLOW_QUERY_THRESHOLD_MS: '100' });
    const service = new DatabaseService();
    const pool = latestPool();
    const result = { rows: [{ ok: true }] };
    pool.query.mockResolvedValueOnce(result);
    vi.spyOn(Date, 'now').mockReturnValueOnce(1_000).mockReturnValueOnce(1_250);
    const consoleWarn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    await expect(
      service.query('SELECT   *\nFROM   tasks WHERE id = $1', ['task-1']),
    ).resolves.toBe(result);

    expect(pool.query).toHaveBeenCalledWith(
      'SELECT   *\nFROM   tasks WHERE id = $1',
      ['task-1'],
    );
    expect(consoleWarn).toHaveBeenCalledWith(
      '[SlowQuery] 250ms: SELECT * FROM tasks WHERE id = $1',
    );
  });

  it('does not log queries below the default slow query threshold', async () => {
    const service = new DatabaseService();
    const pool = latestPool();
    const result = { rows: [{ ok: true }] };
    pool.query.mockResolvedValueOnce(result);
    vi.spyOn(Date, 'now').mockReturnValueOnce(1_000).mockReturnValueOnce(1_999);
    const consoleWarn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    await expect(service.query('SELECT 1')).resolves.toBe(result);

    expect(consoleWarn).not.toHaveBeenCalled();
  });

  it('commits successful transactions and always releases the client', async () => {
    const service = new DatabaseService();
    const pool = latestPool();
    const client = {
      query: vi.fn(async () => ({ rows: [] })),
      release: vi.fn(),
    };
    pool.connect.mockResolvedValueOnce(client);

    await expect(
      service.transaction(async (transactionClient: TransactionClient) => {
        await transactionClient.query('SELECT 42');
        return 'committed';
      }),
    ).resolves.toBe('committed');

    expect(client.query.mock.calls.map(([sql]) => sql)).toEqual([
      'BEGIN',
      'SELECT 42',
      'COMMIT',
    ]);
    expect(client.release).toHaveBeenCalledOnce();
  });

  it('rolls back failed transactions and rethrows the callback error', async () => {
    const service = new DatabaseService();
    const pool = latestPool();
    const client = {
      query: vi.fn(async () => ({ rows: [] })),
      release: vi.fn(),
    };
    const error = new Error('mutation failed');
    pool.connect.mockResolvedValueOnce(client);

    await expect(
      service.transaction(async () => {
        throw error;
      }),
    ).rejects.toBe(error);

    expect(client.query.mock.calls.map(([sql]) => sql)).toEqual(['BEGIN', 'ROLLBACK']);
    expect(client.release).toHaveBeenCalledOnce();
  });

  it('ends the pool on module destroy', async () => {
    const service = new DatabaseService();
    const pool = latestPool();

    await service.onModuleDestroy();

    expect(pool.end).toHaveBeenCalledOnce();
  });
});
