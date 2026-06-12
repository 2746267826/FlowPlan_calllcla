import { Modal, message } from 'antd';
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { JobsPage } from './JobsPage';
import { SettingsPage } from './SettingsPage';
import { TasksSchedulesPage } from './TasksSchedulesPage';

async function confirmLatestPopconfirm() {
  await waitFor(() => {
    expect(
      document.querySelector('.ant-popconfirm-buttons .ant-btn-primary'),
    ).toBeTruthy();
  });
  const buttons = document.querySelectorAll(
    '.ant-popconfirm-buttons .ant-btn-primary',
  );
  fireEvent.click(buttons[buttons.length - 1] as HTMLElement);
}

async function chooseSelectOption(selectIndex: number, optionText: string) {
  const selectors = document.querySelectorAll('.ant-select-selector');
  expect(selectors[selectIndex]).toBeTruthy();
  fireEvent.mouseDown(selectors[selectIndex]);

  await waitFor(() => {
    expect(
      Array.from(document.querySelectorAll('.ant-select-item-option')).some(
        (item) => item.textContent?.includes(optionText),
      ),
    ).toBe(true);
  });

  const option = Array.from(
    document.querySelectorAll('.ant-select-item-option'),
  ).find((item) => item.textContent?.includes(optionText)) as HTMLElement;
  fireEvent.click(option);
}

function editButtonInRow(row: HTMLElement) {
  const button = within(row)
    .getAllByRole('button')
    .find((item) => !item.classList.contains('ant-table-row-expand-icon'));
  expect(button).toBeTruthy();
  return button as HTMLElement;
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('JobsPage final action coverage', () => {
  it('covers success, default-error, non-Error catch, and fallback job fields', async () => {
    const successSpy = vi
      .spyOn(message, 'success')
      .mockImplementation(() => undefined as never);
    const errorSpy = vi
      .spyOn(message, 'error')
      .mockImplementation(() => undefined as never);
    const request = vi.fn().mockImplementation((path: string) => {
      if (path.endsWith('/resume')) {
        return Promise.resolve({ ok: true });
      }
      if (path.endsWith('/trigger')) {
        return Promise.resolve({ ok: false });
      }
      if (path.endsWith('/pause')) {
        return Promise.reject('plain pause failure');
      }
      return Promise.resolve({
        jobs: [
          {
            name: 'mystery-job',
            status: 'paused',
          },
          {
            name: 'no-status-job',
          },
        ],
      });
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<JobsPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('mystery-job')).toBeInTheDocument();
    expect(screen.getByText('no-status-job')).toBeInTheDocument();
    expect(screen.getByText('paused')).toBeInTheDocument();
    expect(screen.getByText('idle')).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole('button', { name: /resume job mystery-job/i }),
    );
    await confirmLatestPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith('/api/admin/jobs/mystery-job/resume', {
        method: 'POST',
      }),
    );
    expect(successSpy).toHaveBeenCalledWith(
      expect.stringContaining('resume mystery-job'),
    );

    await userEvent.click(
      screen.getByRole('button', { name: /trigger job mystery-job/i }),
    );
    await confirmLatestPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith(
        '/api/admin/jobs/mystery-job/trigger',
        { method: 'POST' },
      ),
    );
    expect(errorSpy).toHaveBeenCalledWith(expect.any(String));

    await userEvent.click(
      screen.getByRole('button', { name: /pause job mystery-job/i }),
    );
    await confirmLatestPopconfirm();
    await waitFor(() =>
      expect(errorSpy).toHaveBeenCalledWith('plain pause failure'),
    );
  }, 30000);
});

