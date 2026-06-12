import { describe, expect, it, vi } from 'vitest';
import { TrackingController } from './tracking.controller';

const headers = {
  'x-flowplanv2-user-id': ' 11111111-1111-4111-8111-111111111111 ',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

const defaultContext = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

const batchBody = { batchId: 'batch-1', chunks: 2 };
const query = { limit: '5', status: 'open' };
const chunkBody = { chunkIndex: 1, records: [{ id: 'record-1' }] };
const completeBody = { finalChunkIndex: 1 };

function mockTrackingService() {
  return new Proxy(
    {},
    {
      get(target, prop: string) {
        if (!(prop in target)) {
          (target as Record<string, unknown>)[prop] = vi.fn(async (...args: unknown[]) => ({
            method: prop,
            args,
          }));
        }
        return (target as Record<string, unknown>)[prop];
      },
    },
  ) as Record<string, ReturnType<typeof vi.fn>>;
}

const cases = [
  {
    controllerMethod: 'createBatch',
    serviceMethod: 'createBatch',
    invoke: (controller: TrackingController) => controller.createBatch(batchBody, headers),
    expectedArgs: [batchBody, context],
  },
  {
    controllerMethod: 'batches',
    serviceMethod: 'batches',
    invoke: (controller: TrackingController) => controller.batches(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'appendChunk',
    serviceMethod: 'appendChunk',
    invoke: (controller: TrackingController) => controller.appendChunk('batch-1', chunkBody, headers),
    expectedArgs: ['batch-1', chunkBody, context],
  },
  {
    controllerMethod: 'completeBatch',
    serviceMethod: 'completeBatch',
    invoke: (controller: TrackingController) => controller.completeBatch('batch-1', completeBody, headers),
    expectedArgs: ['batch-1', completeBody, context],
  },
  {
    controllerMethod: 'summary',
    serviceMethod: 'summary',
    invoke: (controller: TrackingController) => controller.summary(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'spoolStatus',
    serviceMethod: 'summary',
    invoke: (controller: TrackingController) => controller.spoolStatus(query, headers),
    expectedArgs: [query, context],
  },
];

describe('TrackingController', () => {
  it('has a delegation case for every public route method', () => {
    const publicMethods = Object.getOwnPropertyNames(TrackingController.prototype)
      .filter((name) => name !== 'constructor')
      .sort();

    expect(cases.map((testCase) => testCase.controllerMethod).sort()).toEqual(publicMethods);
  });

  it.each(cases)('forwards $controllerMethod to $serviceMethod with parsed request context', async (testCase) => {
    const service = mockTrackingService();
    const controller = new TrackingController(service as never);

    await expect(testCase.invoke(controller)).resolves.toEqual({
      method: testCase.serviceMethod,
      args: testCase.expectedArgs,
    });
    expect(service[testCase.serviceMethod]).toHaveBeenCalledWith(...testCase.expectedArgs);
  });

  it('uses the default request context when headers are invalid or absent', async () => {
    const service = mockTrackingService();
    const controller = new TrackingController(service as never);

    await expect(
      controller.batches(query, {
        'x-flowplanv2-user-id': 'not-a-uuid',
        'x-flowplanv2-device-id': ['still-not-a-uuid'],
      }),
    ).resolves.toEqual({
      method: 'batches',
      args: [query, defaultContext],
    });
  });

  it('passes raw batch ids and DTO objects to ingest endpoints without cloning or coercing', async () => {
    const service = {
      appendChunk: vi.fn(async () => ({ acceptedRecords: 1 })),
      completeBatch: vi.fn(async () => ({ completed: true })),
    };
    const controller = new TrackingController(service as never);
    const chunk = { chunkIndex: '003', records: [{ id: 'record-1', durationMs: 12 }] };
    const complete = { completedAt: '2026-06-08T00:00:00.000Z' };

    await expect(controller.appendChunk('batch-001', chunk, headers)).resolves.toEqual({
      acceptedRecords: 1,
    });
    await expect(controller.completeBatch('batch-001', complete, headers)).resolves.toEqual({
      completed: true,
    });
    expect(service.appendChunk.mock.calls[0]).toEqual(['batch-001', chunk, context]);
    expect(service.appendChunk.mock.calls[0][1]).toBe(chunk);
    expect(service.completeBatch.mock.calls[0]).toEqual(['batch-001', complete, context]);
    expect(service.completeBatch.mock.calls[0][1]).toBe(complete);
  });

  it('maps spool status to the summary service with the parsed query and context', async () => {
    const service = {
      summary: vi.fn(async () => ({ batchesPending: 2 })),
    };
    const controller = new TrackingController(service as never);
    const spoolQuery = { since: '2026-06-08T00:00:00.000Z', limit: '10' };

    await expect(controller.spoolStatus(spoolQuery, headers)).resolves.toEqual({
      batchesPending: 2,
    });
    expect(service.summary).toHaveBeenCalledWith(spoolQuery, context);
    expect(service.summary.mock.calls[0][0]).toBe(spoolQuery);
  });

  it('passes service errors through without wrapping them', async () => {
    const service = mockTrackingService();
    const controller = new TrackingController(service as never);
    const error = new Error('batch append failed');
    service.appendChunk.mockRejectedValueOnce(error);

    await expect(controller.appendChunk('batch-1', chunkBody, headers)).rejects.toBe(error);
  });
});
