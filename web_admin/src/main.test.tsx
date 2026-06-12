import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('main bootstrap', () => {
  beforeEach(() => {
    vi.resetModules();
    document.body.innerHTML = '<div id="root"></div>';
  });

  afterEach(() => {
    vi.doUnmock('react-dom/client');
    vi.doUnmock('./app/AdminApp');
  });

  it('mounts AdminApp into the root element inside StrictMode', async () => {
    const render = vi.fn();
    const createRoot = vi.fn(() => ({ render }));
    const AdminApp = vi.fn(() => null);

    vi.doMock('react-dom/client', () => ({
      default: { createRoot },
      createRoot,
    }));
    vi.doMock('./app/AdminApp', () => ({ AdminApp }));

    await import('./main');

    expect(createRoot).toHaveBeenCalledWith(document.getElementById('root'));
    expect(render).toHaveBeenCalledTimes(1);
    const renderedTree = render.mock.calls[0]?.[0] as {
      type: unknown;
      props: { children: { type: unknown } };
    };
    expect(renderedTree.type).toBe(React.StrictMode);
    expect(renderedTree.props.children.type).toBe(AdminApp);
  });
});
