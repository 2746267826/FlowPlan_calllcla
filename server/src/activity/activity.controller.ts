import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import {
  ActivityUnderstandingQuery,
  ActivityUnderstandingService,
} from '../activity-understanding/activity-understanding.service';

@Controller('activity')
export class ActivityController {
  constructor(private readonly service: ActivityUnderstandingService) {}

  @Get('segments')
  segments(
    @Query() query: ActivityUnderstandingQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.segments(query, readRequestContext(headers));
  }

  @Post('segments/:segmentId/confirm')
  confirm(
    @Param('segmentId') segmentId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.confirmSegment(segmentId, body, readRequestContext(headers));
  }

  @Post('segments/:segmentId/reject')
  reject(
    @Param('segmentId') segmentId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.rejectSegment(segmentId, body, readRequestContext(headers));
  }
}
