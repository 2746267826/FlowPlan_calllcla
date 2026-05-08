import { Injectable } from '@nestjs/common';

export interface ScheduleTask {
  id: string;
  title: string;
  estimatedMinutes: number;
  priority: 'urgent' | 'high' | 'normal' | 'low';
  dueAt?: Date;
  dependsOn: string[];   // tasks that must finish first
  locked?: boolean;      // fixed time slot
  lockedStart?: Date;
  lockedEnd?: Date;
}

export interface BusySlot {
  start: Date;
  end: Date;
}

export interface FreeSlot {
  start: Date;
  end: Date;
}

/** A single schedule solution (chromosome): task → time-slot assignment */
export interface ScheduleChromosome {
  genes: TaskGene[];
  fitness: number;
  generation: number;
}

export interface TaskGene {
  taskId: string;
  start: Date;
  end: Date;
  order: number;  // position in the sorted task sequence
}

export interface GaConfig {
  populationSize: number;    // default 50
  generations: number;       // default 100
  mutationRate: number;      // default 0.1
  crossoverRate: number;     // default 0.7
  eliteCount: number;        // default 5 (keep best N)
  tournamentSize: number;    // default 3
}

const DEFAULT_CONFIG: GaConfig = {
  populationSize: 50,
  generations: 100,
  mutationRate: 0.1,
  crossoverRate: 0.7,
  eliteCount: 5,
  tournamentSize: 3,
};

const PRIORITY_WEIGHT: Record<string, number> = {
  urgent: 100, high: 60, normal: 30, low: 10,
};

@Injectable()
export class GeneticSchedulerService {
  private userPreferences = new Map<string, number>(); // taskId → user score
  private slotPreferences = new Map<string, number>(); // "HH:MM" → score

  /**
   * Run the genetic algorithm to find an optimal task schedule.
   */
  evolve(
    tasks: ScheduleTask[],
    freeSlots: FreeSlot[],
    topoOrder: string[],
    config: Partial<GaConfig> = {},
    userScores?: Record<string, number>,  // taskId → user rating (1-5)
  ): { best: ScheduleChromosome; history: number[]; diversity: number[] } {
    const cfg = { ...DEFAULT_CONFIG, ...config };

    // Apply user feedback
    if (userScores) {
      for (const [id, score] of Object.entries(userScores)) {
        this.userPreferences.set(id, (this.userPreferences.get(id) ?? 0) + score * 0.2);
      }
    }

    const taskMap = new Map(tasks.map((t) => [t.id, t]));
    const topoIndex = new Map(topoOrder.map((id, i) => [id, i]));

    // Initialize population
    let population = this.initialize(cfg.populationSize, tasks, freeSlots, topoIndex);

    const history: number[] = [];
    const diversity: number[] = [];

    for (let gen = 0; gen < cfg.generations; gen++) {
      // Evaluate fitness
      for (const chrom of population) {
        chrom.fitness = this.fitness(chrom, taskMap, freeSlots);
      }

      // Sort by fitness (higher = better)
      population.sort((a, b) => b.fitness - a.fitness);

      history.push(population[0].fitness);
      diversity.push(this.populationDiversity(population));

      // Elitism: keep best
      const nextGen: ScheduleChromosome[] = population.slice(0, cfg.eliteCount);

      // Breed
      while (nextGen.length < cfg.populationSize) {
        const parent1 = this.tournamentSelect(population, cfg.tournamentSize);
        const parent2 = this.tournamentSelect(population, cfg.tournamentSize);

        let child: ScheduleChromosome;
        if (Math.random() < cfg.crossoverRate) {
          child = this.crossover(parent1, parent2, gen + 1);
        } else {
          child = { genes: [...parent1.genes.map((g) => ({ ...g }))], fitness: 0, generation: gen + 1 };
        }

        if (Math.random() < cfg.mutationRate) {
          child = this.mutate(child, taskMap, freeSlots);
        }

        child.generation = gen + 1;
        nextGen.push(child);
      }

      population = nextGen.slice(0, cfg.populationSize);
    }

    // Final evaluation
    for (const chrom of population) {
      chrom.fitness = this.fitness(chrom, taskMap, freeSlots);
    }
    population.sort((a, b) => b.fitness - a.fitness);

    return {
      best: population[0],
      history,
      diversity,
    };
  }

