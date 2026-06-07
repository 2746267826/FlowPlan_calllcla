import { describe, expect, it, vi } from 'vitest';
import { AppLogger } from './app-logger.service';

function installSink(logger: AppLogger) {
  const sink = {
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
    verbose: vi.fn(),
  };
  (logger as unknown as { logger: typeof sink }).logger = sink;
  return sink;
}

describe('AppLogger', () => {
  it('forwards messages with string context and object metadata', () => {
    const logger = new AppLogger();
    const sink = installSink(logger);

    logger.log('server ready', 'Bootstrap', { port: 3202 });

    expect(sink.info).toHaveBeenCalledWith({
      message: 'server ready',
      context: 'Bootstrap',
      port: 3202,
    });
  });

  it('forwards object metadata when no context string is provided', () => {
    const logger = new AppLogger();
    const sink = installSink(logger);

    logger.error('sync failed', { mutationUid: 'mut-1' });
    logger.warn('device degraded', { deviceId: 'device-1' });
    logger.debug('cursor moved', { cursor: '42' });
    logger.verbose('trace detail', { scope: 'test' });

    expect(sink.error).toHaveBeenCalledWith({
      message: 'sync failed',
      mutationUid: 'mut-1',
    });
    expect(sink.warn).toHaveBeenCalledWith({
      message: 'device degraded',
      deviceId: 'device-1',
    });
    expect(sink.debug).toHaveBeenCalledWith({
      message: 'cursor moved',
      cursor: '42',
    });
    expect(sink.verbose).toHaveBeenCalledWith({
      message: 'trace detail',
      scope: 'test',
    });
  });

  it('accepts Nest log level updates without changing the winston sink', () => {
    const logger = new AppLogger();

    expect(() => logger.setLogLevels(['log', 'error'])).not.toThrow();
  });
});
