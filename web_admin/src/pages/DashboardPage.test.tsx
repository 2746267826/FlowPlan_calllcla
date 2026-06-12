import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import {
  dashboardPayload,
  monitoringHealthPayload,
  syncHealthPayload,
} from '../test/fixtures/adminData';
import { DashboardPage } from './DashboardPage';

describe('DashboardPage', () => {
  it('loads dashboard evidence and refreshes the summary on demand', async () => {
    const api = createMockAdminApi({
      dashboard: vi.fn().mockResolvedValue(dashboardPayload),
      monitoringHealth: vi.fn().mockResolvedValue(monitoringHealthPayload),
      syncHealth: vi.fn().mockResolvedValue(syncHealthPayload),
    });
    const onDataRefresh = vi.fn();
    const onOpenDetail = vi.fn();

    renderWithProviders(
      <DashboardPage
        api={api as never}
        onDataRefresh={onDataRefresh}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(screen.getByText('3')).toBeInTheDocument();
    expect(onDataRefresh).toHaveBeenCalledTimes(1);

    await userEvent.click(
      screen.getByRole('button', { name: /refresh dashboard/i }),
    );

    await waitFor(() => expect(api.dashboard).toHaveBeenCalledTimes(2));
    expect(onDataRefresh).toHaveBeenCalledTimes(2);

    await userEvent.click(screen.getByRole('button', { name: /详\s*情/ }));
    expect(onOpenDetail).toHaveBeenCalledWith(
      'auditLogs',
      expect.objectContaining({ id: 'audit-1' }),
    );
  });

  it('keeps refresh re-entrant while dashboard loading is in progress', async () => {
    let resolveDashboard: (value: typeof dashboardPayload) => void = () => {};
    const dashboard = vi
      .fn()
      .mockReturnValueOnce(
        new Promise((resolve) => {
          resolveDashboard = resolve;
        }),
      )
      .mockResolvedValue(dashboardPayload);
    const api = createMockAdminApi({
      dashboard,
      monitoringHealth: vi.fn().mockResolvedValue(monitoringHealthPayload),
      syncHealth: vi.fn().mockResolvedValue(syncHealthPayload),
    });
    const onDataRefresh = vi.fn();

    renderWithProviders(
      <DashboardPage
        api={api as never}
        onDataRefresh={onDataRefresh}
        onOpenDetail={vi.fn()}
      />,
    );

    await userEvent.click(
      screen.getByRole('button', { name: /refresh dashboard/i }),
    );
    expect(dashboard).toHaveBeenCalledTimes(2);
    await waitFor(() => expect(onDataRefresh).toHaveBeenCalledTimes(1));

    resolveDashboard(dashboardPayload);

    await waitFor(() => expect(onDataRefresh).toHaveBeenCalledTimes(2));
    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
  });

  it('falls back to an empty device summary when sync health fails', async () => {
    const syncHealth = vi.fn().mockRejectedValue(new Error('sync offline'));
    const api = createMockAdminApi({
      dashboard: vi.fn().mockResolvedValue(dashboardPayload),
      monitoringHealth: vi.fn().mockResolvedValue(monitoringHealthPayload),
      syncHealth,
    });
    const onDataRefresh = vi.fn();

    renderWithProviders(
      <DashboardPage
        api={api as never}
        onDataRefresh={onDataRefresh}
        onOpenDetail={vi.fn()}
      />,
    );

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(syncHealth).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(onDataRefresh).toHaveBeenCalledTimes(1));
  });
});
