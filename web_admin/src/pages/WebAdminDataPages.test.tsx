import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { datasets } from '../app/constants';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { AuditPage } from './AuditPage';
import { BusinessListPage } from './BusinessListPage';
import { DevicesPage } from './DevicesPage';
import { DriveFilesPage } from './DriveFilesPage';
import { LogsPage } from './LogsPage';
import { SettingsPage } from './SettingsPage';

async function confirmLatestPopconfirm() {
  const confirmButton = document.querySelector(
    '.ant-popconfirm-buttons .ant-btn-primary',
  ) as HTMLElement | null;
  expect(confirmButton).not.toBeNull();
  await userEvent.click(confirmButton!);
}

async function chooseSelectOption(selectIndex: number, optionText: string) {
  const selectors = document.querySelectorAll('.ant-select-selector');
  expect(selectors[selectIndex]).toBeTruthy();
  fireEvent.mouseDown(selectors[selectIndex]);

  let options: Element[] = [];
  await waitFor(() => {
    const dropdowns = Array.from(
      document.querySelectorAll('.ant-select-dropdown'),
    );
    const dropdown = dropdowns[dropdowns.length - 1];
    options = dropdown
      ? Array.from(dropdown.querySelectorAll('.ant-select-item-option'))
      : [];
    expect(
      options.some((item) => item.textContent?.includes(optionText)),
    ).toBe(true);
  });

  const option = options.find((item) =>
    item.textContent?.includes(optionText),
  ) as HTMLElement;
  fireEvent.click(option);
}

function rowActionButton(row: HTMLElement) {
  const button = within(row)
    .getAllByRole('button')
    .find((item) => !item.classList.contains('ant-table-row-expand-icon'));
  expect(button).toBeTruthy();
  return button as HTMLElement;
}

