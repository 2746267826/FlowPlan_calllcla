import { describe, expect, it, vi } from 'vitest';
import { FileVersionService } from './file-version.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function databaseMock(rows: Record<string, unknown[]> = {}) {
  const query = vi.fn(async (sql: string) => {
    if (sql.includes('FROM file_version_records') && sql.includes('ORDER BY modified_at')) {
      return { rows: rows.versions ?? [{ id: 'version-1', versionRef: 'snap-1' }] };
    }
    if (sql.includes('FROM file_version_records') && sql.includes('LIMIT 1')) {
      return { rows: rows.version ?? [] };
    }
    if (sql.includes('INSERT INTO file_version_records')) {
      return { rows: rows.savedVersions ?? [{ id: 'version-2', versionUid: 'kopia:file-1:snap-1:hash' }] };
    }
    if (sql.includes('INSERT INTO file_version_download_requests')) {
      return { rows: rows.requests ?? [{ id: 'request-1', status: 'pending', targetMode: 'download_copy' }] };
    }
    if (sql.includes('FROM file_conflict_candidates')) {
      return { rows: rows.conflicts ?? [{ id: 'conflict-1', status: 'open' }] };
    }
    if (sql.includes('INSERT INTO file_conflict_candidates')) {
      return { rows: rows.insertedConflicts ?? [{ id: 'conflict-1', status: 'open' }] };
    }
    if (sql.includes('UPDATE file_conflict_candidates')) {
      return { rows: rows.resolvedConflicts ?? [{ id: 'conflict-1', status: 'resolved' }] };
    }
    return { rows: [] };
  });
  return {
    query,
    transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) => callback({ query })),
  };
}

function createService(database = databaseMock(), kopia = {}) {
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };
  const kopiaService = {
    createSnapshot: vi.fn(async () => ({ snapshots: [{ snapshotId: 's1' }] })),
    listSnapshots: vi.fn(async () => ({ snapshots: [] })),
    downloadVersionCopy: vi.fn(async () => ({ sourceRef: 'snap-1' })),
    prepareRestore: vi.fn(async () => ({ command: 'restore' })),
    ...kopia,
  };
  return {
    service: new FileVersionService(database as never, devices as never, kopiaService as never),
    database,
    devices,
    kopiaService,
  };
}

