import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { DevicesPage } from './DevicesPage';
import { OutlookPage } from './OutlookPage';

describe('final workflow coverage for DevicesPage', () => {
  it('opens a device detail drawer, reviews every related tab, and closes it', async () => {
    const api = createMockAdminApi({
      syncHealth: vi.fn().mockResolvedValue({
        devices: [
          {
            clientDeviceId: 'client-only-device',
            deviceName: null,
            runtimePlatform: 'desktop-runtime',
            status: 'online',
            syncPendingCount: 1,
            syncFailedCount: 1,
            openConflictCount: 1,
            lastHeartbeatAt: '2026-06-08T08:00:00.000Z',
          },
        ],
      }),
      deviceConnectionHistory: vi.fn().mockResolvedValue({
        items: [
          {
            occurredAt: '2026-06-08T08:01:00.000Z',
            action: 'connect',
            message: 'Connected through fallback history fields',
          },
          {
            id: 'history-id-fallback',
            type: 'heartbeat',
          },
        ],
      }),
      adminRows: vi
        .fn()
        .mockResolvedValueOnce([
          {
            updatedAt: '2026-06-08T08:02:00.000Z',
            status: 'failed',
            reason: 'Mutation failed through fallback reason',
          },
        ])
        .mockResolvedValueOnce([
          {
            updatedAt: '2026-06-08T08:03:00.000Z',
            error: 'Conflict rendered through fallback error',
          },
        ]),
    });

    renderWithProviders(
      <DevicesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('desktop-runtime')).toBeInTheDocument();

    const row = screen.getByText('desktop-runtime').closest('tr');
    expect(row).not.toBeNull();
    await userEvent.click(within(row!).getByRole('button'));

    const drawer = await screen.findByRole('dialog');
    expect((await within(drawer).findAllByText('client-only-device')).length)
      .toBeGreaterThan(0);
    await waitFor(() =>
      expect(api.deviceConnectionHistory).toHaveBeenCalledWith(
        'client-only-device',
      ),
    );
    expect(api.adminRows).toHaveBeenNthCalledWith(1, 'sync-mutations', {
      deviceId: 'client-only-device',
      limit: 50,
    });
    expect(api.adminRows).toHaveBeenNthCalledWith(2, 'conflicts', {
      deviceId: 'client-only-device',
      limit: 50,
    });

    const drawerTabs = within(drawer).getAllByRole('tab');
    await userEvent.click(drawerTabs[2]);
    expect(
      await screen.findByText('Connected through fallback history fields'),
    ).toBeInTheDocument();
    expect(screen.getByText('history-id-fallback')).toBeInTheDocument();

    await userEvent.click(drawerTabs[3]);
    expect(
      await screen.findByText('Mutation failed through fallback reason'),
    ).toBeInTheDocument();

    await userEvent.click(drawerTabs[4]);
    expect(
      await screen.findByText('Conflict rendered through fallback error'),
    ).toBeInTheDocument();

    await userEvent.click(
      drawer.querySelector('.ant-drawer-close') as HTMLElement,
    );
    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    );
  }, 30000);
});

describe('final workflow coverage for OutlookPage', () => {
  it('renders a configured authorization step and secure diagnostics', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockResolvedValue({
        connected: false,
        status: 'ready',
        clientIdConfigured: true,
        readOnly: true,
        encryptionKeySecure: true,
        scope: 'Calendars.Read',
      }),
      outlookCalendars: vi.fn().mockResolvedValue({
        items: [{ id: 'configured-calendar', name: 'Configured Calendar' }],
      }),
      outlookRuns: vi.fn().mockResolvedValue({ items: [] }),
      outlookDiagnostics: vi.fn().mockResolvedValue({ ok: true }),
    });

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Configured Calendar')).toBeInTheDocument();

    await userEvent.click(screen.getAllByRole('tab')[2]);
    expect(await screen.findByText('Calendars.Read')).toBeInTheDocument();
  }, 30000);

  it('renders default account data, fallback calendar/run rows, and diagnostics', async () => {
    const onDataRefresh = vi.fn();
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockResolvedValue({
        connected: false,
        status: '',
        clientIdConfigured: false,
        readOnly: false,
        encryptionKeySecure: false,
        scope: '',
      }),
      outlookCalendars: vi.fn().mockResolvedValue({
        calendars: [
          {
            summary: 'Fallback Calendar Without Id',
            selected: true,
            hexColor: '#336699',
          },
        ],
      }),
      outlookRuns: vi.fn().mockResolvedValue({
        runs: [
          {
            startedAt: '2026-06-08T09:00:00.000Z',
            status: 'success',
            mode: 'fallback-run-mode',
            message: 'Run rendered without a stable id',
          },
        ],
      }),
      outlookDiagnostics: vi.fn().mockResolvedValue({
        transport: 'graph',
        account: null,
      }),
    });

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={onDataRefresh} />,
    );

    expect(
      await screen.findByText('Fallback Calendar Without Id'),
    ).toBeInTheDocument();
    expect(screen.getByText('#336699')).toBeInTheDocument();
    await waitFor(() => expect(onDataRefresh).toHaveBeenCalledTimes(1));

    await userEvent.click(screen.getAllByRole('tab')[1]);
    expect(await screen.findByText('fallback-run-mode')).toBeInTheDocument();
    expect(screen.getByText('Run rendered without a stable id')).toBeInTheDocument();

    await userEvent.click(screen.getAllByRole('tab')[2]);
    expect(
      await screen.findByText(/FLOWPLANV2_ENCRYPTION_KEY/),
    ).toBeInTheDocument();

    await userEvent.click(
      document.querySelector('.raw-collapse .ant-collapse-header') as HTMLElement,
    );
    expect(await screen.findByText(/graph/)).toBeInTheDocument();
  }, 30000);
});
