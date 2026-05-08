import { Injectable, OnModuleInit } from '@nestjs/common';
import { Cron, CronExpression, SchedulerRegistry } from '@nestjs/schedule';
import { CronJob } from 'cron';
import { DatabaseService } from '../database/database.service';
import { AppLogger } from '../common/logger/app-logger.service';

export interface JobInfo {
  name: string;
  cron: string;
  description: string;
  lastRun: string | null;
  lastError: string | null;
  status: 'idle' | 'running' | 'failed';
  nextRun: string | null;
  running: boolean;
}

@Injectable()
export class CronJobsService implements OnModuleInit {
  private readonly jobRegistry = new Map<string, JobInfo>();

  constructor(
    private readonly database: DatabaseService,
    private readonly schedulerRegistry: SchedulerRegistry,
    private readonly logger: AppLogger,
  ) {}

  onModuleInit() {
    this.register('refresh-materialized-views', '0 * * * *', 'Refresh materialized analytics views every hour');
    this.register('refresh-weather-cache', '0 */6 * * *', 'Refresh weather cache every 6 hours');
    this.register('clean-tracking-data', '0 3 * * *', 'Clean tracking data older than 90 days (daily at 3 AM)');
    this.register('purge-sync-mutations', '0 4 * * *', 'Purge stale sync mutations older than 30 days (daily at 4 AM)');
    this.register('auto-generate-reports', '0 6 * * *', 'Auto-generate daily reports (every morning at 6 AM)');
    this.logger.log(`CronJobsService initialized with ${this.jobRegistry.size} jobs`);
  }

  /** Register a cron job with metadata. */
  private register(name: string, cronExpression: string, description: string) {
    try {
      const job = new CronJob(cronExpression, () => this.executeJob(name));
      this.schedulerRegistry.addCronJob(name, job);
      job.start();
      this.jobRegistry.set(name, {
        name,
        cron: cronExpression,
        description,
        lastRun: null,
        lastError: null,
        status: 'idle',
        nextRun: job.nextDate()?.toISO() ?? null,
        running: false,
      });
    } catch (error) {
      this.logger.warn(`Failed to register cron job "${name}": ${error instanceof Error ? error.message : error}`);
    }
  }

  /** Execute a job by name and record its result. */
  private async executeJob(name: string) {
    const info = this.jobRegistry.get(name);
    if (!info || info.running) return;

    info.status = 'running';
    info.running = true;
    info.lastRun = new Date().toISOString();
    info.lastError = null;
    this.logger.log(`Cron job "${name}" started`);

    try {
      await this.runJob(name);
      info.status = 'idle';
      this.logger.log(`Cron job "${name}" completed`);
    } catch (error) {
      info.status = 'failed';
      info.lastError = error instanceof Error ? error.message : String(error);
      this.logger.error(`Cron job "${name}" failed: ${info.lastError}`);
    } finally {
      info.running = false;
      // Update next run time
      const cronJob = this.schedulerRegistry.getCronJob(name);
      info.nextRun = cronJob.nextDate()?.toISO() ?? null;
    }
  }

  /** Actual job logic. */
  private async runJob(name: string) {
    switch (name) {
      case 'refresh-materialized-views':
        await this.database.query('REFRESH MATERIALIZED VIEW CONCURRENTLY mv_activity_daily_summary').catch(() => {});
        await this.database.query('REFRESH MATERIALIZED VIEW CONCURRENTLY mv_input_hourly_summary').catch(() => {});
        break;
      case 'refresh-weather-cache':
        // Weather cache is refreshed on-demand via refreshWeather API.
        // This job cleans expired cache entries.
        await this.database.query("DELETE FROM weather_cache WHERE expires_at < now()");
        break;
      case 'clean-tracking-data':
        await this.database.query(
          "DELETE FROM tracking_ingest_chunks WHERE batch_id IN (SELECT id FROM tracking_ingest_batches WHERE created_at < now() - interval '90 days')",
        );
        await this.database.query("DELETE FROM tracking_ingest_batches WHERE created_at < now() - interval '90 days'");
        break;
      case 'purge-sync-mutations':
        await this.database.query(
          `DELETE FROM sync_mutations WHERE created_at < now() - interval '30 days'
           AND mutation_uid NOT IN (SELECT COALESCE(mutation_uid, '') FROM sync_conflicts WHERE status = 'open')`,
        );
        break;
      case 'auto-generate-reports':
        // Mark for future: calls ReportsService.generateReport() for each user.
        // Currently a placeholder — report generation requires user context.
        break;
    }
  }

  /** List all registered jobs with current status. */
  listJobs(): JobInfo[] {
    return [...this.jobRegistry.values()];
  }

  /** Trigger a job immediately (manual run from admin panel). */
  async triggerJob(name: string): Promise<{ ok: boolean; name: string; error?: string }> {
    const info = this.jobRegistry.get(name);
    if (!info) return { ok: false, name, error: `job "${name}" not found` };
    if (info.running) return { ok: false, name, error: `job "${name}" is already running` };

    await this.executeJob(name);
    return { ok: true, name };
  }

  /** Pause a cron job. */
  pauseJob(name: string): { ok: boolean; name: string; error?: string } {
    try {
      const job = this.schedulerRegistry.getCronJob(name);
      job.stop();
      return { ok: true, name };
    } catch {
      return { ok: false, name, error: `job "${name}" not found` };
    }
  }

  /** Resume a paused cron job. */
  resumeJob(name: string): { ok: boolean; name: string; error?: string } {
    try {
      const job = this.schedulerRegistry.getCronJob(name);
      job.start();
      return { ok: true, name };
    } catch {
      return { ok: false, name, error: `job "${name}" not found` };
    }
  }
}
