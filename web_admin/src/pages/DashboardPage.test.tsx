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

    renderWithProviders(
      <DashboardPage
        api={api as never}
        onDataRefresh={onDataRefresh}
        onOpenDetail={vi.fn()}
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
  });
});
