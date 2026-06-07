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

  it('validates missing dependencies', () => {
    const invalid: TaskNode[] = [
      { id: 'A', title: 'A', estimatedMinutes: 30, dependsOn: ['NONEXISTENT'] },
    ];
    const result = service.validate(invalid);
    expect(result.valid).toBe(false);
    expect(result.missing).toContain('A → NONEXISTENT');
  });

  it('handles empty task list', () => {
    const result = service.topoSort([]);
    expect(result.sorted).toEqual([]);
    expect(result.hasCycle).toBe(false);
  });
});
