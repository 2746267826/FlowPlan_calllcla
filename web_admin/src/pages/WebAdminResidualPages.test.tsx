import { Modal } from 'antd';
import { fireEvent, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { DriveFilesPage } from './DriveFilesPage';
import { EnvPage } from './EnvPage';
import { JobsPage } from './JobsPage';
import { OperationsPage } from './OperationsPage';
import { OutlookPage } from './OutlookPage';
import { SchedulePage } from './SchedulePage';
import { SettingsPage } from './SettingsPage';
import { TasksSchedulesPage } from './TasksSchedulesPage';
import { scheduleRows, taskRows } from '../test/fixtures/adminData';

async function confirmLatestPopconfirm() {
  await waitFor(() => {
    expect(
      document.querySelector('.ant-popconfirm-buttons .ant-btn-primary'),
    ).toBeTruthy();
  });
  const confirmButtons = document.querySelectorAll(
    '.ant-popconfirm-buttons .ant-btn-primary',
  );
  const confirmButton = confirmButtons[
    confirmButtons.length - 1
  ] as HTMLElement | undefined;
  expect(confirmButton).not.toBeNull();
  fireEvent.click(confirmButton);
}

describe('DriveFilesPage residual states', () => {
  it('renders diagnostics and reports save, scan, and delete failures', async () => {
    const api = createMockAdminApi({
      driveRoots: vi.fn().mockResolvedValue({
        roots: [
          {
            id: 'root-1',
            rootUid: 'uid-1',
            name: 'Course files',
            providerType: 'server_storage',
            rootUri: 'C:\\FlowPlanDrive\\Documents',
            rootDisplayPath: 'Documents',
            scanStatus: 'failed',
            lastError: 'previous scan failed',
            nodeCount: 8,
            fileCount: 5,
            folderCount: 3,
            totalBytes: 2048,
            storageObjectCount: 4,
            storageTotalBytes: 4096,
            lastOperation: 'scan',
            lastOperationStatus: 'failed',
            lastOperationAt: '2026-06-08T08:00:00.000Z',
            metadata: {
              lastScan: {
                status: 'failed',
                durationMs: 850,
                maxNodes: 10,
                scanned: 8,
                applied: 6,
                reachedMaxNodes: false,
                progressMessage: 'Stopped on error',
                currentPath: 'C:\\FlowPlanDrive\\Documents',
                rootPath: 'C:\\FlowPlanDrive\\Documents',
                error: 'permission denied',
              },
            },
          },
        ],
      }),
      upsertDriveRoot: vi.fn().mockResolvedValue({
        ok: false,
        message: 'save rejected',
      }),
      scanDriveRoot: vi.fn().mockResolvedValue({
        ok: false,
        error: 'scan rejected',
      }),
      deleteDriveRoot: vi.fn().mockResolvedValue({
        ok: false,
        reason: 'delete rejected',
      }),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Course files')).toBeInTheDocument();
    fireEvent.click(document.querySelector('.ant-table-row-expand-icon')!);
    expect(await screen.findByText('permission denied')).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('显示名称'), {
      target: { value: 'Course files' },
    });
    fireEvent.change(screen.getByLabelText('服务器绝对路径'), {
      target: { value: 'C:\\FlowPlanDrive\\Documents' },
    });
    fireEvent.click(
      screen.getByRole('button', { name: /保存 Drive root/ }),
    );
    expect(await screen.findByText(/save rejected/)).toBeInTheDocument();

    fireEvent.click(
      screen.getByRole('button', { name: /scan drive root course files/i }),
    );
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledWith('root-1'));
    expect(await screen.findByText(/scan rejected/)).toBeInTheDocument();

    fireEvent.click(
      screen.getByRole('button', { name: /delete drive root course files/i }),
    );
    await confirmLatestPopconfirm();
    expect(await screen.findByText(/delete rejected/)).toBeInTheDocument();
  }, 30000);
});

describe('OutlookPage residual states', () => {
  it('keeps partial load failures visible and guards empty auth inputs', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockRejectedValue('status offline'),
      outlookCalendars: vi.fn().mockRejectedValue(new Error('calendar offline')),
      outlookRuns: vi.fn().mockRejectedValue(new Error('runs offline')),
      outlookDiagnostics: vi.fn().mockRejectedValue(new Error('diag offline')),
    });

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText(/status offline/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: '开始授权' }));
    await userEvent.click(screen.getByRole('button', { name: '完成授权' }));
  });

  it('surfaces completion errors and accepts alternate authorization URL fields', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockResolvedValue({ connected: false }),
      startOutlookAuth: vi
        .fn()
        .mockResolvedValue({ url: 'https://login.example.test/alternate' }),
      completeOutlookAuth: vi.fn().mockRejectedValue('callback rejected'),
    });
    vi.spyOn(Modal, 'info').mockImplementation(
      () => ({ destroy: vi.fn(), update: vi.fn() }) as never,
    );
    vi.spyOn(Modal, 'error').mockImplementation(
      () => ({ destroy: vi.fn(), update: vi.fn() }) as never,
    );

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await screen.findByText(/未连接/);
    await userEvent.type(
      screen.getByPlaceholderText('输入 Microsoft 应用 Client ID'),
      'client-123',
    );
    await userEvent.click(screen.getByRole('button', { name: '开始授权' }));
    await waitFor(() => expect(Modal.info).toHaveBeenCalled());

    await userEvent.type(
      screen.getByPlaceholderText('粘贴 Microsoft 回调后的完整 URL'),
      'https://app.example.test/callback?code=bad',
    );
    await userEvent.click(screen.getByRole('button', { name: '完成授权' }));

    expect(await screen.findByText('callback rejected')).toBeInTheDocument();
    expect(Modal.error).toHaveBeenCalled();
  }, 30000);
});

