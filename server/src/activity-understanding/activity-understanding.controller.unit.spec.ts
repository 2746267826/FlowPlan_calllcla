import { describe, expect, it, vi } from 'vitest';
import { ActivityUnderstandingController } from './activity-understanding.controller';

const headers = {
  'x-flowplanv2-user-id': '11111111-1111-4111-8111-111111111111',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

function mockActivityUnderstandingService() {
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

describe('ActivityUnderstandingController', () => {
  it('forwards build aliases and segment list queries', () => {
    const service = mockActivityUnderstandingService();
    const controller = new ActivityUnderstandingController(service as never);

    expect(controller.buildSegments({ date: '2026-06-08' }, headers)).toEqual({
      method: 'buildSegments',
      args: [{ date: '2026-06-08' }, context],
    });
    expect(controller.build({ rebuild: true }, headers)).toEqual({
      method: 'buildSegments',
      args: [{ rebuild: true }, context],
    });
    expect(controller.segments({ status: 'candidate', limit: '20' }, headers)).toEqual({
      method: 'segments',
      args: [{ status: 'candidate', limit: '20' }, context],
    });
  });

  it('forwards review, split, and merge actions with route params and bodies', () => {
    const service = mockActivityUnderstandingService();
    const controller = new ActivityUnderstandingController(service as never);

    expect(controller.confirm('segment-1', { taskId: 'task-1' }, headers)).toEqual({
      method: 'confirmSegment',
      args: ['segment-1', { taskId: 'task-1' }, context],
    });
    expect(controller.reject('segment-1', { reason: 'wrong task' }, headers)).toEqual({
      method: 'rejectSegment',
      args: ['segment-1', { reason: 'wrong task' }, context],
    });
    expect(controller.feedback('segment-1', { feedbackType: 'modified' }, headers)).toEqual({
      method: 'feedback',
      args: ['segment-1', { feedbackType: 'modified' }, context],
    });
    expect(controller.splitSegment('segment-1', { splitAt: '2026-06-08T10:00:00Z' }, headers)).toEqual({
      method: 'splitSegment',
      args: ['segment-1', { splitAt: '2026-06-08T10:00:00Z' }, context],
    });
    expect(controller.mergeSegments({ segmentIds: ['segment-1', 'segment-2'] }, headers)).toEqual({
      method: 'mergeSegments',
      args: [{ segmentIds: ['segment-1', 'segment-2'] }, context],
    });
  });

  it('uses default request context for invalid headers', () => {
    const service = mockActivityUnderstandingService();
    const controller = new ActivityUnderstandingController(service as never);

    expect(controller.segments({}, { 'x-flowplanv2-user-id': 'bad' })).toEqual({
      method: 'segments',
      args: [
        {},
        {
          userId: '00000000-0000-4000-8000-000000000001',
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
  });
});
