import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class AuthService {
  constructor(private readonly database: DatabaseService) {}

  async login(body: Record<string, unknown>) {
    const requestedUserId = this.asString(body.userId);
    const userId =
      requestedUserId && this.isUuid(requestedUserId)
        ? requestedUserId
        : randomUUID();
    const displayName = this.asString(body.displayName) ?? 'FlowPlanV2 User';

    await this.database.query(
      `
      INSERT INTO users (id, display_name)
      VALUES ($1, $2)
      ON CONFLICT (id) DO UPDATE SET
        display_name = EXCLUDED.display_name,
        updated_at = now()
      `,
      [userId, displayName],
    );

    return {
      accessToken: `p1-local-token.${userId}`,
      refreshToken: `p1-local-refresh.${userId}`,
      user: {
        id: userId,
        displayName,
      },
    };
  }

  refresh() {
    return {
      accessToken: `p1-local-token.${randomUUID()}`,
      refreshToken: `p1-local-refresh.${randomUUID()}`,
    };
  }

  logout() {
    return {
      ok: true,
    };
  }

  private asString(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : undefined;
  }

  private isUuid(value: string) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }
}
