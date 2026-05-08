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

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey:
        process.env.JWT_ACCESS_SECRET ??
        process.env.FLOWPLANV2_DATABASE_URL ??
        process.env.DATABASE_URL ??
        'flowplanv2-jwt-access-secret',
    });
  }

  validate(payload: JwtPayload): JwtPayload {
    return payload;
  }
}
