import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../../app.module';
import { configureApp } from '../../app.bootstrap';
import { DatabaseService } from '../../database/database.service';

export async function createApiTestApp(): Promise<{
  app: INestApplication;
  db: DatabaseService;
  request: ReturnType<typeof request>;
}> {
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleRef.createNestApplication({ bodyParser: false });
  configureApp(app);
  await app.init();

  const db = app.get(DatabaseService);

  return {
    app,
    db,
    request: request(app.getHttpServer()),
  };
}
