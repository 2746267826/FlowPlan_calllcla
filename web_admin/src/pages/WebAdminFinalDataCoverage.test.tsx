import { Modal, message } from 'antd';
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { datasets } from '../app/constants';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { AuditPage } from './AuditPage';
import { BusinessListPage } from './BusinessListPage';
import { DashboardPage } from './DashboardPage';
import { EnvPage } from './EnvPage';
import { LogsPage } from './LogsPage';
import { OperationsPage } from './OperationsPage';

afterEach(() => {
  vi.restoreAllMocks();
});

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

async function chooseSelectOptionByIndex(
  selectIndex: number,
  optionIndex: number,
) {
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
    expect(options.length).toBeGreaterThan(optionIndex);
  });

  fireEvent.click(options[optionIndex] as HTMLElement);
}

function firstButtonInRow(text: string) {
  const row = screen
    .getAllByText(text)
    .map((item) => item.closest('tr'))
    .find(Boolean);
  expect(row).not.toBeNull();
  const button = within(row as HTMLElement)
    .getAllByRole('button')
    .find((item) => !item.classList.contains('ant-table-row-expand-icon'));
  expect(button).toBeTruthy();
  return button as HTMLElement;
}

function firstButtonInCard(text: string) {
  const card = screen.getByText(text).closest('.ant-card');
  expect(card).not.toBeNull();
  return within(card as HTMLElement).getAllByRole('button')[0];
}

