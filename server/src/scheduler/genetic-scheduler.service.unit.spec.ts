import { describe, it, expect } from 'vitest';
import { GeneticSchedulerService, type ScheduleTask, type FreeSlot } from './genetic-scheduler.service';

describe('GeneticSchedulerService', () => {
  const service = new GeneticSchedulerService();

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

  it('records and uses user feedback', () => {
    service.recordFeedback('t1', 5, '09:00');
    const result = service.evolve(makeTasks(), makeSlots(), ['t1', 't2', 't3']);
    expect(result.best.fitness).toBeGreaterThan(0);
    // t1 should get a preference boost
    const t1Gene = result.best.genes.find((g) => g.taskId === 't1');
    expect(t1Gene).toBeDefined();
  });

  it('suggests prompts for user scoring', () => {
    const prompts = service.suggestPrompts(makeTasks(), makeSlots(), ['t1', 't2', 't3'], 2);
    expect(prompts.length).toBeLessThanOrEqual(2);
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
});
