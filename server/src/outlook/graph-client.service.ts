import { Injectable } from '@nestjs/common';
import { Client } from '@microsoft/microsoft-graph-client';
import type { AuthenticationProvider } from '@microsoft/microsoft-graph-client';

/**
 * Wraps the official @microsoft/microsoft-graph-client SDK.
 *
 * Provides:
 *  - Automatic token refresh via middleware
 *  - Built-in retry + 429 rate-limit handling
 *  - Proper error classification
 */
@Injectable()
export class GraphClientService {
  /**
   * Create a Microsoft Graph client with a Bearer token provider.
   * The `getToken` callback is called on every request, allowing
   * the caller to refresh the access token as needed.
   */
  createClient(getToken: () => Promise<string>): Client {
    const authProvider: AuthenticationProvider = {
      getAccessToken: async () => {
        const token = await getToken();
        return token;
      },
    };

    return Client.initWithMiddleware({
      authProvider,
      defaultVersion: 'v1.0',
    });
  }
}
