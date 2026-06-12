import { describe, expect, it, vi } from 'vitest';
import type { DatabaseService } from '../../database/database.service';
import { VectorService } from './vector.service';

function makeDatabase(
  queryImpl: (sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }> | { rows: unknown[] },
) {
  return {
    query: vi.fn(queryImpl),
  };
}

function l2Norm(values: number[]) {
  return Math.sqrt(values.reduce((sum, value) => sum + value * value, 0));
}

describe('VectorService', () => {
  it('matches tasks with vector SQL and maps task_id rows to numeric similarities', async () => {
    const embedding = [0.1, 0.2, 0.3];
    const database = makeDatabase(async () => ({
      rows: [
        { task_id: 'task-1', similarity: '0.875' },
        { task_id: 'task-2', similarity: 0.625 },
      ],
    }));
    const service = new VectorService(database as unknown as DatabaseService);

    await expect(service.matchTasks('user-1', embedding, 0.72, 3)).resolves.toEqual([
      { taskId: 'task-1', similarity: 0.875 },
      { taskId: 'task-2', similarity: 0.625 },
    ]);

    expect(database.query).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('SELECT * FROM match_tasks($1::vector, $2::uuid, $3, $4)'),
      [JSON.stringify(embedding), 'user-1', 0.72, 3],
    );
  });

  it('returns an empty match list when the database vector query fails', async () => {
    const database = makeDatabase(async () => {
      throw new Error('pgvector unavailable');
    });
    const service = new VectorService(database as unknown as DatabaseService);

    await expect(service.matchTasks('user-1', [0.4, 0.5])).resolves.toEqual([]);

    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('match_tasks'), [
      JSON.stringify([0.4, 0.5]),
      'user-1',
      0.5,
      10,
    ]);
  });

  it('upserts task embeddings with task id, serialized embedding, model, and source text', async () => {
    const database = makeDatabase(async () => ({ rows: [] }));
    const service = new VectorService(database as unknown as DatabaseService);
    const embedding = [0.11, 0.22, 0.33];

    await expect(
      service.upsertEmbedding('user-1', 'task-1', embedding, 'text-embedding-test', 'task notes'),
    ).resolves.toBeUndefined();

    expect(database.query).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO task_embeddings'),
      ['user-1', 'task-1', JSON.stringify(embedding), 'text-embedding-test', 'task notes'],
    );
    expect(database.query.mock.calls[0][0]).toContain('ON CONFLICT (user_id, task_id)');
  });

  it('swallows embedding upsert failures without throwing', async () => {
    const database = makeDatabase(async () => {
      throw new Error('task_embeddings table unavailable');
    });
    const service = new VectorService(database as unknown as DatabaseService);

    await expect(
      service.upsertEmbedding('user-1', 'task-1', [0.1], 'model-name', 'source'),
    ).resolves.toBeUndefined();

    expect(database.query).toHaveBeenCalledTimes(1);
  });

  it('returns a fixed-length all-zero simple embedding for empty text', () => {
    const embedding = VectorService.simpleEmbedding('');

    expect(embedding).toHaveLength(384);
    expect(embedding.every((value) => value === 0)).toBe(true);
    expect(l2Norm(embedding)).toBe(0);
  });

  it('generates deterministic normalized simple embeddings for non-empty text', () => {
    const first = VectorService.simpleEmbedding('Plan the weekly review', 64);
    const second = VectorService.simpleEmbedding('Plan the weekly review', 64);
    const different = VectorService.simpleEmbedding('Plan a different review', 64);

    expect(first).toHaveLength(64);
    expect(second).toEqual(first);
    expect(different).not.toEqual(first);
    expect(first.some((value) => value !== 0)).toBe(true);
    expect(l2Norm(first)).toBeCloseTo(1, 10);
  });
});