describe('Operations and scheduling residual states', () => {
  it('prepares string payloads after editing the operation form', async () => {
    const api = createMockAdminApi({
      prepareOperation: vi.fn().mockResolvedValue({
        confirmationToken: 'confirm-token',
      }),
    });

    renderWithProviders(
      <OperationsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await userEvent.clear(screen.getByRole('textbox'));
    await userEvent.type(screen.getByRole('textbox'), 'plain payload');
    await userEvent.click(screen.getByRole('button', { name: '准备执行' }));

    await waitFor(() =>
      expect(api.prepareOperation).toHaveBeenCalledWith(
        'rebuild-sync-index',
        'plain payload',
      ),
    );
  });

  it('reports invalid topology JSON, renders cycles, and handles genetic failures', async () => {
    const api = createMockAdminApi({
      topoSort: vi.fn().mockResolvedValue({
        sorted: ['A', 'B'],
        hasCycle: true,
        layers: [['A'], ['B']],
        cycles: [['A', 'B', 'A']],
      }),
      geneticEvolve: vi.fn().mockRejectedValue(new Error('genetic failed')),
      listJobs: vi.fn().mockResolvedValue({ jobs: [] }),
    });

    renderWithProviders(
      <SchedulePage api={api as never} onDataRefresh={vi.fn()} />,
    );

    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: '{bad json' },
    });
    await userEvent.click(screen.getByRole('button', { name: /拓扑排序/ }));
    expect(api.topoSort).not.toHaveBeenCalled();

    fireEvent.change(screen.getByRole('textbox'), {
      target: {
        value: '[{"id":"A","dependsOn":["B"]},{"id":"B","dependsOn":["A"]}]',
      },
    });
    await userEvent.click(screen.getByRole('button', { name: /拓扑排序/ }));
    await waitFor(() => expect(api.topoSort).toHaveBeenCalledWith({
      tasks: [
        { id: 'A', dependsOn: ['B'] },
        { id: 'B', dependsOn: ['A'] },
      ],
    }));

    await userEvent.click(screen.getByRole('tab', { name: /遗传算法调度/ }));
    await userEvent.click(screen.getByRole('button', { name: /进化/ }));
    await waitFor(() => expect(api.geneticEvolve).toHaveBeenCalled());
  }, 30000);
});

describe('Settings, jobs, env, and task residual states', () => {
  it('warns on missing config keys and expands remote setting rows', async () => {
    const api = createMockAdminApi({
      settings: vi.fn().mockResolvedValue({
        items: [{ configKey: 'feature.flag', value: { enabled: true } }],
      }),
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

    expect(await screen.findByText('feature.flag')).toBeInTheDocument();
    await userEvent.click(
      screen.getByRole('button', { name: /Save remote config/i }),
    );
    expect(api.patchSetting).not.toHaveBeenCalled();
  });

  it('reports job action errors and thrown request failures', async () => {
    const request = vi.fn().mockImplementation((path: string) => {
      if (path.endsWith('/trigger')) {
        return Promise.resolve({ ok: false, error: 'trigger blocked' });
      }
      if (path.endsWith('/pause')) {
        return Promise.reject(new Error('pause crashed'));
      }
      return Promise.resolve({
        jobs: [
          {
            name: 'custom-job',
            status: 'idle',
            cron: '* * * * *',
            description: 'Custom job',
          },
        ],
      });
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<JobsPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('Custom job')).toBeInTheDocument();
    await userEvent.click(
      screen.getByRole('button', { name: /trigger job custom-job/i }),
    );
    await confirmLatestPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith('/api/admin/jobs/custom-job/trigger', {
        method: 'POST',
      }),
    );

    await userEvent.click(
      screen.getByRole('button', { name: /pause job custom-job/i }),
    );
    await confirmLatestPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith('/api/admin/jobs/custom-job/pause', {
        method: 'POST',
      }),
    );
  });

  it('keeps pasted env content when upload fails', async () => {
    const request = vi.fn().mockImplementation((path: string) => {
      if (path === '/api/admin/env/upload') {
        return Promise.reject(new Error('env upload failed'));
      }
      return Promise.resolve({
        generatedAt: '2026-06-08T08:00:00.000Z',
        database: {},
        encryption: {},
        jwt: {},
        service: {},
        storage: {},
        kopia: {},
      });
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<EnvPage api={api as never} onDataRefresh={vi.fn()} />);

    await screen.findByRole('button', { name: /upload env content/i });
    await userEvent.type(
      screen.getByPlaceholderText('粘贴 .env 文件内容...'),
      'DATABASE_URL=postgres://example',
    );
    await userEvent.click(
      screen.getByRole('button', { name: /upload env content/i }),
    );

    await waitFor(() =>
      expect(request).toHaveBeenCalledWith('/api/admin/env/upload', {
        method: 'POST',
        body: JSON.stringify({ content: 'DATABASE_URL=postgres://example' }),
      }),
    );
    expect(screen.getByDisplayValue('DATABASE_URL=postgres://example'))
      .toBeInTheDocument();
  });

  it('does not batch-complete selected schedules as tasks', async () => {
    const api = createMockAdminApi({
      adminData: vi
        .fn()
        .mockResolvedValueOnce({ items: taskRows })
        .mockResolvedValueOnce({ items: scheduleRows }),
    });

    renderWithProviders(
      <TasksSchedulesPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    expect(await screen.findByRole('button', { name: 'Daily sync' }))
      .toBeInTheDocument();
    await userEvent.click(
      screen.getByRole('checkbox', { name: /select daily sync/i }),
    );
    await userEvent.click(
      screen.getByRole('button', { name: /batch complete selected tasks/i }),
    );

    expect(api.patchAdminData).not.toHaveBeenCalled();
  });
});
