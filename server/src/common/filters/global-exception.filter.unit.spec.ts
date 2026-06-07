import {
  HttpException,
  HttpStatus,
  type ArgumentsHost,
} from '@nestjs/common';
import { describe, expect, it, vi } from 'vitest';
import { AppException } from '../errors/app-exception';
import { ErrorCode } from '../errors/error-codes';
import { GlobalExceptionFilter } from './global-exception.filter';

function createHost(url = '/api/test') {
  const response = {
    status: vi.fn().mockReturnThis(),
    json: vi.fn(),
  };
  const host = {
    switchToHttp: () => ({
      getRequest: () => ({ url }),
      getResponse: () => response,
    }),
  } as unknown as ArgumentsHost;

  return { host, response };
}

describe('GlobalExceptionFilter', () => {
  it('serializes AppException responses with codes and details', () => {
    const logger = { error: vi.fn() };
    const filter = new GlobalExceptionFilter(logger as never);
    const { host, response } = createHost('/api/sync/push');

    filter.catch(
      new AppException(
        ErrorCode.SYNC_VERSION_CONFLICT,
        'Version conflict',
        HttpStatus.CONFLICT,
        { serverVersion: 3 },
      ),
      host,
    );

    expect(response.status).toHaveBeenCalledWith(HttpStatus.CONFLICT);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({
        errorCode: ErrorCode.SYNC_VERSION_CONFLICT,
        message: 'Version conflict',
        statusCode: HttpStatus.CONFLICT,
        path: '/api/sync/push',
        details: { serverVersion: 3 },
        timestamp: expect.any(String),
      }),
    );
  });

  it('joins validation message arrays from Nest HTTP exceptions', () => {
    const logger = { error: vi.fn() };
    const filter = new GlobalExceptionFilter(logger as never);
    const { host, response } = createHost('/api/auth/login');

    filter.catch(
      new HttpException(
        { message: ['displayName must be a string', 'userId must be a UUID'] },
        HttpStatus.BAD_REQUEST,
      ),
      host,
    );

    expect(response.status).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({
        errorCode: ErrorCode.VALIDATION_ERROR,
        message: 'displayName must be a string; userId must be a UUID',
      }),
    );
  });

  it('logs unhandled errors without exposing their messages to clients', () => {
    const logger = { error: vi.fn() };
    const filter = new GlobalExceptionFilter(logger as never);
    const { host, response } = createHost('/api/files');

    filter.catch(new Error('database password leaked'), host);

    expect(logger.error).toHaveBeenCalledWith(
      'Unhandled exception: database password leaked',
      expect.objectContaining({
        path: '/api/files',
        stack: expect.any(String),
      }),
    );
    expect(response.status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({
        errorCode: ErrorCode.INTERNAL_ERROR,
        message: 'Internal server error',
      }),
    );
  });

  it('handles thrown non-error values as unknown internal errors', () => {
    const logger = { error: vi.fn() };
    const filter = new GlobalExceptionFilter(logger as never);
    const { host, response } = createHost();

    filter.catch('panic', host);

    expect(logger.error).not.toHaveBeenCalled();
    expect(response.status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({
        errorCode: ErrorCode.INTERNAL_ERROR,
        message: 'Unknown error',
      }),
    );
  });
});
