import { fireEvent, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import {
  DriveFilesPage,
  RootDiagnostics,
  asRecord,
  displayRootName,
  errorMessage,
  formatBytes,
  formatCount,
  formatDuration,
  readRoots,
  scanStatusColor,
} from './DriveFilesPage';

describe('DriveFilesPage helpers', () => {
  it('normalizes root payloads and scalar helper fallbacks', () => {
    expect(readRoots(null)).toEqual([]);
    expect(readRoots({ roots: 'bad' })).toEqual([]);
    expect(
      readRoots({
        roots: [
          null,
          [],
          { rootId: 'root-id', name: 'From id' },
          { rootUid: 'root-uid', name: 'From uid' },
          { name: 'missing id' },
        ],
      }),
    ).toEqual([
      { rootId: 'root-id', name: 'From id', id: 'root-id' },
      { rootUid: 'root-uid', name: 'From uid', id: 'root-uid' },
    ]);

    expect(asRecord({ ok: true })).toEqual({ ok: true });
    expect(asRecord([])).toEqual({});
    expect(displayRootName({ id: 'root-1', rootDisplayPath: 'Display' })).toBe('Display');
    expect(displayRootName({ id: 'root-1', rootUri: 'C:\\Files' })).toBe('C:\\Files');
    expect(displayRootName({ id: 'root-1' })).toBe('root-1');
    expect(errorMessage(new Error('boom'))).toBe('boom');
    expect(errorMessage('plain')).toBe('plain');
    expect(formatCount('1234.9')).toBe('1,234');
    expect(formatCount('bad')).toBe('0');
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes('bad')).toBe('0 B');
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(1536)).toBe('1.5 KB');
    expect(formatBytes(1024 ** 5)).toBe('1024.0 TB');
    expect(formatDuration(-1)).toBe(formatDuration('bad'));
    expect(formatDuration(-1).length).toBeGreaterThan(0);
    expect(formatDuration(999)).toBe('999 ms');
    expect(formatDuration(1234)).toBe('1.23 s');
    expect(scanStatusColor('completed')).toBe('green');
    expect(scanStatusColor('failed')).toBe('red');
    expect(scanStatusColor('scanning')).toBe('blue');
    expect(scanStatusColor('running')).toBe('blue');
    expect(scanStatusColor('idle')).toBe('default');
  });

  it('renders diagnostics with default and explicit root metadata', () => {
    const { rerender } = renderWithProviders(
      <RootDiagnostics
        root={{
          id: 'root-empty',
          scanStatus: 'running',
          metadata: {},
        }}
      />,
    );

    expect(screen.getByText('root-empty')).toBeInTheDocument();
    expect(screen.getAllByText('0')).not.toHaveLength(0);

    rerender(
      <RootDiagnostics
        root={{
          id: 'root-full',
          rootUid: 'root-uid',
          providerType: 'server_storage',
          syncPolicy: 'metadata_only',
          rootUri: 'C:\\Files',
          rootDisplayPath: 'Files',
          scanStatus: 'completed',
          lastOperation: 'scan',
          lastOperationStatus: 'completed',
          lastOperationAt: '2026-06-08T08:00:00.000Z',
          totalBytes: 1024,
          storageTotalBytes: 2048,
          lastError: 'last failed',
          metadata: {
            lastScan: {
              status: 'completed',
              durationMs: 1250,
              startedAt: '2026-06-08T08:00:00.000Z',
              finishedAt: '2026-06-08T08:01:00.000Z',
              maxNodes: 10,
              scanned: 10,
              applied: 9,
              reachedMaxNodes: true,
              lastProgressAt: '2026-06-08T08:00:30.000Z',
              phase: 'walk',
              queuedFolders: 2,
              progressMessage: 'Done',
              currentPath: 'C:\\Files',
              rootPath: 'C:\\Files',
              error: 'last scan warning',
            },
          },
        }}
      />,
    );

    expect(screen.getByText('root-full')).toBeInTheDocument();
    expect(screen.getByText('last failed')).toBeInTheDocument();
    expect(screen.getByText('last scan warning')).toBeInTheDocument();
    expect(screen.getAllByText('10')).not.toHaveLength(0);
  });
});

