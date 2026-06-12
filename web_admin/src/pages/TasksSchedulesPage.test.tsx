import { Modal, message } from 'antd';
import { fireEvent, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { scheduleRows, taskRows } from '../test/fixtures/adminData';
import { TasksSchedulesPage } from './TasksSchedulesPage';

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

describe('TasksSchedulesPage', () => {
  it('loads rows, filters by search, opens detail, and batch-completes selected tasks', async () => {
    const api = createMockAdminApi({
      adminData: vi
        .fn()
        .mockResolvedValueOnce({ items: taskRows })
        .mockResolvedValueOnce({ items: scheduleRows })
        .mockResolvedValueOnce({ items: taskRows })
        .mockResolvedValueOnce({ items: scheduleRows }),
      patchAdminData: vi.fn().mockResolvedValue({ ok: true }),
    });
    const onOpenDetail = vi.fn();
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return {
        destroy: vi.fn(),
        update: vi.fn(),
      } as never;
    });

    renderWithProviders(
      <TasksSchedulesPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect(await screen.findByRole('button', { name: 'Plan review' }))
      .toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Daily sync' }))
      .toBeInTheDocument();

    await userEvent.type(
      screen.getByRole('searchbox', { name: /search tasks and schedules/i }),
      'Plan',
    );

    expect(screen.getByRole('button', { name: 'Plan review' }))
      .toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Daily sync' }))
      .not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Plan review' }));
    expect(onOpenDetail).toHaveBeenCalledWith(
      expect.objectContaining({ domain: 'tasks' }),
      taskRows[0],
    );

    await userEvent.click(
      screen.getByRole('checkbox', { name: /select plan review/i }),
    );
    await userEvent.click(
      screen.getByRole('button', { name: /batch complete selected tasks/i }),
    );

    await waitFor(() =>
      expect(api.patchAdminData).toHaveBeenCalledWith(
        'tasks',
        'task-1',
        expect.objectContaining({
          payload: expect.objectContaining({ status: 'done' }),
        }),
      ),
    );
  }, 30000);

  it('confirms and soft-deletes selected schedules from the table toolbar', async () => {
    const api = createMockAdminApi({
      adminData: vi
        .fn()
        .mockResolvedValueOnce({ items: taskRows })
        .mockResolvedValueOnce({ items: scheduleRows })
        .mockResolvedValueOnce({ items: taskRows })
        .mockResolvedValueOnce({ items: scheduleRows }),
      patchAdminData: vi.fn().mockResolvedValue({ ok: true }),
    });
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return {
        destroy: vi.fn(),
        update: vi.fn(),
      } as never;
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
      screen.getByRole('button', { name: /batch delete selected items/i }),
    );

    await waitFor(() =>
      expect(api.patchAdminData).toHaveBeenCalledWith(
        'schedules',
        'schedule-1',
        expect.objectContaining({
          deleted: true,
          reason: 'admin batch delete',
        }),
      ),
    );
  });

  it('refreshes rows, opens schedule detail, and filters by dynamic status', async () => {
    const taskItems = [
      ...taskRows,
      {
        id: 'task-blocked',
        title: 'Blocked task',
        status: 'blocked',
        source: 'local',
        dueAt: '2026-06-10T09:00:00.000Z',
        description: 'Blocked by review',
      },
    ];
    const scheduleItems = [
      ...scheduleRows,
      {
        uid: 'outlook-floating-sync',
        summary: 'Floating sync',
        status: 'tentative',
        source: 'outlook',
        location: 'Remote',
      },
    ];
    const api = createMockAdminApi({
      adminData: vi.fn().mockImplementation((domain: string) =>
        Promise.resolve({
          items: domain === 'tasks' ? taskItems : scheduleItems,
        }),
      ),
    });
    const onOpenDetail = vi.fn();

    renderWithProviders(
      <TasksSchedulesPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect(await screen.findByRole('button', { name: 'Daily sync' }))
      .toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Daily sync' }));
    expect(onOpenDetail).toHaveBeenCalledWith(
      expect.objectContaining({ domain: 'schedules' }),
      scheduleRows[0],
    );

    await userEvent.click(
      screen.getByRole('button', { name: /refresh tasks and schedules/i }),
    );
    await waitFor(() => expect(api.adminData).toHaveBeenCalledTimes(4));

    await chooseSelectOption(3, 'blocked');

    expect(screen.getByRole('button', { name: 'Blocked task' }))
      .toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Plan review' }))
      .not.toBeInTheDocument();
  });

  it('warns instead of patching when only schedules are selected for completion', async () => {
    const warning = vi.spyOn(message, 'warning');
    const api = createMockAdminApi({
      adminData: vi.fn().mockImplementation((domain: string) =>
        Promise.resolve({
          items: domain === 'tasks' ? taskRows : scheduleRows,
        }),
      ),
      patchAdminData: vi.fn().mockResolvedValue({ ok: true }),
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

    expect(warning).toHaveBeenCalled();
    expect(api.patchAdminData).not.toHaveBeenCalled();
  });

  it('keeps selected rows and avoids success refresh when a batch patch fails', async () => {
    const success = vi.spyOn(message, 'success');
    const api = createMockAdminApi({
      adminData: vi
        .fn()
        .mockResolvedValueOnce({ items: taskRows })
        .mockResolvedValueOnce({ items: scheduleRows }),
      patchAdminData: vi.fn().mockRejectedValue(new Error('patch failed')),
    });
    const modalFailures: unknown[] = [];
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      Promise.resolve(config.onOk?.()).catch((error: unknown) => {
        modalFailures.push(error);
      });
      return {
        destroy: vi.fn(),
        update: vi.fn(),
      } as never;
    });
    const onDataRefresh = vi.fn();

    renderWithProviders(
      <TasksSchedulesPage
        api={api as never}
        onDataRefresh={onDataRefresh}
        onOpenDetail={vi.fn()}
      />,
    );

    expect(await screen.findByRole('button', { name: 'Plan review' }))
      .toBeInTheDocument();
    expect(onDataRefresh).toHaveBeenCalledTimes(1);

    await userEvent.click(
      screen.getByRole('checkbox', { name: /select plan review/i }),
    );
    expect(
      screen.getByRole('checkbox', { name: /select plan review/i }),
    ).toBeChecked();

    await userEvent.click(
      screen.getByRole('button', { name: /batch complete selected tasks/i }),
    );

    await waitFor(() =>
      expect(api.patchAdminData).toHaveBeenCalledWith(
        'tasks',
        'task-1',
        expect.objectContaining({
          payload: expect.objectContaining({ status: 'done' }),
          reason: 'admin batch complete',
        }),
      ),
    );
    await waitFor(() => expect(modalFailures).toHaveLength(1));
    expect(modalFailures[0]).toEqual(new Error('patch failed'));
    expect(success).not.toHaveBeenCalled();
    expect(api.adminData).toHaveBeenCalledTimes(2);
    expect(onDataRefresh).toHaveBeenCalledTimes(1);
    expect(
      screen.getByRole('checkbox', { name: /select plan review/i }),
    ).toBeChecked();
  });
});
