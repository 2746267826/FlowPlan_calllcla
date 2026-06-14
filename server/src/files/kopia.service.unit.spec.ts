import { beforeEach, describe, expect, it, vi } from 'vitest';

const execFileMock = vi.hoisted(() => vi.fn());
const statMock = vi.hoisted(() => vi.fn());

vi.mock('node:child_process', () => ({
  execFile: execFileMock,
}));

vi.mock('node:fs/promises', () => ({
  stat: statMock,
}));

describe('KopiaService', () => {
  beforeEach(() => {
    vi.resetModules();
    execFileMock.mockReset();
    statMock.mockReset();
    delete process.env.KOPIA_EXE;
    delete process.env.KOPIA_TIMEOUT_MS;
  });

  it('defaults to the Linux-friendly kopia executable unless overridden', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) =>
      callback(null, '[]', ''),
    );
    const { KopiaService } = await import('./kopia.service');

    await new KopiaService().listSnapshots('/data/project');

    expect(execFileMock).toHaveBeenCalledWith(
      'kopia',
      ['snapshot', 'list', '/data/project', '--json'],
      expect.any(Object),
      expect.any(Function),
    );
  });

  it('creates snapshots with configured CLI and normalizes noisy Kopia JSON output', async () => {
    process.env.KOPIA_EXE = 'custom-kopia';
    process.env.KOPIA_TIMEOUT_MS = '5000';
    statMock.mockResolvedValue({ isDirectory: () => true });
    execFileMock.mockImplementation((_exe, _args, _options, callback) => {
      callback(
        null,
        `progress\n{"snapshots":[{"manifestID":"snap-1","endTime":"2026-06-08T01:00:00Z","rootEntry":{"summ":{"size":"42"},"contentID":"hash-1"}}]}\ndone`,
        'warning',
      );
    });
    const { KopiaService } = await import('./kopia.service');
    const service = new KopiaService();

    await expect(service.createSnapshot('/data/project')).resolves.toMatchObject({
      rootPath: '/data/project',
      stderr: 'warning',
      snapshots: [
        {
          snapshotId: 'snap-1',
          versionRef: 'snap-1',
          displayName: 'project @ 2026-06-08T01:00:00Z',
          modifiedAt: '2026-06-08T01:00:00Z',
          sizeBytes: 42,
          checksum: 'hash-1',
          metadata: {
            kopiaExecutable: 'custom-kopia',
            targetPath: '/data/project',
          },
        },
      ],
    });
    expect(statMock).toHaveBeenCalledWith('/data/project');
    expect(execFileMock).toHaveBeenCalledWith(
      'custom-kopia',
      ['snapshot', 'create', '/data/project', '--json'],
      expect.objectContaining({ timeout: 5000, windowsHide: true }),
      expect.any(Function),
    );
  });

  it('lists snapshots and returns an empty normalized list for blank CLI output', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) => callback(null, '  \n', ''));
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().listSnapshots('/data/empty')).resolves.toEqual({
      targetPath: '/data/empty',
      raw: null,
      stderr: '',
      snapshots: [],
    });
    expect(execFileMock).toHaveBeenCalledWith(
      'kopia',
      ['snapshot', 'list', '/data/empty', '--json'],
      expect.any(Object),
      expect.any(Function),
    );
  });

  it('uses default command settings and parses noisy JSON arrays with fallback snapshot fields', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) => {
      callback(
        null,
        `progress\n${JSON.stringify([
          {
            manifestId: '   ',
            snapshotTime: '2026-06-08T03:00:00Z',
            size: 'not-a-number',
            totalSize: '7',
            rootEntry: { obj: 'snap-from-root', hash: 'root-hash' },
          },
        ])}\ndone`,
        '',
      );
    });
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().listSnapshots('/data/project')).resolves.toMatchObject({
      targetPath: '/data/project',
      snapshots: [
        {
          snapshotId: 'snap-from-root',
          versionRef: 'snap-from-root',
          displayName: 'project @ 2026-06-08T03:00:00Z',
          modifiedAt: '2026-06-08T03:00:00Z',
          sizeBytes: 7,
          checksum: 'root-hash',
        },
      ],
    });
    expect(execFileMock).toHaveBeenCalledWith(
      'kopia',
      ['snapshot', 'list', '/data/project', '--json'],
      expect.objectContaining({ timeout: 120000, windowsHide: true }),
      expect.any(Function),
    );
  });

  it('normalizes defensively when a filtered snapshot loses its id during mapping', async () => {
    const { KopiaService } = await import('./kopia.service');
    const service = new KopiaService() as never as {
      normalizeSnapshots: (value: unknown, targetPath: string) => Array<{ snapshotId: string }>;
      snapshotId: (item: Record<string, unknown>) => string | null;
    };
    const originalSnapshotId = service.snapshotId.bind(service);
    let calls = 0;
    service.snapshotId = vi.fn((item: Record<string, unknown>) => {
      calls += 1;
      return calls === 1 ? originalSnapshotId(item) : null;
    });

    expect(service.normalizeSnapshots([{ id: 'snap-transient' }], '/data/project')).toMatchObject([
      { snapshotId: '' },
    ]);
  });

  it('does not invoke Kopia when the snapshot target path is missing', async () => {
    statMock.mockRejectedValue(Object.assign(new Error('missing path'), { code: 'ENOENT' }));
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().createSnapshot('/missing/project')).rejects.toThrow('missing path');
    expect(execFileMock).not.toHaveBeenCalled();
  });

  it('rejects Kopia output that does not contain JSON', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) => callback(null, 'progress without json', ''));
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().listSnapshots('/data/bad-json')).rejects.toThrow('kopia_json_parse_failed');
  });

  it('normalizes numeric snapshot sizes and missing size fallbacks', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) => {
      callback(
        null,
        JSON.stringify({
          items: [
            { snapshotID: 'snap-sized', startTime: '2026-06-08T02:00:00Z', size: 128, checksum: 'checksum-1' },
            { id: 'snap-bare' },
          ],
        }),
        '',
      );
    });
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().listSnapshots('/data/project')).resolves.toMatchObject({
      snapshots: [
        {
          snapshotId: 'snap-sized',
          displayName: 'project @ 2026-06-08T02:00:00Z',
          sizeBytes: 128,
          checksum: 'checksum-1',
        },
        {
          snapshotId: 'snap-bare',
          displayName: 'project @ snap-bare',
          sizeBytes: null,
          checksum: null,
        },
      ],
    });
  });

  it('wraps Kopia CLI failures with stderr details', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) => {
      callback(new Error('spawn failed'), '', 'repository locked');
    });
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().listSnapshots('/data')).rejects.toThrow(
      'kopia_cli_failed: spawn failed; repository locked',
    );
  });

  it('wraps Kopia CLI failures when stderr is empty', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) => {
      callback(new Error('spawn failed'), '', '');
    });
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().listSnapshots('/data')).rejects.toThrow('kopia_cli_failed: spawn failed');
  });

  it('refuses to restore over an existing target path', async () => {
    statMock.mockResolvedValue({});
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().downloadVersionCopy('snap-1', null, '/restore/a.txt')).rejects.toThrow(
      'target_already_exists',
    );
    expect(execFileMock).not.toHaveBeenCalled();
  });

  it('propagates unexpected target stat errors before restoring copies', async () => {
    statMock.mockRejectedValue(Object.assign(new Error('permission denied'), { code: 'EACCES' }));
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().downloadVersionCopy('snap-1', '/data/a.txt', '/restore/a.txt')).rejects.toThrow(
      'permission denied',
    );
    expect(execFileMock).not.toHaveBeenCalled();
  });

  it('restores missing targets and normalizes object paths into snapshot refs', async () => {
    statMock.mockRejectedValue(Object.assign(new Error('missing'), { code: 'ENOENT' }));
    execFileMock.mockImplementation((_exe, _args, _options, callback) => callback(null, 'restored', ''));
    const { KopiaService } = await import('./kopia.service');

    await expect(
      new KopiaService().downloadVersionCopy('snap-1', 'C:\\root\\folder\\a.txt', '/restore/a.txt'),
    ).resolves.toEqual({
      sourceRef: 'snap-1/root/folder/a.txt',
      targetPath: '/restore/a.txt',
      stderr: '',
      stdout: 'restored',
    });
    expect(execFileMock).toHaveBeenCalledWith(
      'kopia',
      ['snapshot', 'restore', 'snap-1/root/folder/a.txt', '/restore/a.txt'],
      expect.any(Object),
      expect.any(Function),
    );
  });

  it('restores a whole snapshot when no object path is provided', async () => {
    statMock.mockRejectedValue(Object.assign(new Error('missing'), { code: 'ENOENT' }));
    execFileMock.mockImplementation((_exe, _args, _options, callback) => callback(null, 'restored', ''));
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().downloadVersionCopy('snap-1', null, '/restore/snapshot')).resolves.toEqual({
      sourceRef: 'snap-1',
      targetPath: '/restore/snapshot',
      stderr: '',
      stdout: 'restored',
    });
    expect(execFileMock).toHaveBeenCalledWith(
      'kopia',
      ['snapshot', 'restore', 'snap-1', '/restore/snapshot'],
      expect.any(Object),
      expect.any(Function),
    );
  });

  it('prepares restore commands without executing Kopia', async () => {
    process.env.KOPIA_EXE = 'kopia.exe';
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().prepareRestore('snap-1', '/data/a.txt', null)).resolves.toEqual({
      executable: 'kopia.exe',
      command: ['kopia.exe', 'snapshot', 'restore', 'snap-1/data/a.txt', '<target-path>'],
      executableStep: false,
      reason: 'restore_prepare_only_requires_second_confirmation',
    });
    expect(execFileMock).not.toHaveBeenCalled();
  });

  it('prepares snapshot-level restore commands when no object path is provided', async () => {
    const { KopiaService } = await import('./kopia.service');

    await expect(new KopiaService().prepareRestore('snap-1', null, '/restore/snapshot')).resolves.toEqual({
      executable: 'kopia',
      command: ['kopia', 'snapshot', 'restore', 'snap-1', '/restore/snapshot'],
      executableStep: false,
      reason: 'restore_prepare_only_requires_second_confirmation',
    });
    expect(execFileMock).not.toHaveBeenCalled();
  });
});
