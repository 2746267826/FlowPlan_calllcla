import { describe, expect, it, vi } from 'vitest';
import { AnalyticsController } from './analytics.controller';

const headers = {
  'x-flowplanv2-user-id': '11111111-1111-4111-8111-111111111111',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

function mockAnalyticsService() {
  return new Proxy(
    {},
    {
      get(target, prop: string) {
        if (!(prop in target)) {
          (target as Record<string, unknown>)[prop] = vi.fn((...args: unknown[]) => ({
            method: prop,
            args,
          }));
        }
        return (target as Record<string, unknown>)[prop];
      },
    },
  ) as Record<string, ReturnType<typeof vi.fn>>;
}

describe('AnalyticsController', () => {
  it('forwards activity overview endpoints with parsed request context', () => {
    const service = mockAnalyticsService();
    const controller = new AnalyticsController(service as never);

    expect(controller.trackerHome({ date: '2026-06-08' }, headers)).toEqual({
      method: 'trackerHome',
      args: [{ date: '2026-06-08' }, context],
    });
    expect(controller.activityDaySummary({ date: '2026-06-08' }, headers)).toEqual({
      method: 'activityDaySummary',
      args: [{ date: '2026-06-08' }, context],
    });
    expect(controller.rangeAnalysis({ bucket: 'day' }, headers)).toEqual({
      method: 'rangeAnalysis',
      args: [{ bucket: 'day' }, context],
    });
    expect(controller.filterOptions({ start: '2026-06-01T00:00:00.000Z' }, headers)).toEqual({
      method: 'filterOptions',
      args: [{ start: '2026-06-01T00:00:00.000Z' }, context],
    });
  });

  it('forwards heatmap and ranked metric endpoints', () => {
    const service = mockAnalyticsService();
    const controller = new AnalyticsController(service as never);

    expect(controller.activityHeatmap({ bucket: 'hour', processName: 'Code' }, headers)).toEqual({
      method: 'activityHeatmap',
      args: [{ bucket: 'hour', processName: 'Code' }, context],
    });
    expect(controller.inputHeatmap({ eventKind: 'key_down' }, headers)).toEqual({
      method: 'inputHeatmap',
      args: [{ eventKind: 'key_down' }, context],
    });
    expect(controller.activityRangeSummary({ start: '2026-06-01T00:00:00.000Z' }, headers)).toEqual({
      method: 'activityRangeSummary',
      args: [{ start: '2026-06-01T00:00:00.000Z' }, context],
    });
    expect(controller.topApps({ limit: '5' }, headers)).toEqual({
      method: 'topApps',
      args: [{ limit: '5' }, context],
    });
    expect(controller.topCategories({ limit: '5' }, headers)).toEqual({
      method: 'topCategories',
      args: [{ limit: '5' }, context],
    });
    expect(controller.taskWorkSummary({ taskId: 'task-1' }, headers)).toEqual({
      method: 'taskWorkSummary',
      args: [{ taskId: 'task-1' }, context],
    });
    expect(controller.focusTrends({ bucket: 'day' }, headers)).toEqual({
      method: 'focusTrends',
      args: [{ bucket: 'day' }, context],
    });
  });

  it('forwards detail and export endpoints', () => {
    const service = mockAnalyticsService();
    const controller = new AnalyticsController(service as never);

    expect(controller.activityRecords({ offset: '10' }, headers)).toEqual({
      method: 'activityRecords',
      args: [{ offset: '10' }, context],
    });
    expect(controller.inputEvents({ offset: '10' }, headers)).toEqual({
      method: 'inputEvents',
      args: [{ offset: '10' }, context],
    });
    expect(controller.exportCSV({ start: '2026-06-01T00:00:00.000Z' }, headers)).toEqual({
      method: 'exportCSV',
      args: [{ start: '2026-06-01T00:00:00.000Z' }, context],
    });
    expect(controller.exportJSON({ end: '2026-06-08T00:00:00.000Z' }, headers)).toEqual({
      method: 'exportJSON',
      args: [{ end: '2026-06-08T00:00:00.000Z' }, context],
    });
  });

  it('uses the default request context when analytics headers are invalid', () => {
    const service = mockAnalyticsService();
    const controller = new AnalyticsController(service as never);

    expect(controller.activityHeatmap({}, { 'x-flowplanv2-user-id': 'bad' })).toEqual({
      method: 'activityHeatmap',
      args: [
        {},
        {
          userId: '00000000-0000-4000-8000-000000000001',
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
  });
});
