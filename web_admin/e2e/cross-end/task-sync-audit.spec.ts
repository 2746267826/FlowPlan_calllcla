import { expect, test } from '@playwright/test';
import { installCrossEndAdminApiRoutes } from './adminApiRoutes';

test('CE-TASK-001 mocked task completion writes audit evidence', async ({ page }) => {
  await installCrossEndAdminApiRoutes(page);
  await page.goto('/');

  await page.locator('.ant-menu-item').nth(1).click();
  await expect(page.getByRole('button', { name: 'Cross-end task', exact: true })).toBeVisible();

  const taskRow = page.locator('.ant-table-row').filter({
    has: page.getByRole('button', { name: 'Cross-end task', exact: true }),
  });
  await taskRow.getByRole('checkbox').click();

  await page.locator('button:has(.anticon-check-circle)').click();
  await page.locator('.ant-modal-confirm-btns .ant-btn-primary').click();

  await page.locator('.ant-menu-item').nth(7).click();
  await expect(page.getByText('task.completed')).toBeVisible();
});