describe('SettingsPage final action coverage', () => {
  it('saves connection settings, edits remote rows, expands raw rows, and saves text values', async () => {
    const successSpy = vi
      .spyOn(message, 'success')
      .mockImplementation(() => undefined as never);
    const settings = vi.fn().mockResolvedValue({
      configs: [
        {
          key: 'feature.remote',
          group: 'client',
          configValue: 'stored text',
          sensitive: true,
          updatedAt: 'not-a-date',
        },
        {
          id: 'setting-id-fallback',
          scope: 'fallback-row',
          sensitive: false,
        },
      ],
    });
    const patchSetting = vi.fn().mockResolvedValue({ ok: true });
    const onSaveConnection = vi.fn();
    const api = createMockAdminApi({ settings, patchSetting });

    renderWithProviders(
      <SettingsPage
        api={api as never}
        apiBase="http://localhost:3202"
        deviceId="admin-device"
        devices={[{ id: 'device-1', name: 'Phone', detail: 'iOS' }]}
        selectedDeviceId="device-1"
        onSaveConnection={onSaveConnection}
        onDataRefresh={vi.fn()}
      />,
    );

    expect(await screen.findByText('feature.remote')).toBeInTheDocument();

    const saveConnectionButton = document.querySelector(
      'button[type="submit"]',
    ) as HTMLElement;
    expect(saveConnectionButton).toBeTruthy();
    await userEvent.click(saveConnectionButton);
    await waitFor(() =>
      expect(onSaveConnection).toHaveBeenCalledWith(
        'http://localhost:3202',
        'admin-device',
        'device-1',
      ),
    );

    const row = screen.getByText('feature.remote').closest('tr');
    expect(row).toBeTruthy();
    await userEvent.click(editButtonInRow(row as HTMLElement));
    expect(screen.getByLabelText('Remote config key')).toHaveValue(
      'feature.remote',
    );
    expect(screen.getByLabelText('Remote config value')).toHaveValue(
      '"stored text"',
    );

    const fallbackRow = screen.getByText('setting-id-fallback').closest('tr');
    expect(fallbackRow).toBeTruthy();
    await userEvent.click(editButtonInRow(fallbackRow as HTMLElement));
    expect(screen.getByLabelText('Remote config key')).toHaveValue(
      'setting-id-fallback',
    );
    expect(screen.getByLabelText('Remote config value')).toHaveValue('{}');

    fireEvent.change(screen.getByLabelText('Remote config key'), {
      target: { value: ' feature.message ' },
    });
    fireEvent.change(screen.getByLabelText('Remote config value'), {
      target: { value: 'plain text value' },
    });
    await userEvent.click(screen.getByLabelText('Sensitive remote config'));
    await userEvent.click(
      screen.getByRole('button', { name: /save remote config/i }),
    );

    await waitFor(() =>
      expect(patchSetting).toHaveBeenCalledWith('feature.message', {
        value: 'plain text value',
        sensitive: true,
        reason: 'web admin setting update',
      }),
    );
    expect(successSpy).toHaveBeenCalled();
    expect(settings).toHaveBeenCalledTimes(2);
  }, 30000);
});

describe('TasksSchedulesPage final action coverage', () => {
  it('renders the selection alert, clears a dynamic status filter, and batch-deletes mixed rows', async () => {
    const tasks = [
      {
        id: 'blocked-task',
        title: 'Blocked task',
        status: 'blocked',
        source: 'local',
        dueAt: '2026-06-10T09:00:00.000Z',
        description: 'Blocked by review',
      },
      {
        id: 'floating-task',
        title: 'Floating task',
        status: 'todo',
        source: 'local',
      },
    ];
    const schedules = [
      {
        uid: 'outlook-floating-sync',
        summary: 'Floating sync',
        status: 'tentative',
        source: 'outlook',
      },
    ];
    const adminData = vi.fn().mockImplementation((domain: string) =>
      Promise.resolve({
        items: domain === 'tasks' ? tasks : schedules,
      }),
    );
    const patchAdminData = vi.fn().mockResolvedValue({ ok: true });
    const successSpy = vi
      .spyOn(message, 'success')
      .mockImplementation(() => undefined as never);
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });
    const api = createMockAdminApi({ adminData, patchAdminData });

    renderWithProviders(
      <TasksSchedulesPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={vi.fn()}
      />,
    );

    expect(await screen.findByRole('button', { name: 'Blocked task' }))
      .toBeInTheDocument();

    await chooseSelectOption(3, 'blocked');
    expect(screen.getByRole('button', { name: 'Blocked task' }))
      .toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Floating task' }))
      .not.toBeInTheDocument();

    const clearButton = document.querySelector('.ant-select-clear');
    expect(clearButton).toBeTruthy();
    fireEvent.mouseDown(clearButton as HTMLElement);
    fireEvent.click(clearButton as HTMLElement);
    expect(await screen.findByRole('button', { name: 'Floating task' }))
      .toBeInTheDocument();

    await userEvent.click(
      screen.getByRole('checkbox', { name: /select blocked task/i }),
    );
    expect(document.body.textContent).toContain('1');

    await userEvent.click(
      screen.getByRole('button', { name: /batch delete selected items/i }),
    );

    await waitFor(() =>
      expect(patchAdminData).toHaveBeenCalledWith(
        'tasks',
        'blocked-task',
        { deleted: true, reason: 'admin batch delete' },
      ),
    );
    expect(successSpy).toHaveBeenCalled();
    expect(adminData).toHaveBeenCalledTimes(4);
  }, 30000);
});
