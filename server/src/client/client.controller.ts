import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { OutlookService } from '../outlook/outlook.service';
import { SyncPushDto } from '../sync/dto';
import { SyncService } from '../sync/sync.service';
import { WebService } from '../web/web.service';
import { ClientService } from './client.service';

@Controller('client')
export class ClientController {
  constructor(
    private readonly clientService: ClientService,
    private readonly webService: WebService,
    private readonly syncService: SyncService,
    private readonly outlookService: OutlookService,
  ) {}

  @Get('bootstrap')
  bootstrap(@Headers() headers: Record<string, unknown>) {
    return this.clientService.bootstrap(readRequestContext(headers));
  }

  @Get('settings')
  settings(@Headers() headers: Record<string, unknown>) {
    return this.clientService.settings(readRequestContext(headers));
  }

  @Get('settings/effective')
  effectiveSettings(@Headers() headers: Record<string, unknown>) {
    return this.clientService.effectiveSettings(readRequestContext(headers));
  }

  @Patch('settings/:key')
  updateSetting(
    @Param('key') key: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.clientService.updateSetting(key, body, readRequestContext(headers));
  }

  @Get('settings-policy')
  settingsPolicy() {
    return this.clientService.settingsPolicy();
  }

  @Get('tasks')
  tasks(
    @Query() query: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.tasks(query, readRequestContext(headers));
  }

  @Post('tasks')
  createTask(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.createTask(body, readRequestContext(headers));
  }

  @Patch('tasks/:id')
  updateTask(
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.updateTask(id, body, readRequestContext(headers));
  }

  @Post('tasks/:id/complete')
  completeTask(
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.completeTask(id, body, readRequestContext(headers));
  }

  @Delete('tasks/:id')
  deleteTask(
    @Param('id') id: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.deleteTask(id, readRequestContext(headers));
  }

  @Get('events')
  events(
    @Query() query: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.events(query, readRequestContext(headers));
  }

  @Post('events')
  createEvent(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.createEvent(body, readRequestContext(headers));
  }

  @Patch('events/:id')
  updateEvent(
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.updateEvent(id, body, readRequestContext(headers));
  }

  @Delete('events/:id')
  deleteEvent(
    @Param('id') id: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.deleteEvent(id, readRequestContext(headers));
  }

  @Get('actual-records')
  actualRecords(
    @Query() query: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.actualRecords(query, readRequestContext(headers));
  }

  @Post('mutations')
  pushMutations(
    @Body() body: SyncPushDto,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.syncService.push(body, readRequestContext(headers));
  }

  @Post('outlook/refresh')
  refreshOutlook(@Headers() headers: Record<string, unknown>) {
    return this.outlookService.syncNow(readRequestContext(headers), 'client');
  }

  @Post('import/local-snapshot')
  createLocalSnapshotImport(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.clientService.createLocalSnapshotImport(
      body,
      readRequestContext(headers),
    );
  }

  @Get('import/:importId')
  importStatus(
    @Param('importId') importId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.clientService.importStatus(importId, readRequestContext(headers));
  }

  @Post('import/:importId/confirm')
  confirmImport(
    @Param('importId') importId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.clientService.confirmImport(importId, readRequestContext(headers));
  }

  @Post('import/:importId/cancel')
  cancelImport(
    @Param('importId') importId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.clientService.cancelImport(
      importId,
      body,
      readRequestContext(headers),
    );
  }
}
