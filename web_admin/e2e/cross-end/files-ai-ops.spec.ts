import { expect, test } from '@playwright/test';
import { installCrossEndAdminApiRoutes } from './adminApiRoutes';

test('CE-FILE-001 mocked Drive root scan exposes recovery evidence', async ({ page }) => {
  await installCrossEndAdminApiRoutes(page);
  await page.goto('/');

  await page.locator('.ant-menu-item').nth(3).click();
  await expect(page.getByText('Cross End Drive Root')).toBeVisible();

  await page.locator('button:has(.anticon-cloud-sync)').click();
  await expect(page.getByText('completed').first()).toBeVisible();
});

test('CE-AI-001 mocked controlled operation exposes audit-ready evidence', async ({ page }) => {
  await installCrossEndAdminApiRoutes(page);
  await page.goto('/');

  await expect(page.getByText(/AI/).first()).toBeVisible();
  await page.locator('.ant-menu-item').nth(9).click();

  await page.locator('button.ant-btn-primary').click();
  await expect(page.getByText('ce-confirmation-token')).toBeVisible();

  await page.locator('button.ant-btn-dangerous').click();
  await page.locator('.ant-modal-confirm-btns .ant-btn-primary').click();
  await expect(page.getByText('audit-ce-ai-001')).toBeVisible();
});
