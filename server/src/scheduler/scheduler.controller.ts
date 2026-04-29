import { Body, Controller, Get, Headers, Param, Post } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { SchedulerService } from './scheduler.service';

@Controller('scheduler')
export class SchedulerController {
  constructor(private readonly schedulerService: SchedulerService) {}

  @Post('runs')
  createRun(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.createRun(body, readRequestContext(headers));
  }

  @Get('runs/:runId')
  run(
    @Param('runId') runId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.run(runId, readRequestContext(headers));
  }

  @Post('runs/:runId/accept')
  acceptRun(
    @Param('runId') runId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.acceptRun(runId, body, readRequestContext(headers));
  }

  @Post('runs/:runId/reject')
  rejectRun(
    @Param('runId') runId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.rejectRun(runId, body, readRequestContext(headers));
  }

  @Post('deviations/detect')
  detectDeviations(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.detectDeviations(body, readRequestContext(headers));
  }
}
