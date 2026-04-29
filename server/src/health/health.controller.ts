import { Controller, Get } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { LocalObjectStorageService } from '../files/local-object-storage.service';

@Controller('health')
export class HealthController {
  constructor(
    private readonly database: DatabaseService,
    private readonly storage: LocalObjectStorageService,
  ) {}

  @Get()
  async check() {
    const startedAt = new Date();
    const checks: Record<string, unknown> = {};
    let ok = true;

    try {
      const db = await this.database.query<{
        now: Date;
        sync_backlog: number;
        open_conflicts: number;
        failed_mutations: number;
        failed_transfers: number;
        model_runs_24h: number;
      }>(
        `
        SELECT
          now() AS now,
          (SELECT COUNT(*)::int FROM sync_changes) AS sync_backlog,
          (SELECT COUNT(*)::int FROM sync_conflicts WHERE status = 'open') AS open_conflicts,
          (SELECT COUNT(*)::int FROM sync_mutations WHERE result = 'rejected') AS failed_mutations,
          (SELECT COUNT(*)::int FROM file_transfer_sessions WHERE status = 'failed') AS failed_transfers,
          (SELECT COUNT(*)::int FROM model_runs WHERE started_at > now() - interval '24 hours') AS model_runs_24h
        `,
      );
      checks.database = { ok: true, serverTime: db.rows[0]?.now };
      checks.sync = {
        syncBacklog: db.rows[0]?.sync_backlog ?? 0,
        openConflicts: db.rows[0]?.open_conflicts ?? 0,
        failedMutations: db.rows[0]?.failed_mutations ?? 0,
      };
      checks.files = {
        failedTransfers: db.rows[0]?.failed_transfers ?? 0,
      };
      checks.models = {
        runsLast24h: db.rows[0]?.model_runs_24h ?? 0,
      };
    } catch (error) {
      ok = false;
      checks.database = {
        ok: false,
        error: this.errorMessage(error),
      };
    }

    try {
      checks.storage = await this.storage.status();
    } catch (error) {
      ok = false;
      checks.storage = {
        ok: false,
        error: this.errorMessage(error),
      };
    }

    return {
      ok,
      service: 'flowplan-server',
      phase: 'p11',
      generatedAt: startedAt.toISOString(),
      checks,
    };
  }

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
