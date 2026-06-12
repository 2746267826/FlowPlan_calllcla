import { expect, test, type Page, type Request } from '@playwright/test';
import { installAdminApiRoutes } from './fixtures/adminApiRoutes';
import { stabilizePage } from './support/stabilize';

type MissingMockGuard = {
  checks: Array<Promise<void>>;
  missingMocks: string[];
};

const missingMockGuards = new WeakMap<Page, MissingMockGuard>();

function installMissingMockGuard(page: Page) {
  if (missingMockGuards.has(page)) return;
  const guard: MissingMockGuard = { checks: [], missingMocks: [] };
  page.on('response', (response) => {
    const url = new URL(response.url());
    if (!url.pathname.startsWith('/api/')) return;

    const check = response.text()
      .then((body) => {
        if (body.includes('missingMock') || body.includes('Missing admin e2e API mock')) {
          guard.missingMocks.push(`${response.status()} ${response.request().method()} ${url.pathname}: ${body}`);
        }
      })
      .catch(() => undefined);
    guard.checks.push(check);
  });
  missingMockGuards.set(page, guard);
}

async function expectNoMissingMocks(page: Page) {
  const guard = missingMockGuards.get(page);
  if (!guard) return;
  await Promise.all(guard.checks);
  expect(guard.missingMocks).toEqual([]);
}

async function openAdmin(page: Page) {
  await stabilizePage(page);
  installMissingMockGuard(page);
  await page.addInitScript(() => {
    Object.defineProperty(window.navigator, 'clipboard', {
      configurable: true,
      value: {
        writeText: async (text: string) => {
          (window as Window & { __lastClipboardText?: string }).__lastClipboardText = text;
        },
      },
    });
  });
  await installAdminApiRoutes(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'FlowPlanV2' })).toBeVisible();
  await expect(page.getByText('flowplanv2-test')).toBeVisible();
}

async function openModule(page: Page, key: string) {
  await page.getByTestId(`nav-${key}`).click();
}

async function confirmModal(page: Page) {
  const modal = page.locator('.ant-modal-confirm').last();
  await expect(modal).toBeVisible();
  await modal.locator('.ant-modal-confirm-btns .ant-btn-primary').click();
  await expect(modal).toBeHidden();
}

async function confirmPopconfirm(page: Page) {
  const popconfirm = page.locator('.ant-popconfirm').last();
  await expect(popconfirm).toBeVisible();
  await popconfirm
    .locator('.ant-popconfirm-buttons .ant-btn-primary')
    .evaluate((button) => (button as HTMLElement).click());
  await expect(popconfirm).toBeHidden();
}

async function chooseToolbarSelectOption(page: Page, selectIndex: number, optionIndex: number) {
  await page.locator('.table-toolbar .ant-select-selector').nth(selectIndex).click();
  const dropdown = page.locator('.ant-select-dropdown:not(.ant-select-dropdown-hidden)').last();
  await expect(dropdown).toBeVisible();
  await dropdown
    .locator('.ant-select-item-option')
    .nth(optionIndex)
    .evaluate((option) => (option as HTMLElement).click());
}

function requestJson(request: Request) {
  const body = request.postDataJSON();
  expect(body).toEqual(expect.any(Object));
  return body as Record<string, unknown>;
}

function requestPath(request: Request) {
  return new URL(request.url()).pathname;
}

test.afterEach(async ({ page }) => {
  await expectNoMissingMocks(page);
});

test('admin can navigate every module and refresh dashboard data', async ({ page }) => {
  await openAdmin(page);

  await expect(page.getByText('Audit: remote setting changed').first()).toBeVisible();

  const dashboardRefresh = page.waitForResponse((response) =>
    response.url().includes('/api/admin/dashboard') && response.status() === 200,
  );
  await page.getByRole('button', { name: /refresh dashboard/i }).click();
  await dashboardRefresh;
  await expect(page.getByText('Audit: operation confirmed').first()).toBeVisible();

  const routeChecks: Array<[string, string | RegExp]> = [
    ['tasks', 'Plan review'],
    ['actuals', 'Deep work session'],
    ['files', 'Course Documents'],
    ['reports', 'Weekly report'],
    ['sync', 'Laptop Alpha'],
    ['outlook', 'calendar@example.com'],
    ['audit', 'Audit: remote setting changed'],
    ['settings', 'outlook.sync.enabled'],
    ['logs', 'Audit: operation confirmed'],
    ['jobs', 'Refresh weather cache'],
    ['alerts', 'weather timeout'],
    ['env', 'C:\\FlowPlanStorage'],
  ];

  for (const [key, expectedText] of routeChecks) {
    await openModule(page, key);
    await expect(page.getByText(expectedText).first()).toBeVisible();
  }

  await openModule(page, 'operations');
  await expect(page.locator('textarea')).toHaveValue(/web_admin operation/);

  await openModule(page, 'schedule');
  await expect(page.locator('textarea')).toHaveValue(/"id":"A"/);
});

