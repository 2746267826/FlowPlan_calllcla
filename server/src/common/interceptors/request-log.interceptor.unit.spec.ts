import type { CallHandler, ExecutionContext } from '@nestjs/common';
import { firstValueFrom, of, throwError } from 'rxjs';
import { describe, expect, it, vi } from 'vitest';
import { RequestLogInterceptor } from './request-log.interceptor';

function createContext(
  request: { method: string; url: string },
  response: { statusCode: number },
): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => request,
      getResponse: () => response,
    }),
  } as unknown as ExecutionContext;
}

describe('RequestLogInterceptor', () => {
  it('logs successful requests with method path status and duration', async () => {
    const logger = { log: vi.fn(), warn: vi.fn() };
    const interceptor = new RequestLogInterceptor(logger as never);
    const context = createContext(
      { method: 'GET', url: '/api/health' },
      { statusCode: 200 },
    );
    const next: CallHandler = { handle: () => of({ ok: true }) };

    await expect(firstValueFrom(interceptor.intercept(context, next))).resolves.toEqual({
      ok: true,
    });

    expect(logger.log).toHaveBeenCalledWith(
      expect.stringMatching(/^GET \/api\/health 200 \d+ms$/),
    );
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it('logs request errors and rethrows them', async () => {
    const logger = { log: vi.fn(), warn: vi.fn() };
    const interceptor = new RequestLogInterceptor(logger as never);
    const context = createContext(
      { method: 'POST', url: '/api/sync/push' },
      { statusCode: 500 },
    );
    const next: CallHandler = {
      handle: () => throwError(() => new Error('boom')),
    };

    await expect(firstValueFrom(interceptor.intercept(context, next))).rejects.toThrow(
      'boom',
    );

    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringMatching(/^POST \/api\/sync\/push - \d+ms error: boom$/),
    );
    expect(logger.log).not.toHaveBeenCalled();
  });

  it('logs non-Error thrown values as request errors', async () => {
    const logger = { log: vi.fn(), warn: vi.fn() };
    const interceptor = new RequestLogInterceptor(logger as never);
    const context = createContext(
      { method: 'DELETE', url: '/api/files/node-1' },
      { statusCode: 500 },
    );
    const next: CallHandler = {
      handle: () => throwError(() => 'plain failure'),
    };

    await expect(firstValueFrom(interceptor.intercept(context, next))).rejects.toBe(
      'plain failure',
    );

    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringMatching(/^DELETE \/api\/files\/node-1 - \d+ms error: plain failure$/),
    );
    expect(logger.log).not.toHaveBeenCalled();
  });
});
