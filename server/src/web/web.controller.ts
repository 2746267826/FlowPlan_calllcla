import { Body, Controller, Get, Headers, Param, Patch, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { WebService } from './web.service';

@Controller('web')
export class WebController {
  constructor(private readonly webService: WebService) {}

  @Get('dashboard')
  dashboard(@Headers() headers: Record<string, unknown>) {
    return this.webService.dashboard(readRequestContext(headers));
  }

  @Get('tasks')
  tasks(@Query() query: Record<string, unknown>, @Headers() headers: Record<string, unknown>) {
    return this.webService.tasks(query, readRequestContext(headers));
  }

  @Post('tasks')
  createTask(@Body() body: Record<string, unknown>, @Headers() headers: Record<string, unknown>) {
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

  @Get('events')
  events(@Query() query: Record<string, unknown>, @Headers() headers: Record<string, unknown>) {
    return this.webService.events(query, readRequestContext(headers));
  }

  @Post('events')
  createEvent(@Body() body: Record<string, unknown>, @Headers() headers: Record<string, unknown>) {
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

  @Get('actual-records')
  actualRecords(@Query() query: Record<string, unknown>, @Headers() headers: Record<string, unknown>) {
    return this.webService.actualRecords(query, readRequestContext(headers));
  }

  @Get('reminders')
  reminders(@Headers() headers: Record<string, unknown>) {
    return this.webService.reminders(readRequestContext(headers));
  }

  @Post('operations/:operationKey/prepare')
  prepareOperation(
    @Param('operationKey') operationKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.prepareOperation(operationKey, body, readRequestContext(headers));
  }

  @Post('operations/:operationKey/confirm')
  confirmOperation(
    @Param('operationKey') operationKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.webService.confirmOperation(operationKey, body, readRequestContext(headers));
  }
}
