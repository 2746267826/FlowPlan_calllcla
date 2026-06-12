import { describe, expect, it, vi } from 'vitest';
import { GraphClientService } from './graph-client.service';
import { Client } from '@microsoft/microsoft-graph-client';

vi.mock('@microsoft/microsoft-graph-client', () => ({
  Client: {
    initWithMiddleware: vi.fn((options) => ({ options })),
  },
}));

describe('GraphClientService', () => {
  it('creates a Microsoft Graph v1 client whose auth provider requests the latest token per call', async () => {
    const getToken = vi
      .fn<() => Promise<string>>()
      .mockResolvedValueOnce('token-1')
      .mockResolvedValueOnce('token-2');
    const service = new GraphClientService();

    const client = service.createClient(getToken) as unknown as {
      options: {
        defaultVersion: string;
        authProvider: { getAccessToken: () => Promise<string> };
      };
    };

    expect(Client.initWithMiddleware).toHaveBeenCalledWith({
      authProvider: expect.objectContaining({ getAccessToken: expect.any(Function) }),
      defaultVersion: 'v1.0',
    });
    await expect(client.options.authProvider.getAccessToken()).resolves.toBe('token-1');
    await expect(client.options.authProvider.getAccessToken()).resolves.toBe('token-2');
    expect(getToken).toHaveBeenCalledTimes(2);
  });
});
