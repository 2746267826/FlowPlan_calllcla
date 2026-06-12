import 'reflect-metadata';
import { describe, expect, it } from 'vitest';
import { validate } from 'class-validator';
import { CreateRunDto, GeneticEvolveDto, TopoSortDto } from './scheduler.dto';

describe('scheduler DTO validation', () => {
  it('accepts scheduler run windows with optional numeric defaults', async () => {
    const dto = Object.assign(new CreateRunDto(), {
      rangeStart: '2026-06-08T00:00:00Z',
      rangeEnd: '2026-06-09T00:00:00Z',
      defaultTaskMinutes: 45,
      strategy: 'genetic',
      mode: 'preview',
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('rejects missing run dates and wrongly typed optional fields', async () => {
    const dto = Object.assign(new CreateRunDto(), {
      defaultTaskMinutes: '45',
      strategy: 1,
      mode: {},
    });

    const errors = await validate(dto);

    expect(errors.map((error) => error.property).sort()).toEqual([
      'defaultTaskMinutes',
      'mode',
      'rangeEnd',
      'rangeStart',
      'strategy',
    ]);
  });

  it('validates genetic evolve arrays and optional object maps', async () => {
    await expect(
      validate(
        Object.assign(new GeneticEvolveDto(), {
          tasks: [{ id: 'task-1' }],
          freeSlots: [{ start: '09:00' }],
          topoOrder: ['task-1'],
          config: { population: 10 },
          userScores: { task1: 1 },
        }),
      ),
    ).resolves.toHaveLength(0);

    const errors = await validate(
      Object.assign(new GeneticEvolveDto(), {
        tasks: {},
        freeSlots: null,
        topoOrder: 'task-1',
        config: [],
        userScores: [],
      }),
    );

    expect(errors.map((error) => error.property).sort()).toEqual([
      'config',
      'freeSlots',
      'tasks',
      'topoOrder',
      'userScores',
    ]);
  });

  it('validates topology sorting task arrays', async () => {
    await expect(
      validate(Object.assign(new TopoSortDto(), { tasks: [{ id: 'task-1' }] })),
    ).resolves.toHaveLength(0);

    const errors = await validate(Object.assign(new TopoSortDto(), { tasks: {} }));

    expect(errors.map((error) => error.property)).toEqual(['tasks']);
  });
});
