import { Body, Controller, Get, Headers, Param, Post } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { SchedulerService } from './scheduler.service';
import { GeneticSchedulerService } from './genetic-scheduler.service';
import { DependencyGraphService } from './dependency-graph.service';

@Controller('scheduler')
export class SchedulerController {
  constructor(
    private readonly schedulerService: SchedulerService,
    private readonly geneticScheduler: GeneticSchedulerService,
    private readonly dependencyGraph: DependencyGraphService,
  ) {}

  // ---- existing ----

  @Post('runs')
  createRun(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.createRun(body, readRequestContext(headers));
  }

  @Get('runs/:runId')
  run(
    @Param('runId') runId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.run(runId, readRequestContext(headers));
  }

  @Post('runs/:runId/accept')
  acceptRun(
    @Param('runId') runId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.acceptRun(runId, body, readRequestContext(headers));
  }

  @Post('runs/:runId/reject')
  rejectRun(
    @Param('runId') runId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.rejectRun(runId, body, readRequestContext(headers));
  }

  @Post('deviations/detect')
  detectDeviations(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.schedulerService.detectDeviations(body, readRequestContext(headers));
  }

  // ---- genetic algorithm ----

  @Post('genetic/evolve')
  geneticEvolve(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    const ctx = readRequestContext(headers);
    // Extract tasks, freeSlots, topoOrder from body
    return this.geneticScheduler.evolve(
      (body.tasks as GeneticSchedulerService['evolve'] extends (t: infer T) => unknown ? T : never) ?? [],
      (body.freeSlots as any[]) ?? [],
      (body.topoOrder as string[]) ?? [],
      body.config as Record<string, number> | undefined,
      body.userScores as Record<string, number> | undefined,
    );
  }

  @Post('genetic/feedback')
  geneticFeedback(
    @Body() body: Record<string, unknown>,
  ) {
    this.geneticScheduler.recordFeedback(
      String(body.taskId ?? ''),
      Number(body.score ?? 3),
      body.preferredSlot as string | undefined,
    );
    return { ok: true };
  }

  @Post('genetic/prompts')
  geneticPrompts(
    @Body() body: Record<string, unknown>,
  ) {
    return {
      prompts: this.geneticScheduler.suggestPrompts(
        (body.tasks as any[]) ?? [],
        (body.freeSlots as any[]) ?? [],
        (body.topoOrder as string[]) ?? [],
        Number(body.count ?? 3),
      ),
    };
  }

  // ---- dependency graph ----

  @Post('dependency/topo')
  topoSort(
    @Body() body: Record<string, unknown>,
  ) {
    return this.dependencyGraph.topoSort(
      (body.tasks as any[]) ?? [],
    );
  }

  @Post('dependency/validate')
  validateDependencies(
    @Body() body: Record<string, unknown>,
  ) {
    return this.dependencyGraph.validate(
      (body.tasks as any[]) ?? [],
    );
  }
}
