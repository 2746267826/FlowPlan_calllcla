import { HttpStatus } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { ErrorCode } from './error-codes';
import { AppException } from './app-exception';

describe('AppException', () => {
  it('keeps machine-readable error code status and details together', () => {
    const details = { field: 'taskId' };
    const exception = new AppException(
      ErrorCode.SYNC_VERSION_CONFLICT,
      'Version conflict',
      HttpStatus.CONFLICT,
      details,
    );

    expect(exception.errorCode).toBe(ErrorCode.SYNC_VERSION_CONFLICT);
    expect(exception.details).toBe(details);
    expect(exception.getStatus()).toBe(HttpStatus.CONFLICT);
    expect(exception.getResponse()).toEqual({
      errorCode: ErrorCode.SYNC_VERSION_CONFLICT,
      message: 'Version conflict',
      details,
    });
  });

  it('defaults business errors to bad requests', () => {
    const exception = new AppException(
      ErrorCode.VALIDATION_ERROR,
      'Invalid payload',
    );

    expect(exception.getStatus()).toBe(HttpStatus.BAD_REQUEST);
  });
});
