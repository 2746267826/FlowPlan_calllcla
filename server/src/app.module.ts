import { Module, ValidationPipe } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { resolve } from 'node:path';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerModule } from '@nestjs/throttler';
import { loadConfig } from './common/config/app-config';
import { AuthController } from './auth/auth.controller';
import { AuthService } from './auth/auth.service';
import { JwtStrategy } from './auth/jwt.strategy';
import { JwtAuthGuard } from './auth/jwt-auth.guard';
import { JwtInterceptor } from './auth/jwt.interceptor';
import { AppLogger } from './common/logger/app-logger.service';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';
import { RequestLogInterceptor } from './common/interceptors/request-log.interceptor';
import { HealthController } from './health/health.controller';
import { SyncController } from './sync/sync.controller';
import { SyncService } from './sync/sync.service';
import { DevicesController } from './devices/devices.controller';
import { DatabaseService } from './database/database.service';
import { DevicesService } from './devices/devices.service';
import { AnalyticsController } from './analytics/analytics.controller';
import { AnalyticsService } from './analytics/analytics.service';
import { AdminController } from './admin/admin.controller';
import { AdminService } from './admin/admin.service';
import { FilesController } from './files/files.controller';
import { FileTreeService } from './files/file-tree.service';
import { FileTransferService } from './files/file-transfer.service';
import { FilesService } from './files/files.service';
import { FileVersionService } from './files/file-version.service';
import { KopiaService } from './files/kopia.service';
import { LocalObjectStorageService } from './files/local-object-storage.service';
import { AiController } from './ai/ai.controller';
import { AiService } from './ai/ai.service';
import { ActivityUnderstandingController } from './activity-understanding/activity-understanding.controller';
import { ActivityUnderstandingService } from './activity-understanding/activity-understanding.service';
import { ActivityController } from './activity/activity.controller';
import { ClientController } from './client/client.controller';
import { ClientService } from './client/client.service';
import { ReportsController } from './reports/reports.controller';
import { ReportsService } from './reports/reports.service';
import { SchedulerController } from './scheduler/scheduler.controller';
import { SchedulerService } from './scheduler/scheduler.service';
import { GeneticSchedulerService } from './scheduler/genetic-scheduler.service';
import { DependencyGraphService } from './scheduler/dependency-graph.service';
import { CronJobsService } from './scheduler/cron-jobs.service';
import { CronJobsController } from './scheduler/cron-jobs.controller';
import { TrackingController } from './tracking/tracking.controller';
import { TrackingService } from './tracking/tracking.service';
import { WebController } from './web/web.controller';
import { WebService } from './web/web.service';
import { ModelsController } from './models/models.controller';
import { ModelsService } from './models/models.service';
import { OutlookService } from './outlook/outlook.service';
import { GraphClientService } from './outlook/graph-client.service';
import { AuditService } from './common/audit/audit.service';
import { SyncObjectRepository } from './common/repositories/sync-object.repository';
import { VectorService } from './common/utils/vector.service';

const appConfig = loadConfig();

@Module({
  imports: [
    ScheduleModule.forRoot(),
    ConfigModule.forRoot({ isGlobal: true, envFilePath: resolve(__dirname, '.env'), load: [loadConfig] }),
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get('jwtAccessSecret', appConfig.jwtAccessSecret),
        signOptions: { expiresIn: config.get('jwtAccessExpires', '24h') },
      }),
    }),
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 100,
      },
    ]),
  ],
  controllers: [
    HealthController,
    AuthController,
    DevicesController,
    SyncController,
    AnalyticsController,
    AdminController,
    FilesController,
    AiController,
    ActivityUnderstandingController,
    ActivityController,
    SchedulerController,
    ReportsController,
    ClientController,
    TrackingController,
    WebController,
    ModelsController,
    CronJobsController,
  ],
  providers: [
    AppLogger,
    DatabaseService,
    AuthService,
    JwtStrategy,
    JwtAuthGuard,
    JwtInterceptor,
    {
      provide: APP_INTERCEPTOR,
      useClass: JwtInterceptor,
    },
    {
      provide: APP_INTERCEPTOR,
      useClass: RequestLogInterceptor,
    },
    {
      provide: APP_FILTER,
      useClass: GlobalExceptionFilter,
    },
    {
      provide: APP_PIPE,
      useFactory: () =>
        new ValidationPipe({
          whitelist: true,
          transform: true,
          forbidNonWhitelisted: false,
        }),
    },
    DevicesService,
    SyncService,
    AnalyticsService,
    AdminService,
    FilesService,
    FileTreeService,
    FileTransferService,
    FileVersionService,
    LocalObjectStorageService,
    KopiaService,
    AiService,
    ActivityUnderstandingService,
    SchedulerService,
    GeneticSchedulerService,
    DependencyGraphService,
    CronJobsService,
    ReportsService,
    ClientService,
    TrackingService,
    WebService,
    ModelsService,
    OutlookService,
    GraphClientService,
    AuditService,
    SyncObjectRepository,
    VectorService,
  ],
})
export class AppModule {}
