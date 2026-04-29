import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { ClientService } from './client.service';

@Controller('client')
export class ClientController {
  constructor(private readonly clientService: ClientService) {}

  @Get('bootstrap')
  bootstrap(@Headers() headers: Record<string, unknown>) {
    return this.clientService.bootstrap(readRequestContext(headers));
  }

  @Get('settings')
  settings(@Headers() headers: Record<string, unknown>) {
    return this.clientService.settings(readRequestContext(headers));
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
