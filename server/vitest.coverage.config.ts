import { resolve } from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    fileParallelism: false,
    maxConcurrency: 1,
    root: resolve(__dirname, 'src'),
    include: ['**/*.unit.spec.ts', '**/*.integration.spec.ts', '**/*.api.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 30000,
    hookTimeout: 15000,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'text-summary', 'html', 'json-summary', 'lcov'],
      include: ['**/*.ts'],
      exclude: ['**/*.spec.ts', 'test-setup.ts', 'common/test/**', 'main.ts'],
      thresholds: {
        lines: 100,
        branches: 100,
        functions: 100,
        statements: 100,
      },
    },
  },
  resolve: { alias: { '@': resolve(__dirname, 'src') } },
});
