import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import {
  ActivityUnderstandingQuery,
  ActivityUnderstandingService,
} from './activity-understanding.service';

@Controller('activity-understanding')
export class ActivityUnderstandingController {
  constructor(private readonly service: ActivityUnderstandingService) {}

  @Post('build-segments')
  buildSegments(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.buildSegments(body, readRequestContext(headers));
  }

  @Post('build')
  build(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.buildSegments(body, readRequestContext(headers));
  }

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

  @Post('segments/:segmentId/feedback')
  feedback(
    @Param('segmentId') segmentId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.feedback(segmentId, body, readRequestContext(headers));
  }

  @Post('segments/:segmentId/split')
  splitSegment(
    @Param('segmentId') segmentId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.splitSegment(segmentId, body, readRequestContext(headers));
  }

  @Post('segments/merge')
  mergeSegments(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.service.mergeSegments(body, readRequestContext(headers));
  }
}
