import type { Page, Route } from '@playwright/test';

const now = '2026-06-08T09:00:00.000Z';

export async function installCrossEndAdminApiRoutes(page: Page): Promise<void> {
  await page.route('**/api/**', async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const method = request.method();

    if (path === '/api/auth/login' || path === '/api/auth/refresh') {
      return json(route, {
        accessToken: 'cross-end-access-token',
        refreshToken: 'cross-end-refresh-token',
        user: { id: 'ce-user-001', displayName: 'Cross End Admin' },
      });
    }

    if (path === '/api/health') {
      return json(route, { ok: true, service: 'flowplanv2-test', time: now });
    }

    if (path === '/api/admin/sync-health') {
      return json(route, {
        rows: [
          {
            id: 'device-web-admin',
            deviceId: 'device-web-admin',
            deviceName: 'Web Admin Test Device',
            platform: 'web-admin',
            status: 'online',
          },
        ],
      });
    }

    if (path === '/api/admin/dashboard') {
      return json(route, {
        pending: { tasks: 1, aiDrafts: 1, alerts: 0 },
        recentAuditLogs: [
          {
            id: 'audit-ce-task',
            action: 'task.completed',
            entityType: 'task',
            summary: 'Cross-end task completed',
            occurredAt: now,
          },
        ],
      });
    }

    if (path === '/api/admin/data/tasks' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'task-ce-001',
            uid: 'ce-task-001',
            title: 'Cross-end task',
            status: 'todo',
            source: 'client',
            dueAt: now,
            updatedAt: now,
          },
        ],
      });
    }

    if (path === '/api/admin/data/schedules' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'schedule-ce-001',
            title: 'Cross-end task schedule',
            status: 'planned',
            source: 'scheduler',
            startAt: now,
            endAt: '2026-06-08T09:45:00.000Z',
          },
        ],
      });
    }

    if (path.startsWith('/api/admin/data/tasks/') && method === 'PATCH') {
      return json(route, {
        ok: true,
        id: path.split('/').pop(),
        status: 'done',
        auditId: 'audit-ce-task',
      });
    }

    if (path === '/api/admin/data/audit-logs' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'audit-ce-task',
            action: 'task.completed',
            entityType: 'task',
            entityId: 'task-ce-001',
            summary: 'Cross-end task completed from Web Admin',
            occurredAt: now,
          },
        ],
      });
    }

    if (path === '/api/files/drive/roots' && method === 'GET') {
      return json(route, {
        roots: [
          {
            id: 'drive-root-ce-001',
            name: 'Cross End Drive Root',
            rootUri: 'C:\\FlowPlanDrive\\CrossEnd',
            scanStatus: 'completed',
            nodeCount: 3,
            fileCount: 2,
            folderCount: 1,
            totalBytes: 10485760,
            metadata: {
              lastScan: {
                scanned: 3,
                phase: 'completed',
                hashVerified: true,
              },
            },
          },
        ],
      });
    }

    if (path.match(/^\/api\/files\/drive\/roots\/[^/]+\/scan$/) && method === 'POST') {
      return json(route, {
        ok: true,
        rootId: path.split('/').at(-2),
        scanned: 3,
        status: 'completed',
        recovery: 'resumable',
      });
    }

    if (path.match(/^\/api\/admin\/operations\/[^/]+\/prepare$/) && method === 'POST') {
      return json(route, {
        ok: true,
        operationKey: path.split('/').at(-2),
        confirmationToken: 'ce-confirmation-token',
        affectedCount: 1,
        auditPreview: 'ai.operation.prepare',
      });
    }

    if (path.match(/^\/api\/admin\/operations\/[^/]+\/confirm$/) && method === 'POST') {
      return json(route, {
        ok: true,
        operationKey: path.split('/').at(-2),
        auditId: 'audit-ce-ai-001',
        status: 'completed',
      });
    }

    return json(route, { ok: false, missingMock: `${method} ${path}` }, 404);
  });
}

async function json(route: Route, body: unknown, status = 200): Promise<void> {
  await route.fulfill({
    status,
    contentType: 'application/json',
    body: JSON.stringify(body),
  });
}
