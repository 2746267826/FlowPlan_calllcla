import { HttpException, HttpStatus } from '@nestjs/common';
import type { ErrorCodeType } from './error-codes';

/**
 * Application-level exception carrying a machine-readable error code.
 *
 * All business-logic errors should use this instead of the generic
 * `BadRequestException` / `NotFoundException` etc. so the global
 * exception filter can produce a consistent response shape.
 */
export class AppException extends HttpException {
  public readonly errorCode: ErrorCodeType;
  public readonly details?: unknown;

  constructor(
    errorCode: ErrorCodeType,
    message: string,
    status: HttpStatus = HttpStatus.BAD_REQUEST,
    details?: unknown,
  ) {
    super({ errorCode, message, details }, status);
    this.errorCode = errorCode;
    this.details = details;
  }
}
