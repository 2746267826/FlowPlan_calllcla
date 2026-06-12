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

test('CE-FILE-001 mocked Drive root scan exposes recovery evidence', async ({ page }) => {
  await openCrossEndAdmin(page);

  await page.locator('.ant-menu-item').nth(3).click();
  await expect(page.getByText('Cross End Drive Root')).toBeVisible();

  const scanRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    requestPath(request) === '/api/files/drive/roots/drive-root-ce-001/scan',
  );
  await page.locator('button:has(.anticon-cloud-sync)').click();
  expect(requestJson(await scanRequest)).toEqual({});
  await expect(page.getByText('completed').first()).toBeVisible();
});

test('CE-AI-001 mocked controlled operation exposes audit-ready evidence', async ({ page }) => {
  await openCrossEndAdmin(page);

  await expect(page.getByText(/AI/).first()).toBeVisible();
  await page.locator('.ant-menu-item').nth(9).click();

  await page.locator('.ant-select-selector').first().click();
  await page
    .locator('.ant-select-dropdown:not(.ant-select-dropdown-hidden)')
    .last()
    .locator('.ant-select-item-option')
    .nth(3)
    .click();

  const prepareRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    requestPath(request) === '/api/admin/operations/recompute-report-summary/prepare',
  );
  await page.locator('button.ant-btn-primary').click();
  expect(requestJson(await prepareRequest)).toMatchObject({
    payload: { reason: 'web_admin operation' },
    reason: 'web_admin prepare',
  });
  await expect(page.getByText('ce-confirmation-token')).toBeVisible();

  const confirmRequest = page.waitForRequest((request) =>
    request.method() === 'POST' &&
    requestPath(request) === '/api/admin/operations/recompute-report-summary/confirm',
  );
  await page.locator('button.ant-btn-dangerous').click();
  await page.locator('.ant-modal-confirm-btns .ant-btn-primary').click();
  expect(requestJson(await confirmRequest)).toMatchObject({
    payload: { reason: 'web_admin operation' },
    confirmationToken: 'ce-confirmation-token',
    reason: 'web_admin confirm',
  });
  await expect(page.getByText('audit-ce-ai-001')).toBeVisible();
});
