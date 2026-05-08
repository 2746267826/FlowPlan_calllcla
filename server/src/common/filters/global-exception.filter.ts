import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { AppLogger } from '../logger/app-logger.service';
import { AppException } from '../errors/app-exception';
import { ErrorCode } from '../errors/error-codes';

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  constructor(private readonly logger: AppLogger) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const request = ctx.getRequest<Request>();
    const response = ctx.getResponse<Response>();

    let status: number;
    let errorCode: string;
    let message: string;
    let details: unknown;

    if (exception instanceof AppException) {
      status = exception.getStatus();
      errorCode = exception.errorCode;
      message = exception.message;
      details = exception.details;
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      errorCode = ErrorCode.VALIDATION_ERROR;
      const res = exception.getResponse();
      if (typeof res === 'object' && res !== null && 'message' in res) {
        message = Array.isArray(res.message)
          ? res.message.join('; ')
          : String(res.message);
      } else {
        message = exception.message;
      }
    } else if (exception instanceof Error) {
      status = HttpStatus.INTERNAL_SERVER_ERROR;
      errorCode = ErrorCode.INTERNAL_ERROR;
      message = 'Internal server error';
      this.logger.error(`Unhandled exception: ${exception.message}`, {
        stack: exception.stack,
        path: request.url,
      });
    } else {
      status = HttpStatus.INTERNAL_SERVER_ERROR;
      errorCode = ErrorCode.INTERNAL_ERROR;
      message = 'Unknown error';
    }

    const body = {
      errorCode,
      message,
      statusCode: status,
      timestamp: new Date().toISOString(),
      path: request.url,
      ...(details ? { details } : {}),
    };

    response.status(status).json(body);
  }
}
