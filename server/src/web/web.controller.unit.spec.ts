import { describe, expect, it, vi } from 'vitest';
import { WebController } from './web.controller';

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

const taskQuery = { status: 'open', limit: '5' };
const taskBody = { title: 'Plan release', priority: 'high' };
const eventQuery = { from: '2026-06-08T00:00:00.000Z', limit: '3' };
const eventBody = { title: 'Design review', startAt: '2026-06-08T09:00:00.000Z' };
const actualQuery = { from: '2026-06-01T00:00:00.000Z' };
const operationBody = { targetId: 'task-1', confirmationToken: 'token-1' };

function mockWebService() {
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

const completeBody = { completedAt: 'now' };

const cases = [
  {
    controllerMethod: 'dashboard',
    serviceMethod: 'dashboard',
    invoke: (controller: WebController) => controller.dashboard(headers),
    expectedArgs: [context],
  },
  {
    controllerMethod: 'tasks',
    serviceMethod: 'tasks',
    invoke: (controller: WebController) => controller.tasks(taskQuery, headers),
    expectedArgs: [taskQuery, context],
  },
  {
    controllerMethod: 'createTask',
    serviceMethod: 'createTask',
    invoke: (controller: WebController) => controller.createTask(taskBody, headers),
    expectedArgs: [taskBody, context],
  },
  {
    controllerMethod: 'updateTask',
    serviceMethod: 'updateTask',
    invoke: (controller: WebController) => controller.updateTask('task-1', taskBody, headers),
    expectedArgs: ['task-1', taskBody, context],
  },
  {
    controllerMethod: 'events',
    serviceMethod: 'events',
    invoke: (controller: WebController) => controller.events(eventQuery, headers),
    expectedArgs: [eventQuery, context],
  },
  {
    controllerMethod: 'createEvent',
    serviceMethod: 'createEvent',
    invoke: (controller: WebController) => controller.createEvent(eventBody, headers),
    expectedArgs: [eventBody, context],
  },
  {
    controllerMethod: 'completeTask',
    serviceMethod: 'completeTask',
    invoke: (controller: WebController) => controller.completeTask('task-1', completeBody, headers),
    expectedArgs: ['task-1', completeBody, context],
  },
  {
    controllerMethod: 'deleteTask',
    serviceMethod: 'deleteTask',
    invoke: (controller: WebController) => controller.deleteTask('task-1', headers),
    expectedArgs: ['task-1', context],
  },
  {
    controllerMethod: 'deleteEvent',
    serviceMethod: 'deleteEvent',
    invoke: (controller: WebController) => controller.deleteEvent('event-1', headers),
    expectedArgs: ['event-1', context],
  },
  {
    controllerMethod: 'updateEvent',
    serviceMethod: 'updateEvent',
    invoke: (controller: WebController) => controller.updateEvent('event-1', eventBody, headers),
    expectedArgs: ['event-1', eventBody, context],
  },
  {
    controllerMethod: 'actualRecords',
    serviceMethod: 'actualRecords',
    invoke: (controller: WebController) => controller.actualRecords(actualQuery, headers),
    expectedArgs: [actualQuery, context],
  },
  {
    controllerMethod: 'reminders',
    serviceMethod: 'reminders',
    invoke: (controller: WebController) => controller.reminders(headers),
    expectedArgs: [context],
  },
  {
    controllerMethod: 'prepareOperation',
    serviceMethod: 'prepareOperation',
    invoke: (controller: WebController) => controller.prepareOperation('delete-task', operationBody, headers),
    expectedArgs: ['delete-task', operationBody, context],
  },
  {
    controllerMethod: 'confirmOperation',
    serviceMethod: 'confirmOperation',
    invoke: (controller: WebController) => controller.confirmOperation('delete-task', operationBody, headers),
    expectedArgs: ['delete-task', operationBody, context],
  },
];

describe('WebController', () => {
  it('has a delegation case for every public route method', () => {
    const publicMethods = Object.getOwnPropertyNames(WebController.prototype)
      .filter((name) => name !== 'constructor')
      .sort();

    expect(cases.map((testCase) => testCase.controllerMethod).sort()).toEqual(publicMethods);
  });

  it.each(cases)('forwards $controllerMethod to $serviceMethod with parsed request context', async (testCase) => {
    const service = mockWebService();
    const controller = new WebController(service as never);

    await expect(testCase.invoke(controller)).resolves.toEqual({
      method: testCase.serviceMethod,
      args: testCase.expectedArgs,
    });
    expect(service[testCase.serviceMethod]).toHaveBeenCalledWith(...testCase.expectedArgs);
  });

  it('uses the default request context when headers are invalid or absent', async () => {
    const service = mockWebService();
    const controller = new WebController(service as never);

    await expect(controller.dashboard({ 'x-flowplanv2-user-id': 'bad' })).resolves.toEqual({
      method: 'dashboard',
      args: [defaultContext],
    });
  });

  it('preserves query object identity and normalized context for task listing', async () => {
    const service = {
      tasks: vi.fn(async () => ({ items: [{ id: 'task-1' }], nextCursor: 'cursor-2' })),
    };
    const controller = new WebController(service as never);
    const queryWithArrayHeader = { status: 'open', tags: ['focus', 'deep'], limit: '02' };

    await expect(
      controller.tasks(queryWithArrayHeader, {
        'x-flowplanv2-user-id': [context.userId],
        'x-flowplanv2-device-id': ` ${context.deviceId} `,
      }),
    ).resolves.toEqual({ items: [{ id: 'task-1' }], nextCursor: 'cursor-2' });
    expect(service.tasks).toHaveBeenCalledWith(queryWithArrayHeader, context);
    expect(service.tasks.mock.calls[0][0]).toBe(queryWithArrayHeader);
  });

  it('keeps prepare and confirm operation keys distinct for guarded actions', async () => {
    const service = {
      prepareOperation: vi.fn(async () => ({ confirmationRequired: true })),
      confirmOperation: vi.fn(async () => ({ confirmed: true })),
    };
    const controller = new WebController(service as never);
    const prepareBody = { targetId: 'task-1', reason: 'cleanup' };
    const confirmBody = { confirmationToken: 'token-1' };

    await expect(controller.prepareOperation('delete-task', prepareBody, headers)).resolves.toEqual({
      confirmationRequired: true,
    });
    await expect(controller.confirmOperation('delete-task', confirmBody, headers)).resolves.toEqual({
      confirmed: true,
    });
    expect(service.prepareOperation.mock.calls[0]).toEqual(['delete-task', prepareBody, context]);
    expect(service.confirmOperation.mock.calls[0]).toEqual(['delete-task', confirmBody, context]);
    expect(service.prepareOperation.mock.calls[0][1]).toBe(prepareBody);
    expect(service.confirmOperation.mock.calls[0][1]).toBe(confirmBody);
  });

  it('passes service errors through without wrapping them', async () => {
    const service = mockWebService();
    const controller = new WebController(service as never);
    const error = new Error('operation prepare failed');
    service.prepareOperation.mockRejectedValueOnce(error);

    await expect(controller.prepareOperation('delete-task', operationBody, headers)).rejects.toBe(error);
  });
});
