import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { DatabaseService } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { AnalyticsService } from './analytics.service';
import { cleanDatabase, createTestUser, createTestDevice } from '../common/test/test-utils';
import type { FlowPlanV2RequestContext } from '../common/request-context';

describe('AnalyticsService', () => {
  let db: DatabaseService;
  let service: AnalyticsService;
  let ctx: FlowPlanV2RequestContext;

  beforeAll(async () => {
    db = new DatabaseService();
    await db.onModuleInit();
    const devices = new DevicesService(db);
    service = new AnalyticsService(db, devices);
  });

  afterAll(async () => {
    await db.onModuleDestroy();
  });

  beforeEach(async () => {
    await cleanDatabase(db);
    const user = await createTestUser(db, { id: '00000000-0000-0000-0000-000000000001' });
    const dev = await createTestDevice(db, user.id, { id: '00000000-0000-0000-0000-000000000101' });
    ctx = { userId: user.id, deviceId: dev.id };
  });

  it('returns trackerHome with empty data', async () => {
    const result = await service.trackerHome({}, ctx);
    expect(result.range).toBeDefined();
    expect(result.daySummary).toBeDefined();
    expect(result.activityHeatmap.buckets).toEqual([]);
  });

  it('returns activityDaySummary for today', async () => {
    const result = await service.activityDaySummary({}, ctx);
    expect(result.range).toBeDefined();
    expect(result.insights.recordCount).toBe(0);
  });

  it('returns activityHeatmap (MV or live fallback)', async () => {
    const result = await service.activityHeatmap(
      { start: '2024-01-01', end: '2024-01-31' },
      ctx,
    );
    expect(result.buckets).toEqual([]);
    expect(['materialized_view', 'server-live-sync-objects']).toContain(result.source);
  });

  it('returns inputHeatmap (MV or live fallback)', async () => {
    const result = await service.inputHeatmap(
      { start: '2024-01-01', end: '2024-01-31' },
      ctx,
    );
    expect(result.buckets).toEqual([]);
    expect(['materialized_view', 'server-live-sync-objects']).toContain(result.source);
  });

  it('returns topApps with empty data', async () => {
    const result = await service.topApps({}, ctx);
    expect(result.items).toEqual([]);
  });

  it('returns topCategories with empty data', async () => {
    const result = await service.topCategories({}, ctx);
    expect(result.items).toEqual([]);
  });

  it('returns filterOptions', async () => {
    const result = await service.filterOptions({}, ctx);
    expect(result.processOptions).toEqual([]);
    expect(result.categoryOptions).toEqual([]);
  });

  it('exports CSV', async () => {
    const result = await service.exportCSV(
      { start: '2024-01-01', end: '2024-01-31' },
      ctx,
    );
    expect(result.format).toBe('csv');
    expect(result.headers.length).toBeGreaterThan(0);
    expect(typeof result.data).toBe('string');
  });

  it('exports JSON', async () => {
    const result = await service.exportJSON(
      { start: '2024-01-01', end: '2024-01-31' },
      ctx,
    );
    expect(result.format).toBe('json');
    expect(result.items).toEqual([]);
  });
});
