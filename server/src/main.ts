import 'reflect-metadata';

// ── .env must be loaded BEFORE any other module imports ──
import { config } from 'dotenv';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

// Try multiple paths: dev (src/ → ..), prod (dist/src/ → ../../), cwd fallback
const envCandidates = [
  resolve(__dirname, '..', '.env'),           // src/main.ts → server/
  resolve(__dirname, '..', '..', '.env'),      // dist/src/main.js → server/
  resolve(process.cwd(), '.env'),
  resolve(process.cwd(), 'server', '.env'),
];
const envPath = envCandidates.find((p) => existsSync(p));

if (envPath) {
  const result = config({ path: envPath });
  const count = Object.keys(result.parsed ?? {}).length;
  console.log(`[Env] Loaded ${count} vars from ${envPath}`);
} else {
  console.warn(`[Env] .env not found. Searched: ${envCandidates.join(', ')}`);
  console.warn('[Env] Using system environment variables only.');
}

import { NestFactory } from '@nestjs/core';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AppLogger } from './common/logger/app-logger.service';

const bodyParser = require('body-parser') as {
  json: (options: { limit: string }) => unknown;
  urlencoded: (options: { extended: boolean; limit: string }) => unknown;
};

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false });

  const bodyLimit = process.env.FLOWPLANV2_BODY_LIMIT ?? '50mb';
  app.use(bodyParser.json({ limit: bodyLimit }) as never);
  app.use(bodyParser.urlencoded({ extended: true, limit: bodyLimit }) as never);
  app.enableCors({
    origin: process.env.ADMIN_CORS_ORIGIN ?? true,
    credentials: false,
  });
  app.setGlobalPrefix('api');

  const swaggerConfig = new DocumentBuilder()
    .setTitle('FlowPlanV2 API')
    .setDescription('个人数据管理系统 — 日历、任务、追踪、文件、报告、同步、AI')
    .setVersion('2.0.0')
    .addBearerAuth()
    .build();
  const swaggerDoc = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, swaggerDoc);

  const port = Number(process.env.PORT ?? 3202);
  const host = process.env.HOST ?? '0.0.0.0';

  await app.listen(port, host);

  const logger = app.get(AppLogger);
  logger.log(`FlowPlanV2 server listening on http://${host}:${port}/api`);
  logger.log(`Encryption key: ${process.env.FLOWPLANV2_ENCRYPTION_KEY ? '✅ configured' : '❌ NOT SET — set FLOWPLANV2_ENCRYPTION_KEY in .env'}`);
}

bootstrap().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error('FlowPlanV2 server startup failed.');
  console.error(message);
  console.error(
    [
      'Startup checklist:',
      '1. Ensure .env exists in server/ with FLOWPLANV2_DATABASE_URL.',
      '2. Confirm PostgreSQL is running and reachable.',
      '3. Run: cd server; npm run build; npm run db:schema',
      '4. Run: cd server; npm start  (or npm run dev)',
    ].join('\n'),
  );
  process.exit(1);
});
