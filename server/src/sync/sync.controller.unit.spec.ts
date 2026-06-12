import { describe, expect, it, vi } from 'vitest';
import { SyncController } from './sync.controller';

const userId = '11111111-1111-4111-8111-111111111111';
const deviceId = '22222222-2222-4222-8222-222222222222';
const context = { userId, deviceId };
const defaultContext = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function createController() {
  const syncService = {
    push: vi.fn((...args: unknown[]) => ({ method: 'push', args })),
    pull: vi.fn((...args: unknown[]) => ({ method: 'pull', args })),
    ack: vi.fn((...args: unknown[]) => ({ method: 'ack', args })),
    conflicts: vi.fn((...args: unknown[]) => ({ method: 'conflicts', args })),
    status: vi.fn((...args: unknown[]) => ({ method: 'status', args })),
    resolveConflict: vi.fn((...args: unknown[]) => ({
      method: 'resolveConflict',
      args,
    })),
    health: vi.fn((...args: unknown[]) => ({ method: 'health', args })),
    purgeStaleMutations: vi.fn((...args: unknown[]) => ({
      method: 'purgeStaleMutations',
      args,
    })),
  };
  return {
    controller: new SyncController(syncService as never),
    syncService,
  };
}

describe('SyncController', () => {
  it('forwards every sync route to the service with parsed request context', () => {
    const { controller } = createController();
    const headers = {
      'x-flowplanv2-user-id': ` ${userId} `,
      'x-flowplanv2-device-id': ` ${deviceId} `,
    };
    const pushDto = {
      mutations: [
        {
          mutationUid: 'mutation-1',
          objectType: 'task_item',
          localId: 'local-1',
          action: 'upsert' as const,
          payload: { title: 'Task' },
        },
      ],
    };
    const ackDto = { cursor: '42', appliedChangeIds: ['41', '42'] };
    const resolveDto = {
      strategy: 'merge' as const,
      payload: { title: 'Merged' },
    };

    expect(controller.push(pushDto, headers)).toEqual({
      method: 'push',
      args: [pushDto, context],
    });
    expect(controller.pull('10', ' task_item ', '25', headers)).toEqual({
      method: 'pull',
      args: ['10', context, { objectType: ' task_item ', limit: '25' }],
    });
    expect(controller.ack(ackDto, headers)).toEqual({
      method: 'ack',
      args: [ackDto, context],
    });
    expect(controller.conflicts(headers)).toEqual({
      method: 'conflicts',
      args: [context],
    });
    expect(controller.status(headers)).toEqual({
      method: 'status',
      args: [context],
    });
    expect(controller.resolveConflict('conflict-1', resolveDto, headers)).toEqual({
      method: 'resolveConflict',
      args: ['conflict-1', resolveDto, context],
    });
    expect(controller.health(headers)).toEqual({
      method: 'health',
      args: [context],
    });
    expect(controller.purgeStale(45, headers)).toEqual({
      method: 'purgeStaleMutations',
      args: [context, 45],
    });
  });

  it('uses array headers and defaults invalid or missing request context values', () => {
    const { controller } = createController();

    expect(
      controller.conflicts({
        'x-flowplanv2-user-id': [userId],
        'x-flowplanv2-device-id': [deviceId],
      }),
    ).toEqual({
      method: 'conflicts',
      args: [context],
    });

    expect(
      controller.status({
        'x-flowplanv2-user-id': 'not-a-uuid',
        'x-flowplanv2-device-id': '',
      }),
    ).toEqual({
      method: 'status',
      args: [defaultContext],
    });

    expect(controller.purgeStale(undefined, {})).toEqual({
      method: 'purgeStaleMutations',
      args: [defaultContext, undefined],
    });
  });
});
