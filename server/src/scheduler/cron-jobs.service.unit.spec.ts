import { describe, expect, it, vi } from 'vitest';
import { CronJobsService } from './cron-jobs.service';

function createService() {
  const jobs = new Map<string, { start: () => void; stop: () => void; nextDate: () => { toISO: () => string } }>();
  const registry = {
    addCronJob: vi.fn((name: string, job: { start: () => void; stop: () => void; nextDate: () => { toISO: () => string } }) => {
      jobs.set(name, job);
    }),
    getCronJob: vi.fn((name: string) => {
      const job = jobs.get(name);
      if (!job) {
        throw new Error('missing job');
      }
      return job;
    }),
  };
  const database = { query: vi.fn(async () => ({ rows: [] })) };
  const logger = { log: vi.fn(), warn: vi.fn(), error: vi.fn() };
  const service = new CronJobsService(database as never, registry as never, logger as never);
  return { service, database, registry, logger, jobs };
}

describe('CronJobsService', () => {
  it('registers the expected cron jobs on module init', () => {
    const { service, registry, logger } = createService();

    service.onModuleInit();

    expect(registry.addCronJob).toHaveBeenCalledTimes(5);
    expect(service.listJobs().map((job) => job.name)).toEqual([
      'refresh-materialized-views',
      'refresh-weather-cache',
      'clean-tracking-data',
      'purge-sync-mutations',
      'auto-generate-reports',
    ]);
    expect(logger.log).toHaveBeenCalledWith('CronJobsService initialized with 5 jobs');
  });

  it('logs registration failures for Error and non-Error causes', () => {
    const { service, registry, logger } = createService();
    const internal = service as never as {
      register: (name: string, cronExpression: string, description: string) => void;
    };
    registry.addCronJob
      .mockImplementationOnce(() => {
        throw new Error('registry offline');
      })
      .mockImplementationOnce(() => {
        throw 'plain registry failure';
      });

    internal.register('bad-error', '0 * * * *', 'Bad error job');
    internal.register('bad-string', '0 * * * *', 'Bad string job');

    expect(logger.warn).toHaveBeenCalledWith(
      'Failed to register cron job "bad-error": registry offline',
    );
    expect(logger.warn).toHaveBeenCalledWith(
      'Failed to register cron job "bad-string": plain registry failure',
    );
    expect(service.listJobs()).toEqual([]);
  });

  it('records null next run values when cron nextDate is unavailable', async () => {
    const { service, registry, jobs } = createService();
    registry.addCronJob.mockImplementation((name, job) => {
      const nullableJob = job as typeof job & { nextDate: () => null };
      nullableJob.nextDate = () => null;
      jobs.set(name, nullableJob as never);
    });

    service.onModuleInit();
    await service.triggerJob('auto-generate-reports');

    expect(service.listJobs().find((job) => job.name === 'auto-generate-reports')).toMatchObject({
      nextRun: null,
      status: 'idle',
      running: false,
    });
  });

  it('triggers a registered job and records successful completion', async () => {
    const { service, database } = createService();
    service.onModuleInit();

    await expect(service.triggerJob('refresh-weather-cache')).resolves.toEqual({
      ok: true,
      name: 'refresh-weather-cache',
    });

    expect(database.query).toHaveBeenCalledWith("DELETE FROM weather_cache WHERE expires_at < now()");
    expect(service.listJobs().find((job) => job.name === 'refresh-weather-cache')).toMatchObject({
      status: 'idle',
      running: false,
      lastError: null,
    });
  });

  it('runs maintenance job SQL and tolerates materialized view refresh failures', async () => {
    const { service, database } = createService();
    service.onModuleInit();
    database.query
      .mockRejectedValueOnce(new Error('concurrent refresh locked'))
      .mockRejectedValueOnce(new Error('hourly refresh locked'));

    await expect(service.triggerJob('refresh-materialized-views')).resolves.toEqual({
      ok: true,
      name: 'refresh-materialized-views',
    });
    await expect(service.triggerJob('clean-tracking-data')).resolves.toEqual({
      ok: true,
      name: 'clean-tracking-data',
    });
    await expect(service.triggerJob('purge-sync-mutations')).resolves.toEqual({
      ok: true,
      name: 'purge-sync-mutations',
    });
    await expect(service.triggerJob('auto-generate-reports')).resolves.toEqual({
      ok: true,
      name: 'auto-generate-reports',
    });

    expect(database.query).toHaveBeenCalledWith(
      'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_activity_daily_summary',
    );
    expect(database.query).toHaveBeenCalledWith(
      'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_input_hourly_summary',
    );
    expect(database.query).toHaveBeenCalledWith(
      "DELETE FROM tracking_ingest_chunks WHERE batch_id IN (SELECT id FROM tracking_ingest_batches WHERE created_at < now() - interval '90 days')",
    );
    expect(database.query).toHaveBeenCalledWith(
      "DELETE FROM tracking_ingest_batches WHERE created_at < now() - interval '90 days'",
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('DELETE FROM sync_mutations'),
    );
    expect(service.listJobs().find((job) => job.name === 'refresh-materialized-views')).toMatchObject({
      status: 'idle',
      lastError: null,
    });
  });

  it('executes the registered CronJob callback', async () => {
    const { service, database, jobs } = createService();
    service.onModuleInit();
    const job = jobs.get('refresh-weather-cache') as unknown as { fireOnTick: () => void };

    job.fireOnTick();
    await new Promise<void>((resolve) => {
      setImmediate(resolve);
    });

    expect(database.query).toHaveBeenCalledWith("DELETE FROM weather_cache WHERE expires_at < now()");
    expect(service.listJobs().find((item) => item.name === 'refresh-weather-cache')).toMatchObject({
      status: 'idle',
      running: false,
    });
  });

  it('reports missing and already running jobs without running SQL', async () => {
    const { service, database } = createService();
    service.onModuleInit();
    const [job] = service.listJobs();
    job.running = true;

    await expect(service.triggerJob('missing')).resolves.toEqual({
      ok: false,
      name: 'missing',
      error: 'job "missing" not found',
    });
    await expect(service.triggerJob(job.name)).resolves.toEqual({
      ok: false,
      name: job.name,
      error: `job "${job.name}" is already running`,
    });
    expect(database.query).not.toHaveBeenCalled();
  });

  it('ignores direct execution requests for missing or running jobs', async () => {
    const { service, database } = createService();
    const internal = service as never as { executeJob: (name: string) => Promise<void> };
    service.onModuleInit();
    const [job] = service.listJobs();
    job.running = true;

    await expect(internal.executeJob('missing')).resolves.toBeUndefined();
    await expect(internal.executeJob(job.name)).resolves.toBeUndefined();

    expect(database.query).not.toHaveBeenCalled();
    expect(job.status).toBe('idle');
  });

  it('marks failed jobs with the thrown error message', async () => {
    const { service, database, logger } = createService();
    service.onModuleInit();
    database.query.mockRejectedValueOnce(new Error('cache table missing'));

    await expect(service.triggerJob('refresh-weather-cache')).resolves.toEqual({
      ok: true,
      name: 'refresh-weather-cache',
    });

    expect(service.listJobs().find((job) => job.name === 'refresh-weather-cache')).toMatchObject({
      status: 'failed',
      running: false,
      lastError: 'cache table missing',
    });
    expect(logger.error).toHaveBeenCalledWith(
      'Cron job "refresh-weather-cache" failed: cache table missing',
    );
  });

  it('records non-Error job failures as string messages', async () => {
    const { service, database, logger } = createService();
    service.onModuleInit();
    database.query.mockRejectedValueOnce('plain SQL failure');

    await expect(service.triggerJob('refresh-weather-cache')).resolves.toEqual({
      ok: true,
      name: 'refresh-weather-cache',
    });

    expect(service.listJobs().find((job) => job.name === 'refresh-weather-cache')).toMatchObject({
      status: 'failed',
      lastError: 'plain SQL failure',
      running: false,
    });
    expect(logger.error).toHaveBeenCalledWith(
      'Cron job "refresh-weather-cache" failed: plain SQL failure',
    );
  });

  it('pauses and resumes jobs through the scheduler registry', () => {
    const { service, registry, jobs } = createService();
    service.onModuleInit();
    const job = jobs.get('refresh-weather-cache');
    const stop = vi.spyOn(job as never, 'stop');
    const start = vi.spyOn(job as never, 'start');

    expect(service.pauseJob('refresh-weather-cache')).toEqual({
      ok: true,
      name: 'refresh-weather-cache',
    });
    expect(stop).toHaveBeenCalled();
    expect(service.resumeJob('refresh-weather-cache')).toEqual({
      ok: true,
      name: 'refresh-weather-cache',
    });
    expect(start).toHaveBeenCalledOnce();

    registry.getCronJob.mockImplementationOnce(() => {
      throw new Error('not found');
    });
    expect(service.pauseJob('missing')).toEqual({
      ok: false,
      name: 'missing',
      error: 'job "missing" not found',
    });

    registry.getCronJob.mockImplementationOnce(() => {
      throw new Error('not found');
    });
    expect(service.resumeJob('missing')).toEqual({
      ok: false,
      name: 'missing',
      error: 'job "missing" not found',
    });
  });
});
