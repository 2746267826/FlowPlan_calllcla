import { describe, it, expect } from 'vitest';
import { DependencyGraphService, type TaskNode } from './dependency-graph.service';

describe('DependencyGraphService', () => {
  const service = new DependencyGraphService();

  const makeTasks = (): TaskNode[] => [
    { id: 'A', title: 'Task A', estimatedMinutes: 60, dependsOn: [] },
    { id: 'B', title: 'Task B', estimatedMinutes: 30, dependsOn: ['A'] },
    { id: 'C', title: 'Task C', estimatedMinutes: 120, dependsOn: ['A'] },
    { id: 'D', title: 'Task D', estimatedMinutes: 45, dependsOn: ['B', 'C'] },
  ];

  it('topologically sorts a DAG', () => {
    const result = service.topoSort(makeTasks());
    expect(result.hasCycle).toBe(false);
    expect(result.sorted[0]).toBe('A'); // no dependencies
    expect(result.sorted[result.sorted.length - 1]).toBe('D'); // depends on everything
  });

  it('builds graph entries for duplicate tasks and external dependency IDs', () => {
    const result = service.buildGraph([
      { id: 'A', title: 'First A', estimatedMinutes: 15, dependsOn: [] },
      { id: 'A', title: 'Duplicate A', estimatedMinutes: 20, dependsOn: ['EXTERNAL'] },
      { id: 'B', title: 'Task B', estimatedMinutes: 30, dependsOn: ['A'] },
    ]);

    expect([...(result.adjIn.get('A') ?? [])]).toEqual(['EXTERNAL']);
    expect([...(result.adjOut.get('EXTERNAL') ?? [])]).toEqual(['A']);
    expect([...(result.adjOut.get('A') ?? [])]).toEqual(['B']);
    expect(result.inDegree.get('EXTERNAL')).toBe(0);
    expect(result.inDegree.get('A')).toBe(1);
    expect(result.inDegree.get('B')).toBe(1);
  });

  it('groups tasks into parallel layers', () => {
    const result = service.topoSort(makeTasks());
    expect(result.layers[0]).toEqual(['A']); // layer 1
    expect(result.layers[1]).toContain('B');
    expect(result.layers[1]).toContain('C');
    expect(result.layers[2]).toEqual(['D']); // layer 3
  });

  it('detects cycles', () => {
    const cyclic: TaskNode[] = [
      { id: 'X', title: 'X', estimatedMinutes: 30, dependsOn: ['Y'] },
      { id: 'Y', title: 'Y', estimatedMinutes: 30, dependsOn: ['Z'] },
      { id: 'Z', title: 'Z', estimatedMinutes: 30, dependsOn: ['X'] },
    ];
    const result = service.topoSort(cyclic);
    expect(result.hasCycle).toBe(true);
    expect(result.cycles.length).toBeGreaterThan(0);
  });

  it('leaves non-cyclic positive in-degree nodes out of detected cycles', () => {
    const internal = service as never as {
      findCycles: (tasks: TaskNode[], indeg: Map<string, number>) => string[][];
      dfsCycle: (
        node: string,
        taskMap: Map<string, TaskNode>,
        visited: Set<string>,
        path: string[],
        stack: Set<string>,
      ) => boolean;
    };
    const tasks: TaskNode[] = [
      { id: 'A', title: 'A', estimatedMinutes: 30, dependsOn: [] },
      { id: 'B', title: 'B', estimatedMinutes: 30, dependsOn: ['A'] },
    ];

    expect(internal.findCycles(tasks, new Map([['B', 1]]))).toEqual([]);
    expect(
      internal.dfsCycle(
        'A',
        new Map(tasks.map((task) => [task.id, task])),
        new Set(['A']),
        [],
        new Set(),
      ),
    ).toBe(false);
    expect(
      internal.dfsCycle(
        'A',
        new Map(tasks.map((task) => [task.id, task])),
        new Set(),
        [],
        new Set(['A']),
      ),
    ).toBe(true);
    expect(
      internal.dfsCycle(
        'MISSING',
        new Map(tasks.map((task) => [task.id, task])),
        new Set(),
        [],
        new Set(),
      ),
    ).toBe(false);
  });

  it('extracts the repeated portion when DFS re-enters an active path node', () => {
    const internal = service as never as {
      dfsCycle: (
        node: string,
        taskMap: Map<string, TaskNode>,
        visited: Set<string>,
        path: string[],
        stack: Set<string>,
      ) => boolean;
    };
    const path = ['A', 'B', 'C'];

    expect(
      internal.dfsCycle(
        'B',
        new Map(makeTasks().map((task) => [task.id, task])),
        new Set(['A', 'B', 'C']),
        path,
        new Set(['A', 'B', 'C']),
      ),
    ).toBe(true);
    expect(path).toEqual(['B', 'C', 'B']);
  });

  it('validates missing dependencies', () => {
    const invalid: TaskNode[] = [
      { id: 'A', title: 'A', estimatedMinutes: 30, dependsOn: ['NONEXISTENT'] },
    ];
    const result = service.validate(invalid);
    expect(result.valid).toBe(false);
    expect(result.missing).toContain('A → NONEXISTENT');
  });

  it('validates empty and complete dependency declarations', () => {
    expect(service.validate([])).toEqual({ valid: true, missing: [] });
    expect(service.validate(makeTasks())).toEqual({ valid: true, missing: [] });
  });

  it('handles empty task list', () => {
    const result = service.topoSort([]);
    expect(result.sorted).toEqual([]);
    expect(result.hasCycle).toBe(false);
  });
});
