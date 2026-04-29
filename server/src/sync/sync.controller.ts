import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { ResolveConflictDto, SyncAckDto, SyncPushDto } from './dto';
import { SyncService } from './sync.service';

@Controller('sync')
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  @Post('push')
  push(
    @Body() dto: SyncPushDto,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.syncService.push(dto, readRequestContext(headers));
  }

  @Get('pull')
  pull(
    @Query('cursor') cursor: string | undefined,
    @Query('objectType') objectType: string | undefined,
    @Query('limit') limit: string | undefined,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.syncService.pull(cursor, readRequestContext(headers), {
      objectType,
      limit,
    });
  }

  @Post('ack')
  ack(
    @Body() dto: SyncAckDto,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.syncService.ack(dto, readRequestContext(headers));
  }

  @Get('conflicts')
  conflicts(@Headers() headers: Record<string, unknown>) {
    return this.syncService.conflicts(readRequestContext(headers));
  }

  @Get('status')
  status(@Headers() headers: Record<string, unknown>) {
    return this.syncService.status(readRequestContext(headers));
  }

  @Post('conflicts/:conflictId/resolve')
  resolveConflict(
    @Param('conflictId') conflictId: string,
    @Body() dto: ResolveConflictDto,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.syncService.resolveConflict(
      conflictId,
      dto,
      readRequestContext(headers),
    );
  }
}
