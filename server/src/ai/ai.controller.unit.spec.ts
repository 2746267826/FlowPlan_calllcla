import { describe, expect, it, vi } from 'vitest';
import { AiController } from './ai.controller';

const headers = {
  'x-flowplanv2-user-id': '11111111-1111-4111-8111-111111111111',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

function mockAiService() {
  return new Proxy(
    {},
    {
      get(target, prop: string) {
        if (!(prop in target)) {
          (target as Record<string, unknown>)[prop] = vi.fn((...args: unknown[]) => ({
            method: prop,
            args,
          }));
        }
        return (target as Record<string, unknown>)[prop];
      },
    },
  ) as Record<string, ReturnType<typeof vi.fn>>;
}

describe('AiController', () => {
  it('forwards provider, context, and policy endpoints', () => {
    const service = mockAiService();
    const controller = new AiController(service as never);

    expect(controller.settings(headers)).toEqual({ method: 'settings', args: [context] });
    expect(controller.upsertProvider('openai', { model: 'gpt' }, headers)).toEqual({
      method: 'upsertProvider',
      args: ['openai', { model: 'gpt' }, context],
    });
    expect(controller.testProvider('openai', headers)).toEqual({
      method: 'testProvider',
      args: ['openai', context],
    });
    expect(controller.context(headers)).toEqual({ method: 'context', args: [context] });
    expect(controller.createContextSnapshot({ contextType: 'mixed' }, headers)).toEqual({
      method: 'createContextSnapshot',
      args: [{ contextType: 'mixed' }, context],
    });
    expect(controller.toolPolicies(headers)).toEqual({
      method: 'toolPolicies',
      args: [context],
    });
    expect(controller.upsertToolPolicy('create_task', { riskLevel: 'low' }, headers)).toEqual({
      method: 'upsertToolPolicy',
      args: ['create_task', { riskLevel: 'low' }, context],
    });
  });

  it('forwards conversation, message, and draft endpoints', () => {
    const service = mockAiService();
    const controller = new AiController(service as never);

    expect(controller.conversations({ status: 'open' }, headers)).toEqual({
      method: 'conversations',
      args: [{ status: 'open' }, context],
    });
    expect(controller.createConversation({ title: 'Plan' }, headers)).toEqual({
      method: 'createConversation',
      args: [{ title: 'Plan' }, context],
    });
    expect(controller.messages('conversation-1', headers)).toEqual({
      method: 'messages',
      args: ['conversation-1', context],
    });
    expect(controller.sendMessage({ content: 'hello' }, headers)).toEqual({
      method: 'sendMessage',
      args: [{ content: 'hello' }, context],
    });
    expect(controller.explainActivitySegment('segment-1', { prompt: 'why' }, headers)).toEqual({
      method: 'explainActivitySegment',
      args: ['segment-1', { prompt: 'why' }, context],
    });
    expect(controller.toolDrafts({ status: 'pending' }, headers)).toEqual({
      method: 'toolDrafts',
      args: [{ status: 'pending' }, context],
    });
    expect(controller.reviewDraft('draft-1', { status: 'approved' }, headers)).toEqual({
      method: 'reviewDraft',
      args: ['draft-1', { status: 'approved' }, context],
    });
    expect(controller.confirmDraft('draft-1', { confirmationToken: 'ok' }, headers)).toEqual({
      method: 'confirmDraft',
      args: ['draft-1', { confirmationToken: 'ok' }, context],
    });
  });

  it('uses default context when request headers do not contain valid UUIDs', () => {
    const service = mockAiService();
    const controller = new AiController(service as never);

    expect(controller.settings({ 'x-flowplanv2-device-id': 'not-a-uuid' })).toEqual({
      method: 'settings',
      args: [
        {
          userId: '00000000-0000-4000-8000-000000000001',
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
  });
});
