import { Module } from '@nestjs/common';
import { AuthController } from './auth/auth.controller';
import { HealthController } from './health/health.controller';
import { SyncController } from './sync/sync.controller';
import { SyncService } from './sync/sync.service';
import { DevicesController } from './devices/devices.controller';
import { DatabaseService } from './database/database.service';
import { AuthService } from './auth/auth.service';
import { DevicesService } from './devices/devices.service';
import { AnalyticsController } from './analytics/analytics.controller';
import { AnalyticsService } from './analytics/analytics.service';
import { AdminController } from './admin/admin.controller';
import { AdminService } from './admin/admin.service';
import { FilesController } from './files/files.controller';
import { FilesService } from './files/files.service';
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
import { TrackingController } from './tracking/tracking.controller';
import { TrackingService } from './tracking/tracking.service';
import { WebController } from './web/web.controller';
import { WebService } from './web/web.service';
import { ModelsController } from './models/models.controller';
import { ModelsService } from './models/models.service';

@Module({
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
  ],
  providers: [
    DatabaseService,
    AuthService,
    DevicesService,
    SyncService,
    AnalyticsService,
    AdminService,
    FilesService,
    LocalObjectStorageService,
    KopiaService,
    AiService,
    ActivityUnderstandingService,
    SchedulerService,
    ReportsService,
    ClientService,
    TrackingService,
    WebService,
    ModelsService,
  ],
})
export class AppModule {}
