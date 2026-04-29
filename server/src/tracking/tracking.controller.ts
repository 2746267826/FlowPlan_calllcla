import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { TrackingIngestQuery, TrackingService } from './tracking.service';

@Controller('tracking')
export class TrackingController {
  constructor(private readonly trackingService: TrackingService) {}

  @Post('ingest/batches')
  createBatch(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.trackingService.createBatch(body, readRequestContext(headers));
  }

  @Get('ingest/batches')
  batches(
    @Query() query: TrackingIngestQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.trackingService.batches(query, readRequestContext(headers));
  }

  @Post('ingest/batches/:batchId/chunks')
  appendChunk(
    @Param('batchId') batchId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.trackingService.appendChunk(
      batchId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('ingest/batches/:batchId/complete')
  completeBatch(
    @Param('batchId') batchId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.trackingService.completeBatch(
      batchId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('summary')
  summary(
    @Query() query: TrackingIngestQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.trackingService.summary(query, readRequestContext(headers));
  }
}
