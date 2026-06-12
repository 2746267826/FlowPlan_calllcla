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
          {
            id: 'device-offline-conflict',
            deviceId: 'device-offline-conflict',
            deviceName: 'Offline conflict handset',
            platform: 'flutter',
            status: 'offline',
            lastSeenAt: '2026-06-08T08:50:00.000Z',
            lastDisconnectedAt: '2026-06-08T08:55:00.000Z',
            lastConnectionError: 'offline_conflict_ce_001',
            syncPendingCount: 2,
            syncFailedCount: 1,
            openConflictCount: 1,
            pullCursor: 'cursor-before-conflict',
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
          {
            id: 'audit-ce-report',
            action: 'report.generated',
            entityType: 'report',
            summary: 'Cross-end evidence report generated',
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
          {
            id: 'audit-ce-file',
            action: 'file.drive.root.scan',
            entityType: 'file_root',
            entityId: 'drive-root-ce-001',
            summary: 'Cross-end Drive root scan completed',
            occurredAt: now,
          },
          {
            id: 'audit-ce-ai-001',
            action: 'ai.operation.confirm',
            entityType: 'ai_operation',
            entityId: 'recompute-report-summary',
            summary: 'Cross-end AI operation confirmed',
            occurredAt: now,
          },
          {
            id: 'audit-ce-report',
            action: 'report.generated',
            entityType: 'report',
            entityId: 'report-ce-001',
            summary: 'Cross-end evidence report generated',
            occurredAt: now,
          },
        ],
      });
    }

    if (path === '/api/admin/devices/device-offline-conflict/connection-history' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'history-ce-offline-001',
            type: 'disconnect',
            status: 'offline',
            summary: 'Device disconnected before pushing local task edit',
            createdAt: '2026-06-08T08:55:00.000Z',
          },
        ],
      });
    }

    if (path === '/api/admin/data/sync-mutations' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'mutation-ce-offline-001',
            mutationUid: 'mutation-ce-offline-001',
            objectType: 'task_item',
            action: 'update',
            status: 'conflict',
            result: 'conflict',
            summary: 'mutation-ce-offline-001: Offline task title edit collided with server version 3',
            createdAt: now,
          },
        ],
      });
    }

    if (path === '/api/admin/data/conflicts' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'conflict-ce-offline-001',
            conflictId: 'conflict-ce-offline-001',
            objectType: 'task_item',
            status: 'open',
            summary: 'conflict-ce-offline-001: Offline title conflict',
            fields: [
              {
                field: 'title',
                base: 'Cross-end task',
                local: 'Cross-end task from phone',
                server: 'Cross-end task from web',
              },
            ],
            createdAt: now,
          },
        ],
      });
    }

    if (path === '/api/admin/data/reports' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'report-ce-001',
            title: 'Cross-end evidence report',
            period: '2026-06-08',
            status: 'draft',
            generatedAt: now,
            summary: 'Includes task, file, AI, and sync evidence links',
          },
        ],
      });
    }

    if (path === '/api/admin/data/push-deliveries' && method === 'GET') {
      return json(route, {
        rows: [
          {
            id: 'delivery-ce-report-001',
            channel: 'manual-preview',
            target: 'cross-end-acceptance',
            status: 'queued',
            createdAt: now,
            error: null,
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