describe('final data coverage pages', () => {
  it('covers AuditPage fallback fields, action filtering, JSON row keys, and detail callbacks', async () => {
    const api = createMockAdminApi({
      adminData: vi.fn().mockResolvedValue({
        items: [
          {
            summary: 'Created by fallback row',
            createdBy: 'fallback-user',
            objectType: 'document',
            uid: 'audit-uid-1',
            createdAt: '2026-06-08T08:00:00.000Z',
          },
          {
            id: 'audit-custom',
            action: 'custom.review',
            actor: 'reviewer',
            targetType: 'file',
            targetId: 'target-file',
            summary: 'Filtered custom audit',
          },
          {
            summary: 'Keyless object summary',
            metadata: { requestId: 'raw-row' },
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

    expect((await screen.findAllByText('Created by fallback row')).length)
      .toBeGreaterThan(0);
    expect(screen.getByText('fallback-user')).toBeInTheDocument();
    expect(screen.getByText('document')).toBeInTheDocument();
    expect(screen.getByText('audit-uid-1')).toBeInTheDocument();
    expect(screen.getAllByText('Keyless object summary').length)
      .toBeGreaterThan(0);

    await chooseSelectOption(0, 'custom.review');

    await waitFor(() =>
      expect(screen.queryAllByText('Created by fallback row')).toHaveLength(0),
    );
    expect(screen.getAllByText('Filtered custom audit').length)
      .toBeGreaterThan(0);

    await userEvent.click(firstButtonInRow('Filtered custom audit'));
    expect(onOpenDetail).toHaveBeenCalledWith(
      datasets.auditLogs,
      expect.objectContaining({ id: 'audit-custom' }),
    );
  });

  it('covers BusinessListPage state and syncStatus fallbacks with detail callbacks', async () => {
    const api = createMockAdminApi({
      request: vi.fn().mockResolvedValue({
        items: [
          {
            title: 'State-only business item',
            state: 'paused',
            startedAt: '2026-06-08T09:00:00.000Z',
          },
          {
            title: 'Sync-only business item',
            syncStatus: 'pending',
            payload: { owner: 'payload-owner' },
          },
          {
            title: 'Empty status business item',
          },
        ],
      }),
    });
    const onOpenDetail = vi.fn();

    renderWithProviders(
      <BusinessListPage
        title="Readable records"
        description="Readable data coverage"
        panels={[
          {
            dataset: datasets.actuals,
            endpoint: '/api/admin/data/actuals?archived=true',
            columns: [
              { key: 'title', label: 'Title' },
              { key: 'status', label: 'Status', type: 'status' },
              { key: 'startedAt', label: 'Started', type: 'date' },
              { key: 'owner', label: 'Owner' },
            ],
          },
        ]}
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect(await screen.findByText('State-only business item'))
      .toBeInTheDocument();
    expect(api.request).toHaveBeenCalledWith(
      '/api/admin/data/actuals?archived=true&limit=100',
    );
    expect(screen.getByText('payload-owner')).toBeInTheDocument();

    await chooseSelectOptionByIndex(0, 1);

    await waitFor(() =>
      expect(screen.queryByText('State-only business item'))
        .not.toBeInTheDocument(),
    );
    expect(screen.getByText('Sync-only business item')).toBeInTheDocument();

    await userEvent.click(firstButtonInRow('Sync-only business item'));
    expect(onOpenDetail).toHaveBeenCalledWith(
      datasets.actuals,
      expect.objectContaining({ title: 'Sync-only business item' }),
    );
  });

  it('covers DashboardPage fallback health rows, rejected sync health, refresh, and audit open', async () => {
    const api = createMockAdminApi({
      dashboard: vi.fn().mockResolvedValue({
        generatedAt: '2026-06-08T08:00:00.000Z',
        pending: {},
        recentAuditLogs: [
          {
            id: 'dashboard-audit',
            summary: 'Dashboard audit fallback',
            action: 'custom.dashboard',
          },
        ],
      }),
      monitoringHealth: vi.fn().mockResolvedValue({
        customProbe: { state: 'odd' },
      }),
      syncHealth: vi.fn().mockRejectedValue(new Error('sync unavailable')),
    });
    const onOpenDetail = vi.fn();

    renderWithProviders(
      <DashboardPage
        api={api as never}
        onDataRefresh={vi.fn()}
        onOpenDetail={onOpenDetail}
      />,
    );

    expect(await screen.findByText('customProbe')).toBeInTheDocument();
    expect(screen.getByText('{"state":"odd"}')).toBeInTheDocument();
    expect(screen.getByText('Dashboard audit fallback')).toBeInTheDocument();

    await userEvent.click(firstButtonInCard('Dashboard audit fallback'));
    expect(onOpenDetail).toHaveBeenCalledWith(
      'auditLogs',
      expect.objectContaining({ id: 'dashboard-audit' }),
    );

    await userEvent.click(
      screen.getByRole('button', { name: /refresh dashboard/i }),
    );
    await waitFor(() => expect(api.dashboard).toHaveBeenCalledTimes(2));
  });

  it('covers EnvPage fallback upload success and non-error upload failures', async () => {
    const successSpy = vi
      .spyOn(message, 'success')
      .mockImplementation(() => undefined as never);
    const errorSpy = vi
      .spyOn(message, 'error')
      .mockImplementation(() => undefined as never);
    let uploadCount = 0;
    const request = vi.fn().mockImplementation((path: string) => {
      if (path === '/api/admin/env/upload') {
        uploadCount += 1;
        if (uploadCount === 1) return Promise.resolve({});
        return Promise.reject('plain env failure');
      }
      return Promise.resolve({
        generatedAt: '2026-06-08T08:00:00.000Z',
        database: { urlPresent: false },
        encryption: { keySecure: false },
        jwt: {},
        service: {},
        storage: {},
        kopia: {},
      });
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<EnvPage api={api as never} onDataRefresh={vi.fn()} />);

    const input = await screen.findByRole('textbox');
    await userEvent.type(input, 'FIRST=1');
    await userEvent.click(
      screen.getByRole('button', { name: /upload env content/i }),
    );

    await waitFor(() =>
      expect(request).toHaveBeenCalledWith('/api/admin/env/upload', {
        method: 'POST',
        body: JSON.stringify({ content: 'FIRST=1' }),
      }),
    );
    expect(successSpy).toHaveBeenCalled();
    await waitFor(() => expect(input).toHaveValue(''));

    await userEvent.type(input, 'SECOND=2');
    await userEvent.click(
      screen.getByRole('button', { name: /upload env content/i }),
    );

    await waitFor(() => expect(errorSpy).toHaveBeenCalledWith('plain env failure'));
    expect(input).toHaveValue('SECOND=2');
  });

  it('covers LogsPage empty action filtering and clearing the actor select', async () => {
    const api = createMockAdminApi({
      adminData: vi.fn().mockResolvedValue({
        rows: [
          {
            id: 'server-row',
            actor: 'server',
            action: 'server.restart',
            summary: 'Server restart',
          },
          {
            id: 'missing-action-row',
            summary: 'Missing action row',
          },
          {
            id: 'custom-row',
            actor: 'custom-actor',
            action: 'custom.trace',
            summary: 'Custom trace',
            metadata: { first: 1, second: 2, third: 3, fourth: 4 },
          },
        ],
      }),
    });

    renderWithProviders(<LogsPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('Server restart')).toBeInTheDocument();
    expect(screen.getByText('Missing action row')).toBeInTheDocument();
    expect(screen.getByText('first, second, third')).toBeInTheDocument();

    await chooseSelectOption(0, 'custom-actor');
    await waitFor(() =>
      expect(screen.queryByText('Server restart')).not.toBeInTheDocument(),
    );
    expect(screen.getByText('Custom trace')).toBeInTheDocument();

    const clearButton = document.querySelector('.ant-select-clear');
    expect(clearButton).not.toBeNull();
    fireEvent.mouseDown(clearButton!);
    fireEvent.click(clearButton!);
    await waitFor(() => expect(screen.getByText('Server restart')).toBeInTheDocument());

    await userEvent.type(screen.getByRole('textbox'), 'restart');

    expect(screen.getByText('Server restart')).toBeInTheDocument();
    expect(screen.queryByText('Missing action row')).not.toBeInTheDocument();
  });

  it('covers OperationsPage operation selection before prepare and confirm', async () => {
    const api = createMockAdminApi({
      prepareOperation: vi.fn().mockResolvedValue({
        confirmationToken: 'retry-token',
        affectedCount: 1,
      }),
      confirmOperation: vi.fn().mockResolvedValue({ ok: true }),
    });
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });
    vi.spyOn(message, 'success').mockImplementation(() => undefined as never);

    renderWithProviders(
      <OperationsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await chooseSelectOptionByIndex(0, 1);
    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: '{"reason":"rerun"}' },
    });
    const buttons = screen.getAllByRole('button');
    await userEvent.click(buttons[0]);

    await waitFor(() =>
      expect(api.prepareOperation).toHaveBeenCalledWith(
        'retry-failed-pushes',
        { reason: 'rerun' },
      ),
    );

    await userEvent.click(screen.getAllByRole('button')[1]);
    await waitFor(() =>
      expect(api.confirmOperation).toHaveBeenCalledWith(
        'retry-failed-pushes',
        { reason: 'rerun' },
        'retry-token',
      ),
    );
  });
});
