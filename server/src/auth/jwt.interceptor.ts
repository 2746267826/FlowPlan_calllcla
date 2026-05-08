import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import type { JwtPayload } from './jwt.strategy';

/**
 * Global interceptor that reads the JWT from the Authorization header
 * and injects the claims into the request headers.
 *
 * This lets the existing `readRequestContext()` function work without
 * any changes — it continues to read `x-flowplanv2-user-id` and
 * `x-flowplanv2-device-id` from headers, but now those headers are
 * populated from a verified JWT instead of being sent in plain text.
 */
@Injectable()
export class JwtInterceptor implements NestInterceptor {
  constructor(private readonly jwtService: JwtService) {}

  intercept(context: ExecutionContext, next: CallHandler) {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers?.authorization;

    if (authHeader && typeof authHeader === 'string') {
      try {
        const token = authHeader.replace(/^Bearer\s+/i, '');
        const payload: JwtPayload =
          this.jwtService.verify<JwtPayload>(token, {
            secret:
              process.env.JWT_ACCESS_SECRET ??
              process.env.FLOWPLANV2_DATABASE_URL ??
              process.env.DATABASE_URL ??
              'flowplanv2-jwt-access-secret',
          });

        if (payload.sub) {
          request.headers['x-flowplanv2-user-id'] = payload.sub;
        }
        if (payload.deviceId) {
          request.headers['x-flowplanv2-device-id'] = payload.deviceId;
        }
      } catch {
        // Token invalid / expired — leave headers untouched.
        // Protected routes will be rejected by JwtAuthGuard if applied.
      }
    }

    return next.handle();
  }
}
