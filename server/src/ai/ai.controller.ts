import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { AiQuery, AiService } from './ai.service';

@Controller('ai')
export class AiController {
  constructor(private readonly aiService: AiService) {}

  @Get('settings')
  settings(@Headers() headers: Record<string, unknown>) {
    return this.aiService.settings(readRequestContext(headers));
  }

  @Patch('settings/:providerKey')
  upsertProvider(
    @Param('providerKey') providerKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.upsertProvider(
      providerKey,
      body,
      readRequestContext(headers),
    );
  }

  @Post('settings/:providerKey/test')
  testProvider(
    @Param('providerKey') providerKey: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.testProvider(providerKey, readRequestContext(headers));
  }

  @Get('context')
  context(@Headers() headers: Record<string, unknown>) {
    return this.aiService.context(readRequestContext(headers));
  }

  @Post('context/snapshots')
  createContextSnapshot(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.createContextSnapshot(body, readRequestContext(headers));
  }

  @Get('tool-policies')
  toolPolicies(@Headers() headers: Record<string, unknown>) {
    return this.aiService.toolPolicies(readRequestContext(headers));
  }

  @Patch('tool-policies/:toolName')
  upsertToolPolicy(
    @Param('toolName') toolName: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.upsertToolPolicy(
      toolName,
      body,
      readRequestContext(headers),
    );
  }

  @Get('conversations')
  conversations(
    @Query() query: AiQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.conversations(query, readRequestContext(headers));
  }

  @Post('conversations')
  createConversation(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.createConversation(body, readRequestContext(headers));
  }

  @Get('conversations/:conversationId/messages')
  messages(
    @Param('conversationId') conversationId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.messages(conversationId, readRequestContext(headers));
  }

  @Post('messages')
  sendMessage(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.sendMessage(body, readRequestContext(headers));
  }

  @Post('activity-segments/:segmentId/explain')
  explainActivitySegment(
    @Param('segmentId') segmentId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.explainActivitySegment(
      segmentId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('tool-drafts')
  toolDrafts(
    @Query() query: AiQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.toolDrafts(query, readRequestContext(headers));
  }

  @Patch('tool-drafts/:draftId')
  reviewDraft(
    @Param('draftId') draftId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.reviewDraft(
      draftId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('tool-drafts/:draftId/confirm')
  confirmDraft(
    @Param('draftId') draftId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.aiService.confirmDraft(
      draftId,
      body,
      readRequestContext(headers),
    );
  }
}
