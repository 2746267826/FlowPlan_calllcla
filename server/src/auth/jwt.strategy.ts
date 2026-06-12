import { ExtractJwt, Strategy } from 'passport-jwt';
import { PassportStrategy } from '@nestjs/passport';
import { Injectable } from '@nestjs/common';

export interface JwtPayload {
  sub: string;       // userId
  deviceId: string;
  displayName?: string;
  iat: number;
  exp: number;
}

export function resolveJwtStrategySecret(): string {
  return (
    process.env.JWT_ACCESS_SECRET ??
    process.env.FLOWPLANV2_DATABASE_URL ??
    process.env.DATABASE_URL ??
    'flowplanv2-jwt-access-secret'
  );
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: resolveJwtStrategySecret(),
    });
  }

  validate(payload: JwtPayload): JwtPayload {
    return payload;
  }
}
