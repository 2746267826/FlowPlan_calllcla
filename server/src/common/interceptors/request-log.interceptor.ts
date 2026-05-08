import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { AppLogger } from '../logger/app-logger.service';

/**
 * Logs every HTTP request with method, path, status code, and duration.
 */
@Injectable()
export class RequestLogInterceptor implements NestInterceptor {
  constructor(private readonly logger: AppLogger) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    const { method, url } = request;
    const start = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const response = context.switchToHttp().getResponse();
          const ms = Date.now() - start;
          this.logger.log(`${method} ${url} ${response.statusCode} ${ms}ms`);
        },
        error: (error: unknown) => {
          const ms = Date.now() - start;
          const message = error instanceof Error ? error.message : String(error);
          this.logger.warn(`${method} ${url} - ${ms}ms error: ${message}`);
        },
      }),
    );
  }
}