describe('DriveFilesPage', () => {
  it('loads roots, searches, saves a root, refreshes, and scans a row', async () => {
    const api = createMockAdminApi({
      driveRoots: vi.fn().mockResolvedValue({
        roots: [
          {
            id: 'root-1',
            name: 'Course files',
            rootUri: 'C:\\FlowPlanDrive\\Documents',
            scanStatus: 'idle',
            nodeCount: 3,
            fileCount: 2,
            folderCount: 1,
          },
        ],
      }),
      upsertDriveRoot: vi.fn().mockResolvedValue({ ok: true }),
      scanDriveRoot: vi.fn().mockResolvedValue({ ok: true, scanned: 3 }),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Course files')).toBeInTheDocument();

    await userEvent.type(
      screen.getByPlaceholderText('搜索 root 名称或路径'),
      'Course{enter}',
    );
    await waitFor(() => expect(api.driveRoots).toHaveBeenCalledWith('Course'));

    await userEvent.type(
      screen.getByLabelText('显示名称'),
      'Course files',
    );
    await userEvent.type(
      screen.getByLabelText('服务器绝对路径'),
      'C:\\FlowPlanDrive\\Documents',
    );
    await userEvent.type(
      screen.getByLabelText('显示路径'),
      'Documents',
    );
    await userEvent.click(
      screen.getByRole('button', { name: /保存 Drive root/ }),
    );

    await waitFor(() =>
      expect(api.upsertDriveRoot).toHaveBeenCalledWith({
        name: 'Course files',
        rootUri: 'C:\\FlowPlanDrive\\Documents',
        rootDisplayPath: 'Documents',
      }),
    );

    await userEvent.click(
      screen.getByRole('button', { name: /scan drive root course files/i }),
    );
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledWith('root-1'));

    await userEvent.click(screen.getByRole('button', { name: /刷新/ }));
    await waitFor(() => expect(api.driveRoots).toHaveBeenCalledTimes(5));
  }, 30000);

  it('shows an operation error when loading roots fails', async () => {
    const api = createMockAdminApi({
      driveRoots: vi.fn().mockRejectedValue(new Error('storage offline')),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('操作失败')).toBeInTheDocument();
    expect(screen.getByText(/storage offline/)).toBeInTheDocument();
  });

  it('confirms and deletes a drive root index without deleting server files', async () => {
    const api = createMockAdminApi({
      driveRoots: vi
        .fn()
        .mockResolvedValueOnce({
          roots: [
            {
              id: 'root-1',
              name: 'Course files',
              rootUri: 'C:\\FlowPlanDrive\\Documents',
              scanStatus: 'idle',
            },
          ],
        })
        .mockResolvedValueOnce({ roots: [] }),
      deleteDriveRoot: vi.fn().mockResolvedValue({
        ok: true,
        deletedCounts: { nodes: 3 },
      }),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Course files')).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole('button', { name: /delete drive root course files/i }),
    );
    await confirmLatestPopconfirm();

    await waitFor(() =>
      expect(api.deleteDriveRoot).toHaveBeenCalledWith('root-1'),
    );
    await waitFor(() => expect(api.driveRoots).toHaveBeenCalledTimes(2));
  });
});

describe('DevicesPage', () => {
  it('loads devices, refreshes, and opens the device drawer with related data', async () => {
    const api = createMockAdminApi({
      syncHealth: vi.fn().mockResolvedValue({
        devices: [
          {
            deviceId: 'device-1',
            deviceName: 'Desk client',
            platform: 'windows',
            status: 'online',
            syncPendingCount: 2,
            syncFailedCount: 1,
            openConflictCount: 1,
            lastHeartbeatAt: '2026-06-08T08:00:00.000Z',
          },
        ],
      }),
      deviceConnectionHistory: vi.fn().mockResolvedValue({
        items: [{ id: 'history-1', type: 'connect', summary: 'Connected' }],
      }),
      adminRows: vi
        .fn()
        .mockResolvedValueOnce([{ id: 'failure-1', error: 'Write failed' }])
        .mockResolvedValueOnce([{ id: 'conflict-1', summary: 'Conflict' }]),
    });

    renderWithProviders(
      <DevicesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Desk client')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /刷新/ }));
    await waitFor(() => expect(api.syncHealth).toHaveBeenCalledTimes(2));

    await userEvent.click(screen.getByRole('button', { name: /查\s*看/ }));

    expect(await screen.findByText(/设备详情/)).toBeInTheDocument();
    await waitFor(() =>
      expect(api.deviceConnectionHistory).toHaveBeenCalledWith('device-1'),
    );

    const drawer = screen.getByRole('dialog');
    const drawerTabs = within(drawer).getAllByRole('tab');
    await userEvent.click(drawerTabs[3]);
    expect(await screen.findByText('Write failed')).toBeInTheDocument();

    await userEvent.click(drawerTabs[4]);
    expect(await screen.findByText('Conflict')).toBeInTheDocument();
  });

  it('renders fallback device fields and empty detail tabs after related loads fail', async () => {
    const api = createMockAdminApi({
      syncHealth: vi.fn().mockResolvedValue({
        devices: [
          {
            id: 'fallback-client',
            platform: '',
            syncPendingCount: '3.7',
            openConflictCount: 'bad count',
          },
          {
            clientDeviceId: 'heartbeat-client',
            runtimePlatform: 'linux',
            lastHeartbeatAt: '2026-06-08T08:00:00.000Z',
          },
        ],
      }),
      deviceConnectionHistory: vi.fn().mockRejectedValue(new Error('history down')),
      adminRows: vi.fn().mockRejectedValue(new Error('rows down')),
    });

    renderWithProviders(
      <DevicesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('fallback-client')).toBeInTheDocument();
    expect(screen.getByText('linux')).toBeInTheDocument();

    const row = screen.getByText('fallback-client').closest('tr');
    expect(row).not.toBeNull();
    await userEvent.click(within(row!).getByRole('button'));

    const drawer = await screen.findByRole('dialog');
    await waitFor(() =>
      expect(api.deviceConnectionHistory).toHaveBeenCalledWith('fallback-client'),
    );

    const drawerTabs = within(drawer).getAllByRole('tab');
    await userEvent.click(drawerTabs[2]);
    expect(drawer.querySelector('.ant-empty')).not.toBeNull();

    await userEvent.click(drawerTabs[3]);
    expect(drawer.querySelector('.ant-empty')).not.toBeNull();

    await userEvent.click(drawerTabs[4]);
    expect(drawer.querySelector('.ant-empty')).not.toBeNull();
  });
});

describe('BusinessListPage', () => {
  it('loads readable rows, filters by search, refreshes, and opens detail', async () => {
    const api = createMockAdminApi({
      request: vi.fn().mockResolvedValue({
        items: [
          {
            id: 'actual-1',
            title: 'Focus block',
            status: 'done',
            source: 'tracker',
            startedAt: '2026-06-08T09:00:00.000Z',
          },
          { id: 'actual-2', title: 'Filtered away', status: 'open' },
        ],
      }),
    });
    const onOpenDetail = vi.fn();

    renderWithProviders(
      <BusinessListPage
        title="Actuals"
        description="Readable actual records"
        panels={[
          {
            dataset: datasets.actuals,
            endpoint: '/api/admin/data/actuals',
            columns: [
              { key: 'title', label: 'Title' },
              { key: 'status', label: 'Status', type: 'status' },
            ],
          },
        ]}
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect(await screen.findByText('Focus block')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('搜索当前列表'), 'Focus');

    expect(screen.getByText('Focus block')).toBeInTheDocument();
    expect(screen.queryByText('Filtered away')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /刷新/ }));
    await waitFor(() =>
      expect(api.request).toHaveBeenLastCalledWith(
        '/api/admin/data/actuals?limit=100',
      ),
    );

    await userEvent.click(screen.getByRole('button', { name: /详\s*情/ }));
    expect(onOpenDetail).toHaveBeenCalledWith(
      datasets.actuals,
      expect.objectContaining({ id: 'actual-1' }),
    );
  });

  it('keeps endpoint query params and filters rows by fallback status fields', async () => {
    const api = createMockAdminApi({
      request: vi.fn().mockResolvedValue({
        items: [
          {
            uid: 'actual-state-1',
            title: 'Paused import',
            state: 'paused',
            startedAt: '2026-06-08T09:00:00.000Z',
          },
          {
            key: 'actual-sync-1',
            title: 'Pending import',
            syncStatus: 'pending',
            startedAt: '2026-06-08T10:00:00.000Z',
          },
          {
            title: 'No key import',
            status: 'done',
            startedAt: '2026-06-08T11:00:00.000Z',
          },
        ],
      }),
    });

    renderWithProviders(
      <BusinessListPage
        title="Actuals"
        description="Readable actual records"
        panels={[
          {
            dataset: datasets.actuals,
            endpoint: '/api/admin/data/actuals?includeArchived=true',
            columns: [
              { key: 'title', label: 'Title' },
              { key: 'state', label: 'State', type: 'status' },
              { key: 'startedAt', label: 'Started', type: 'date' },
            ],
          },
        ]}
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    expect(await screen.findByText('Paused import')).toBeInTheDocument();
    expect(api.request).toHaveBeenCalledWith(
      '/api/admin/data/actuals?includeArchived=true&limit=100',
    );
    expect(screen.getAllByText(/2026-06-08/).length).toBeGreaterThan(0);

    await chooseSelectOption(0, 'paused');

    expect(screen.getByText('Paused import')).toBeInTheDocument();
    expect(screen.queryByText('Pending import')).not.toBeInTheDocument();
  });
});

describe('AuditPage', () => {
  it('loads audit rows, searches, refreshes, and opens a detail drawer callback', async () => {
    const api = createMockAdminApi({
      adminData: vi.fn().mockResolvedValue({
        items: [
          {
            id: 'audit-1',
            action: 'admin.object.update',
            actor: 'admin',
            summary: 'Updated task',
            entityType: 'task',
            entityId: 'task-1',
          },
          {
            id: 'audit-2',
            action: 'admin.operation.prepare',
            actor: 'system',
            summary: 'Prepared operation',
          },
        ],
      }),
    });
    const onOpenDetail = vi.fn();

    renderWithProviders(
      <AuditPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect((await screen.findAllByText('Updated task')).length)
      .toBeGreaterThan(0);

    await userEvent.type(
      screen.getByPlaceholderText('搜索摘要、对象、操作者'),
      'Updated',
    );

    expect(screen.getAllByText('Updated task').length).toBeGreaterThan(0);
    expect(screen.queryAllByText('Prepared operation')).toHaveLength(0);

    await userEvent.click(screen.getByRole('button', { name: /刷新/ }));
    await waitFor(() =>
      expect(api.adminData).toHaveBeenLastCalledWith('audit-logs', {
        limit: 200,
      }),
    );

    await userEvent.click(screen.getByRole('button', { name: /查\s*看/ }));
    expect(onOpenDetail).toHaveBeenCalledWith(
      datasets.auditLogs,
      expect.objectContaining({ id: 'audit-1' }),
    );
  });

  it('filters by action and renders audit fallback columns', async () => {
    const api = createMockAdminApi({
      adminData: vi.fn().mockResolvedValue({
        items: [
          {
            action: 'custom.action',
            createdBy: 'auditor',
            createdAt: '2026-06-08T09:00:00.000Z',
            targetType: 'setting',
            targetId: 'setting-1',
          },
          {
            id: 'audit-other',
            action: 'admin.operation.prepare',
            actor: 'system',
            summary: 'Prepared operation',
          },
        ],
      }),
    });

    renderWithProviders(
      <AuditPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    expect((await screen.findAllByText('custom.action')).length)
      .toBeGreaterThan(0);
    expect(screen.getByText('auditor')).toBeInTheDocument();
    expect(screen.getByText('setting-1')).toBeInTheDocument();

    await chooseSelectOption(0, 'custom.action');

    expect(screen.getAllByText('custom.action').length).toBeGreaterThan(0);
    expect(screen.queryByText('Prepared operation')).not.toBeInTheDocument();
  });
});

describe('LogsPage', () => {
  it('loads row payloads, renders fallback log fields, and filters by actor and action', async () => {
    const api = createMockAdminApi({
      adminData: vi.fn().mockResolvedValue({
        rows: [
          {
            id: 'log-admin',
            actor: 'admin',
            action: 'admin.object.update',
            summary: 'Admin update',
            metadata: { field: 'status' },
          },
          {
            id: 'log-missing-actor',
            action: 'missing.actor',
            summary: 'Missing actor',
          },
          {
            id: 'log-health',
            actor: 'client',
            action: 'system.health.check',
            summary: 'Health check',
            metadataJson: { requestId: 'req-1', stage: 'health' },
          },
          {
            id: 'log-other',
            actor: 'client',
            action: 'other.action',
            summary: 'Other client',
          },
        ],
      }),
    });

    renderWithProviders(
      <LogsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Admin update')).toBeInTheDocument();
    expect(screen.getAllByText('unknown').length).toBeGreaterThan(0);
    expect(screen.getByText('requestId, stage')).toBeInTheDocument();

    await chooseSelectOption(0, 'client');

    expect(screen.queryByText('Admin update')).not.toBeInTheDocument();
    expect(screen.getByText('Health check')).toBeInTheDocument();
    expect(screen.getByText('Other client')).toBeInTheDocument();

    await userEvent.type(screen.getByRole('textbox'), 'health');

    expect(screen.getByText('Health check')).toBeInTheDocument();
    expect(screen.queryByText('Other client')).not.toBeInTheDocument();
  });
});

describe('SettingsPage', () => {
  it('saves connection settings and patches an edited remote setting', async () => {
    const api = createMockAdminApi({
      settings: vi.fn().mockResolvedValue({
        items: [
          {
            configKey: 'outlook.sync.enabled',
            value: { enabled: true },
            sensitive: true,
            updatedAt: '2026-06-08T08:00:00.000Z',
          },
        ],
      }),
      patchSetting: vi.fn().mockResolvedValue({ ok: true }),
    });
    const onSaveConnection = vi.fn();

    renderWithProviders(
      <SettingsPage
        api={api as never}
        apiBase="http://localhost:3202"
        deviceId="admin-device"
        devices={[{ id: 'device-1', name: 'Desk client', detail: 'windows' }]}
        selectedDeviceId="all"
        onSaveConnection={onSaveConnection}
        onDataRefresh={vi.fn()}
      />,
    );

    expect(await screen.findByText('outlook.sync.enabled')).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole('button', { name: /保存连接设置/ }),
    );
    expect(onSaveConnection).toHaveBeenCalledWith(
      'http://localhost:3202',
      'admin-device',
      'all',
    );

    await userEvent.click(screen.getByRole('button', { name: /编\s*辑/ }));
    await userEvent.click(screen.getByRole('button', { name: /save remote config/i }));

    await waitFor(() =>
      expect(api.patchSetting).toHaveBeenCalledWith(
        'outlook.sync.enabled',
        expect.objectContaining({
          value: { enabled: true },
          sensitive: true,
          reason: 'web admin setting update',
        }),
      ),
    );
  });

  it('saves a manually entered sensitive remote text setting', async () => {
    const api = createMockAdminApi({
      settings: vi.fn().mockResolvedValue({ items: [] }),
      patchSetting: vi.fn().mockResolvedValue({ ok: true }),
    });

    renderWithProviders(
      <SettingsPage
        api={api as never}
        apiBase="http://localhost:3202"
        deviceId="admin-device"
        devices={[]}
        selectedDeviceId="all"
        onSaveConnection={vi.fn()}
        onDataRefresh={vi.fn()}
      />,
    );

    await screen.findByLabelText('Remote config key');

    await userEvent.type(
      screen.getByLabelText('Remote config key'),
      'feature.banner',
    );
    await userEvent.clear(screen.getByLabelText('Remote config value'));
    await userEvent.type(
      screen.getByLabelText('Remote config value'),
      'enabled',
    );
    await userEvent.click(
      screen.getByRole('switch', { name: /sensitive remote config/i }),
    );
    await userEvent.click(
      screen.getByRole('button', { name: /save remote config/i }),
    );

    await waitFor(() =>
      expect(api.patchSetting).toHaveBeenCalledWith(
        'feature.banner',
        expect.objectContaining({
          value: 'enabled',
          sensitive: true,
          reason: 'web admin setting update',
        }),
      ),
    );
  });

  it('guards empty remote keys and edits legacy setting fields', async () => {
    const api = createMockAdminApi({
      settings: vi
        .fn()
        .mockResolvedValueOnce({
          items: [
            {
              key: 'legacy.flag',
              configValue: 'legacy text',
              group: 'client',
              sensitive: false,
              updatedAt: '2026-06-08T08:00:00.000Z',
            },
            {
              value: 'row without stable key',
            },
          ],
        })
        .mockResolvedValueOnce({ items: [] }),
      patchSetting: vi.fn().mockResolvedValue({ ok: true }),
    });

    renderWithProviders(
      <SettingsPage
        api={api as never}
        apiBase="http://localhost:3202"
        deviceId="admin-device"
        devices={[]}
        selectedDeviceId="all"
        onSaveConnection={vi.fn()}
        onDataRefresh={vi.fn()}
      />,
    );

    expect(await screen.findByText('legacy.flag')).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole('button', { name: /save remote config/i }),
    );
    expect(api.patchSetting).not.toHaveBeenCalled();

    const row = screen.getByText('legacy.flag').closest('tr');
    expect(row).not.toBeNull();
    await userEvent.click(rowActionButton(row!));

    expect(screen.getByDisplayValue('legacy.flag')).toBeInTheDocument();
    expect(screen.getByDisplayValue('"legacy text"')).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole('button', { name: /save remote config/i }),
    );

    await waitFor(() =>
      expect(api.patchSetting).toHaveBeenCalledWith(
        'legacy.flag',
        expect.objectContaining({
          value: 'legacy text',
          sensitive: false,
          reason: 'web admin setting update',
        }),
      ),
    );
    await waitFor(() => expect(api.settings).toHaveBeenCalledTimes(2));
  });
});
