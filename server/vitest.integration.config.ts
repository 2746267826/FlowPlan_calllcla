import { resolve } from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    fileParallelism: false,
    maxConcurrency: 1,
    root: resolve(__dirname, 'src'),
    include: ['**/*.integration.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 30000,
    hookTimeout: 15000,
  },
  resolve: { alias: { '@': resolve(__dirname, 'src') } },
});
