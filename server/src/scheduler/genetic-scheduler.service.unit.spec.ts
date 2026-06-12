import { afterEach, describe, it, expect, vi } from 'vitest';
import { GeneticSchedulerService, type FreeSlot, type ScheduleChromosome, type ScheduleTask } from './genetic-scheduler.service';

describe('GeneticSchedulerService', () => {
  const service = new GeneticSchedulerService();

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const makeTasks = (): ScheduleTask[] => [
    { id: 't1', title: 'High priority', estimatedMinutes: 60, priority: 'high', dependsOn: [] },
    { id: 't2', title: 'Normal task', estimatedMinutes: 30, priority: 'normal', dependsOn: [] },
    { id: 't3', title: 'Urgent task', estimatedMinutes: 45, priority: 'urgent', dependsOn: ['t1'], dueAt: new Date(Date.now() + 3600000) },
  ];

  const makeSlots = (): FreeSlot[] => [
    { start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T12:00:00Z') },
    { start: new Date('2026-01-01T14:00:00Z'), end: new Date('2026-01-01T18:00:00Z') },
  ];

  it('evolves a schedule with genetic algorithm', () => {
    const result = service.evolve(makeTasks(), makeSlots(), ['t1', 't3', 't2']);
    expect(result.best).toBeDefined();
    expect(result.best.fitness).toBeGreaterThan(0);
    expect(result.best.genes.length).toBe(3);
    expect(result.history.length).toBe(100); // default generations
  });

  it('converges over generations', () => {
    const result = service.evolve(makeTasks(), makeSlots(), ['t1', 't2', 't3']);
    // Fitness should improve (not guaranteed strictly monotonic due to exploration)
    const firstHalf = result.history.slice(0, 50).reduce((a, b) => a + b, 0) / 50;
    const secondHalf = result.history.slice(50).reduce((a, b) => a + b, 0) / 50;
    expect(secondHalf).toBeGreaterThanOrEqual(firstHalf * 0.8); // tolerant
  });

  it('records feedback that changes fitness and population ranking', () => {
    const local = new GeneticSchedulerService();
    const internal = local as never as {
      fitness: (
        chrom: ScheduleChromosome,
        taskMap: Map<string, ScheduleTask>,
        freeSlots: FreeSlot[],
      ) => number;
    };
    const start = new Date('2026-01-01T09:00:00Z');
    const end = new Date('2026-01-01T09:30:00Z');
    const freeSlots: FreeSlot[] = [
      { start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T10:00:00Z') },
    ];
    const taskMap = new Map<string, ScheduleTask>([
      ['preferred', { id: 'preferred', title: 'Preferred', estimatedMinutes: 30, priority: 'normal', dependsOn: [] }],
      ['other', { id: 'other', title: 'Other', estimatedMinutes: 30, priority: 'normal', dependsOn: [] }],
    ]);
    const preferredChrom: ScheduleChromosome = {
      genes: [{ taskId: 'preferred', start, end, order: 0 }],
      fitness: 0,
      generation: 0,
    };
    const otherChrom: ScheduleChromosome = {
      genes: [{ taskId: 'other', start, end, order: 0 }],
      fitness: 0,
      generation: 0,
    };

    const baselinePreferred = internal.fitness(preferredChrom, taskMap, freeSlots);
    const baselineOther = internal.fitness(otherChrom, taskMap, freeSlots);

    const preferredSlot = `${start.getHours()}:${String(start.getMinutes()).padStart(2, '0')}`;

    local.recordFeedback('preferred', 5, preferredSlot);
    preferredChrom.fitness = internal.fitness(preferredChrom, taskMap, freeSlots);
    otherChrom.fitness = internal.fitness(otherChrom, taskMap, freeSlots);
    const ranked = [otherChrom, preferredChrom].sort((a, b) => b.fitness - a.fitness);

    expect(baselinePreferred).toBe(baselineOther);
    expect(preferredChrom.fitness).toBe(baselinePreferred + 55);
    expect(otherChrom.fitness).toBe(baselineOther + 5);
    expect(ranked.map((chrom) => chrom.genes[0].taskId)).toEqual(['preferred', 'other']);
  });

  it('applies per-run user scores and overdue penalties during evolution', () => {
    const local = new GeneticSchedulerService();
    const tasks: ScheduleTask[] = [
      {
        id: 'late',
        title: 'Late task',
        estimatedMinutes: 60,
        priority: 'normal',
        dependsOn: [],
        dueAt: new Date('2026-01-01T09:30:00Z'),
      },
    ];
    const freeSlots: FreeSlot[] = [
      { start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T10:00:00Z') },
    ];

    const withoutScore = local.evolve(tasks, freeSlots, ['late'], {
      populationSize: 2,
      generations: 1,
      eliteCount: 1,
      tournamentSize: 1,
      crossoverRate: 0,
      mutationRate: 0,
    }).best.fitness;
    const withScore = local.evolve(tasks, freeSlots, ['late'], {
      populationSize: 2,
      generations: 1,
      eliteCount: 1,
      tournamentSize: 1,
      crossoverRate: 0,
      mutationRate: 0,
    }, { late: 5 }).best.fitness;

    expect(withScore).toBeCloseTo(withoutScore + 10, 5);
    expect(withoutScore).toBeLessThan(1080);
  });

  it('uses fallback topo order for tasks omitted from topoOrder', () => {
    const local = new GeneticSchedulerService();
    const tasks: ScheduleTask[] = [
      { id: 'known', title: 'Known', estimatedMinutes: 30, priority: 'normal', dependsOn: [] },
      { id: 'unknown', title: 'Unknown', estimatedMinutes: 30, priority: 'normal', dependsOn: [] },
    ];

    const result = local.evolve(tasks, makeSlots(), ['known'], {
      populationSize: 2,
      generations: 1,
      eliteCount: 1,
      tournamentSize: 1,
      crossoverRate: 0,
      mutationRate: 0,
    });

    expect(result.best.genes.map((gene) => gene.taskId)).toEqual(['known', 'unknown']);
  });

  it('keeps input order when every task is omitted from topoOrder', () => {
    const local = new GeneticSchedulerService();
    const tasks: ScheduleTask[] = [
      { id: 'first', title: 'First', estimatedMinutes: 30, priority: 'normal', dependsOn: [] },
      { id: 'second', title: 'Second', estimatedMinutes: 30, priority: 'normal', dependsOn: [] },
    ];

    const result = local.evolve(tasks, makeSlots(), [], {
      populationSize: 1,
      generations: 1,
      eliteCount: 1,
      tournamentSize: 1,
      crossoverRate: 0,
      mutationRate: 0,
    });

    expect(result.best.genes.map((gene) => gene.taskId)).toEqual(['first', 'second']);
  });

  it('suggests prompts for user scoring', () => {
    const prompts = service.suggestPrompts(makeTasks(), makeSlots(), ['t1', 't2', 't3'], 2);
    expect(prompts.length).toBeLessThanOrEqual(2);
  });

  it('clamps feedback scores and limits generated prompt slot options', () => {
    const local = new GeneticSchedulerService();
    const task: ScheduleTask = {
      id: 'feedback',
      title: 'Feedback task',
      estimatedMinutes: 30,
      priority: 'normal',
      dependsOn: [],
    };
    const manySlots: FreeSlot[] = Array.from({ length: 6 }, (_, index) => ({
      start: new Date(Date.UTC(2026, 0, 1, 8 + index, 0, 0)),
      end: new Date(Date.UTC(2026, 0, 1, 8 + index, 45, 0)),
    }));

    local.recordFeedback('feedback', -10);
    local.recordFeedback('feedback', 10, '8:00');

    const prompts = local.suggestPrompts(
      [
        task,
        { id: 'new-task', title: 'New task', estimatedMinutes: 30, priority: 'low', dependsOn: [] },
      ],
      manySlots,
      ['feedback', 'new-task'],
      2,
    );
    const result = local.evolve([task], manySlots.slice(0, 1), ['feedback'], {
      populationSize: 2,
      generations: 1,
      eliteCount: 1,
      tournamentSize: 1,
      crossoverRate: 0,
      mutationRate: 0,
    });

    expect(prompts.map((prompt) => prompt.taskId)).toEqual(['new-task']);
    expect(prompts[0].options).toHaveLength(5);
    expect(result.best.fitness).toBeGreaterThan(1080);
  });

  it('omits prompt options for slots that are too short', () => {
    const local = new GeneticSchedulerService();
    const prompts = local.suggestPrompts(
      [{ id: 'long', title: 'Long', estimatedMinutes: 60, priority: 'normal', dependsOn: [] }],
      [{ start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T09:30:00Z') }],
      ['long'],
      1,
    );

    expect(prompts).toEqual([{ taskId: 'long', title: 'Long', options: [] }]);
  });

  it('respects locked tasks', () => {
    const tasks: ScheduleTask[] = [
      { id: 'l1', title: 'Locked', estimatedMinutes: 30, priority: 'normal',
        dependsOn: [], locked: true,
        lockedStart: new Date('2026-01-01T10:00:00Z'),
        lockedEnd: new Date('2026-01-01T10:30:00Z'),
      },
      { id: 'l2', title: 'Flexible', estimatedMinutes: 45, priority: 'high', dependsOn: [] },
    ];
    const result = service.evolve(tasks, makeSlots(), ['l1', 'l2']);
    const lockedGene = result.best.genes.find((g) => g.taskId === 'l1');
    expect(lockedGene?.start).toEqual(new Date('2026-01-01T10:00:00Z'));
  });

  it('penalizes dependency violations', () => {
    const tasks: ScheduleTask[] = [
      { id: 'base', title: 'Base', estimatedMinutes: 60, priority: 'high', dependsOn: [] },
      { id: 'child', title: 'Child', estimatedMinutes: 30, priority: 'high', dependsOn: ['base'] },
    ];
    // Only 1 tiny slot, forces dependency violation
    const tinySlots: FreeSlot[] = [
      { start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T09:45:00Z') },
    ];
    const result = service.evolve(tasks, tinySlots, ['base', 'child']);
    // With only 45 min slot for 90 min of work, fitness should be low
    expect(result.best.fitness).toBeLessThan(1200);
  });

  it('exercises mutation boundaries for empty, unknown, locked and movable genes', () => {
    const local = new GeneticSchedulerService();
    const internal = local as never as {
      mutate: (
        chrom: ScheduleChromosome,
        taskMap: Map<string, ScheduleTask>,
        freeSlots: FreeSlot[],
      ) => ScheduleChromosome;
      populationDiversity: (population: ScheduleChromosome[]) => number;
      chromosomeDistance: (a: ScheduleChromosome, b: ScheduleChromosome) => number;
    };
    const slot = { start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T12:00:00Z') };
    const empty: ScheduleChromosome = { genes: [], fitness: 0, generation: 3 };
    const unknown: ScheduleChromosome = {
      genes: [{ taskId: 'missing', start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T09:30:00Z'), order: 0 }],
      fitness: 0,
      generation: 4,
    };
    const locked: ScheduleChromosome = {
      genes: [{ taskId: 'locked', start: new Date('2026-01-01T09:00:00Z'), end: new Date('2026-01-01T09:30:00Z'), order: 0 }],
      fitness: 0,
      generation: 5,
    };
    const movable: ScheduleChromosome = {
      genes: [{ taskId: 'move', start: new Date('2026-01-01T10:00:00Z'), end: new Date('2026-01-01T10:30:00Z'), order: 0 }],
      fitness: 0,
      generation: 6,
    };
    const taskMap = new Map<string, ScheduleTask>([
      ['locked', { id: 'locked', title: 'Locked', estimatedMinutes: 30, priority: 'normal', dependsOn: [], locked: true }],
      ['move', { id: 'move', title: 'Move', estimatedMinutes: 30, priority: 'normal', dependsOn: [] }],
    ]);

    expect(internal.mutate(empty, taskMap, [slot])).toBe(empty);
    expect(internal.mutate(unknown, taskMap, [slot])).toBe(unknown);
    expect(internal.mutate(locked, taskMap, [slot])).toBe(locked);

    vi.spyOn(Math, 'random').mockReturnValueOnce(0).mockReturnValueOnce(1);
    const mutated = internal.mutate(movable, taskMap, [slot]);

    expect(mutated).not.toBe(movable);
    expect(mutated.genes[0].start).toEqual(new Date('2026-01-01T10:30:00Z'));
    expect(mutated.genes[0].end).toEqual(new Date('2026-01-01T11:00:00Z'));
    expect(internal.populationDiversity([movable])).toBe(0);
    expect(internal.chromosomeDistance(movable, { genes: [], fitness: 0, generation: 0 })).toBe(120);
  });

  it('scores unknown genes, unknown priorities, matching slot preferences and zero free time', () => {
    const local = new GeneticSchedulerService();
    const internal = local as never as {
      fitness: (
        chrom: ScheduleChromosome,
        taskMap: Map<string, ScheduleTask>,
        freeSlots: FreeSlot[],
      ) => number;
    };
    const start = new Date('2026-01-01T09:00:00Z');
    const chrom: ScheduleChromosome = {
      genes: [
        { taskId: 'missing', start, end: new Date('2026-01-01T09:30:00Z'), order: 0 },
        { taskId: 'odd', start, end: new Date('2026-01-01T10:00:00Z'), order: 1 },
      ],
      fitness: 0,
      generation: 0,
    };
    const taskMap = new Map<string, ScheduleTask>([
      ['odd', { id: 'odd', title: 'Odd priority', estimatedMinutes: 60, priority: 'unknown' as never, dependsOn: [] }],
    ]);

    const baseline = internal.fitness(chrom, taskMap, []);
    local.recordFeedback('odd', 3, `${start.getHours()}:00`);
    const withSlotPreference = internal.fitness(chrom, taskMap, []);

    expect(baseline).toBe(950);
    expect(withSlotPreference).toBe(985);
  });
});
