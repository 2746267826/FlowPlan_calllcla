import { describe, expect, it, vi } from 'vitest';
import { AuthController } from './auth.controller';

function mockAuthService() {
  return new Proxy(
    {},
    {
      get(target, prop: string) {
        if (!(prop in target)) {
          (target as Record<string, unknown>)[prop] = vi.fn(async (...args: unknown[]) => ({
            method: prop,
            args,
          }));
        }
        return (target as Record<string, unknown>)[prop];
      },
    },
  ) as Record<string, ReturnType<typeof vi.fn>>;
}

const loginBody = { displayName: 'Unit User' };
const refreshBody = { refreshToken: 'refresh-token-1' };

const cases = [
  {
    controllerMethod: 'login',
    serviceMethod: 'login',
    invoke: (controller: AuthController) => controller.login(loginBody),
    expectedArgs: [loginBody],
  },
  {
    controllerMethod: 'refresh',
    serviceMethod: 'refresh',
    invoke: (controller: AuthController) => controller.refresh(refreshBody),
    expectedArgs: [refreshBody],
  },
  {
    controllerMethod: 'logout',
    serviceMethod: 'logout',
    invoke: (controller: AuthController) => controller.logout(),
    expectedArgs: [],
  },
];

describe('AuthController', () => {
  it('has a delegation case for every public route method', () => {
    const publicMethods = Object.getOwnPropertyNames(AuthController.prototype)
      .filter((name) => name !== 'constructor')
      .sort();

    expect(cases.map((testCase) => testCase.controllerMethod).sort()).toEqual(publicMethods);
  });

  it.each(cases)('forwards $controllerMethod to $serviceMethod', async (testCase) => {
    const service = mockAuthService();
    const controller = new AuthController(service as never);

    await expect(testCase.invoke(controller)).resolves.toEqual({
      method: testCase.serviceMethod,
      args: testCase.expectedArgs,
    });
    expect(service[testCase.serviceMethod]).toHaveBeenCalledWith(...testCase.expectedArgs);
  });

  it('passes login and refresh DTO instances through unchanged and returns service results', async () => {
    const service = {
      login: vi.fn(async () => ({ accessToken: 'access-1', refreshToken: 'refresh-1' })),
      refresh: vi.fn(async () => ({ accessToken: 'access-2', refreshToken: 'refresh-2' })),
    };
    const controller = new AuthController(service as never);
    const loginDto = { userId: '11111111-1111-4111-8111-111111111111', displayName: 'Unit User' };
    const refreshDto = { refreshToken: 'refresh-token-1' };

    await expect(controller.login(loginDto)).resolves.toEqual({
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    });
    await expect(controller.refresh(refreshDto)).resolves.toEqual({
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
    });
    expect(service.login.mock.calls[0][0]).toBe(loginDto);
    expect(service.refresh.mock.calls[0][0]).toBe(refreshDto);
  });

  it('logout remains a bodyless route adapter', async () => {
    const service = {
      logout: vi.fn(async () => ({ ok: true })),
    };
    const controller = new AuthController(service as never);

    await expect(controller.logout()).resolves.toEqual({ ok: true });
    expect(service.logout).toHaveBeenCalledWith();
  });

  it('passes service errors through without wrapping them', async () => {
    const service = mockAuthService();
    const controller = new AuthController(service as never);
    const error = new Error('login failed');
    service.login.mockRejectedValueOnce(error);

    await expect(controller.login(loginBody)).rejects.toBe(error);
  });
});
