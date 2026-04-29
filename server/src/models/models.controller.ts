import { Body, Controller, Get, Headers, Param, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { ModelsService } from './models.service';

@Controller('models')
export class ModelsController {
  constructor(private readonly modelsService: ModelsService) {}

  @Get()
  list(@Headers() headers: Record<string, unknown>) {
    return this.modelsService.list(readRequestContext(headers));
  }

  @Get('llm/health')
  llmHealth(@Headers() headers: Record<string, unknown>) {
    return this.modelsService.llmHealth(readRequestContext(headers));
  }

  @Get(':modelKey/versions')
  versions(
    @Param('modelKey') modelKey: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.modelsService.versions(modelKey, readRequestContext(headers));
  }

  @Get(':modelKey/runs')
  runs(
    @Param('modelKey') modelKey: string,
    @Query() query: Record<string, string | undefined>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.modelsService.runs(modelKey, query, readRequestContext(headers));
  }

  @Post(':modelKey/feedback')
  feedback(
    @Param('modelKey') modelKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.modelsService.feedback(modelKey, body, readRequestContext(headers));
  }

  @Post(':modelKey/evaluate')
  evaluate(
    @Param('modelKey') modelKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.modelsService.evaluate(modelKey, body, readRequestContext(headers));
  }

  @Post(':modelKey/learn')
  learn(
    @Param('modelKey') modelKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.modelsService.learn(modelKey, body, readRequestContext(headers));
  }

  @Post(':modelKey/versions/:versionId/activate')
  activate(
    @Param('modelKey') modelKey: string,
    @Param('versionId') versionId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.modelsService.activate(modelKey, versionId, body, readRequestContext(headers));
  }
}
