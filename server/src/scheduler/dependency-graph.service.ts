import { Injectable } from '@nestjs/common';

export interface TaskNode {
  id: string;
  title: string;
  estimatedMinutes: number;
  dependsOn: string[];    // Task IDs that must complete before this one
}

export interface TopoResult {
  sorted: string[];         // Topologically sorted task IDs
  layers: string[][];       // Tasks grouped by parallel-executable layers
  cycles: string[][];       // Detected cycles (if any)
  hasCycle: boolean;
}

@Injectable()
export class DependencyGraphService {
  /**
   * Build adjacency list from task dependency declarations.
   *  tasks: A depends on B means "B must finish before A starts".
   */
  buildGraph(tasks: TaskNode[]): {
    adjIn: Map<string, Set<string>>;   // inbound edges: task → its prerequisites
    adjOut: Map<string, Set<string>>;  // outbound edges: task → tasks that depend on it
    inDegree: Map<string, number>;
  } {
    const adjIn = new Map<string, Set<string>>();
    const adjOut = new Map<string, Set<string>>();
    const inDegree = new Map<string, number>();

    for (const t of tasks) {
      if (!inDegree.has(t.id)) inDegree.set(t.id, 0);
      if (!adjIn.has(t.id)) adjIn.set(t.id, new Set());
      if (!adjOut.has(t.id)) adjOut.set(t.id, new Set());
    }

    for (const t of tasks) {
      for (const dep of t.dependsOn) {
        if (!adjOut.has(dep)) {
          adjOut.set(dep, new Set());
          inDegree.set(dep, 0);
        }
        adjIn.get(t.id)!.add(dep);
        adjOut.get(dep)!.add(t.id);
        inDegree.set(t.id, (inDegree.get(t.id) ?? 0) + 1);
      }
    }
    return { adjIn, adjOut, inDegree };
  }

  /**
   * Kahn's algorithm for topological sort.
   * Returns tasks grouped into parallel layers, plus any detected cycles.
   */
  topoSort(tasks: TaskNode[]): TopoResult {
    const { inDegree } = this.buildGraph(tasks);

    // Copy in-degree map
    const indeg = new Map(inDegree);
    const queue: string[] = [];

    for (const [id, deg] of indeg) {
      if (deg === 0) queue.push(id);
    }

    const sorted: string[] = [];
    const layers: string[][] = [];

    while (queue.length > 0) {
      const layer: string[] = [];
      const nextQueue: string[] = [];

      for (const node of queue) {
        sorted.push(node);
        layer.push(node);

        const deps = this.buildGraph(tasks).adjOut.get(node);
        if (deps) {
          for (const dependent of deps) {
            const newDeg = (indeg.get(dependent) ?? 1) - 1;
            indeg.set(dependent, newDeg);
            if (newDeg === 0) {
              nextQueue.push(dependent);
            }
          }
        }
      }
      layers.push(layer);
      queue.length = 0;
      queue.push(...nextQueue);
    }

    // Detect cycles: nodes still with in-degree > 0
    const cycleNodes: string[] = [];
    for (const [id, deg] of indeg) {
      if (deg > 0) cycleNodes.push(id);
    }

    const cycles = cycleNodes.length > 0 ? this.findCycles(tasks, indeg) : [];

    return {
      sorted,
      layers,
      cycles,
      hasCycle: cycles.length > 0,
    };
  }

  /**
   * Find actual cycles from remaining high-in-degree nodes.
   */
  private findCycles(
    tasks: TaskNode[],
    indeg: Map<string, number>,
  ): string[][] {
    const taskMap = new Map(tasks.map((t) => [t.id, t]));
    const visited = new Set<string>();
    const cycles: string[][] = [];

    for (const [id, deg] of indeg) {
      if (deg > 0 && !visited.has(id)) {
        const path: string[] = [];
        const stack = new Set<string>();
        if (this.dfsCycle(id, taskMap, visited, path, stack)) {
          cycles.push([...path]);
        }
      }
    }
    return cycles;
  }

  private dfsCycle(
    node: string,
    taskMap: Map<string, TaskNode>,
    visited: Set<string>,
    path: string[],
    stack: Set<string>,
  ): boolean {
    if (stack.has(node)) {
      // Found a cycle — extract the cycle portion
      const idx = path.indexOf(node);
      if (idx >= 0) {
        const cycle = path.slice(idx);
        cycle.push(node);
        path.length = 0;
        path.push(...cycle);
      }
      return true;
    }
    if (visited.has(node)) return false;

    visited.add(node);
    stack.add(node);
    path.push(node);

    const task = taskMap.get(node);
    if (task) {
      for (const dep of task.dependsOn) {
        if (this.dfsCycle(dep, taskMap, visited, path, stack)) {
          return true;
        }
      }
    }

    stack.delete(node);
    path.pop();
    return false;
  }

  /**
   * Validate dependencies: check that all dependsOn IDs exist in the task list.
   */
  validate(tasks: TaskNode[]): { valid: boolean; missing: string[] } {
    const ids = new Set(tasks.map((t) => t.id));
    const missing: string[] = [];
    for (const t of tasks) {
      for (const dep of t.dependsOn) {
        if (!ids.has(dep)) missing.push(`${t.id} → ${dep}`);
      }
    }
    return { valid: missing.length === 0, missing };
  }
}