describe('FileVersionService', () => {
  it('lists versions for a file', async () => {
    const database = databaseMock({ versions: [{ id: 'version-1', versionRef: 'snap-1' }] });
    const { service } = createService(database);

    await expect(service.versions('file-1', context)).resolves.toEqual({
      versions: [{ id: 'version-1', versionRef: 'snap-1' }],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM file_version_records'),
      [context.userId, 'file-1'],
    );
  });

  it('creates a version download request only when the version exists', async () => {
    const database = databaseMock({
      version: [{ id: 'version-1', file_id: 'file-1', provider: 'kopia', version_ref: 'snap-1' }],
      requests: [{ id: 'request-1', status: 'pending', targetMode: 'restore_original' }],
    });
    const { service } = createService(database);

    await expect(
      service.createVersionDownloadRequest('version-1', { targetMode: 'restore_original', targetPath: '/tmp/a' }, context),
    ).resolves.toEqual({
      ok: true,
      request: { id: 'request-1', status: 'pending', targetMode: 'restore_original' },
    });
    expect(database.transaction).toHaveBeenCalledOnce();
  });

  it('creates version download requests with the default target mode and cleaned audit note', async () => {
    const database = databaseMock({
      version: [{ id: 'version-1', file_id: 'file-1', provider: 'kopia', version_ref: 'snap-1' }],
      requests: [{ id: 'request-1', status: 'pending', targetMode: 'download_copy', targetPath: '/tmp/copy' }],
    });
    const { service } = createService(database);

    await expect(
      service.createVersionDownloadRequest('version-1', { targetPath: '/tmp/copy', auditNote: '   ' }, context),
    ).resolves.toEqual({
      ok: true,
      request: { id: 'request-1', status: 'pending', targetMode: 'download_copy', targetPath: '/tmp/copy' },
    });
    const insertCall = database.query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO file_version_download_requests'));
    expect(insertCall?.[1]).toEqual([
      context.userId,
      'version-1',
      'file-1',
      'kopia',
      'snap-1',
      'download_copy',
      '/tmp/copy',
      null,
    ]);
  });

  it('returns null request when the version does not exist', async () => {
    const { service } = createService(databaseMock({ version: [] }));

    await expect(service.createVersionDownloadRequest('missing', {}, context)).resolves.toEqual({
      ok: false,
      request: null,
    });
  });

  it('validates required Kopia snapshot and refresh inputs', async () => {
    const { service, kopiaService } = createService();

    await expect(service.createKopiaSnapshot({}, context)).resolves.toEqual({
      ok: false,
      reason: 'rootPath_required',
    });
    await expect(service.refreshKopiaVersions({ fileId: 'file-1' }, context)).resolves.toEqual({
      ok: false,
      reason: 'fileId_and_filePath_required',
    });
    expect(kopiaService.createSnapshot).not.toHaveBeenCalled();
    expect(kopiaService.listSnapshots).not.toHaveBeenCalled();
  });

  it('records failed Kopia snapshot attempts with the error reason', async () => {
    const database = databaseMock();
    const { service } = createService(database, {
      createSnapshot: vi.fn(async () => {
        throw new Error('kopia unavailable');
      }),
    });

    await expect(service.createKopiaSnapshot({ rootPath: '/data' }, context)).resolves.toEqual({
      ok: false,
      reason: 'kopia unavailable',
    });
    expect(database.transaction).toHaveBeenCalledOnce();
  });

  it('audits successful Kopia snapshot attempts', async () => {
    const database = databaseMock();
    const { service, kopiaService } = createService(database, {
      createSnapshot: vi.fn(async () => ({
        rootPath: '/data',
        stderr: '',
        snapshots: [{ snapshotId: 'snap-1', versionRef: 'snap-1' }],
      })),
    });

    await expect(service.createKopiaSnapshot({ rootPath: '/data', rootId: 'root-1' }, context)).resolves.toEqual({
      ok: true,
      rootPath: '/data',
      stderr: '',
      snapshots: [{ snapshotId: 'snap-1', versionRef: 'snap-1' }],
    });
    expect(kopiaService.createSnapshot).toHaveBeenCalledWith('/data');
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'files.kopia.snapshot.create']),
    );
  });

  it('refreshes Kopia versions using display-name defaults and snapshot metadata', async () => {
    const database = databaseMock({
      savedVersions: [{ id: 'saved-1', versionUid: 'kopia:file-1:snap-1:uid', displayName: 'Snapshot A' }],
    });
    const { service, kopiaService } = createService(database, {
      listSnapshots: vi.fn(async () => ({
        targetPath: 'C:\\data\\report.md',
        raw: null,
        stderr: '',
        snapshots: [
          {
            snapshotId: 'snap-1',
            versionRef: 'snap-1',
            displayName: 'Snapshot A',
            modifiedAt: '2026-06-08T01:00:00Z',
            sizeBytes: 42,
            checksum: 'hash-1',
            metadata: { targetPath: 'C:\\data\\report.md' },
          },
        ],
      })),
    });

    await expect(
      service.refreshKopiaVersions({ fileId: 'file-1', filePath: 'C:\\data\\report.md' }, context),
    ).resolves.toEqual({
      ok: true,
      versions: [{ id: 'saved-1', versionUid: 'kopia:file-1:snap-1:uid', displayName: 'Snapshot A' }],
    });
    expect(kopiaService.listSnapshots).toHaveBeenCalledWith('C:\\data\\report.md');
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_version_records'),
      expect.arrayContaining([
        context.userId,
        expect.stringMatching(/^kopia:file-1:snap-1:/),
        'file-1',
        'snap-1',
        'Snapshot A',
        42,
        expect.any(Date),
        'hash-1',
        context.deviceId,
        'Kopia snapshot snap-1',
        expect.stringContaining('"displayName":"report.md"'),
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'files.kopia.versions.refresh']),
    );
  });

  it('records failed Kopia version refreshes', async () => {
    const database = databaseMock();
    const { service } = createService(database, {
      listSnapshots: vi.fn(async () => {
        throw new Error('list failed');
      }),
    });

    await expect(service.refreshKopiaVersions({ fileId: 'file-1', filePath: '/data/report.md' }, context)).resolves.toEqual({
      ok: false,
      reason: 'list failed',
      versions: [],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'files.kopia.versions.failed']),
    );
  });

  it('refreshes Kopia versions with nullable snapshot defaults and explicit display metadata', async () => {
    const database = databaseMock({
      savedVersions: [{ id: 'saved-1', versionUid: 'kopia:file-1:snap-minimal:uid', checksum: null }],
    });
    const { service } = createService(database, {
      listSnapshots: vi.fn(async () => ({
        targetPath: '/data/report.md',
        raw: null,
        stderr: '',
        snapshots: [
          {
            snapshotId: 'snap-minimal',
            versionRef: 'snap-minimal',
            displayName: 'Minimal Snapshot',
            modifiedAt: null,
            sizeBytes: null,
            checksum: null,
            metadata: { objectPath: '/snapshot/report.md' },
          },
        ],
      })),
    });

    await expect(
      service.refreshKopiaVersions({ fileId: 'file-1', filePath: '/data/report.md', displayName: 'Quarterly Report' }, context),
    ).resolves.toEqual({
      ok: true,
      versions: [{ id: 'saved-1', versionUid: 'kopia:file-1:snap-minimal:uid', checksum: null }],
    });
    const insertCall = database.query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO file_version_records'));
    const params = insertCall?.[1] as unknown[];
    expect(params[4]).toBe('Minimal Snapshot');
    expect(params[5]).toBeNull();
    expect(params[6]).toBeNull();
    expect(params[7]).toBeNull();
    expect(JSON.parse(String(params[10]))).toMatchObject({
      displayName: 'Quarterly Report',
      sourcePath: '/data/report.md',
      sourceRootId: null,
      objectPath: '/snapshot/report.md',
      kopiaSnapshotId: 'snap-minimal',
    });
  });

  it('lists, creates and resolves conflict records', async () => {
    const database = databaseMock({
      conflicts: [{ id: 'conflict-1', status: 'open' }],
      insertedConflicts: [{ id: 'conflict-2', status: 'open' }],
      resolvedConflicts: [{ id: 'conflict-2', status: 'resolved', resolution: { winner: 'a' } }],
    });
    const { service } = createService(database);

    await expect(service.conflicts(context)).resolves.toEqual({
      conflicts: [{ id: 'conflict-1', status: 'open' }],
    });
    await expect(service.createConflict({ fileUid: 'file-1', path: '/a.txt', versionA: { etag: 'a' } }, context)).resolves.toEqual({
      ok: true,
      conflict: { id: 'conflict-2', status: 'open' },
    });
    await expect(service.resolveConflict('conflict-2', { resolution: { winner: 'a' } }, context)).resolves.toEqual({
      ok: true,
      conflict: { id: 'conflict-2', status: 'resolved', resolution: { winner: 'a' } },
    });
  });

  it('creates conflict records with default providers, path and reason', async () => {
    const database = databaseMock({ insertedConflicts: [{ id: 'conflict-2', status: 'open' }] });
    const { service } = createService(database);

    await expect(service.createConflict({ fileUid: 'file-1' }, context)).resolves.toEqual({
      ok: true,
      conflict: { id: 'conflict-2', status: 'open' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_conflict_candidates'),
      [
        context.userId,
        'file-1',
        '/',
        'server_storage',
        'onedrive',
        '{}',
        '{}',
        'provider_version_mismatch',
      ],
    );
  });

  it('returns a closed status when resolving conflicts that are no longer open', async () => {
    const database = databaseMock({ resolvedConflicts: [] });
    const { service } = createService(database);

    await expect(service.resolveConflict('conflict-2', { resolution: { winner: 'a' } }, context)).resolves.toEqual({
      ok: false,
      conflict: null,
    });
    expect(database.transaction).toHaveBeenCalledOnce();
  });

  it('uses the request body as the resolution payload when no resolution wrapper is provided', async () => {
    const database = databaseMock({ resolvedConflicts: [{ id: 'conflict-2', status: 'resolved' }] });
    const { service } = createService(database);

    await expect(service.resolveConflict('conflict-2', { winner: 'provider-a' }, context)).resolves.toEqual({
      ok: true,
      conflict: { id: 'conflict-2', status: 'resolved' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE file_conflict_candidates'),
      [context.userId, 'conflict-2', JSON.stringify({ winner: 'provider-a' })],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'files.conflict.resolve',
        'conflict-2',
        expect.stringContaining('"winner":"provider-a"'),
      ]),
    );
  });

  it('prepares restore requests when a version exists', async () => {
    const database = databaseMock({
      version: [{ id: 'version-1', version_ref: 'snap-1', metadata: { sourcePath: '/data/a.txt' } }],
    });
    const { service, kopiaService } = createService(database);

    await expect(service.prepareVersionRestore('version-1', { targetPath: '/restore/a.txt' }, context)).resolves.toEqual({
      ok: true,
      prepare: { command: 'restore' },
    });
    expect(kopiaService.prepareRestore).toHaveBeenCalledWith('snap-1', '/data/a.txt', '/restore/a.txt');
  });

  it('prefers explicit object paths when preparing Kopia restore commands', async () => {
    const database = databaseMock({
      version: [
        {
          id: 'version-1',
          version_ref: 'snap-1',
          metadata: { objectPath: '/snapshot/object.txt', targetPath: '/target/not-used.txt', sourcePath: '/source/not-used.txt' },
        },
      ],
    });
    const { service, kopiaService } = createService(database);

    await expect(service.prepareVersionRestore('version-1', { targetPath: '/restore/object.txt' }, context)).resolves.toEqual({
      ok: true,
      prepare: { command: 'restore' },
    });
    expect(kopiaService.prepareRestore).toHaveBeenCalledWith('snap-1', '/snapshot/object.txt', '/restore/object.txt');
  });

  it('falls back to relative paths and then whole-snapshot restores when resolving Kopia objects', async () => {
    const relativeDatabase = databaseMock({
      version: [{ id: 'version-1', version_ref: 'snap-1', metadata: { relativePath: 'docs/a.txt' } }],
    });
    const relative = createService(relativeDatabase);

    await expect(relative.service.prepareVersionRestore('version-1', {}, context)).resolves.toEqual({
      ok: true,
      prepare: { command: 'restore' },
    });
    expect(relative.kopiaService.prepareRestore).toHaveBeenCalledWith('snap-1', 'docs/a.txt', null);

    const snapshotDatabase = databaseMock({
      version: [{ id: 'version-2', version_ref: 'snap-2', metadata: {} }],
    });
    const snapshot = createService(snapshotDatabase);

    await expect(snapshot.service.prepareVersionRestore('version-2', {}, context)).resolves.toEqual({
      ok: true,
      prepare: { command: 'restore' },
    });
    expect(snapshot.kopiaService.prepareRestore).toHaveBeenCalledWith('snap-2', null, null);
  });

  it('validates download copy target paths before opening a transaction', async () => {
    const database = databaseMock();
    const { service } = createService(database);

    await expect(service.downloadVersionCopy('version-1', {}, context)).resolves.toEqual({
      ok: false,
      reason: 'targetPath_required',
    });
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('returns not found when downloading a missing version copy', async () => {
    const database = databaseMock({ version: [] });
    const { service } = createService(database);

    await expect(service.downloadVersionCopy('missing', { targetPath: '/restore/a.txt' }, context)).resolves.toEqual({
      ok: false,
      reason: 'version_not_found',
    });
  });

  it('downloads a Kopia version copy and marks the request completed', async () => {
    const database = databaseMock({
      version: [{ id: 'version-1', file_id: 'file-1', provider: 'kopia', version_ref: 'snap-1', metadata: { targetPath: '/data/a.txt' } }],
      requests: [{ id: 'request-1' }],
    });
    const { service, kopiaService } = createService(database, {
      downloadVersionCopy: vi.fn(async () => ({ sourceRef: 'snap-1/data/a.txt', targetPath: '/restore/a.txt' })),
    });

    await expect(service.downloadVersionCopy('version-1', { targetPath: '/restore/a.txt', auditNote: 'copy' }, context)).resolves.toEqual({
      ok: true,
      request: { id: 'request-1' },
      download: { sourceRef: 'snap-1/data/a.txt', targetPath: '/restore/a.txt' },
    });
    expect(kopiaService.downloadVersionCopy).toHaveBeenCalledWith('snap-1', '/data/a.txt', '/restore/a.txt');
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'completed'"),
      [context.userId, 'request-1'],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'files.kopia.version.download_copy']),
    );
  });

  it('marks download copy requests failed when Kopia restore fails', async () => {
    const database = databaseMock({
      version: [{ id: 'version-1', file_id: 'file-1', provider: 'kopia', version_ref: 'snap-1', metadata: { filePath: '/data/a.txt' } }],
      requests: [{ id: 'request-1' }],
    });
    const { service } = createService(database, {
      downloadVersionCopy: vi.fn(async () => {
        throw new Error('restore failed');
      }),
    });

    await expect(service.downloadVersionCopy('version-1', { targetPath: '/restore/a.txt' }, context)).resolves.toEqual({
      ok: false,
      reason: 'restore failed',
      request: { id: 'request-1' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'failed'"),
      [context.userId, 'request-1'],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'files.kopia.version.download_failed']),
    );
  });

  it('returns not found when preparing restore for a missing version', async () => {
    const database = databaseMock({ version: [] });
    const { service, kopiaService } = createService(database);

    await expect(service.prepareVersionRestore('missing', {}, context)).resolves.toEqual({
      ok: false,
      reason: 'version_not_found',
    });
    expect(kopiaService.prepareRestore).not.toHaveBeenCalled();
  });
});
