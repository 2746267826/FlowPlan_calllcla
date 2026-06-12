import type { CallHandler, ExecutionContext } from '@nestjs/common';
import { firstValueFrom, of } from 'rxjs';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { JwtInterceptor } from './jwt.interceptor';

function contextFor(request: Record<string, unknown>): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => request,
    }),
  } as unknown as ExecutionContext;
}

describe('JwtInterceptor', () => {
  const originalEnv = {
    JWT_ACCESS_SECRET: process.env.JWT_ACCESS_SECRET,
    FLOWPLANV2_DATABASE_URL: process.env.FLOWPLANV2_DATABASE_URL,
    DATABASE_URL: process.env.DATABASE_URL,
  };

  afterEach(() => {
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it('injects request-context headers from a verified bearer token', async () => {
    const jwt = {
      verify: vi.fn(() => ({
        sub: 'user-1',
        deviceId: 'device-1',
        iat: 1,
        exp: 2,
      })),
    };
    const request = { headers: { authorization: 'Bearer signed-token' } };
    const next: CallHandler = { handle: () => of({ ok: true }) };
    const interceptor = new JwtInterceptor(jwt as never);

    await expect(firstValueFrom(interceptor.intercept(contextFor(request), next))).resolves.toEqual({
      ok: true,
    });

    expect(jwt.verify).toHaveBeenCalledWith('signed-token', {
      secret: expect.any(String),
    });
    expect(request.headers).toMatchObject({
      authorization: 'Bearer signed-token',
      'x-flowplanv2-user-id': 'user-1',
      'x-flowplanv2-device-id': 'device-1',
    });
  });

  it('leaves headers unchanged when token verification fails', async () => {
    const jwt = { verify: vi.fn(() => { throw new Error('bad token'); }) };
    const request = { headers: { authorization: 'Bearer bad-token' } };
    const next: CallHandler = { handle: () => of('next') };
    const interceptor = new JwtInterceptor(jwt as never);

    await expect(firstValueFrom(interceptor.intercept(contextFor(request), next))).resolves.toBe('next');

    expect(request.headers).toEqual({ authorization: 'Bearer bad-token' });
  });

  it('passes through requests without an authorization header', async () => {
    const jwt = { verify: vi.fn() };
    const request = { headers: {} };
    const next: CallHandler = { handle: () => of('next') };
    const interceptor = new JwtInterceptor(jwt as never);

    await expect(firstValueFrom(interceptor.intercept(contextFor(request), next))).resolves.toBe('next');

    expect(jwt.verify).not.toHaveBeenCalled();
    expect(request.headers).toEqual({});
  });

  it('uses the hardcoded JWT fallback and leaves device context absent when the token has no device id', async () => {
    delete process.env.JWT_ACCESS_SECRET;
    delete process.env.FLOWPLANV2_DATABASE_URL;
    delete process.env.DATABASE_URL;
    const jwt = {
      verify: vi.fn(() => ({
        sub: 'user-no-device',
        iat: 1,
        exp: 2,
      })),
    };
    const request = { headers: { authorization: 'Bearer fallback-token' } };
    const next: CallHandler = { handle: () => of('ok') };
    const interceptor = new JwtInterceptor(jwt as never);

    await expect(firstValueFrom(interceptor.intercept(contextFor(request), next))).resolves.toBe('ok');

    expect(jwt.verify).toHaveBeenCalledWith('fallback-token', {
      secret: 'flowplanv2-jwt-access-secret',
    });
    expect(request.headers).toEqual({
      authorization: 'Bearer fallback-token',
      'x-flowplanv2-user-id': 'user-no-device',
    });
  });
});
