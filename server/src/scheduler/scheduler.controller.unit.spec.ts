import { describe, expect, it, vi } from 'vitest';
import { DependencyGraphService } from './dependency-graph.service';
import { GeneticSchedulerService } from './genetic-scheduler.service';
import { SchedulerController } from './scheduler.controller';
import { SchedulerService } from './scheduler.service';

const headers = {
  'x-flowplanv2-user-id': '11111111-1111-4111-8111-111111111111',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

function mockMethods<T extends string>(methods: T[]) {
  return Object.fromEntries(
    methods.map((method) => [
      method,
      vi.fn((...args: unknown[]) => ({ method, args })),
    ]),
  ) as Record<T, ReturnType<typeof vi.fn>>;
}

function createController() {
  const schedulerService = mockMethods([
    'createRun',
    'run',
    'acceptRun',
    'rejectRun',
    'detectDeviations',
  ]);
  const geneticScheduler = mockMethods([
    'evolve',
    'recordFeedback',
    'suggestPrompts',
  ]);
  const dependencyGraph = mockMethods(['topoSort', 'validate']);
  const controller = new SchedulerController(
    schedulerService as unknown as SchedulerService,
    geneticScheduler as unknown as GeneticSchedulerService,
    dependencyGraph as unknown as DependencyGraphService,
  );

  return { controller, schedulerService, geneticScheduler, dependencyGraph };
}

describe('SchedulerController', () => {
  it('forwards schedule run endpoints with parsed request context', () => {
    const { controller, schedulerService } = createController();

    expect(controller.createRun({ strategy: 'balanced' }, headers)).toEqual({
      method: 'createRun',
      args: [{ strategy: 'balanced' }, context],
    });
    expect(controller.run('run-1', headers)).toEqual({
      method: 'run',
      args: ['run-1', context],
    });
    expect(controller.acceptRun('run-1', { acceptedItemIds: ['item-1'] }, headers)).toEqual({
      method: 'acceptRun',
      args: ['run-1', { acceptedItemIds: ['item-1'] }, context],
    });
    expect(controller.rejectRun('run-1', { reason: 'busy' }, headers)).toEqual({
      method: 'rejectRun',
      args: ['run-1', { reason: 'busy' }, context],
    });
    expect(controller.detectDeviations({ rangeStart: '2026-06-08T00:00:00Z' }, headers)).toEqual({
      method: 'detectDeviations',
      args: [{ rangeStart: '2026-06-08T00:00:00Z' }, context],
    });

    expect(schedulerService.createRun).toHaveBeenCalledWith({ strategy: 'balanced' }, context);
    expect(schedulerService.run).toHaveBeenCalledWith('run-1', context);
    expect(schedulerService.acceptRun).toHaveBeenCalledWith(
      'run-1',
      { acceptedItemIds: ['item-1'] },
      context,
    );
    expect(schedulerService.rejectRun).toHaveBeenCalledWith('run-1', { reason: 'busy' }, context);
    expect(schedulerService.detectDeviations).toHaveBeenCalledWith(
      { rangeStart: '2026-06-08T00:00:00Z' },
      context,
    );
  });

  it('uses default context for invalid schedule headers', () => {
    const { controller } = createController();

    expect(controller.run('run-1', { 'x-flowplanv2-user-id': 'bad' })).toEqual({
      method: 'run',
      args: [
        'run-1',
        {
          userId: '00000000-0000-4000-8000-000000000001',
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
  });

  it('forwards genetic scheduling endpoints with body defaults and conversions', () => {
    const { controller, geneticScheduler } = createController();
    const tasks = [{ id: 'task-1' }];
    const freeSlots = [{ start: '2026-06-08T09:00:00Z' }];
    const topoOrder = ['task-1'];
    const config = { generations: 4 };
    const userScores = { 'task-1': 5 };

    expect(
      controller.geneticEvolve({ tasks, freeSlots, topoOrder, config, userScores }, headers),
    ).toEqual({
      method: 'evolve',
      args: [tasks, freeSlots, topoOrder, config, userScores],
    });
    expect(controller.geneticEvolve({}, headers)).toEqual({
      method: 'evolve',
      args: [[], [], [], undefined, undefined],
    });

    expect(controller.geneticFeedback({ taskId: 42, score: '4.5', preferredSlot: '09:00' })).toEqual({
      ok: true,
    });
    expect(geneticScheduler.recordFeedback).toHaveBeenCalledWith('42', 4.5, '09:00');
    expect(controller.geneticFeedback({})).toEqual({
      ok: true,
    });
    expect(geneticScheduler.recordFeedback).toHaveBeenLastCalledWith('', 3, undefined);

    expect(controller.geneticPrompts({ tasks, freeSlots, topoOrder, count: '2' })).toEqual({
      prompts: {
        method: 'suggestPrompts',
        args: [tasks, freeSlots, topoOrder, 2],
      },
    });
    expect(controller.geneticPrompts({})).toEqual({
      prompts: {
        method: 'suggestPrompts',
        args: [[], [], [], 3],
      },
    });
  });

  it('forwards dependency graph endpoints with task array defaults', () => {
    const { controller } = createController();
    const tasks = [{ id: 'task-1', dependsOn: [] }];

    expect(controller.topoSort({ tasks })).toEqual({
      method: 'topoSort',
      args: [tasks],
    });
    expect(controller.topoSort({})).toEqual({
      method: 'topoSort',
      args: [[]],
    });
    expect(controller.validateDependencies({ tasks })).toEqual({
      method: 'validate',
      args: [tasks],
    });
    expect(controller.validateDependencies({})).toEqual({
      method: 'validate',
      args: [[]],
    });
  });

  it('returns genetic evolve results while preserving body arrays, config, and user score maps', () => {
    const schedulerService = mockMethods(['createRun', 'run', 'acceptRun', 'rejectRun', 'detectDeviations']);
    const geneticScheduler = {
      evolve: vi.fn(() => ({ best: { genes: [{ taskId: 'task-1' }] }, history: [1010] })),
      recordFeedback: vi.fn(),
      suggestPrompts: vi.fn(),
    };
    const dependencyGraph = mockMethods(['topoSort', 'validate']);
    const controller = new SchedulerController(
      schedulerService as unknown as SchedulerService,
      geneticScheduler as unknown as GeneticSchedulerService,
      dependencyGraph as unknown as DependencyGraphService,
    );
    const tasks = [{ id: 'task-1', estimatedMinutes: 30 }];
    const freeSlots = [{ start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') }];
    const topoOrder = ['task-1'];
    const config = { generations: 2, populationSize: 4 };
    const userScores = { 'task-1': 5 };

    expect(
      controller.geneticEvolve({ tasks, freeSlots, topoOrder, config, userScores }, headers),
    ).toEqual({ best: { genes: [{ taskId: 'task-1' }] }, history: [1010] });
    expect(geneticScheduler.evolve).toHaveBeenCalledWith(
      tasks,
      freeSlots,
      topoOrder,
      config,
      userScores,
    );
    expect(geneticScheduler.evolve.mock.calls[0][0]).toBe(tasks);
    expect(geneticScheduler.evolve.mock.calls[0][1]).toBe(freeSlots);
    expect(geneticScheduler.evolve.mock.calls[0][3]).toBe(config);
    expect(geneticScheduler.evolve.mock.calls[0][4]).toBe(userScores);
  });

  it('parses genetic prompt count and feedback score before calling genetic services', () => {
    const { controller, geneticScheduler } = createController();
    const tasks = [{ id: 'task-1' }];
    const freeSlots = [{ start: '2026-06-08T09:00:00Z' }];
    const topoOrder = ['task-1'];

    expect(controller.geneticPrompts({ tasks, freeSlots, topoOrder, count: '02' })).toEqual({
      prompts: {
        method: 'suggestPrompts',
        args: [tasks, freeSlots, topoOrder, 2],
      },
    });
    expect(geneticScheduler.suggestPrompts).toHaveBeenCalledWith(tasks, freeSlots, topoOrder, 2);

    expect(controller.geneticFeedback({ taskId: 42, score: '4.5', preferredSlot: '09:00' })).toEqual({
      ok: true,
    });
    expect(geneticScheduler.recordFeedback).toHaveBeenCalledWith('42', 4.5, '09:00');
  });

  it('passes genetic service errors through without wrapping them', () => {
    const { controller, geneticScheduler } = createController();
    const error = new Error('genetic evolution failed');
    geneticScheduler.evolve.mockImplementationOnce(() => {
      throw error;
    });

    expect(() => controller.geneticEvolve({}, headers)).toThrow(error);
  });
});
