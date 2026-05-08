import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { asString } from '../common/utils';
import type { LoginDto, RefreshDto } from './auth.dto';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  user: {
    id: string;
    displayName: string;
  };
}

@Injectable()
export class AuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly jwtService: JwtService,
  ) {}

  async login(body: LoginDto): Promise<TokenPair> {
    const requestedUserId = body.userId;
    const userId =
      requestedUserId && this.isUuid(requestedUserId)
        ? requestedUserId
        : randomUUID();
    const displayName = body.displayName ?? 'FlowPlanV2 User';

    await this.database.query(
      `INSERT INTO users (id, display_name)
       VALUES ($1, $2)
       ON CONFLICT (id) DO UPDATE SET
         display_name = EXCLUDED.display_name,
         updated_at = now()`,
      [userId, displayName],
    );

    const tokens = this.issueTokenPair(userId, displayName);
    return { ...tokens, user: { id: userId, displayName } };
  }

  async refresh(body: RefreshDto): Promise<TokenPair> {
    const token = body.refreshToken;
    if (!token) {
      throw new UnauthorizedException('refreshToken is required');
    }

    let payload: { sub: string; displayName?: string };
    try {
      payload = this.jwtService.verify<{ sub: string; displayName?: string }>(
        token,
        { secret: this.refreshSecret() },
      );
    } catch {
      throw new UnauthorizedException('invalid or expired refresh token');
    }

    const userId = payload.sub;
    const user = await this.database.query<{
      id: string;
      display_name: string;
    }>('SELECT id, display_name FROM users WHERE id = $1 LIMIT 1', [userId]);

    if (!user.rows[0]) {
      throw new UnauthorizedException('user not found');
    }

    const displayName = user.rows[0].display_name;
    const tokens = this.issueTokenPair(userId, displayName);
    return { ...tokens, user: { id: userId, displayName } };
  }

  logout(): { ok: boolean } {
    return { ok: true };
  }

  // ---- internal ----

  private issueTokenPair(
    userId: string,
    displayName: string,
  ): { accessToken: string; refreshToken: string } {
    const payload = { sub: userId, displayName };
    const accessToken = this.jwtService.sign(payload, {
      expiresIn: '24h' as const,
    });
    const refreshToken = this.jwtService.sign(payload, {
      secret: this.refreshSecret(),
      expiresIn: '7d' as const,
    });
    return { accessToken, refreshToken };
  }

  private refreshSecret(): string {
    return (
      process.env.JWT_REFRESH_SECRET ??
      process.env.JWT_ACCESS_SECRET ??
      process.env.FLOWPLANV2_DATABASE_URL ??
      process.env.DATABASE_URL ??
      'flowplanv2-jwt-refresh-secret'
    );
  }

  private isUuid(value: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }
}
