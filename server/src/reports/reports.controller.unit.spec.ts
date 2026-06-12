import { describe, expect, it, vi } from 'vitest';
import { ReportsController } from './reports.controller';

const headers = {
  'x-flowplanv2-user-id': '11111111-1111-4111-8111-111111111111',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

function mockReportsService() {
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

describe('ReportsController', () => {
  it('forwards report document endpoints with parsed request context', () => {
    const service = mockReportsService();
    const controller = new ReportsController(service as never);

    expect(controller.reports({ status: 'draft' }, headers)).toEqual({
      method: 'reports',
      args: [{ status: 'draft' }, context],
    });
    expect(controller.report('report-1', headers)).toEqual({
      method: 'report',
      args: ['report-1', context],
    });
    expect(controller.generateReport({ reportType: 'daily' }, headers)).toEqual({
      method: 'generateReport',
      args: [{ reportType: 'daily' }, context],
    });
    expect(controller.updateReport('report-1', { title: 'Updated' }, headers)).toEqual({
      method: 'updateReport',
      args: ['report-1', { title: 'Updated' }, context],
    });
    expect(controller.confirmReport('report-1', headers)).toEqual({
      method: 'confirmReport',
      args: ['report-1', context],
    });
    expect(controller.polishReport('report-1', headers)).toEqual({
      method: 'polishReport',
      args: ['report-1', context],
    });
    expect(controller.pushReport('report-1', { channelIds: ['email'] }, headers)).toEqual({
      method: 'pushReport',
      args: ['report-1', { channelIds: ['email'] }, context],
    });
  });

  it('forwards diary endpoints with body and route params', () => {
    const service = mockReportsService();
    const controller = new ReportsController(service as never);

    expect(controller.diary({ limit: '5' }, headers)).toEqual({
      method: 'diary',
      args: [{ limit: '5' }, context],
    });
    expect(controller.generateDiary({ date: '2026-06-08' }, headers)).toEqual({
      method: 'generateDiary',
      args: [{ date: '2026-06-08' }, context],
    });
    expect(controller.updateDiary('diary-1', { title: 'Day' }, headers)).toEqual({
      method: 'updateDiary',
      args: ['diary-1', { title: 'Day' }, context],
    });
    expect(controller.confirmDiary('diary-1', headers)).toEqual({
      method: 'confirmDiary',
      args: ['diary-1', context],
    });
    expect(controller.polishDiary('diary-1', headers)).toEqual({
      method: 'polishDiary',
      args: ['diary-1', context],
    });
  });

  it('forwards template, push, weather, and quality endpoints', () => {
    const service = mockReportsService();
    const controller = new ReportsController(service as never);

    expect(controller.templates(headers)).toEqual({
      method: 'templates',
      args: [context],
    });
    expect(controller.upsertTemplate({ templateType: 'daily_report' }, headers)).toEqual({
      method: 'upsertTemplate',
      args: [{ templateType: 'daily_report' }, context],
    });
    expect(controller.pushChannels(headers)).toEqual({
      method: 'pushChannels',
      args: [context],
    });
    expect(controller.upsertPushChannel({ channelType: 'webhook' }, headers)).toEqual({
      method: 'upsertPushChannel',
      args: [{ channelType: 'webhook' }, context],
    });
    expect(controller.pushDeliveries({ status: 'failed' }, headers)).toEqual({
      method: 'pushDeliveries',
      args: [{ status: 'failed' }, context],
    });
    expect(controller.retryDelivery('delivery-1', headers)).toEqual({
      method: 'retryDelivery',
      args: ['delivery-1', context],
    });
    expect(controller.weatherLocations(headers)).toEqual({
      method: 'weatherLocations',
      args: [context],
    });
    expect(controller.upsertWeatherLocation({ name: 'Shanghai' }, headers)).toEqual({
      method: 'upsertWeatherLocation',
      args: [{ name: 'Shanghai' }, context],
    });
    expect(controller.refreshWeather('weather-1', headers)).toEqual({
      method: 'refreshWeather',
      args: ['weather-1', context],
    });
    expect(controller.weatherSummary({ date: '2026-06-08' }, headers)).toEqual({
      method: 'weatherSummary',
      args: [{ date: '2026-06-08' }, context],
    });
    expect(controller.reportQuality('report-1', headers)).toEqual({
      method: 'reportQualityScore',
      args: ['report-1', context],
    });
    expect(controller.compareReports('report-1', 'report-2', headers)).toEqual({
      method: 'compareReports',
      args: ['report-1', 'report-2', context],
    });
  });

  it('passes report generation and push DTOs through unchanged while returning service results', () => {
    const service = {
      generateReport: vi.fn(() => ({ reportId: 'report-1', modelUsed: 'rule_learned' })),
      pushReport: vi.fn(() => ({ queued: true, deliveryIds: ['delivery-1'] })),
    };
    const controller = new ReportsController(service as never);
    const generateDto = {
      reportType: 'weekly',
      date: '2026-06-08',
      useLlm: true,
      locationId: 'weather-1',
    };
    const pushDto = {
      channelIds: ['email', 'webhook'],
      confirmationToken: 'token-1',
    };

    expect(controller.generateReport(generateDto, headers)).toEqual({
      reportId: 'report-1',
      modelUsed: 'rule_learned',
    });
    expect(controller.pushReport('report-1', pushDto, headers)).toEqual({
      queued: true,
      deliveryIds: ['delivery-1'],
    });
    expect(service.generateReport.mock.calls[0]).toEqual([generateDto, context]);
    expect(service.generateReport.mock.calls[0][0]).toBe(generateDto);
    expect(service.pushReport.mock.calls[0]).toEqual(['report-1', pushDto, context]);
    expect(service.pushReport.mock.calls[0][1]).toBe(pushDto);
  });

  it('passes compare query target and parsed context to compareReports', () => {
    const service = {
      compareReports: vi.fn(() => ({ delta: { entryCount: 2 } })),
    };
    const controller = new ReportsController(service as never);

    expect(controller.compareReports('report-current', 'report-baseline', headers)).toEqual({
      delta: { entryCount: 2 },
    });
    expect(service.compareReports).toHaveBeenCalledWith(
      'report-current',
      'report-baseline',
      context,
    );
  });

  it('falls back to the default context when headers are invalid', () => {
    const service = mockReportsService();
    const controller = new ReportsController(service as never);

    expect(controller.templates({ 'x-flowplanv2-user-id': 'bad' })).toEqual({
      method: 'templates',
      args: [
        {
          userId: '00000000-0000-4000-8000-000000000001',
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
  });

  it('uses the first array header value and defaults invalid device headers independently', () => {
    const service = mockReportsService();
    const controller = new ReportsController(service as never);

    expect(
      controller.reports(
        { status: 'confirmed', limit: '10' },
        {
          'x-flowplanv2-user-id': [context.userId, '11111111-1111-4111-8111-000000000000'],
          'x-flowplanv2-device-id': ['bad-device-id'],
        },
      ),
    ).toEqual({
      method: 'reports',
      args: [
        { status: 'confirmed', limit: '10' },
        {
          userId: context.userId,
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
  });

  it('passes service errors through without wrapping them', () => {
    const service = {
      report: vi.fn(() => {
        throw new Error('report not found');
      }),
    };
    const controller = new ReportsController(service as never);

    expect(() => controller.report('missing-report', headers)).toThrow('report not found');
  });
});
