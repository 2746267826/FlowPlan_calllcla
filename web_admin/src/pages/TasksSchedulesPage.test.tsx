import { Modal } from 'antd';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { scheduleRows, taskRows } from '../test/fixtures/adminData';
import { TasksSchedulesPage } from './TasksSchedulesPage';

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
  });
});
