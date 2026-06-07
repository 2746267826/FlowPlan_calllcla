import type { Page } from '@playwright/test';

export async function stabilizePage(page: Page) {
  await page.addInitScript(() => {
    const styleText = `
      *, *::before, *::after {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        scroll-behavior: auto !important;
        transition-duration: 0.01ms !important;
      }
    `;
    const installStyle = () => {
      const style = document.createElement('style');
      style.setAttribute('data-test-stabilize', 'true');
      style.textContent = styleText;
      document.head.appendChild(style);
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', installStyle, {
        once: true,
      });
    } else {
      installStyle();
    }
  });
}
