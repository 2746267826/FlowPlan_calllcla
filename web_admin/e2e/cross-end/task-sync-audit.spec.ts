import { expect, test, type Page, type Request } from '@playwright/test';
import { installCrossEndAdminApiRoutes } from './adminApiRoutes';

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
        if (body.includes('missingMock')) {
          guard.missingMocks.push(`${response.status()} ${response.request().method()} ${url.pathname}: ${body}`);
        }
      })
      .catch(() => undefined);
    guard.checks.push(check);
  });
  missingMockGuards.set(page, guard);
}

async function openCrossEndAdmin(page: Page) {
  installMissingMockGuard(page);
  await installCrossEndAdminApiRoutes(page);
  await page.route('**/api/admin/monitoring/health', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        database: { status: 'ok', message: 'cross-end ready' },
        api: { status: 'ok', message: 'cross-end responding' },
        worker: { status: 'ok', message: 'cross-end idle' },
      }),
    });
  });
  await page.goto('/');
}

async function expectNoMissingMocks(page: Page) {
  const guard = missingMockGuards.get(page);
  if (!guard) return;
  await Promise.all(guard.checks);
  expect(guard.missingMocks).toEqual([]);
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

test('CE-TASK-001 mocked task completion writes audit evidence', async ({ page }) => {
  await openCrossEndAdmin(page);

  await page.locator('.ant-menu-item').nth(1).click();
  await expect(page.getByRole('button', { name: 'Cross-end task', exact: true })).toBeVisible();

  const taskRow = page.locator('.ant-table-row').filter({
    has: page.getByRole('button', { name: 'Cross-end task', exact: true }),
  });
  await taskRow.getByRole('checkbox').click();

  const completeRequest = page.waitForRequest((request) =>
    request.method() === 'PATCH' &&
    requestPath(request) === '/api/admin/data/tasks/task-ce-001',
  );
  await page.locator('button:has(.anticon-check-circle)').click();
  await page.locator('.ant-modal-confirm-btns .ant-btn-primary').click();
  expect(requestJson(await completeRequest)).toMatchObject({
    payload: {
      status: 'done',
      completedAt: expect.any(String),
    },
    reason: 'admin batch complete',
  });

  await page.locator('.ant-menu-item').nth(7).click();
  await expect(page.getByText('task.completed')).toBeVisible();
});

test('CE-SYNC-001 mocked offline conflict exposes device, mutation, and conflict evidence', async ({ page }) => {
  await openCrossEndAdmin(page);

  await page.getByTestId('nav-sync').click();
  await expect(page.getByText('Offline conflict handset')).toBeVisible();
  await expect(page.getByText('cursor-before-conflict')).toBeVisible();

  const offlineRow = page.locator('.ant-table-row').filter({
    hasText: 'Offline conflict handset',
  });
  const historyRequest = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/admin/devices/device-offline-conflict/connection-history',
  );
  const mutationRequest = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/admin/data/sync-mutations',
  );
  const conflictRequest = page.waitForRequest((request) =>
    request.method() === 'GET' &&
    requestPath(request) === '/api/admin/data/conflicts',
  );
  await offlineRow.locator('button').click();
  await historyRequest;

  await page.getByRole('tab').nth(3).click();
  await mutationRequest;
  await expect(page.getByText('mutation-ce-offline-001')).toBeVisible();

  await page.getByRole('tab').nth(4).click();
  await conflictRequest;
  await expect(page.getByText('conflict-ce-offline-001')).toBeVisible();
  await expect(page.getByText('Offline title conflict')).toBeVisible();
});
