import { Body, Controller, Get, Headers, Param, Patch, Post } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { DevicesService } from './devices.service';

@Controller('devices')
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Post('register')
  register(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.devicesService.register(body, readRequestContext(headers));
  }

  @Get()
  list(@Headers() headers: Record<string, unknown>) {
    return this.devicesService.list(readRequestContext(headers));
  }

  @Patch(':deviceId')
  update(
    @Param('deviceId') deviceId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.devicesService.update(deviceId, body, readRequestContext(headers));
  }

  @Post(':deviceId/revoke')
  revoke(
    @Param('deviceId') deviceId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.devicesService.revoke(deviceId, body, readRequestContext(headers));
  }

  @Post(':deviceId/heartbeat')
  heartbeat(
    @Param('deviceId') deviceId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.devicesService.heartbeat(
      deviceId,
      body,
      readRequestContext(headers),
    );
  }
}
