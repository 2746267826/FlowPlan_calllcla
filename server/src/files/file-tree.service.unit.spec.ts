import { afterEach, describe, expect, it, vi } from 'vitest';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { FileTreeService } from './file-tree.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function createDatabase(options: {
  root?: Record<string, unknown> | null;
  savedNodeId?: string;
} = {}) {
  const query = vi.fn(async (sql: string) => {
    if (sql.includes('FROM file_roots') && sql.includes('root_uri')) {
      return { rows: options.root === undefined ? [{ id: 'root-1', rootUri: '/data', name: 'data' }] : options.root ? [options.root] : [] };
    }
    if (sql.includes('SELECT id::text AS id') && sql.includes('FROM file_nodes')) {
      return { rows: [{ id: options.savedNodeId ?? 'node-1' }] };
    }
    return { rows: [] };
  });
  return {
    query,
    transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) => callback({ query })),
  };
}

function createService(database = createDatabase()) {
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };
  return {
    service: new FileTreeService(database as never, devices as never),
    database,
    devices,
  };
}

describe('FileTreeService', () => {
  const tempDirs: string[] = [];

  afterEach(async () => {
    vi.restoreAllMocks();
    await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
  });

  it('rejects node snapshots without a root id before opening a transaction', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(service.applyNodeSnapshot({ nodes: [{ name: 'a.txt' }] }, context)).resolves.toEqual({
      ok: false,
      error: 'rootId is required',
      applied: 0,
    });
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('applies node snapshots with generated defaults, device locations, identity mappings and audit logging', async () => {
    const database = createDatabase({ savedNodeId: 'node-42' });
    const { service } = createService(database);

    await expect(
      service.applyNodeSnapshot(
        {
          rootId: 'root-1',
          nodes: [
            {
              relativePath: 'docs/report.md',
              localPath: '/data/docs/report.md',
              hashSha256: 'hash-1',
              sizeBytes: '128',
              mtime: '2026-06-08T00:00:00Z',
              metadata: { tag: 'report' },
            },
          ],
          scanStatus: 'partial',
          scanDiagnostic: { startedAt: '2026-06-08T00:00:00Z', scanned: 1 },
        },
        context,
      ),
    ).resolves.toMatchObject({ ok: true, rootId: 'root-1', applied: 1 });
    expect(database.transaction).toHaveBeenCalledOnce();
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_nodes'),
      expect.arrayContaining([
        context.userId,
        'node:root-1:docs/report.md',
        'root-1',
        null,
        'file',
        'report.md',
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_node_device_locations'),
      expect.arrayContaining([context.userId, 'node-42', context.deviceId, '/data/docs/report.md', 'available']),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_identity_mappings'),
      expect.arrayContaining([context.userId, 'node-42', 'local', null, context.deviceId, '/data/docs/report.md', 'hash-1']),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'file.nodes.snapshot']),
    );
  });

  it('applies node snapshots with anonymous-node defaults and no optional mappings', async () => {
    const database = createDatabase({ savedNodeId: 'node-42' });
    const { service } = createService(database);

    await expect(service.applyNodeSnapshot({ rootId: 'root-1', nodes: [{}] }, context)).resolves.toMatchObject({
      ok: true,
      rootId: 'root-1',
      applied: 1,
    });
    const insertCall = database.query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO file_nodes'));
    const params = insertCall?.[1] as unknown[];
    expect(params[1]).toEqual(expect.stringMatching(/^node:root-1:/));
    expect(params[3]).toBeNull();
    expect(params[4]).toBe('file');
    expect(params[5]).toBe(params[1]);
    expect(params[6]).toBe('');
    expect(params[16]).toBe('none');
    expect(params[17]).toBe('none');
    expect(params[18]).toBe('none');
    expect(params[19]).toBe(false);
    expect(params[20]).toBe(false);
    expect(params[21]).toBe('{}');
    expect(database.query).not.toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_node_device_locations'),
      expect.any(Array),
    );
    expect(database.query).not.toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_identity_mappings'),
      expect.any(Array),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE file_roots'),
      [context.userId, 'root-1', 'completed', '{}'],
    );
  });

  it('uses parentUid aliases and identity confidence fallbacks when parent rows are missing', async () => {
    const database = createDatabase({ savedNodeId: 'node-42' });
    const { service } = createService(database);

    await expect(
      service.applyNodeSnapshot(
        {
          rootId: 'root-1',
          nodes: [
            {
              relativePath: 'docs/provider-id.txt',
              parentUid: 'node:root-1:missing-parent',
              providerFileId: 'provider-1',
            },
            {
              relativePath: 'docs/path-only.txt',
              localPath: '/data/docs/path-only.txt',
              sizeBytes: '9',
              mtime: '2026-06-08T00:00:00Z',
            },
          ],
        },
        context,
      ),
    ).resolves.toMatchObject({ ok: true, rootId: 'root-1', applied: 2 });
    const nodeInsertCalls = database.query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO file_nodes'));
    expect((nodeInsertCalls[0]?.[1] as unknown[])[3]).toBe('node:root-1:missing-parent');

    const identityCalls = database.query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO file_identity_mappings'));
    expect(identityCalls).toHaveLength(2);
    expect(identityCalls.map(([, params]) => (params as unknown[])[9])).toEqual(['provider_id', 'path_size_mtime']);
    expect(database.query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO file_node_device_locations'))).toHaveLength(1);
  });

  it('returns not found when scan root metadata is missing', async () => {
    const database = createDatabase({ root: null });
    const { service } = createService(database);

    await expect(service.scanDriveRoot('missing-root', {}, context)).resolves.toEqual({
      ok: false,
      reason: 'root_not_found_or_path_missing',
      applied: 0,
    });
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('records failed scan metadata from the last collected node and handles unnamed roots', async () => {
    const database = createDatabase({ root: { id: 'root-1', rootUri: '/data' } });
    const { service } = createService(database);
    const internal = service as never as {
      collectLocalNodesForRoot: (
        userId: string,
        rootId: string,
        rootPath: string,
        maxNodes: number,
        nodes: Record<string, unknown>[],
      ) => Promise<void>;
    };
    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    vi.spyOn(internal, 'collectLocalNodesForRoot').mockImplementation(async (
      _userId,
      _rootId,
      _rootPath,
      _maxNodes,
      nodes,
    ) => {
      nodes.push({ localPath: '/data/last-node.txt' });
      throw new Error('scan failed after first node');
    });

    await expect(service.scanDriveRoot('root-1', { maxNodes: 5 }, context)).resolves.toMatchObject({
      ok: false,
      reason: 'scan_failed',
      error: 'scan failed after first node',
      applied: 0,
    });

    expect(consoleSpy.mock.calls[0]?.[0]).toContain('name=""');
    const failedUpdate = database.query.mock.calls.find(([sql]) =>
      String(sql).includes("scan_status = 'failed'"),
    );
    const failedMetadata = JSON.parse(String((failedUpdate?.[1] as unknown[])[3]));
    expect(failedMetadata.lastScan.currentPath).toBe('/data/last-node.txt');
  });

  it('applies an empty snapshot when nodes is not an array and omits invalid duration metadata', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(
      service.applyNodeSnapshot(
        {
          rootId: 'root-1',
          nodes: { ignored: true },
          scanDiagnostic: { scanned: 0 },
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, rootId: 'root-1', applied: 0 });

    expect(database.query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO file_nodes'))).toHaveLength(0);
    const rootUpdate = database.query.mock.calls.find(([sql, params]) =>
      String(sql).includes('UPDATE file_roots') && Array.isArray(params) && params[2] === 'completed',
    );
    const metadata = JSON.parse(String((rootUpdate?.[1] as unknown[])[3]));
    expect(metadata.lastScan).toMatchObject({
      status: 'completed',
      applied: 0,
      scanned: 0,
      progressMessage: 'completed: applied 0 nodes',
    });
    expect(metadata.lastScan).not.toHaveProperty('durationMs');
  });

  it('scans a small temporary root, respects maxNodes and applies the collected snapshot', async () => {
    const rootPath = await mkdtemp(join(tmpdir(), 'flowplan-file-tree-'));
    tempDirs.push(rootPath);
    await writeFile(join(rootPath, 'a.txt'), 'hello');
    await writeFile(join(rootPath, 'b.txt'), 'world');
    const database = createDatabase({ root: { id: 'root-1', rootUri: rootPath, name: 'tmp-root' } });
    const { service } = createService(database);
    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => undefined);

    await expect(service.scanDriveRoot('root-1', { maxNodes: 2, rootPath: 'ignored-client-path' }, context)).resolves.toMatchObject({
      ok: true,
      rootId: 'root-1',
      scanned: 2,
      applied: 2,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_operation_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'file.drive.root.scan_path_override_ignored']),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE file_roots'),
      expect.arrayContaining([context.userId, 'root-1', 'completed']),
    );
    expect(consoleSpy).toHaveBeenCalled();
  });

  it('throttles scan progress updates when the publish interval has not elapsed', async () => {
    const rootPath = await mkdtemp(join(tmpdir(), 'flowplan-file-tree-throttle-'));
    tempDirs.push(rootPath);
    await writeFile(join(rootPath, 'a.txt'), 'hello');
    const database = createDatabase({ root: { id: 'root-1', rootUri: rootPath, name: 'tmp-root' } });
    const { service } = createService(database);
    vi.spyOn(Date, 'now').mockReturnValue(1000);
    vi.spyOn(console, 'log').mockImplementation(() => undefined);

    await expect(service.scanDriveRoot('root-1', { maxNodes: 0 }, context)).resolves.toMatchObject({
      ok: true,
      rootId: 'root-1',
      scanned: 2,
      applied: 2,
    });
    const progressPayloads = database.query.mock.calls
      .map(([, params]) => (Array.isArray(params) ? params.find((value) => typeof value === 'string' && value.includes('"phase"')) : undefined))
      .filter(Boolean);
    expect(progressPayloads).toEqual([]);
  });

  it('continues safely if the pending scan queue yields no current folder', async () => {
    const rootPath = await mkdtemp(join(tmpdir(), 'flowplan-file-tree-empty-shift-'));
    tempDirs.push(rootPath);
    await writeFile(join(rootPath, 'not-scanned.txt'), 'hello');
    const { service } = createService();
    const internal = service as never as {
      collectLocalNodesForRoot: (
        userId: string,
        rootId: string,
        rootPath: string,
        maxNodes: number,
        nodes: Record<string, unknown>[],
      ) => Promise<void>;
    };
    const nodes: Record<string, unknown>[] = [];
    const originalShift = Array.prototype.shift;
    Array.prototype.shift = function (this: unknown[]) {
      if (
        this.length === 1 &&
        typeof this[0] === 'object' &&
        this[0] !== null &&
        (this[0] as { path?: unknown }).path === rootPath
      ) {
        originalShift.call(this);
        return undefined;
      }
      return originalShift.call(this);
    };

    try {
      await expect(
        internal.collectLocalNodesForRoot(context.userId, 'root-1', rootPath, 0, nodes),
      ).resolves.toBeUndefined();
    } finally {
      Array.prototype.shift = originalShift;
    }

    expect(nodes).toHaveLength(1);
    expect(nodes[0]).toMatchObject({
      nodeType: 'folder',
      localPath: rootPath,
    });
  });

  it('skips scanned directory entries that are neither files nor folders', async () => {
    vi.resetModules();
    const rootPath = 'C:\\flowplan-special-root';
    const keptPath = join(rootPath, 'kept.txt');
    const ignoredPath = join(rootPath, 'ignored-special');
    const readdirMock = vi.fn(async () => [
      {
        name: 'ignored-special',
        isFile: () => false,
        isDirectory: () => false,
      },
      {
        name: 'kept.txt',
        isFile: () => true,
        isDirectory: () => false,
      },
    ]);
    const statMock = vi.fn(async (path: string) => ({
      size: path === keptPath ? 4 : 0,
      mtime: new Date('2026-06-08T00:00:00.000Z'),
      ctime: new Date('2026-06-08T00:00:00.000Z'),
    }));
    vi.doMock('node:fs/promises', async () => ({
      ...(await vi.importActual<typeof import('node:fs/promises')>('node:fs/promises')),
      readdir: readdirMock,
      stat: statMock,
    }));
    const { FileTreeService: MockedFileTreeService } = await import('./file-tree.service');
    const { database, devices } = createService();
    const service = new MockedFileTreeService(database as never, devices as never);
    const internal = service as never as {
      collectLocalNodesForRoot: (
        userId: string,
        rootId: string,
        rootPath: string,
        maxNodes: number,
        nodes: Record<string, unknown>[],
      ) => Promise<void>;
    };
    const nodes: Record<string, unknown>[] = [];

    await internal.collectLocalNodesForRoot(context.userId, 'root-1', rootPath, 0, nodes);

    expect(nodes.map((node) => node.name)).toEqual(['flowplan-special-root', 'kept.txt']);
    expect(statMock).toHaveBeenCalledWith(rootPath);
    expect(statMock).toHaveBeenCalledWith(keptPath);
    expect(statMock).not.toHaveBeenCalledWith(ignoredPath);
    expect(nodes.find((node) => node.name === 'ignored-special')).toBeUndefined();
    vi.doUnmock('node:fs/promises');
    vi.resetModules();
  });

  it('scans nested folders and records mime metadata for supported extensions', async () => {
    const rootPath = await mkdtemp(join(tmpdir(), 'flowplan-file-tree-mime-'));
    tempDirs.push(rootPath);
    const nestedPath = join(rootPath, 'nested');
    await mkdir(nestedPath);
    const files = [
      ['readme.md', '# notes'],
      ['data.json', '{}'],
      ['export.csv', 'a,b'],
      ['notes.yaml', 'a: b'],
      ['config.yml', 'a: b'],
      ['runtime.log', 'line'],
      ['image.png', 'png'],
      ['photo.jpg', 'jpg'],
      ['photo.jpeg', 'jpeg'],
      ['anim.gif', 'gif'],
      ['bitmap.bmp', 'bmp'],
      ['asset.webp', 'webp'],
      ['manual.pdf', 'pdf'],
      ['unknown.bin', 'bin'],
      ['UPPER.TXT', 'upper'],
      ['LICENSE', 'license'],
    ] as const;
    await Promise.all(files.map(([name, content]) => writeFile(join(nestedPath, name), content)));
    const database = createDatabase({ root: { id: 'root-1', rootUri: rootPath, name: 'tmp-root' } });
    const { service } = createService(database);
    vi.spyOn(console, 'log').mockImplementation(() => undefined);

    await expect(service.scanDriveRoot('root-1', { maxNodes: 0 }, context)).resolves.toMatchObject({
      ok: true,
      rootId: 'root-1',
      scanned: 18,
      applied: 18,
    });
    const nodeRows = new Map(
      database.query.mock.calls
        .filter(([sql]) => String(sql).includes('INSERT INTO file_nodes'))
        .map(([, params]) => {
          const values = params as unknown[];
          return [values[5], values] as const;
        }),
    );
    expect(nodeRows.get('nested')?.[4]).toBe('folder');
    expect(nodeRows.get('readme.md')?.[10]).toBe('text/markdown');
    expect(nodeRows.get('data.json')?.[10]).toBe('application/json');
    expect(nodeRows.get('export.csv')?.[10]).toBe('text/csv');
    expect(nodeRows.get('notes.yaml')?.[10]).toBe('text/yaml');
    expect(nodeRows.get('config.yml')?.[10]).toBe('text/yaml');
    expect(nodeRows.get('runtime.log')?.[10]).toBe('text/plain');
    expect(nodeRows.get('image.png')?.[10]).toBe('image/png');
    expect(nodeRows.get('photo.jpg')?.[10]).toBe('image/jpeg');
    expect(nodeRows.get('photo.jpeg')?.[10]).toBe('image/jpeg');
    expect(nodeRows.get('anim.gif')?.[10]).toBe('image/gif');
    expect(nodeRows.get('bitmap.bmp')?.[10]).toBe('image/bmp');
    expect(nodeRows.get('asset.webp')?.[10]).toBe('image/webp');
    expect(nodeRows.get('manual.pdf')?.[10]).toBe('application/pdf');
    expect(nodeRows.get('unknown.bin')?.[10]).toBeNull();
    expect(nodeRows.get('UPPER.TXT')?.[10]).toBe('text/plain');
    expect(nodeRows.get('UPPER.TXT')?.[11]).toBe('TXT');
    expect(nodeRows.get('LICENSE')?.[10]).toBeNull();
    expect(nodeRows.get('LICENSE')?.[11]).toBeNull();
  });

  it('scans with default maxNodes and records no-limit completion metadata', async () => {
    const rootPath = await mkdtemp(join(tmpdir(), 'flowplan-file-tree-default-scan-'));
    tempDirs.push(rootPath);
    await writeFile(join(rootPath, 'a.txt'), 'hello');
    const database = createDatabase({ root: { id: 'root-1', rootUri: rootPath, name: 'tmp-root' } });
    const { service } = createService(database);
    vi.spyOn(console, 'log').mockImplementation(() => undefined);

    await expect(service.scanDriveRoot('root-1', {}, context)).resolves.toMatchObject({
      ok: true,
      rootId: 'root-1',
      scanned: 2,
      applied: 2,
    });
    expect(database.query.mock.calls.some(([, params]) => Array.isArray(params) && params.includes('file.drive.root.scan_path_override_ignored'))).toBe(false);
    const rootMetadataPatches = database.query.mock.calls
      .map(([, params]) => (Array.isArray(params) ? params[3] : undefined))
      .filter((value): value is string => typeof value === 'string' && value.includes('lastScan'));
    expect(rootMetadataPatches.some((patch) => patch.includes('"maxNodes":0'))).toBe(true);
    expect(rootMetadataPatches.some((patch) => patch.includes('"reachedMaxNodes":false'))).toBe(true);
  });

  it('marks scans failed and audits when the server root cannot be read', async () => {
    const database = createDatabase({ root: { id: 'root-1', rootUri: join(tmpdir(), 'flowplan-missing-root'), name: 'missing' } });
    const { service } = createService(database);
    vi.spyOn(console, 'log').mockImplementation(() => undefined);

    await expect(service.scanDriveRoot('root-1', { maxNodes: 10 }, context)).resolves.toMatchObject({
      ok: false,
      reason: 'scan_failed',
      applied: 0,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET\n          scan_status = 'failed'"),
      expect.arrayContaining([context.userId, 'root-1']),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_operation_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'file.drive.root.scan', null]),
    );
  });

  it('selects audit entity ids from each fallback detail field', async () => {
    const database = createDatabase();
    const { service } = createService(database);
    const internal = service as never as {
      recordAudit: (
        client: { query: typeof database.query },
        userId: string,
        deviceId: string,
        action: string,
        details: Record<string, unknown>,
      ) => Promise<void>;
    };
    const cases = [
      [{ nodeId: 'node-1' }, 'node-1'],
      [{ sessionId: 'session-1' }, 'session-1'],
      [{ providerKey: 'provider-1' }, 'provider-1'],
      [{ conflictId: 'conflict-1' }, 'conflict-1'],
      [{}, null],
    ] as const;

    for (const [details, expected] of cases) {
      await internal.recordAudit(database, context.userId, context.deviceId, 'file.audit.test', details);
      const auditCall = database.query.mock.calls.at(-1);
      expect((auditCall?.[1] as unknown[])[3]).toBe(expected);
    }
  });
});