describe('DriveFilesPage background scan polling', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('keeps silent polling failures off the visible error banner while a scan is running', async () => {
    let finishScan!: (value: { ok: true; scanned: number }) => void;
    const scanPromise = new Promise<{ ok: true; scanned: number }>((resolve) => {
      finishScan = resolve;
    });
    const driveRoots = vi
      .fn()
      .mockResolvedValueOnce({
        roots: [{ id: 'root-1', name: 'Course files', scanStatus: 'idle' }],
      })
      .mockRejectedValueOnce(new Error('background offline'))
      .mockResolvedValue({
        roots: [{ id: 'root-1', name: 'Course files', scanStatus: 'completed' }],
      });
    const api = createMockAdminApi({
      driveRoots,
      scanDriveRoot: vi.fn().mockReturnValue(scanPromise),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Course files')).toBeInTheDocument();
    fireEvent.click(
      screen.getByRole('button', { name: /scan drive root course files/i }),
    );

    await new Promise((resolve) => window.setTimeout(resolve, 2100));
    await waitFor(() => expect(driveRoots).toHaveBeenCalledTimes(2));
    expect(screen.queryByText(/background offline/)).not.toBeInTheDocument();

    finishScan({ ok: true, scanned: 1 });
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledWith('root-1'));
  }, 15000);

  it('shows scan applied-count fallback and deletion count fallback', async () => {
    const api = createMockAdminApi({
      driveRoots: vi.fn().mockResolvedValue({
        roots: [{ id: 'root-1', name: 'Course files', scanStatus: 'idle' }],
      }),
      scanDriveRoot: vi.fn().mockResolvedValue({ ok: true, applied: 2 }),
      deleteDriveRoot: vi.fn().mockResolvedValue({ ok: true }),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Course files')).toBeInTheDocument();
    await userEvent.click(
      screen.getByRole('button', { name: /scan drive root course files/i }),
    );
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledWith('root-1'));

    await userEvent.click(
      screen.getByRole('button', { name: /delete drive root course files/i }),
    );
    const confirmButton = document.querySelector(
      '.ant-popconfirm-buttons .ant-btn-primary',
    ) as HTMLElement | null;
    expect(confirmButton).not.toBeNull();
    fireEvent.click(confirmButton!);
    await waitFor(() => expect(api.deleteDriveRoot).toHaveBeenCalledWith('root-1'));
  });

  it('covers sparse rows and alternate operation failure fallbacks', async () => {
    const driveRoots = vi.fn().mockResolvedValue({
      roots: [
        {
          id: 'root-sparse',
          rootUri: 'C:\\Sparse',
          lastOperation: 'scan',
          scanStatus: undefined,
        },
        {
          id: 'root-scanning',
          name: 'Scanning root',
          scanStatus: 'scanning',
          metadata: { lastScan: {} },
        },
      ],
    });
    const api = createMockAdminApi({
      driveRoots,
      upsertDriveRoot: vi
        .fn()
        .mockResolvedValueOnce({ ok: false, reason: 'save reason' })
        .mockResolvedValueOnce({ ok: false }),
      scanDriveRoot: vi
        .fn()
        .mockResolvedValueOnce({ ok: false, reason: 'scan reason' })
        .mockResolvedValueOnce({ ok: false })
        .mockResolvedValueOnce({ ok: true }),
      deleteDriveRoot: vi
        .fn()
        .mockResolvedValueOnce({ ok: false, message: 'delete message' })
        .mockResolvedValueOnce({ ok: false }),
    });

    renderWithProviders(
      <DriveFilesPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Scanning root')).toBeInTheDocument();
    expect(screen.getByText('root-sparse')).toBeInTheDocument();
    const expandButtons = document.querySelectorAll('.ant-table-row-expand-icon');
    fireEvent.click(expandButtons[0]);
    await waitFor(() => expect(screen.getAllByText('root-sparse').length).toBeGreaterThan(1));
    expect(screen.getAllByText('C:\\Sparse')).not.toHaveLength(0);

    const textInputs = document.querySelectorAll('input');
    fireEvent.change(textInputs[0], { target: { value: 'Sparse' } });
    fireEvent.change(textInputs[1], { target: { value: 'C:\\Sparse' } });
    const submitButton = document.querySelector('button[type="submit"]') as HTMLElement | null;
    expect(submitButton).not.toBeNull();
    fireEvent.click(submitButton!);
    expect(await screen.findByText(/save reason/)).toBeInTheDocument();

    fireEvent.click(submitButton!);
    await waitFor(() => expect(api.upsertDriveRoot).toHaveBeenCalledTimes(2));

    fireEvent.click(
      screen.getByRole('button', { name: /scan drive root scanning root/i }),
    );
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledTimes(1));

    fireEvent.click(
      screen.getByRole('button', { name: /scan drive root scanning root/i }),
    );
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledTimes(2));

    fireEvent.click(
      screen.getByRole('button', { name: /scan drive root scanning root/i }),
    );
    await waitFor(() => expect(api.scanDriveRoot).toHaveBeenCalledTimes(3));

    fireEvent.click(
      screen.getByRole('button', { name: /delete drive root scanning root/i }),
    );
    let confirmButton = document.querySelector(
      '.ant-popconfirm-buttons .ant-btn-primary',
    ) as HTMLElement | null;
    expect(confirmButton).not.toBeNull();
    fireEvent.click(confirmButton!);
    expect(await screen.findByText(/delete message/)).toBeInTheDocument();

    fireEvent.click(
      screen.getByRole('button', { name: /delete drive root scanning root/i }),
    );
    confirmButton = document.querySelector(
      '.ant-popconfirm-buttons .ant-btn-primary',
    ) as HTMLElement | null;
    expect(confirmButton).not.toBeNull();
    fireEvent.click(confirmButton!);
    await waitFor(() => expect(api.deleteDriveRoot).toHaveBeenCalledTimes(2));
  }, 30000);
});
