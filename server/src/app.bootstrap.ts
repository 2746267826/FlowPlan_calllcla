import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

const bodyParser = require('body-parser') as {
  json: (options: { limit: string }) => unknown;
  urlencoded: (options: { extended: boolean; limit: string }) => unknown;
};

export function configureApp<TApp extends INestApplication>(app: TApp): TApp {
  const bodyLimit = process.env.FLOWPLANV2_BODY_LIMIT ?? '50mb';

  app.use(bodyParser.json({ limit: bodyLimit }) as never);
  app.use(bodyParser.urlencoded({ extended: true, limit: bodyLimit }) as never);
  app.enableCors({
    origin: process.env.ADMIN_CORS_ORIGIN ?? true,
    credentials: false,
  });
  app.setGlobalPrefix('api');
  app.enableShutdownHooks();

  const swaggerConfig = new DocumentBuilder()
    .setTitle('FlowPlanV2 API')
    .setDescription('个人数据管理系统 — 日历、任务、追踪、文件、报告、同步、AI')
    .setVersion('2.0.0')
    .addBearerAuth()
    .build();
  const swaggerDoc = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, swaggerDoc);

  return app;
}