  /**
   * Ask the user to rate a specific schedule suggestion.
   * The score is stored and used to bias future schedule generation.
   */
  recordFeedback(taskId: string, score: number, preferredSlot?: string): void {
    const clamped = Math.max(1, Math.min(5, score));
    this.userPreferences.set(taskId, (this.userPreferences.get(taskId) ?? 0) + clamped);
    if (preferredSlot) {
      this.slotPreferences.set(preferredSlot, (this.slotPreferences.get(preferredSlot) ?? 0) + 1);
    }
  }

  /** Suggest which schedules to ask the user about (those with lowest confidence). */
  suggestPrompts(
    tasks: ScheduleTask[],
    freeSlots: FreeSlot[],
    topoOrder: string[],
    count = 3,
  ): Array<{ taskId: string; title: string; options: string[] }> {
    const taskMap = new Map(tasks.map((t) => [t.id, t]));

    // Find tasks with fewest user feedback scores
    const unscored = tasks
      .filter((t) => !this.userPreferences.has(t.id))
      .slice(0, count);

    return unscored.map((t) => {
      const options = this.generateSlotOptions(t, freeSlots);
      return { taskId: t.id, title: t.title, options };
    });
  }

  // ---- internal initialisation ----

  private initialize(
    size: number,
    tasks: ScheduleTask[],
    freeSlots: FreeSlot[],
    topoIndex: Map<string, number>,
  ): ScheduleChromosome[] {
    const population: ScheduleChromosome[] = [];

    for (let i = 0; i < size; i++) {
      const genes: TaskGene[] = [];
      const remaining: FreeSlot[] = freeSlots.map((s) => ({ ...s }));
      let order = 0;

      // Sort tasks by topological order (respect dependencies)
      const sorted = [...tasks].sort((a, b) =>
        (topoIndex.get(a.id) ?? 999) - (topoIndex.get(b.id) ?? 999),
      );

      // Random shuffle within layers for diversity
      if (i > 0) {
        for (let j = sorted.length - 1; j > 0; j--) {
          const k = Math.floor(Math.random() * (j + 1));
          [sorted[j], sorted[k]] = [sorted[k], sorted[j]];
        }
      }

      for (const task of sorted) {
        const gene = this.assignSlot(task, remaining, order++);
        if (gene) genes.push(gene);
      }

      population.push({ genes, fitness: 0, generation: 0 });
    }

    return population;
  }

  private assignSlot(
    task: ScheduleTask,
    slots: FreeSlot[],
    order: number,
  ): TaskGene | null {
    if (task.locked && task.lockedStart && task.lockedEnd) {
      return {
        taskId: task.id,
        start: task.lockedStart,
        end: task.lockedEnd,
        order,
      };
    }

    const needed = task.estimatedMinutes;

    // Try to find a slot large enough
    for (const slot of slots) {
      const available = (slot.end.getTime() - slot.start.getTime()) / 60000;
      if (available >= needed) {
        const start = new Date(slot.start);
        const end = new Date(start.getTime() + needed * 60000);
        slot.start = end; // consume slot
        return { taskId: task.id, start, end, order };
      }
    }

    return null;
  }

  // ---- genetic operators ----

  private fitness(
    chrom: ScheduleChromosome,
    taskMap: Map<string, ScheduleTask>,
    freeSlots: FreeSlot[],
  ): number {
    let score = 1000;
    const scheduled = new Set<string>();

    for (const gene of chrom.genes) {
      const task = taskMap.get(gene.taskId);
      if (!task) { score -= 50; continue; }

      // Priority bonus
      score += PRIORITY_WEIGHT[task.priority] ?? 0;

      // User preference bias
      const userScore = this.userPreferences.get(task.id);
      if (userScore) score += userScore * 10;

      // Due date penalty
      if (task.dueAt && gene.end > task.dueAt) {
        const overdueHours = (gene.end.getTime() - task.dueAt.getTime()) / 3600000;
        score -= overdueHours * 20;
      }

      // Dependency check: prerequisites must be scheduled earlier
      for (const dep of task.dependsOn) {
        const depGene = chrom.genes.find((g) => g.taskId === dep);
        if (depGene && depGene.end > gene.start) {
          score -= 200; // dependency violation penalty
        }
      }

      // Slot preference
      const slotKey = `${gene.start.getHours()}:${String(gene.start.getMinutes()).padStart(2, '0')}`;
      const slotScore = this.slotPreferences.get(slotKey);
      if (slotScore) score += slotScore * 5;

      // Task scheduled successfully
      scheduled.add(task.id);
    }

    // Penalty for unscheduled tasks
    score -= (taskMap.size - scheduled.size) * 100;

    // Time utilization bonus (scheduled density)
    const scheduledMinutes = chrom.genes.reduce(
      (sum, g) => sum + (g.end.getTime() - g.start.getTime()) / 60000, 0,
    );
    const totalFree = freeSlots.reduce(
      (sum, s) => sum + (s.end.getTime() - s.start.getTime()) / 60000, 0,
    );
    if (totalFree > 0) {
      score += (scheduledMinutes / totalFree) * 50;
    }

    return score;
  }

