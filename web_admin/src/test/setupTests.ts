import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import React from 'react';
import { afterAll, afterEach, beforeAll, vi } from 'vitest';
import { server } from './msw/server';

vi.mock('@ant-design/charts', () => ({
  Area: (props: { data?: unknown[] }) =>
    React.createElement('div', {
      role: 'img',
      'aria-label': `area chart with ${props.data?.length ?? 0} points`,
    }),
  Line: (props: { data?: unknown[] }) =>
    React.createElement('div', {
      role: 'img',
      'aria-label': `line chart with ${props.data?.length ?? 0} points`,
    }),
}));

vi.mock('@ant-design/pro-components', async () => {
  const mock = await import('./mocks/proComponents');
  return mock;
});

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

class ResizeObserverMock {
  observe() {}
  unobserve() {}
  disconnect() {}
}

class IntersectionObserverMock {
  observe() {}
  unobserve() {}
  disconnect() {}
  takeRecords() {
    return [];
  }
}

Object.defineProperty(window, 'ResizeObserver', {
  writable: true,
  value: ResizeObserverMock,
});
Object.defineProperty(window, 'IntersectionObserver', {
  writable: true,
  value: IntersectionObserverMock,
});
Object.defineProperty(Element.prototype, 'scrollTo', {
  writable: true,
  value: vi.fn(),
});
Object.defineProperty(window, 'scrollTo', {
  writable: true,
  value: vi.fn(),
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));

afterEach(() => {
  cleanup();
  server.resetHandlers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

afterAll(() => server.close());
