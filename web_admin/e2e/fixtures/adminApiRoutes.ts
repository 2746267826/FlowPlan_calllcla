import type { Page, Route } from '@playwright/test';

const taskRows = [
  {
    id: 'task-1',
    title: 'Plan review',
    status: 'open',
    source: 'local',
    dueAt: '2026-06-08T09:00:00.000Z',
  },
];

const scheduleRows = [
  {
    id: 'schedule-1',
    summary: 'Daily sync',
    status: 'CONFIRMED',
    source: 'outlook',
    dtstart: '2026-06-08T10:00:00.000Z',
  },
];

async function fulfillJson(route: Route, json: unknown) {
  await route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(json),
  });
}

export async function installAdminApiRoutes(page: Page) {
  await page.route('**/api/**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;

    if (path === '/api/auth/login' || path === '/api/auth/refresh') {
      await fulfillJson(route, {
        accessToken: 'test-token',
        refreshToken: 'refresh-token',
        user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
      });
      return;
    }

    if (path === '/api/health') {
      await fulfillJson(route, { ok: true });
      return;
    }

    if (path === '/api/admin/dashboard') {
      await fulfillJson(route, {
        generatedAt: '2026-06-08T08:00:00.000Z',
        pending: { conflicts: 1, aiDrafts: 0, failedPushes: 0, failedJobs: 0 },
        recentAuditLogs: [],
      });
      return;
    }

    if (path === '/api/admin/monitoring/health') {
      await fulfillJson(route, {
        database: { status: 'ok', message: 'ready' },
        api: { status: 'ok', message: 'responding' },
      });
      return;
    }

    if (path === '/api/admin/sync-health') {
      await fulfillJson(route, {
        devices: [{ deviceId: 'device-1', status: 'online' }],
      });
      return;
    }

    if (path === '/api/admin/data/tasks') {
      await fulfillJson(route, { items: taskRows });
      return;
    }

    if (path === '/api/admin/data/schedules') {
      await fulfillJson(route, { items: scheduleRows });
      return;
    }

    if (path.startsWith('/api/admin/data/')) {
      await fulfillJson(route, { items: [] });
      return;
    }

    await fulfillJson(route, { ok: true });
  });
}
