import { Injectable, LoggerService, LogLevel } from '@nestjs/common';
import { createLogger, format, transports, Logger as WinstonLogger } from 'winston';

const { combine, timestamp, errors, json, colorize, simple, printf } = format;

const devFormat = printf(({ level, message, timestamp, context, trace, ...meta }) => {
  const ctx = context ? `[${context}] ` : '';
  const metaStr = Object.keys(meta).length > 0 ? ` ${JSON.stringify(meta)}` : '';
  return `${timestamp} ${level} ${ctx}${message}${metaStr}`;
});

/**
 * Application-wide logger wrapping winston.
 *
 * In development: colourised human-readable output.
 * In production: structured JSON to stdout (for log aggregators).
 */
@Injectable()
export class AppLogger implements LoggerService {
  private readonly logger: WinstonLogger;

  constructor() {
    const isProduction =
      process.env.NODE_ENV === 'production' || process.env.LOG_FORMAT === 'json';

    this.logger = createLogger({
      level: process.env.LOG_LEVEL ?? (isProduction ? 'info' : 'debug'),
      format: isProduction
        ? combine(timestamp(), errors({ stack: true }), json())
        : combine(
            timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
            errors({ stack: true }),
            devFormat,
          ),
      transports: [new transports.Console()],
    });
  }

  log(message: string, ...optionalParams: unknown[]): void {
    this.logger.info(this.buildMessage(message, optionalParams));
  }

  error(message: string, ...optionalParams: unknown[]): void {
    this.logger.error(this.buildMessage(message, optionalParams));
  }

  warn(message: string, ...optionalParams: unknown[]): void {
    this.logger.warn(this.buildMessage(message, optionalParams));
  }

  debug(message: string, ...optionalParams: unknown[]): void {
    this.logger.debug(this.buildMessage(message, optionalParams));
  }

  verbose(message: string, ...optionalParams: unknown[]): void {
    this.logger.verbose(this.buildMessage(message, optionalParams));
  }

  /** NestJS integration: filter log levels by context. */
  setLogLevels(_levels: LogLevel[]): void {
    // winston handles levels via config; no-op for now.
  }

  // ---- internal ----

  private buildMessage(message: string, params: unknown[]): Record<string, unknown> {
    const context = params.length > 0 && typeof params[0] === 'string' ? params[0] : undefined;
    const meta =
      params.length > 1
        ? params[params.length - 1]
        : params.length === 1 && typeof params[0] !== 'string'
          ? params[0]
          : undefined;
    return {
      message,
      context,
      ...(meta && typeof meta === 'object' ? (meta as Record<string, unknown>) : {}),
    };
  }
}
