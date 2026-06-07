import { expect, test } from '@playwright/test';
import { installAdminApiRoutes } from './fixtures/adminApiRoutes';
import { stabilizePage } from './support/stabilize';

test('admin can navigate to tasks and filter mocked task data', async ({ page }) => {
  await stabilizePage(page);
  await installAdminApiRoutes(page);

  await page.goto('/');

  await expect(page.getByText('FlowPlanV2')).toBeVisible();
  await page.getByTestId('nav-tasks').click();
  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();

  await page
    .getByRole('searchbox', { name: /search tasks and schedules/i })
    .fill('Plan');

  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Daily sync' })).toHaveCount(0);

  await page.getByRole('button', { name: /refresh tasks and schedules/i }).click();
  await expect(page.getByRole('button', { name: 'Plan review' })).toBeVisible();
});