  private tournamentSelect(
    population: ScheduleChromosome[],
    size: number,
  ): ScheduleChromosome {
    let best: ScheduleChromosome | null = null;
    for (let i = 0; i < size; i++) {
      const idx = Math.floor(Math.random() * population.length);
      if (!best || population[idx].fitness > best.fitness) {
        best = population[idx];
      }
    }
    return best!;
  }

  private crossover(
    a: ScheduleChromosome,
    b: ScheduleChromosome,
    generation: number,
  ): ScheduleChromosome {
    const cut = Math.floor(Math.random() * Math.min(a.genes.length, b.genes.length));
    const childGenes = [
      ...a.genes.slice(0, cut).map((g) => ({ ...g })),
      ...b.genes.slice(cut).map((g) => ({ ...g })),
    ];
    return { genes: childGenes, fitness: 0, generation };
  }

  private mutate(
    chrom: ScheduleChromosome,
    taskMap: Map<string, ScheduleTask>,
    freeSlots: FreeSlot[],
  ): ScheduleChromosome {
    const genes = chrom.genes.map((g) => ({ ...g }));
    if (genes.length === 0) return chrom;

    const idx = Math.floor(Math.random() * genes.length);
    const task = taskMap.get(genes[idx].taskId);
    if (!task || task.locked) return chrom;

    // Shift start time by ±30 minutes within available range
    const shift = (Math.random() - 0.5) * 60 * 60000;
    const newStart = new Date(genes[idx].start.getTime() + shift);
    const duration = genes[idx].end.getTime() - genes[idx].start.getTime();

    // Clamp to free slots
    for (const slot of freeSlots) {
      if (newStart >= slot.start && newStart.getTime() + duration <= slot.end.getTime()) {
        genes[idx].start = newStart;
        genes[idx].end = new Date(newStart.getTime() + duration);
        break;
      }
    }

    return { genes, fitness: 0, generation: chrom.generation };
  }

  private populationDiversity(population: ScheduleChromosome[]): number {
    if (population.length < 2) return 0;
    let totalDiff = 0;
    let count = 0;
    for (let i = 0; i < population.length - 1; i++) {
      for (let j = i + 1; j < population.length; j++) {
        totalDiff += this.chromosomeDistance(population[i], population[j]);
        count++;
      }
    }
    return count > 0 ? totalDiff / count : 0;
  }

  private chromosomeDistance(a: ScheduleChromosome, b: ScheduleChromosome): number {
    const ids = new Set([...a.genes.map((g) => g.taskId), ...b.genes.map((g) => g.taskId)]);
    const aMap = new Map(a.genes.map((g) => [g.taskId, g]));
    const bMap = new Map(b.genes.map((g) => [g.taskId, g]));
    let diff = 0;
    for (const id of ids) {
      const ag = aMap.get(id);
      const bg = bMap.get(id);
      if (!ag || !bg) { diff += 120; continue; }
      diff += Math.abs(ag.start.getTime() - bg.start.getTime()) / 60000;
    }
    return diff;
  }

  // ---- slot generation ----

  private generateSlotOptions(task: ScheduleTask, freeSlots: FreeSlot[]): string[] {
    const options: string[] = [];
    const needed = task.estimatedMinutes;
    for (const slot of freeSlots) {
      const available = (slot.end.getTime() - slot.start.getTime()) / 60000;
      if (available >= needed) {
        const start = slot.start;
        options.push(
          `${start.getHours().toString().padStart(2, '0')}:${start.getMinutes().toString().padStart(2, '0')}`,
        );
      }
    }
    return options.slice(0, 5);
  }
}
