import type { Page, Request, Route } from '@playwright/test';

const now = '2026-06-08T09:00:00.000Z';

type AdminRouteRecord = Record<string, any>;

const taskRows: AdminRouteRecord[] = [
  {
    id: 'task-1',
    title: 'Plan review',
    status: 'open',
    source: 'local',
    dueAt: '2026-06-08T09:00:00.000Z',
    taskListName: 'Admin QA',
    description: 'Review the rollout checklist',
    location: 'Focus room',
  },
  {
    id: 'task-2',
    title: 'Daily sync',
    status: 'todo',
    source: 'local',
    dueAt: '2026-06-09T02:00:00.000Z',
    taskListName: 'Admin QA',
    description: 'Follow up with mobile team',
  },
];

const scheduleRows: AdminRouteRecord[] = [
  {
    id: 'schedule-1',
    summary: 'Outlook planning block',
    status: 'CONFIRMED',
    source: 'outlook',
    dtstart: '2026-06-08T10:00:00.000Z',
    dtend: '2026-06-08T10:30:00.000Z',
    calendarName: 'Work Calendar',
    location: 'Teams',
  },
];

const actualRows: AdminRouteRecord[] = [
  {
    id: 'actual-1',
    title: 'Deep work session',
    source: 'tracker',
    startAt: '2026-06-08T07:00:00.000Z',
    endAt: '2026-06-08T08:30:00.000Z',
    confidence: 0.92,
    status: 'confirmed',
  },
];

const reportRows: AdminRouteRecord[] = [
  {
    id: 'report-1',
    title: 'Weekly report',
    period: '2026-W23',
    status: 'completed',
    generatedAt: now,
    summary: 'Plan review and Outlook sync are healthy',
  },
];

const pushRows: AdminRouteRecord[] = [
  {
    id: 'push-1',
    channel: 'email',
    target: 'ops@example.com',
    status: 'failed',
    createdAt: now,
    error: 'SMTP test failure',
  },
];

const auditRows: AdminRouteRecord[] = [
  {
    id: 'audit-1',
    action: 'admin.remote_config.upsert',
    actor: 'admin',
    entityType: 'settings',
    entityId: 'outlook.sync.enabled',
    summary: 'Audit: remote setting changed',
    occurredAt: now,
    metadata: { configKey: 'outlook.sync.enabled', source: 'e2e' },
  },
  {
    id: 'audit-2',
    action: 'admin.operation.confirm',
    actor: 'server',
    entityType: 'operation',
    entityId: 'retry-failed-pushes',
    summary: 'Audit: operation confirmed',
    occurredAt: '2026-06-08T09:05:00.000Z',
    metadata: { affectedCount: 2 },
  },
];

const deviceRows: AdminRouteRecord[] = [
  {
    id: 'device-1',
    deviceId: 'device-1',
    deviceName: 'Laptop Alpha',
    platform: 'windows',
    status: 'online',
    lastHeartbeatAt: now,
    lastConnectedAt: now,
    appVersion: '1.5.0',
    networkType: 'wifi',
    syncPendingCount: 2,
    syncFailedCount: 1,
    openConflictCount: 1,
    pullCursor: 'cursor-alpha',
  },
];

const driveRoots: AdminRouteRecord[] = [
  {
    id: 'drive-root-1',
    rootUid: 'root-uid-1',
    name: 'Course Documents',
    providerType: 'server_storage',
    rootUri: 'C:\\FlowPlanDrive\\CourseDocs',
    rootDisplayPath: 'Course Docs',
    scanStatus: 'completed',
    lastScanAt: now,
    syncPolicy: 'metadata_only',
    nodeCount: 8,
    fileCount: 5,
    folderCount: 3,
    totalBytes: 4096,
    storageObjectCount: 2,
    storageTotalBytes: 2048,
    lastOperation: 'scan',
    lastOperationStatus: 'completed',
    lastOperationAt: now,
    metadata: {
      lastScan: {
        scanned: 8,
        applied: 8,
        phase: 'completed',
        progressMessage: 'Scan complete',
        startedAt: '2026-06-08T08:59:00.000Z',
        finishedAt: now,
      },
    },
  },
];

const settingRows: AdminRouteRecord[] = [
  {
    id: 'setting-1',
    configKey: 'outlook.sync.enabled',
    scope: 'global',
    sensitive: false,
    value: { enabled: true },
    updatedAt: now,
  },
];

