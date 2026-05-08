import 'reflect-metadata';
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

  // Swagger / OpenAPI
  const swaggerConfig = new DocumentBuilder()
    .setTitle('FlowPlanV2 API')
    .setDescription('个人数据管理系统 — 日历、任务、追踪、文件、报告、同步、AI')
    .setVersion('1.5.0')
    .addBearerAuth()
    .build();
  const swaggerDoc = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, swaggerDoc);

  const port = Number(process.env.PORT ?? 3202);
  const host = process.env.HOST ?? '0.0.0.0';

  await app.listen(port, host);

  const logger = app.get(AppLogger);
  logger.log(`FlowPlanV2 server listening on http://${host}:${port}/api`);
}

bootstrap().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  // Use console here because DI is not available during bootstrap failure.
  console.error('FlowPlanV2 server startup failed.');
  console.error(message);
  console.error(
    [
      'Startup checklist:',
      '1. Copy flowplanv2.local.env.example to flowplanv2.local.env and set FLOWPLANV2_DATABASE_URL.',
      '2. Confirm PostgreSQL is running and reachable from FLOWPLANV2_DATABASE_URL.',
      '3. Run: cd server; npm run db:schema',
      '4. Run: cd server; npm run dev',
    ].join('\n'),
  );
  process.exit(1);
});