test('admin can filter, inspect, complete, and soft-delete tasks and schedules', async ({ page }) => {
  await openAdmin(page);
  await openModule(page, 'tasks');

  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Daily sync' })).toBeVisible();

  await page
    .getByRole('searchbox', { name: /search tasks and schedules/i })
    .fill('Plan');

  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Daily sync' })).toHaveCount(0);

  await chooseToolbarSelectOption(page, 0, 2);
  await expect(page.getByRole('button', { name: 'Outlook planning block' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Plan review' })).toHaveCount(0);

  await chooseToolbarSelectOption(page, 0, 0);
  await chooseToolbarSelectOption(page, 1, 2);
  await expect(page.getByRole('button', { name: 'Outlook planning block' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Plan review' })).toHaveCount(0);

  await chooseToolbarSelectOption(page, 1, 1);
  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Outlook planning block' })).toHaveCount(0);

  await page
    .getByRole('searchbox', { name: /search tasks and schedules/i })
    .fill('');
  await chooseToolbarSelectOption(page, 1, 0);
  await chooseToolbarSelectOption(page, 2, 3);
  await expect(page.getByRole('button', { name: 'Daily sync' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Outlook planning block' })).toHaveCount(0);

  await chooseToolbarSelectOption(page, 2, 0);
  await page
    .getByRole('searchbox', { name: /search tasks and schedules/i })
    .fill('Plan');

  const detailRequest = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/admin/data/tasks/task-1',
  );
  await page.getByRole('button', { name: 'Plan review' }).click();
  await detailRequest;
  const detailDrawer = page.getByRole('dialog', { name: /Plan review/ });
  await expect(detailDrawer).toBeVisible();
  await expect(detailDrawer.getByText('task-1')).toBeVisible();

  const detailCompleteRequest = page.waitForRequest((request) =>
    request.method() === 'PATCH' &&
    requestPath(request) === '/api/admin/data/tasks/task-1',
  );
  await detailDrawer.locator('.ant-drawer-extra').getByRole('button').first().click();
  const detailComplete = await detailCompleteRequest;
  expect(requestJson(detailComplete)).toMatchObject({
    payload: {
      status: 'COMPLETED',
      completedAt: expect.any(String),
    },
    reason: 'admin complete task in detail',
  });

  const detailDeleteRequest = page.waitForRequest((request) =>
    request.method() === 'PATCH' &&
    requestPath(request) === '/api/admin/data/tasks/task-1',
  );
  await detailDrawer.locator('.ant-drawer-extra').getByRole('button').last().click();
  await confirmModal(page);
  const detailDelete = await detailDeleteRequest;
  expect(requestJson(detailDelete)).toMatchObject({
    deleted: true,
    reason: 'admin delete from detail drawer',
  });
  await page.keyboard.press('Escape');

  await page
    .getByRole('searchbox', { name: /search tasks and schedules/i })
    .fill('');

  const planRow = page.locator('tr', { hasText: 'Plan review' }).first();
  await planRow.locator('input[type="checkbox"]').check({ force: true });

  const completeRequest = page.waitForRequest((request) =>
    request.method() === 'PATCH' &&
    request.url().includes('/api/admin/data/tasks/task-1'),
  );
  await page
    .getByRole('button', { name: /batch complete selected tasks/i })
    .click();
  await confirmModal(page);
  const batchComplete = await completeRequest;
  expect(requestJson(batchComplete)).toMatchObject({
    payload: {
      status: 'done',
      completedAt: expect.any(String),
    },
    reason: 'admin batch complete',
  });

  const scheduleRow = page.locator('tr', { hasText: 'Outlook planning block' }).first();
  await scheduleRow.locator('input[type="checkbox"]').check({ force: true });

  const deleteRequest = page.waitForRequest((request) =>
    request.method() === 'PATCH' &&
    request.url().includes('/api/admin/data/schedules/schedule-1'),
  );
  await page
    .getByRole('button', { name: /batch delete selected items/i })
    .click();
  await confirmModal(page);
  const batchDelete = await deleteRequest;
  expect(requestJson(batchDelete)).toMatchObject({
    deleted: true,
    reason: 'admin batch delete',
  });

  const refresh = page.waitForResponse((response) =>
    response.url().includes('/api/admin/data/tasks') && response.status() === 200,
  );
  await page
    .getByRole('button', { name: /refresh tasks and schedules/i })
    .click();
  await refresh;
  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();
});

test('admin can manage drive roots through add, scan, search, and delete actions', async ({ page }) => {
  await openAdmin(page);
  await openModule(page, 'files');

  await expect(page.getByText('Course Documents')).toBeVisible();

  const rootsCard = page.locator('.ant-card', { hasText: 'Drive Roots' }).first();
  const courseDiagnosticsRow = page.locator('tr', { hasText: 'Course Documents' }).first();
  await courseDiagnosticsRow.locator('.ant-table-row-expand-icon').click();
  await expect(page.getByText('root-uid-1')).toBeVisible();
  await expect(page.getByText('Scan complete')).toBeVisible();

  const refreshRequest = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/files/drive/roots' &&
    !new URL(request.url()).searchParams.has('q'),
  );
  await rootsCard.locator('button:has(.anticon-reload)').click();
  await refreshRequest;

  const formTextboxes = page.locator('.ant-form').first().getByRole('textbox');
  await formTextboxes.nth(0).fill('Project Archive');
  await formTextboxes.nth(1).fill('C:\\FlowPlanDrive\\ProjectArchive');
  await formTextboxes.nth(2).fill('Project Archive Display');

  const createRequest = page.waitForRequest((request) =>
    request.method() === 'POST' && request.url().endsWith('/api/files/roots'),
  );
  await page.locator('.ant-form').first().getByRole('button', { name: /Drive root/i }).click();
  const createDriveRoot = await createRequest;
  expect(requestJson(createDriveRoot)).toMatchObject({
    name: 'Project Archive',
    rootUri: 'C:\\FlowPlanDrive\\ProjectArchive',
    rootDisplayPath: 'Project Archive Display',
    providerType: 'server_storage',
    isManaged: true,
    syncPolicy: 'metadata_only',
    metadata: { source: 'web_admin_drive_root' },
  });
  await expect(page.getByText('Project Archive')).toBeVisible();

  const archiveRow = page.locator('tr', { hasText: 'Project Archive' }).first();
  const scanRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/files/drive/roots/drive-root-2/scan'),
  );
  await archiveRow.locator('td').last().getByRole('button').first().click();
  const scanDriveRoot = await scanRequest;
  expect(requestJson(scanDriveRoot)).toEqual({});
  await expect(page.getByText('Project Archive')).toBeVisible();

  const searchRequest = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/files/drive/roots' &&
    new URL(request.url()).searchParams.get('q') === 'Course',
  );
  await page.getByPlaceholder(/root/i).fill('Course');
  await page.keyboard.press('Enter');
  await searchRequest;
  await expect(page.getByText('Course Documents')).toBeVisible();
  await expect(page.getByText('Project Archive')).toHaveCount(0);

  const courseRow = page.locator('tr', { hasText: 'Course Documents' }).first();
  const deleteRequest = page.waitForRequest((request) =>
    request.method() === 'DELETE' &&
    request.url().includes('/api/files/drive/roots/drive-root-1'),
  );
  await courseRow.locator('td').last().getByRole('button').last().click();
  await confirmPopconfirm(page);
  await deleteRequest;
  await expect(page.getByText('Course Documents')).toHaveCount(0);
});

test('admin can run Outlook auth, sync, reset, and diagnostics workflows', async ({ page }) => {
  await openAdmin(page);
  await openModule(page, 'outlook');

  await expect(page.getByText('calendar@example.com')).toBeVisible();
  await expect(page.getByText('Admin Calendar')).toBeVisible();

  const authStart = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/outlook/auth/start'),
  );
  const clientIdInput = page.getByPlaceholder(/Microsoft.*Client ID/i);
  await clientIdInput.fill('e2e-client');
  await clientIdInput.press('Enter');
  const authStartRequest = await authStart;
  expect(requestJson(authStartRequest)).toMatchObject({ clientId: 'e2e-client' });

  await page.context().route('https://login.microsoftonline.com/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html',
      body: '<!doctype html><title>Mock Microsoft auth</title><h1>Mock Microsoft auth</h1>',
    });
  });

  await expect(page.getByText(/login\.microsoftonline\.com/)).toBeVisible();
  const authModal = page.locator('.ant-modal-confirm', { hasText: /login\.microsoftonline\.com/ }).last();
  const modalActions = authModal.locator('.ant-modal-confirm-content .ant-btn');
  await expect(modalActions).toHaveCount(2);

  const popupPromise = page.waitForEvent('popup');
  await modalActions.first().click();
  const authPopup = await popupPromise;
  await authPopup.waitForLoadState('domcontentloaded');
  await expect(authPopup).toHaveURL(/login\.microsoftonline\.com/);
  await authPopup.close();

  await modalActions.nth(1).click();
  await expect.poll(() =>
    page.evaluate(() => (window as Window & { __lastClipboardText?: string }).__lastClipboardText ?? ''),
  ).toContain('login.microsoftonline.com');
  await confirmModal(page);

  const authComplete = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/outlook/auth/complete'),
  );
  const callbackInput = page.getByPlaceholder(/Microsoft.*URL/i);
  await callbackInput.fill('http://localhost/outlook/callback?code=e2e');
  await callbackInput.press('Enter');
  const authCompleteRequest = await authComplete;
  expect(requestJson(authCompleteRequest)).toMatchObject({
    callbackUrl: 'http://localhost/outlook/callback?code=e2e',
  });

  const syncRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/outlook/sync'),
  );
  await page.locator('.ant-card-extra button', { has: page.locator('.anticon-cloud-sync') }).click();
  await confirmModal(page);
  await syncRequest;

  const resetRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/outlook/reset'),
  );
  await page.locator('.ant-card-extra button.ant-btn-dangerous').click();
  await confirmModal(page);
  await resetRequest;

  await page.getByRole('tab').nth(2).click();
  await expect(page.getByText('Calendars.Read')).toBeVisible();

  const diagnosticsRefresh = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/admin/outlook/diagnostics',
  );
  await page.locator('.ant-card-extra button:has(.anticon-reload)').click();
  await diagnosticsRefresh;
});

