import 'reflect-metadata';

import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { config } from 'dotenv';

const envCandidates = [
  resolve(__dirname, '..', '.env'),
  resolve(__dirname, '..', '..', '.env'),
  resolve(process.cwd(), '.env'),
  resolve(process.cwd(), 'server', '.env'),
];
const envPath = envCandidates.find((candidate) => existsSync(candidate));

if (envPath) {
  const result = config({ path: envPath });
  const count = Object.keys(result.parsed ?? {}).length;
  console.log(`[Env] Loaded ${count} vars from ${envPath}`);
} else {
  console.warn(`[Env] .env not found. Searched: ${envCandidates.join(', ')}`);
  console.warn('[Env] Using system environment variables only.');
}

import { NestFactory } from '@nestjs/core';
import { configureApp } from './app.bootstrap';
import { AppModule } from './app.module';
import { AppLogger } from './common/logger/app-logger.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  configureApp(app);

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
