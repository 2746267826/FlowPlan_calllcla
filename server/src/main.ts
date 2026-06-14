import 'reflect-metadata';

import { formatEnvLoadMessage, loadEnvFile } from './common/config/env-files';

const loadedEnv = loadEnvFile();
console.log(formatEnvLoadMessage(loadedEnv));

async function bootstrap() {
  const [{ NestFactory }, { configureApp }, { AppModule }, { AppLogger }] =
    await Promise.all([
      import('@nestjs/core'),
      import('./app.bootstrap'),
      import('./app.module'),
      import('./common/logger/app-logger.service'),
    ]);
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  configureApp(app);

  const port = Number(process.env.PORT ?? 3202);
  const host = process.env.HOST ?? '0.0.0.0';

  await app.listen(port, host);

  const logger = app.get(AppLogger);
  logger.log(`FlowPlanV2 server listening on http://${host}:${port}/api`);
  logger.log(
    `Encryption key: ${
      process.env.FLOWPLANV2_ENCRYPTION_KEY
        ? 'configured'
        : 'NOT SET - set FLOWPLANV2_ENCRYPTION_KEY in the environment'
    }`,
  );
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
