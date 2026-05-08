import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { OutlookService } from '../outlook/outlook.service';
import { ResolveConflictDto } from '../sync/dto';
import { SyncService } from '../sync/sync.service';
import { AdminService, AdminQuery } from './admin.service';

@Controller('admin')
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly syncService: SyncService,
    private readonly outlookService: OutlookService,
  ) {}

  @Get('overview')
  overview(@Headers() headers: Record<string, unknown>) {
    return this.adminService.overview(readRequestContext(headers));
  }

  @Get('dashboard')
  dashboard(@Headers() headers: Record<string, unknown>) {
    return this.adminService.dashboard(readRequestContext(headers));
  }

  @Get('sync-health')
  syncHealth(@Headers() headers: Record<string, unknown>) {
    return this.adminService.syncHealth(readRequestContext(headers));
  }

  @Get('data/:domain')
  adminData(
    @Param('domain') domain: string,
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.adminData(
      domain,
      query,
      readRequestContext(headers),
    );
  }

  @Get('data/:domain/:id')
  adminDataDetail(
    @Param('domain') domain: string,
    @Param('id') id: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.adminDataDetail(
      domain,
      id,
      readRequestContext(headers),
    );
  }

  @Get('devices/online-summary')
  deviceOnlineSummary(@Headers() headers: Record<string, unknown>) {
    return this.adminService.deviceOnlineSummary(readRequestContext(headers));
  }

  @Get('new-info')
  newInfo(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.newInfo(query, readRequestContext(headers));
  }

  @Get('devices/:deviceId/connection-history')
  deviceConnectionHistory(
    @Param('deviceId') deviceId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.deviceConnectionHistory(
      deviceId,
      readRequestContext(headers),
    );
  }

  @Patch('data/:domain/:id')
  updateAdminData(
    @Param('domain') domain: string,
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.updateAdminData(
      domain,
      id,
      body,
      readRequestContext(headers),
    );
  }

  @Get('settings')
  adminSettings(@Headers() headers: Record<string, unknown>) {
    return this.adminService.adminSettings(readRequestContext(headers));
  }

  @Patch('settings/:configKey')
  upsertAdminSetting(
    @Param('configKey') configKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.upsertRemoteConfig(
      configKey,
      body,
      readRequestContext(headers),
    );
  }

  @Get('monitoring/health')
  monitoringHealth(@Headers() headers: Record<string, unknown>) {
    return this.adminService.monitoringHealth(readRequestContext(headers));
  }

  @Get('monitoring/logs')
  monitoringLogs(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.monitoringLogs(query, readRequestContext(headers));
  }

  @Get('monitoring/jobs')
  monitoringJobs(@Headers() headers: Record<string, unknown>) {
    return this.adminService.monitoringJobs(readRequestContext(headers));
  }

  @Post('operations/:operationKey/prepare')
  prepareOperation(
    @Param('operationKey') operationKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.prepareOperation(
      operationKey,
      body,
      readRequestContext(headers),
    );
  }

  @Post('operations/:operationKey/confirm')
  confirmOperation(
    @Param('operationKey') operationKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.confirmOperation(
      operationKey,
      body,
      readRequestContext(headers),
    );
  }

  @Get('objects')
  objects(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.objects(query, readRequestContext(headers));
  }

  @Patch('objects/:objectId')
  updateObject(
    @Param('objectId') objectId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.updateObject(
      objectId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('actual-records')
  actualRecords(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.actualRecords(query, readRequestContext(headers));
  }

  @Patch('actual-records/:actualId')
  updateActualRecord(
    @Param('actualId') actualId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.updateActualRecord(
      actualId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('files')
  files(@Query() query: AdminQuery, @Headers() headers: Record<string, unknown>) {
    return this.adminService.files(query, readRequestContext(headers));
  }

  @Patch('files/:fileId')
  updateFile(
    @Param('fileId') fileId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.updateFile(fileId, body, readRequestContext(headers));
  }

  @Get('conflicts')
  conflicts(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.conflicts(query, readRequestContext(headers));
  }

  @Post('conflicts/:conflictId/resolve')
  async resolveConflict(
    @Param('conflictId') conflictId: string,
    @Body() dto: ResolveConflictDto,
    @Headers() headers: Record<string, unknown>,
  ) {
    const context = readRequestContext(headers);
    const result = await this.syncService.resolveConflict(conflictId, dto, context);
    await this.adminService.recordAdminAction(context, 'admin.conflict.resolve', {
      conflictId,
      strategy: dto.strategy,
    });
    return result;
  }

  @Get('outlook')
  outlook(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.status(readRequestContext(headers));
  }

  @Get('outlook/status')
  outlookStatus(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.status(readRequestContext(headers));
  }

  @Post('outlook/auth/start')
  outlookAuthStart(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.outlookService.startAuth(body, readRequestContext(headers));
  }

  @Post('outlook/auth/complete')
  outlookAuthComplete(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.outlookService.completeAuth(body, readRequestContext(headers));
  }

  @Post('outlook/token-secret')
  outlookTokenSecret(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.outlookService.saveTokenSecret(body, readRequestContext(headers));
  }

  @Post('outlook/sync')
  outlookSync(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.syncNow(readRequestContext(headers), 'admin');
  }

  @Post('outlook/reset')
  outlookReset(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.reset(readRequestContext(headers));
  }

  @Post('outlook/drafts/prepare')
  outlookPrepareWrite(@Body() body: Record<string, unknown>, @Headers() headers: Record<string, unknown>) {
    return this.outlookService.prepareWrite(body, readRequestContext(headers));
  }

  @Get('outlook/drafts')
  outlookDrafts(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.drafts(readRequestContext(headers));
  }

  @Post('outlook/drafts/:draftId/confirm')
  outlookConfirmWrite(
    @Param('draftId') draftId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.outlookService.confirmWrite(draftId, body, readRequestContext(headers));
  }

  @Post('outlook/drafts/:draftId/reject')
  outlookRejectWrite(
    @Param('draftId') draftId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.outlookService.rejectWrite(draftId, body, readRequestContext(headers));
  }

  @Get('alerts')
  alerts(@Headers() headers: Record<string, unknown>) {
    const ctx = readRequestContext(headers);
    return this.adminService.alerts(ctx.userId);
  }

  @Get('outlook/calendars')
  outlookCalendars(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.calendars(readRequestContext(headers));
  }

  @Get('outlook/runs')
  outlookRuns(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.runs(readRequestContext(headers));
  }

  @Get('outlook/diagnostics')
  outlookDiagnostics(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.diagnostics(readRequestContext(headers));
  }

  @Get('audit-logs')
  auditLogs(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.auditLogs(query, readRequestContext(headers));
  }

  @Get('reports')
  reports(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.reports(query, readRequestContext(headers));
  }

  @Get('push-deliveries')
  pushDeliveries(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.pushDeliveries(query, readRequestContext(headers));
  }

  @Get('ai-drafts')
  aiDrafts(
    @Query() query: AdminQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.aiDrafts(query, readRequestContext(headers));
  }

  @Patch('ai-drafts/:draftId')
  updateAiDraft(
    @Param('draftId') draftId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.updateAiDraft(
      draftId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('jobs')
  jobs(@Headers() headers: Record<string, unknown>) {
    return this.adminService.jobs(readRequestContext(headers));
  }

  @Patch('jobs/:jobKey')
  upsertJob(
    @Param('jobKey') jobKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.upsertJob(jobKey, body, readRequestContext(headers));
  }

  @Get('remote-configs')
  remoteConfigs(@Headers() headers: Record<string, unknown>) {
    return this.adminService.remoteConfigs(readRequestContext(headers));
  }

  @Patch('remote-configs/:configKey')
  upsertRemoteConfig(
    @Param('configKey') configKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.adminService.upsertRemoteConfig(
      configKey,
      body,
      readRequestContext(headers),
    );
  }
}
