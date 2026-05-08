import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    fileParallelism: false,
    maxConcurrency: 1,
    root: resolve(__dirname, 'src'),
    include: ['**/*.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 15000,
    hookTimeout: 15000,
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
});
