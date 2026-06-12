import { expect, test, type Page } from '@playwright/test';
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

function requestPath(url: string) {
  return new URL(url).pathname;
}

test.afterEach(async ({ page }) => {
  await expectNoMissingMocks(page);
});

test('CE-REPORT-001 mocked report evidence is visible from reports and audit pages', async ({ page }) => {
  await openCrossEndAdmin(page);

  const reportsRequest = page.waitForResponse((response) =>
    response.request().method() === 'GET' &&
    requestPath(response.url()) === '/api/admin/data/reports' &&
    response.status() === 200,
  );
  const pushDeliveriesRequest = page.waitForResponse((response) =>
    response.request().method() === 'GET' &&
    requestPath(response.url()) === '/api/admin/data/push-deliveries' &&
    response.status() === 200,
  );
  await page.getByTestId('nav-reports').click();
  await reportsRequest;
  await pushDeliveriesRequest;
  await expect(page.getByText('Cross-end evidence report')).toBeVisible();
  await expect(page.getByText('Includes task, file, AI, and sync evidence links')).toBeVisible();
  await expect(page.getByText('cross-end-acceptance')).toBeVisible();
  await expect(page.getByText('queued')).toBeVisible();

  const auditRequest = page.waitForResponse((response) =>
    response.request().method() === 'GET' &&
    requestPath(response.url()) === '/api/admin/data/audit-logs' &&
    response.status() === 200,
  );
  await page.getByTestId('nav-audit').click();
  await auditRequest;
  await expect(page.getByText('report.generated')).toBeVisible();
  await expect(page.getByText('report-ce-001')).toBeVisible();
  await expect(page.getByText('Cross-end evidence report generated')).toBeVisible();
});