test('admin can inspect devices and update local plus remote settings', async ({ page }) => {
  await openAdmin(page);
  await openModule(page, 'sync');

  await expect(page.getByText('Laptop Alpha')).toBeVisible();
  const deviceRow = page.locator('tr', { hasText: 'Laptop Alpha' }).first();
  await deviceRow.locator('td').last().getByRole('button').click();
  await expect(page.getByText(/device-1|Laptop Alpha/).first()).toBeVisible();
  await page.getByRole('tab').nth(2).click();
  await expect(page.getByText('Laptop Alpha connected')).toBeVisible();
  await page.keyboard.press('Escape');

  await openModule(page, 'settings');
  const connectionInputs = page.locator('.ant-form').first().locator('input');
  await connectionInputs.nth(0).fill('http://127.0.0.1:3999/api');
  await connectionInputs.nth(1).fill('web-admin-e2e');
  await page.locator('.ant-form').first().getByRole('button').click();
  await expect(page.locator('.server-button')).toContainText('http://127.0.0.1:3999');

  const healthCheck = page.waitForRequest((request) =>
    request.url().includes('/api/health'),
  );
  await page.locator('.server-button').click();
  await healthCheck;

  const remoteCard = page.locator('.ant-card', { has: page.locator('textarea') }).first();
  await page.locator('tr', { hasText: 'outlook.sync.enabled' }).first().locator('td').last().getByRole('button').click();
  await expect(remoteCard.locator('input').first()).toHaveValue('outlook.sync.enabled');
  await remoteCard.locator('textarea').fill('{"enabled":false,"minutes":15}');
  const sensitiveSwitch = remoteCard.getByRole('switch', { name: /sensitive remote config/i });
  await sensitiveSwitch.click();
  await expect(sensitiveSwitch).toBeChecked();

  const settingPatch = page.waitForRequest((request) =>
    request.method() === 'PATCH' &&
    request.url().includes('/api/admin/settings/outlook.sync.enabled'),
  );
  await remoteCard.getByRole('button').click();
  const patchSetting = await settingPatch;
  expect(requestJson(patchSetting)).toMatchObject({
    value: { enabled: false, minutes: 15 },
    sensitive: true,
    reason: 'web admin setting update',
  });
  await expect(page.getByText('outlook.sync.enabled')).toBeVisible();
});

