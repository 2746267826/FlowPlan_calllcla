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

export function collectProductionConfigWarnings(
  env: NodeJS.ProcessEnv = process.env,
): string[] {
  if (env.NODE_ENV !== 'production') {
    return [];
  }

  const warnings: string[] = [];
  if (!env.JWT_ACCESS_SECRET) {
    warnings.push(
      'JWT_ACCESS_SECRET is not set in production; configure a dedicated access token secret.',
    );
  }
  if (!env.JWT_REFRESH_SECRET) {
    warnings.push(
      'JWT_REFRESH_SECRET is not set in production; configure a dedicated refresh token secret.',
    );
  }
  if (!env.FLOWPLANV2_ENCRYPTION_KEY) {
    warnings.push(
      'FLOWPLANV2_ENCRYPTION_KEY is not set in production; encrypted integrations may be unavailable.',
    );
  }
  if (!env.ADMIN_CORS_ORIGIN) {
    warnings.push(
      'ADMIN_CORS_ORIGIN is not set in production; configure the expected admin origin.',
    );
  }
  return warnings;
}
