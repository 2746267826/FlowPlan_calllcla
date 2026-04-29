import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

const bodyParser = require('body-parser') as {
  json: (options: { limit: string }) => unknown;
  urlencoded: (options: { extended: boolean; limit: string }) => unknown;
};

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  const bodyLimit = process.env.FLOWPLAN_BODY_LIMIT ?? '50mb';
  app.use(bodyParser.json({ limit: bodyLimit }) as never);
  app.use(bodyParser.urlencoded({ extended: true, limit: bodyLimit }) as never);
  app.enableCors({
    origin: process.env.ADMIN_CORS_ORIGIN ?? true,
    credentials: false,
  });
  app.setGlobalPrefix('api');
  const port = Number(process.env.PORT ?? 3200);
  const host = process.env.HOST ?? '127.0.0.1';
  await app.listen(port, host);
  console.log(`FlowPlan server listening on http://${host}:${port}/api`);
}

bootstrap();