test('admin can use logs, jobs, operations, audit details, scheduler, alerts, and env tools', async ({ page }) => {
  await openAdmin(page);

  await openModule(page, 'logs');
  await expect(page.getByText('Audit: remote setting changed').first()).toBeVisible();
  await page.locator('main input[type="text"]').last().fill('operation');
  await expect(page.getByText('Audit: operation confirmed')).toBeVisible();
  await expect(page.getByText('Audit: remote setting changed')).toHaveCount(0);

  await openModule(page, 'jobs');
  await expect(page.getByText('Refresh weather cache')).toBeVisible();
  const weatherJob = page.locator('.ant-card', { hasText: 'Refresh weather cache' }).first();
  const triggerJob = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/jobs/refresh-weather-cache/trigger'),
  );
  await weatherJob.getByRole('button').first().click();
  await confirmPopconfirm(page);
  await triggerJob;

  const pauseJob = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/jobs/refresh-weather-cache/pause'),
  );
  await page.getByRole('button', { name: /pause job refresh-weather-cache/i }).click();
  await confirmPopconfirm(page);
  await pauseJob;
  await expect(weatherJob.getByText('paused')).toBeVisible();

  const resumeJob = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/jobs/refresh-weather-cache/resume'),
  );
  await page.getByRole('button', { name: /resume job refresh-weather-cache/i }).click();
  await confirmPopconfirm(page);
  await resumeJob;
  await expect(weatherJob.getByText('idle')).toBeVisible();

  await openModule(page, 'operations');
  const prepareRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/operations/rebuild-sync-index/prepare'),
  );
  await page.locator('.ant-card').filter({ has: page.locator('textarea') }).getByRole('button').first().click();
  await prepareRequest;
  await expect(page.getByText('e2e-confirmation-token')).toBeVisible();

  const confirmRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/operations/rebuild-sync-index/confirm'),
  );
  await page.locator('.ant-card').filter({ has: page.locator('textarea') }).getByRole('button').last().click();
  await confirmModal(page);
  await confirmRequest;
  await expect(page.getByText('audit-operation-confirm')).toBeVisible();

  await openModule(page, 'audit');
  await page.locator('main').getByRole('searchbox').fill('remote setting');
  await expect(page.getByText('Audit: remote setting changed').first()).toBeVisible();
  await page.locator('tr', { hasText: 'Audit: remote setting changed' }).first().locator('td').last().getByRole('button').click();
  const auditDrawer = page.getByRole('dialog', { name: /Audit: remote setting changed/ });
  await expect(auditDrawer).toBeVisible();
  await expect(auditDrawer.getByText('audit-1')).toBeVisible();
  await page.keyboard.press('Escape');

  await openModule(page, 'schedule');
  const topoRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/scheduler/dependency/topo'),
  );
  await page.locator('.ant-tabs-tabpane-active').getByRole('button').click();
  await topoRequest;
  await expect(page.getByText('已排序: A → B')).toBeVisible();

  await page.getByRole('tab').nth(1).click();
  const geneticRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/scheduler/genetic/evolve'),
  );
  await page.locator('.ant-tabs-tabpane-active').getByRole('button').click();
  await geneticRequest;
  await expect(page.getByText(/98/)).toBeVisible();

  await openModule(page, 'alerts');
  await expect(page.getByText('weather timeout')).toBeVisible();
  await expect(page.getByText('push delivery bounced')).toBeVisible();

  await openModule(page, 'env');
  await expect(page.getByText('C:\\FlowPlanStorage')).toBeVisible();
  const uploadRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    request.url().includes('/api/admin/env/upload'),
  );
  await page.locator('textarea').fill('FLOWPLANV2_E2E=true');
  await page.getByRole('button').filter({ has: page.locator('.anticon-upload') }).click();
  await uploadRequest;
});
