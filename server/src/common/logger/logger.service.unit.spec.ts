import { afterEach, describe, expect, it, vi } from 'vitest';

const originalEnv = {
  NODE_ENV: process.env.NODE_ENV,
  LOG_FORMAT: process.env.LOG_FORMAT,
  LOG_LEVEL: process.env.LOG_LEVEL,
};

function setEnv(name: keyof typeof originalEnv, value: string | undefined) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}

async function loadLogger(env: Partial<Record<keyof typeof originalEnv, string | undefined>> = {}) {
  vi.resetModules();
  for (const key of Object.keys(originalEnv) as (keyof typeof originalEnv)[]) {
    setEnv(key, env[key]);
  }

  const sink = {
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
    verbose: vi.fn(),
  };
  const consoleTransport = { name: 'console' };
  const Console = vi.fn(function Console() {
    return consoleTransport;
  });
  const format = {
    combine: vi.fn((...parts: unknown[]) => ({ kind: 'combine', parts })),
    timestamp: vi.fn((options?: unknown) => ({ kind: 'timestamp', options })),
    errors: vi.fn((options?: unknown) => ({ kind: 'errors', options })),
    json: vi.fn(() => ({ kind: 'json' })),
    colorize: vi.fn(),
    simple: vi.fn(),
    printf: vi.fn((formatter: unknown) => ({ kind: 'printf', formatter })),
  };
  const createLogger = vi.fn(() => sink);

  vi.doMock('winston', () => ({
    createLogger,
    format,
    transports: { Console },
    Logger: class Logger {},
  }));

  const module = await import('./app-logger.service');
  return { AppLogger: module.AppLogger, sink, createLogger, format, Console };
}

afterEach(() => {
  vi.doUnmock('winston');
  vi.resetModules();
  for (const key of Object.keys(originalEnv) as (keyof typeof originalEnv)[]) {
    setEnv(key, originalEnv[key]);
  }
});

describe('AppLogger configuration', () => {
  it('uses structured JSON logging in production with an explicit level', async () => {
    const { AppLogger, createLogger, format, Console } = await loadLogger({
      NODE_ENV: 'production',
      LOG_LEVEL: 'warn',
    });

    new AppLogger();

    expect(createLogger).toHaveBeenCalledWith({
      level: 'warn',
      format: { kind: 'combine', parts: expect.any(Array) },
      transports: [{ name: 'console' }],
    });
    expect(format.timestamp).toHaveBeenCalledWith();
    expect(format.errors).toHaveBeenCalledWith({ stack: true });
    expect(format.json).toHaveBeenCalledTimes(1);
    expect(createLogger.mock.calls[0][0].format.parts).toEqual([
      { kind: 'timestamp', options: undefined },
      { kind: 'errors', options: { stack: true } },
      { kind: 'json' },
    ]);
    expect(Console).toHaveBeenCalledTimes(1);
  });

  it('treats LOG_FORMAT=json as production-style logging', async () => {
    const { AppLogger, createLogger, format } = await loadLogger({
      NODE_ENV: 'development',
      LOG_FORMAT: 'json',
    });

    new AppLogger();

    expect(createLogger).toHaveBeenCalledWith(
      expect.objectContaining({
        level: 'info',
      }),
    );
    expect(format.json).toHaveBeenCalledTimes(1);
  });

  it('uses the development formatter and default debug level outside production', async () => {
    const { AppLogger, createLogger, format } = await loadLogger({
      NODE_ENV: 'test',
    });

    new AppLogger();

    expect(createLogger).toHaveBeenCalledWith(
      expect.objectContaining({
        level: 'debug',
      }),
    );
    expect(format.timestamp).toHaveBeenCalledWith({ format: 'YYYY-MM-DD HH:mm:ss' });
    expect(format.printf).toHaveBeenCalledTimes(1);

    const formatter = format.printf.mock.calls[0][0] as (entry: Record<string, unknown>) => string;
    expect(
      formatter({
        timestamp: '2026-01-01 10:00:00',
        level: 'info',
        context: 'Bootstrap',
        message: 'ready',
        port: 3202,
      }),
    ).toBe('2026-01-01 10:00:00 info [Bootstrap] ready {"port":3202}');
    expect(
      formatter({
        timestamp: '2026-01-01 10:00:01',
        level: 'warn',
        message: 'plain',
      }),
    ).toBe('2026-01-01 10:00:01 warn plain');
  });
});

describe('AppLogger methods', () => {
  it('normalizes Nest logger parameters before forwarding to winston', async () => {
    const { AppLogger, sink } = await loadLogger({ NODE_ENV: 'test' });
    const logger = new AppLogger();

    logger.log('server ready', 'Bootstrap', { port: 3202 });
    logger.error('sync failed', { mutationUid: 'mut-1' });
    logger.warn('context only', 'Tasks');
    logger.debug('primitive trailing meta', 'Tasks', 'ignored');
    logger.verbose('primitive first param', 123);

    expect(sink.info).toHaveBeenCalledWith({
      message: 'server ready',
      context: 'Bootstrap',
      port: 3202,
    });
    expect(sink.error).toHaveBeenCalledWith({
      message: 'sync failed',
      context: undefined,
      mutationUid: 'mut-1',
    });
    expect(sink.warn).toHaveBeenCalledWith({
      message: 'context only',
      context: 'Tasks',
    });
    expect(sink.debug).toHaveBeenCalledWith({
      message: 'primitive trailing meta',
      context: 'Tasks',
    });
    expect(sink.verbose).toHaveBeenCalledWith({
      message: 'primitive first param',
      context: undefined,
    });
  });

  it('accepts Nest log level updates as a no-op', async () => {
    const { AppLogger, createLogger } = await loadLogger({ NODE_ENV: 'test' });
    const logger = new AppLogger();

    expect(() => logger.setLogLevels(['log', 'error'])).not.toThrow();
    expect(createLogger).toHaveBeenCalledTimes(1);
  });
});