const jobs: AdminRouteRecord[] = [
  {
    name: 'refresh-weather-cache',
    status: 'idle',
    running: false,
    cron: '0 */6 * * *',
    description: 'Refresh weather cache',
    lastRun: '2026-06-08T06:00:00.000Z',
    nextRun: '2026-06-08T12:00:00.000Z',
  },
  {
    name: 'auto-generate-reports',
    status: 'running',
    running: true,
    cron: '0 18 * * *',
    description: 'Generate daily report',
  },
];

async function fulfillJson(route: Route, json: unknown, status = 200) {
  await route.fulfill({
    status,
    contentType: 'application/json',
    body: JSON.stringify(json),
  });
}

function postDataJson(request: Request): AdminRouteRecord {
  try {
    const body = request.postDataJSON();
    return body && typeof body === 'object' && !Array.isArray(body)
      ? body as AdminRouteRecord
      : {};
  } catch {
    return {};
  }
}

export async function installAdminApiRoutes(page: Page) {
  await page.route('**/api/**', async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const method = request.method();

    if (path === '/api/auth/login' || path === '/api/auth/refresh') {
      await fulfillJson(route, {
        accessToken: 'test-token',
        refreshToken: 'refresh-token',
        user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
      });
      return;
    }

    if (path === '/api/health') {
      await fulfillJson(route, {
        ok: true,
        service: 'flowplanv2-test',
        phase: 'ready',
        time: now,
      });
      return;
    }

    if (path === '/api/admin/dashboard') {
      await fulfillJson(route, {
        generatedAt: '2026-06-08T08:00:00.000Z',
        overview: { users: 1 },
        pending: { conflicts: 1, aiDrafts: 2, failedPushes: 1, failedJobs: 1 },
        recentAuditLogs: auditRows,
      });
      return;
    }

    if (path === '/api/admin/monitoring/health') {
      await fulfillJson(route, {
        database: { status: 'ok', message: 'ready' },
        api: { status: 'ok', message: 'responding' },
        worker: { status: 'degraded', message: 'one retry queued' },
      });
      return;
    }

    if (path === '/api/admin/sync-health') {
      await fulfillJson(route, { devices: deviceRows, rows: deviceRows });
      return;
    }

    if (path === '/api/admin/devices/device-1/connection-history') {
      await fulfillJson(route, {
        rows: [
          {
            id: 'history-1',
            type: 'connected',
            summary: 'Laptop Alpha connected',
            createdAt: now,
          },
        ],
      });
      return;
    }

    if (path === '/api/admin/devices/online-summary') {
      await fulfillJson(route, { online: 1, total: 1 });
      return;
    }

    if (path === '/api/admin/settings' && method === 'GET') {
      await fulfillJson(route, { rows: settingRows });
      return;
    }

    if (path.startsWith('/api/admin/settings/') && method === 'PATCH') {
      const configKey = decodeURIComponent(path.split('/').pop() ?? '');
      const body = postDataJson(request);
      settingRows.unshift({
        id: `setting-${settingRows.length + 1}`,
        configKey,
        scope: 'global',
        sensitive: Boolean(body.sensitive),
        value: body.value ?? body,
        updatedAt: now,
      });
      await fulfillJson(route, { ok: true, configKey });
      return;
    }

    if (path === '/api/files/drive/roots' && method === 'GET') {
      const q = url.searchParams.get('q')?.toLowerCase() ?? '';
      const roots = q
        ? driveRoots.filter((root) =>
            `${root.name} ${root.rootUri}`.toLowerCase().includes(q),
          )
        : driveRoots;
      await fulfillJson(route, { roots });
      return;
    }

    if (path === '/api/files/roots' && method === 'POST') {
      const body = postDataJson(request);
      const id = `drive-root-${driveRoots.length + 1}`;
      driveRoots.unshift({
        id,
        rootUid: id,
        name: String(body.name ?? 'New Drive Root'),
        providerType: 'server_storage',
        rootUri: String(body.rootUri ?? 'C:\\FlowPlanDrive\\NewRoot'),
        rootDisplayPath: String(body.rootDisplayPath ?? ''),
        scanStatus: 'idle',
        syncPolicy: 'metadata_only',
        nodeCount: 0,
        fileCount: 0,
        folderCount: 0,
        totalBytes: 0,
        metadata: {},
      });
      await fulfillJson(route, { ok: true, id });
      return;
    }

    if (path.match(/^\/api\/files\/drive\/roots\/[^/]+\/scan$/) && method === 'POST') {
      const rootId = decodeURIComponent(path.split('/').at(-2) ?? '');
      const root = driveRoots.find((item) => item.id === rootId);
      if (root) {
        root.scanStatus = 'completed';
        root.lastScanAt = now;
        root.metadata = {
          ...root.metadata,
          lastScan: { scanned: 9, applied: 9, phase: 'completed' },
        };
      }
      await fulfillJson(route, { ok: true, rootId, scanned: 9, status: 'completed' });
      return;
    }

    if (path.match(/^\/api\/files\/drive\/roots\/[^/]+$/) && method === 'DELETE') {
      const rootId = decodeURIComponent(path.split('/').pop() ?? '');
      const index = driveRoots.findIndex((item) => item.id === rootId);
      if (index >= 0) driveRoots.splice(index, 1);
      await fulfillJson(route, { ok: true, deletedCounts: { nodes: 8, files: 5 } });
      return;
    }

    if (path === '/api/admin/outlook/status') {
      await fulfillJson(route, {
        connected: true,
        status: 'connected',
        clientIdConfigured: true,
        accountEmail: 'calendar@example.com',
        accountDisplayName: 'Calendar User',
        lastSyncAt: now,
        readOnly: true,
        encryptionKeySecure: true,
        scope: 'Calendars.Read',
      });
      return;
    }

    if (path === '/api/admin/outlook/calendars') {
      await fulfillJson(route, {
        rows: [
          {
            id: 'cal-1',
            name: 'Admin Calendar',
            enabled: true,
            color: '#1f6f78',
          },
        ],
      });
      return;
    }

    if (path === '/api/admin/outlook/runs') {
      await fulfillJson(route, {
        rows: [
          {
            id: 'run-1',
            status: 'completed',
            scope: 'calendar',
            summary: 'Read-only sync completed',
            createdAt: now,
          },
        ],
      });
      return;
    }

    if (path === '/api/admin/outlook/diagnostics') {
      await fulfillJson(route, {
        tokenStore: 'encrypted',
        redirectUri: 'http://localhost/outlook/callback',
      });
      return;
    }

    if (path === '/api/admin/outlook/auth/start' && method === 'POST') {
      await fulfillJson(route, {
        authorizeUrl: 'https://login.microsoftonline.com/test/oauth2/v2.0/authorize?client_id=e2e-client',
      });
      return;
    }

    if (path === '/api/admin/outlook/auth/complete' && method === 'POST') {
      await fulfillJson(route, { ok: true, connected: true });
      return;
    }

    if (path === '/api/admin/outlook/sync' && method === 'POST') {
      await fulfillJson(route, { ok: true, runId: 'run-2' });
      return;
    }

    if (path === '/api/admin/outlook/reset' && method === 'POST') {
      await fulfillJson(route, { ok: true });
      return;
    }

    if (path.match(/^\/api\/admin\/operations\/[^/]+\/prepare$/) && method === 'POST') {
      await fulfillJson(route, {
        ok: true,
        operationKey: decodeURIComponent(path.split('/').at(-2) ?? ''),
        confirmationToken: 'e2e-confirmation-token',
        affectedCount: 2,
        risk: 'medium',
      });
      return;
    }

    if (path.match(/^\/api\/admin\/operations\/[^/]+\/confirm$/) && method === 'POST') {
      await fulfillJson(route, {
        ok: true,
        operationKey: decodeURIComponent(path.split('/').at(-2) ?? ''),
        auditId: 'audit-operation-confirm',
        status: 'completed',
      });
      return;
    }

    if (path === '/api/scheduler/dependency/topo' && method === 'POST') {
      await fulfillJson(route, {
        sorted: ['A', 'B'],
        hasCycle: false,
        layers: [['A'], ['B']],
        cycles: [],
      });
      return;
    }

    if (path === '/api/scheduler/genetic/evolve' && method === 'POST') {
      await fulfillJson(route, {
        best: {
          fitness: 98,
          genes: [
            {
              taskId: 't1',
              start: '2026-01-01T09:00:00.000Z',
              end: '2026-01-01T10:00:00.000Z',
              order: 1,
            },
          ],
        },
      });
      return;
    }

    if (path === '/api/admin/jobs' && method === 'GET') {
      await fulfillJson(route, { jobs });
      return;
    }

    if (path.match(/^\/api\/admin\/jobs\/[^/]+\/(trigger|pause|resume)$/) && method === 'POST') {
      const parts = path.split('/');
      const jobName = decodeURIComponent(parts.at(-2) ?? '');
      const op = parts.at(-1);
      const job = jobs.find((item) => item.name === jobName);
      if (job) {
        job.status = op === 'pause' ? 'paused' : 'idle';
        job.running = false;
        job.lastRun = now;
      }
      await fulfillJson(route, { ok: true, jobName, op });
      return;
    }

    if (path === '/api/admin/alerts') {
      await fulfillJson(route, {
        trackingFailures: [
          { id: 'alert-1', status: 'failed', lastError: 'weather timeout', updatedAt: now },
        ],
        syncFailures: [
          { id: 'alert-2', status: 'failed', lastError: 'mutation retry needed', updatedAt: now },
        ],
        outlookFailures: [],
        jobFailures: [],
        pushFailures: [
          { id: 'alert-3', status: 'failed', lastError: 'push delivery bounced', updatedAt: now },
        ],
      });
      return;
    }

    if (path === '/api/admin/env' && method === 'GET') {
      await fulfillJson(route, {
        generatedAt: now,
        database: { urlPresent: true, poolMax: 10, slowQueryThresholdMs: 250 },
        encryption: { keySecure: true, source: 'env' },
        jwt: { accessExpires: '15m', refreshExpires: '30d' },
        service: { port: 3202, host: '127.0.0.1', bodyLimit: '10mb', corsOrigin: '*' },
        storage: { dir: 'C:\\FlowPlanStorage' },
        kopia: { exePath: 'kopia.exe', timeoutMs: 30000 },
      });
      return;
    }

    if (path === '/api/admin/env/upload' && method === 'POST') {
      await fulfillJson(route, { ok: true, message: 'env uploaded' });
      return;
    }

    if (path === '/api/admin/data/tasks' && method === 'GET') {
      await fulfillJson(route, { items: taskRows });
      return;
    }

    if (path === '/api/admin/data/schedules' && method === 'GET') {
      await fulfillJson(route, { items: scheduleRows });
      return;
    }

    if (path === '/api/admin/data/actuals' && method === 'GET') {
      await fulfillJson(route, { rows: actualRows });
      return;
    }

    if (path === '/api/admin/data/reports' && method === 'GET') {
      await fulfillJson(route, { rows: reportRows });
      return;
    }

    if (path === '/api/admin/data/push-deliveries' && method === 'GET') {
      await fulfillJson(route, { rows: pushRows });
      return;
    }

    if (path === '/api/admin/data/audit-logs' && method === 'GET') {
      await fulfillJson(route, { rows: auditRows });
      return;
    }

    if (path === '/api/admin/data/sync-mutations' && method === 'GET') {
      await fulfillJson(route, {
        rows: [
          { id: 'mutation-1', type: 'write_failed', summary: 'Device mutation failed', createdAt: now },
        ],
      });
      return;
    }

    if (path === '/api/admin/data/conflicts' && method === 'GET') {
      await fulfillJson(route, {
        rows: [
          { id: 'conflict-1', type: 'task_conflict', summary: 'Task changed on two devices', createdAt: now },
        ],
      });
      return;
    }

    const detailMatch = path.match(/^\/api\/admin\/data\/([^/]+)\/([^/]+)$/);
    if (detailMatch && method === 'GET') {
      const [, domain, id] = detailMatch;
      await fulfillJson(route, {
        id: decodeURIComponent(id),
        domain: decodeURIComponent(domain),
        summary: `Detail for ${decodeURIComponent(id)}`,
        before: { status: 'open' },
        after: { status: 'done' },
      });
      return;
    }

    if (detailMatch && method === 'PATCH') {
      const [, domain, id] = detailMatch;
      if (domain === 'tasks') {
        const task = taskRows.find((item) => item.id === decodeURIComponent(id));
        if (task) task.status = 'done';
      }
      await fulfillJson(route, {
        ok: true,
        domain: decodeURIComponent(domain),
        id: decodeURIComponent(id),
        auditId: 'audit-patch',
      });
      return;
    }

    if (path.startsWith('/api/admin/data/')) {
      await fulfillJson(route, { rows: [] });
      return;
    }

    await fulfillJson(route, { ok: false, error: `Missing admin e2e API mock: ${method} ${path}` }, 501);
  });
}
