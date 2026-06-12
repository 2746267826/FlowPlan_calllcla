/**
 * Centralised config values derived from environment variables.
 * Use with @nestjs/config ConfigService, or import directly in non-DI contexts.
 */

export interface AppConfig {
  port: number;
  host: string;
  databaseUrl: string;
  bodyLimit: string;
  corsOrigin: string | boolean;
  jwtAccessSecret: string;
  jwtRefreshSecret: string;
  jwtAccessExpires: string;
  jwtRefreshExpires: string;
  logLevel: string;
  logFormat: string;
}

export function loadConfig(): AppConfig {
  const databaseUrl =
    process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL ?? '';

  return {
    port: Number(process.env.PORT ?? 3202),
    host: process.env.HOST ?? '0.0.0.0',
    databaseUrl,
    bodyLimit: process.env.FLOWPLANV2_BODY_LIMIT ?? '50mb',
    corsOrigin: process.env.ADMIN_CORS_ORIGIN ?? true,
    jwtAccessSecret:
      process.env.JWT_ACCESS_SECRET ?? databaseUrl,
    jwtRefreshSecret:
      process.env.JWT_REFRESH_SECRET ?? process.env.JWT_ACCESS_SECRET ?? databaseUrl,
    jwtAccessExpires: process.env.JWT_ACCESS_EXPIRES ?? '24h',
    jwtRefreshExpires: process.env.JWT_REFRESH_EXPIRES ?? '7d',
    logLevel: process.env.LOG_LEVEL ?? 'debug',
    logFormat: process.env.LOG_FORMAT ?? 'dev',
  };
}
