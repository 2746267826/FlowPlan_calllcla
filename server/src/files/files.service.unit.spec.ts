import { describe, expect, it, vi } from 'vitest';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { FilesService } from './files.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function createDatabase(overrides: Record<string, unknown[]> = {}) {
  const query = vi.fn(async (sql: string, params?: unknown[]) => {
    if (sql.includes('FROM file_providers')) {
      return { rows: overrides.providers ?? [{ providerKey: 'server_storage' }] };
    }
    if (sql.includes('INSERT INTO file_providers')) {
      return { rows: overrides.upsertedProviders ?? [{ id: 'provider-1', providerKey: params?.[1], status: params?.[5], updatedAt: 'now' }] };
    }
    if (sql.includes('FROM cloud_file_tree_nodes')) {
      return { rows: overrides.tree ?? [{ id: 'node-1', displayName: 'Report.md' }] };
    }
    if (sql.includes('FROM file_transfer_sessions')) {
      return { rows: overrides.sessions ?? [] };
    }
    if (sql.includes('SELECT payload') && sql.includes('FROM file_transfer_chunks')) {
      return { rows: overrides.payloadChunks ?? [] };
    }
    if (sql.includes('FROM file_transfer_chunks')) {
      return { rows: overrides.chunks ?? [] };
    }
    if (sql.includes('INSERT INTO file_transfer_sessions')) {
      return {
        rows: overrides.insertedSessions ?? [
          {
            sessionId: 'session-1',
            resumeToken: 'resume-1',
            providerKey: 'server_storage',
            objectKey: 'object-1',
            chunkSize: 4,
            expectedChunks: 3,
            status: 'open',
          },
        ],
      };
    }
    if (sql.includes('INSERT INTO file_storage_objects')) {
      return { rows: overrides.storageObjects ?? [{ storageObjectId: 'storage-1', objectKey: 'object-1' }] };
    }
    if (sql.includes('INSERT INTO file_nodes')) {
      return { rows: overrides.insertedNodes ?? [{ id: 'node-1' }] };
    }
    if (sql.includes('INSERT INTO file_node_device_locations')) {
      return {
        rows: overrides.locations ?? [
          {
            id: 'location-1',
            nodeId: params?.[1],
            localPath: params?.[3],
            availability: params?.[4] ?? 'available',
          },
        ],
      };
    }
    if (sql.includes('FROM file_roots') && sql.includes('root_uri')) {
      return { rows: overrides.rootLookup ?? [] };
    }
    if (sql.includes('DELETE FROM file_roots')) {
      return { rows: [] };
    }
    if (sql.includes('UPDATE file_nodes')) {
      return { rows: overrides.updatedNodes ?? [{ id: 'node-1', nodeUid: 'node-uid', name: 'Report.md' }] };
    }
    if (sql.includes('FROM file_nodes n')) {
      return { rows: overrides.nodes ?? [] };
    }
    if (sql.includes('FROM file_nodes') && sql.includes('SELECT relative_path')) {
      return { rows: overrides.parentNodes ?? [] };
    }
    if (sql.includes('FROM file_storage_objects')) {
      return { rows: overrides.storageLookup ?? [] };
    }
    if (sql.includes('INSERT INTO file_conflict_candidates')) {
      return { rows: overrides.conflicts ?? [{ id: 'conflict-1', status: 'open' }] };
    }
    if (sql.includes('UPDATE file_conflict_candidates')) {
      return { rows: overrides.resolvedConflicts ?? [] };
    }
    if (sql.includes('INSERT INTO file_context_links')) {
      return { rows: overrides.links ?? [{ id: 'link-1', linkUid: 'file-link:task:t1:n1' }] };
    }
    if (sql.includes('FROM file_context_links')) {
      return { rows: overrides.links ?? [{ id: 'link-1' }] };
    }
    if (sql.includes('FROM file_recommendations')) {
      return { rows: overrides.recommendations ?? [{ id: 'rec-1', score: 0.8 }] };
    }
    if (sql.includes('UPDATE file_recommendations')) {
      return {
        rows: overrides.reviewedRecommendations ?? [
          {
            id: 'rec-1',
            entityType: 'task',
            entityId: 'task-1',
            nodeId: 'node-1',
            status: 'accepted',
          },
        ],
      };
    }
    if (sql.includes('INSERT INTO file_roots')) {
      return { rows: overrides.roots ?? [{ id: 'root-1', rootUid: 'server-root:/data', name: 'data' }] };
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
  const objectStorage = {
    status: vi.fn(async () => ({ ok: true, root: '/storage' })),
    root: vi.fn(() => '/storage'),
    readRange: vi.fn(async () => Buffer.from('range-bytes')),
    writeObjectFromChunks: vi.fn(async () => ({
      objectKey: 'object-1',
      storagePath: '/storage/object-1',
      relativePath: 'object-1',
      sizeBytes: 12,
      checksum: 'checksum',
    })),
  };
  const fileTree = {
    scanDriveRoot: vi.fn(async (...args: unknown[]) => ({ method: 'scanDriveRoot', args })),
    applyNodeSnapshot: vi.fn(async (...args: unknown[]) => ({ method: 'applyNodeSnapshot', args })),
  };
  const fileTransfer = {
    storageStatus: vi.fn(async () => ({ ok: true })),
    storageObjects: vi.fn(async (...args: unknown[]) => ({ method: 'storageObjects', args })),
    registerStorageObject: vi.fn(async (...args: unknown[]) => ({ method: 'registerStorageObject', args })),
    upsertNetworkPresence: vi.fn(async (...args: unknown[]) => ({ method: 'upsertNetworkPresence', args })),
    networkPresence: vi.fn(async (...args: unknown[]) => ({ method: 'networkPresence', args })),
    transferCandidates: vi.fn(async (...args: unknown[]) => ({ method: 'transferCandidates', args })),
    upsertTransferCandidate: vi.fn(async (...args: unknown[]) => ({ method: 'upsertTransferCandidate', args })),
    appendTransferEvent: vi.fn(async (...args: unknown[]) => ({ method: 'appendTransferEvent', args })),
  };
  const fileVersion = {
    versions: vi.fn(async (...args: unknown[]) => ({ method: 'versions', args })),
    createVersionDownloadRequest: vi.fn(async (...args: unknown[]) => ({ method: 'createVersionDownloadRequest', args })),
    createKopiaSnapshot: vi.fn(async (...args: unknown[]) => ({ method: 'createKopiaSnapshot', args })),
    refreshKopiaVersions: vi.fn(async (...args: unknown[]) => ({ method: 'refreshKopiaVersions', args })),
    downloadVersionCopy: vi.fn(async (...args: unknown[]) => ({ method: 'downloadVersionCopy', args })),
    prepareVersionRestore: vi.fn(async (...args: unknown[]) => ({ method: 'prepareVersionRestore', args })),
    conflicts: vi.fn(async (...args: unknown[]) => ({ method: 'conflicts', args })),
    createConflict: vi.fn(async (...args: unknown[]) => ({ method: 'createConflict', args })),
    resolveConflict: vi.fn(async (...args: unknown[]) => ({ method: 'resolveConflict', args })),
  };
  const service = new FilesService(
    database as never,
    devices as never,
    objectStorage as never,
    fileTree as never,
    fileTransfer as never,
    fileVersion as never,
  );
  return { service, database, devices, objectStorage, fileTree, fileTransfer, fileVersion };
}

const session = {
  id: 'session-1',
  provider_key: 'server_storage',
  direction: 'upload',
  file_name: 'report.txt',
  object_key: 'object-1',
  storage_object_id: null,
  total_bytes: '12',
  chunk_size: 4,
  expected_chunks: 4,
  received_chunks: 2,
  received_bytes: '8',
  checksum: null,
  status: 'open',
  metadata: {},
};

function driveNodeRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'node-1',
    nodeUid: 'node-uid',
    rootId: 'root-1',
    parentId: null,
    nodeType: 'file',
    name: 'report.md',
    relativePath: 'docs/report.md',
    displayPath: 'docs/report.md',
    localPath: '/server/docs/report.md',
    providerFileId: 'provider-file-1',
    mimeType: 'text/markdown',
    extension: 'md',
    sizeBytes: '128',
    mtime: '2026-06-08T00:00:00.000Z',
    hashSha256: 'hash-1',
    previewStatus: 'ready',
    indexStatus: 'indexed',
    isDeleted: false,
    isMissing: false,
    rootName: 'Workspace',
    rootProviderType: 'server_storage',
    rootUri: '/server',
    rootDisplayPath: '/server',
    storageObjectId: 'storage-1',
    storageProviderKey: 'server_storage',
    storageStatus: 'available',
    storageChecksum: 'hash-1',
    deviceLocationId: 'location-1',
    deviceLocalPath: 'C:/workspace/report.md',
    deviceAvailability: 'available',
    deviceLastSeenAt: '2026-06-08T00:00:00.000Z',
    knownDeviceLocationCount: '1',
    metadata: { contentHash: 'hash-1' },
    updatedAt: '2026-06-08T00:00:00.000Z',
    ...overrides,
  };
}

describe('FilesService', () => {
  it('ensures default providers before listing providers', async () => {
    const database = createDatabase({ providers: [{ providerKey: 'server_storage', status: 'enabled' }] });
    const { service } = createService(database);

    await expect(service.providers(context)).resolves.toEqual({
      providers: [{ providerKey: 'server_storage', status: 'enabled' }],
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_providers'),
      [context.userId],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM file_providers'),
      [context.userId],
    );
  });

  it('combines provider, tree, transfer, version, conflict and storage status for dashboard', async () => {
    const database = createDatabase({
      providers: [{ providerKey: 'server_storage' }],
      tree: [{ providerKey: 'server_storage', count: 2 }],
    });
    const { service, objectStorage } = createService(database);

    const result = await service.dashboard(context);

    expect(result).toMatchObject({
      storageStatus: { ok: true, root: '/storage' },
      providers: [{ providerKey: 'server_storage' }],
    });
    expect(objectStorage.status).toHaveBeenCalledOnce();
  });

  it('queries tree nodes with normalized limit, offset and search filters', async () => {
    const database = createDatabase({ tree: [{ id: 'node-1', displayName: 'Report.md' }] });
    const { service } = createService(database);

    await expect(
      service.tree({ providerKey: 'onedrive', parentRemoteId: 'root', q: 'Report', limit: '2', offset: '3' }, context),
    ).resolves.toEqual({
      limit: 2,
      offset: 3,
      hasMore: false,
      items: [{ id: 'node-1', displayName: 'Report.md' }],
    });
    expect(database.query).toHaveBeenLastCalledWith(
      expect.stringContaining('FROM cloud_file_tree_nodes'),
      [context.userId, 'onedrive', 'root', '%Report%', 2, 3],
    );
  });

  it('upserts providers and applies tree snapshots with mark-missing audits', async () => {
    const database = createDatabase({
      upsertedProviders: [{ id: 'provider-1', providerKey: 'onedrive', status: 'enabled', updatedAt: 'now' }],
    });
    const { service } = createService(database);

    await expect(
      service.upsertProvider(
        'onedrive',
        {
          providerType: 'onedrive',
          displayName: 'OneDrive',
          priority: '4',
          status: 'enabled',
          rootRemoteId: 'root',
          localMirrorPath: '/mirror',
          mobileDownloadRoot: '/mobile',
          syncMode: 'mirror',
          capabilities: { tree: true },
          config: { tenant: 't1' },
          lastError: ' ',
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      provider: { id: 'provider-1', providerKey: 'onedrive', status: 'enabled', updatedAt: 'now' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_providers'),
      [
        context.userId,
        'onedrive',
        'onedrive',
        'OneDrive',
        4,
        'enabled',
        'root',
        '/mirror',
        '/mobile',
        'mirror',
        '{"tree":true}',
        '{"tenant":"t1"}',
        null,
      ],
    );

    database.query.mockClear();
    await expect(
      service.applyTreeSnapshot(
        {
          providerKey: 'onedrive',
          treeRevision: 'rev-1',
          markMissing: true,
          nodes: [
            null,
            { remoteId: '', path: '/skip' },
            {
              remoteId: 'remote-1',
              parentRemoteId: 'root',
              path: '/Docs/Report.md',
              displayName: '',
              itemType: 'file',
              mimeType: 'text/markdown',
              sizeBytes: '42',
              etag: 'etag',
              ctag: 'ctag',
              checksum: 'hash',
              localPath: 'C:/Docs/Report.md',
              availability: '',
              modifiedAt: '2026-06-08T00:00:00.000Z',
              metadata: { source: 'graph' },
            },
          ],
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, providerKey: 'onedrive', treeRevision: 'rev-1', accepted: 1 });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO cloud_file_tree_nodes'),
      expect.arrayContaining([
        context.userId,
        'onedrive',
        'remote-1',
        'root',
        '/Docs/Report.md',
        'Report.md',
        'file',
        'text/markdown',
        42,
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET availability = 'missing'"),
      [context.userId, 'onedrive', 'rev-1'],
    );
  });

  it('uses provider and tree snapshot defaults without marking missing nodes', async () => {
    const database = createDatabase({
      upsertedProviders: [{ id: 'provider-default', providerKey: 'box', status: 'enabled', updatedAt: 'now' }],
    });
    const { service } = createService(database);

    await expect(service.upsertProvider('box', {}, context)).resolves.toEqual({
      ok: true,
      provider: { id: 'provider-default', providerKey: 'box', status: 'enabled', updatedAt: 'now' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_providers'),
      [
        context.userId,
        'box',
        'box',
        'box',
        100,
        'enabled',
        null,
        null,
        null,
        'manual',
        '{}',
        '{}',
        null,
      ],
    );

    database.query.mockClear();
    await expect(service.applyTreeSnapshot({ nodes: 'not-an-array' }, context)).resolves.toMatchObject({
      ok: true,
      providerKey: 'onedrive',
      treeRevision: expect.any(String),
      accepted: 0,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_providers'),
      [context.userId, 'onedrive'],
    );
    expect(database.query.mock.calls.some(([sql]) => String(sql).includes("SET availability = 'missing'"))).toBe(false);
    const auditParams = database.query.mock.calls.find(([sql, params]) =>
      String(sql).includes('INSERT INTO audit_logs') &&
      Array.isArray(params) &&
      params[2] === 'files.tree.snapshot',
    )?.[1] as unknown[];
    expect(JSON.parse(String(auditParams[4]))).toMatchObject({
      providerKey: 'onedrive',
      accepted: 0,
      markMissing: false,
    });

    database.query.mockClear();
    await expect(
      service.applyTreeSnapshot(
        {
          providerKey: 'box',
          nodes: [{ remoteId: 'remote-defaults', path: '/Docs/Untyped' }],
        },
        context,
      ),
    ).resolves.toMatchObject({ ok: true, providerKey: 'box', accepted: 1 });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO cloud_file_tree_nodes'),
      expect.arrayContaining([
        context.userId,
        'box',
        'remote-defaults',
        null,
        '/Docs/Untyped',
        'Untyped',
        'file',
      ]),
    );
    expect(database.query.mock.calls.some(([sql]) => String(sql).includes("SET availability = 'missing'"))).toBe(false);
  });

  it('creates upload sessions with computed expected chunks and audit logging', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(
      service.createUploadSession(
        { providerKey: 'server_storage', fileName: 'report.txt', totalBytes: 10, chunkSize: 4, objectKey: 'object-1' },
        context,
      ),
    ).resolves.toEqual({
      uploadSession: {
        sessionId: 'session-1',
        resumeToken: 'resume-1',
        providerKey: 'server_storage',
        objectKey: 'object-1',
        chunkSize: 4,
        expectedChunks: 3,
        status: 'open',
      },
    });
    expect(database.transaction).toHaveBeenCalledOnce();
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_transfer_sessions'),
      expect.arrayContaining([context.userId, 'server_storage', 'report.txt', null, null, 'object-1', 10, 4, 3]),
    );
  });

  it('uses transfer session defaults and ignores chunks for completed uploads', async () => {
    const defaultChunkSize = 5 * 1024 * 1024;
    const uploadDb = createDatabase({
      insertedSessions: [
        {
          sessionId: 'upload-default',
          resumeToken: 'resume-upload',
          providerKey: 'server_storage',
          objectKey: 'generated-object',
          chunkSize: defaultChunkSize,
          expectedChunks: 0,
          status: 'open',
        },
      ],
    });
    const upload = createService(uploadDb);

    await expect(upload.service.createUploadSession({}, context)).resolves.toEqual({
      uploadSession: {
        sessionId: 'upload-default',
        resumeToken: 'resume-upload',
        providerKey: 'server_storage',
        objectKey: 'generated-object',
        chunkSize: defaultChunkSize,
        expectedChunks: 0,
        status: 'open',
      },
    });
    expect(uploadDb.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_transfer_sessions'),
      [
        context.userId,
        'server_storage',
        'unnamed',
        null,
        null,
        expect.any(String),
        0,
        defaultChunkSize,
        0,
        null,
        '{}',
      ],
    );

    const downloadDb = createDatabase({
      insertedSessions: [
        {
          sessionId: 'download-default',
          resumeToken: 'resume-download',
          status: 'open',
          chunkSize: defaultChunkSize,
          totalBytes: 0,
          expectedChunks: 0,
          checksum: null,
          storageObjectId: null,
        },
      ],
    });
    const download = createService(downloadDb);
    await expect(download.service.createDownloadSession({}, context)).resolves.toEqual({
      downloadSession: {
        sessionId: 'download-default',
        resumeToken: 'resume-download',
        status: 'open',
        chunkSize: defaultChunkSize,
        totalBytes: 0,
        expectedChunks: 0,
        checksum: null,
        storageObjectId: null,
      },
    });
    expect(downloadDb.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_transfer_sessions'),
      [
        context.userId,
        'server_storage',
        'download',
        null,
        null,
        '',
        null,
        0,
        defaultChunkSize,
        0,
        null,
        '{}',
      ],
    );

    const completedDb = createDatabase({ sessions: [{ ...session, status: 'completed' }] });
    const completed = createService(completedDb);
    const payload = Buffer.from('late-chunk').toString('base64');
    await expect(completed.service.uploadChunk('session-1', '0', { payloadBase64: payload }, context))
      .resolves.toEqual({ ok: false, session: null });
    expect(completedDb.query.mock.calls.some(([sql]) => String(sql).includes('INSERT INTO file_transfer_chunks'))).toBe(false);
  });

  it('rejects invalid upload chunks before opening a transaction', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(service.uploadChunk('session-1', '-1', {}, context)).resolves.toEqual({
      ok: false,
      reason: 'chunkIndex and payloadBase64 are required',
    });
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('stores valid upload chunks and reports missing upload sessions', async () => {
    const database = createDatabase({ sessions: [session] });
    const { service } = createService(database);
    const payload = Buffer.from('chunk-data').toString('base64');

    await expect(
      service.uploadChunk('session-1', '1', { payloadBase64: payload, startByte: '5' }, context),
    ).resolves.toEqual({
      ok: true,
      session: {
        sessionId: 'session-1',
        providerKey: 'server_storage',
        direction: 'upload',
        fileName: 'report.txt',
        storageObjectId: null,
        totalBytes: 12,
        chunkSize: 4,
        expectedChunks: 4,
        receivedChunks: 2,
        receivedBytes: 8,
        status: 'open',
        checksum: null,
      },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_transfer_chunks'),
      [context.userId, 'session-1', 1, 5, 14, 10, expect.any(String), payload],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE file_transfer_sessions s'),
      [context.userId, 'session-1'],
    );

    await expect(createService(createDatabase({ sessions: [] })).service.uploadChunk('missing', '0', { payloadBase64: payload }, context))
      .resolves.toEqual({ ok: false, session: null });
    await expect(createService(createDatabase({ sessions: [] })).service.missingUploadChunks('missing', context))
      .resolves.toEqual({ ok: false, reason: 'session_not_found' });
  });

  it('reports missing upload chunks from received chunk indexes', async () => {
    const database = createDatabase({
      sessions: [session],
      chunks: [{ chunk_index: 1 }, { chunk_index: 3 }],
    });
    const { service } = createService(database);

    await expect(service.missingUploadChunks('session-1', context)).resolves.toEqual({
      ok: true,
      session: {
        sessionId: 'session-1',
        providerKey: 'server_storage',
        direction: 'upload',
        fileName: 'report.txt',
        storageObjectId: null,
        totalBytes: 12,
        chunkSize: 4,
        expectedChunks: 4,
        receivedChunks: 2,
        receivedBytes: 8,
        status: 'open',
        checksum: null,
      },
      missingChunks: [0, 2],
      receivedChunks: 2,
      expectedChunks: 4,
    });
  });

  it('stops upload completion when chunks are missing', async () => {
    const database = createDatabase({ sessions: [session] });
    const { service, objectStorage } = createService(database);

    await expect(service.completeUploadSession('session-1', context)).resolves.toEqual({
      ok: false,
      reason: 'missing_chunks',
      session: {
        sessionId: 'session-1',
        providerKey: 'server_storage',
        direction: 'upload',
        fileName: 'report.txt',
        storageObjectId: null,
        totalBytes: 12,
        chunkSize: 4,
        expectedChunks: 4,
        receivedChunks: 2,
        receivedBytes: 8,
        status: 'open',
        checksum: null,
      },
    });
    expect(objectStorage.writeObjectFromChunks).not.toHaveBeenCalled();
  });

  it('reports missing upload and download sessions before doing storage work', async () => {
    const { service, objectStorage } = createService(createDatabase({ sessions: [] }));

    await expect(service.completeUploadSession('missing-upload', context)).resolves.toEqual({
      ok: false,
      reason: 'session_not_found',
    });
    await expect(service.downloadRange('missing-download', {}, context)).resolves.toEqual({
      ok: false,
      reason: 'download_session_missing',
    });
    expect(objectStorage.writeObjectFromChunks).not.toHaveBeenCalled();
    expect(objectStorage.readRange).not.toHaveBeenCalled();
  });

  it('completes uploaded chunks into storage and a linked drive node', async () => {
    const completedSession = {
      ...session,
      received_chunks: 2,
      expected_chunks: 2,
      metadata: {
        rootId: 'root-1',
        parentId: 'parent-1',
        nodeName: 'report.md',
        relativePath: 'docs/report.md',
      },
    };
    const database = createDatabase({
      sessions: [completedSession],
      payloadChunks: [{ payload: Buffer.from('part-one') }, { payload: Buffer.from('part-two') }],
      storageObjects: [{ storageObjectId: 'storage-1', objectKey: 'object-1' }],
      insertedNodes: [{ id: 'node-1' }],
    });
    const { service, objectStorage } = createService(database);

    await expect(service.completeUploadSession('session-1', context)).resolves.toEqual({
      ok: true,
      storageObject: { storageObjectId: 'storage-1', objectKey: 'object-1' },
      fileNodeId: 'node-1',
      checksum: 'checksum',
    });

    expect(objectStorage.writeObjectFromChunks).toHaveBeenCalledWith(
      context.userId,
      'object-1',
      [Buffer.from('part-one'), Buffer.from('part-two')],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_storage_objects'),
      expect.arrayContaining([context.userId, 'server_storage', 'object-1', 'report.txt', 12, 'checksum', 4, 2]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_nodes'),
      expect.arrayContaining([
        context.userId,
        'server_storage:root-1:docs/report.md',
        'root-1',
        'parent-1',
        'report.md',
        'docs/report.md',
        'text/markdown',
        'md',
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_identity_mappings'),
      expect.arrayContaining([context.userId, 'node-1', 'object-1', 'storage-1', 'checksum', 12]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'files.upload.complete']),
    );
  });

  it('defaults completed upload file node metadata from parent and file name', async () => {
    const completedSession = {
      ...session,
      file_name: 'notes.md',
      object_key: null,
      received_chunks: 1,
      expected_chunks: 1,
      metadata: {
        rootId: 'root-1',
        parentId: 'parent-1',
      },
    };
    const database = createDatabase({
      sessions: [completedSession],
      parentNodes: [{ relative_path: 'docs' }],
      payloadChunks: [{ payload: Buffer.from('# Notes') }],
      storageObjects: [{ storageObjectId: 'storage-1', objectKey: 'generated-object' }],
      insertedNodes: [{ id: 'node-1' }],
    });
    const { service, objectStorage } = createService(database);

    await expect(service.completeUploadSession('session-1', context)).resolves.toEqual({
      ok: true,
      storageObject: { storageObjectId: 'storage-1', objectKey: 'generated-object' },
      fileNodeId: 'node-1',
      checksum: 'checksum',
    });
    expect(objectStorage.writeObjectFromChunks).toHaveBeenCalledWith(
      context.userId,
      expect.any(String),
      [Buffer.from('# Notes')],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_nodes'),
      expect.arrayContaining([
        context.userId,
        'server_storage:root-1:docs/notes.md',
        'root-1',
        'parent-1',
        'notes.md',
        'docs/notes.md',
        'text/markdown',
        'md',
        12,
        'checksum',
        'ready',
      ]),
    );
    const nodeParams = database.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO file_nodes'),
    )?.[1] as unknown[];
    expect(JSON.parse(String(nodeParams[11]))).toMatchObject({
      rootId: 'root-1',
      parentId: 'parent-1',
      storageObjectId: 'storage-1',
      uploadSessionId: 'session-1',
      providerKey: 'server_storage',
    });
  });

  it('completes a root upload with fallback file node metadata and no node linkage when id is absent', async () => {
    const completedSession = {
      ...session,
      file_name: 'README',
      received_chunks: 1,
      expected_chunks: 1,
      metadata: {
        rootId: 'root-1',
      },
    };
    const database = createDatabase({
      sessions: [completedSession],
      payloadChunks: [{ payload: Buffer.from('plain bytes') }],
      storageObjects: [{ storageObjectId: 'storage-1', objectKey: 'object-1' }],
      insertedNodes: [{ id: null }],
    });
    const { service } = createService(database);

    await expect(service.completeUploadSession('session-1', context)).resolves.toEqual({
      ok: true,
      storageObject: { storageObjectId: 'storage-1', objectKey: 'object-1' },
      fileNodeId: null,
      checksum: 'checksum',
    });
    expect(database.query.mock.calls.some(([sql]) => String(sql).includes('SELECT relative_path'))).toBe(false);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_nodes'),
      expect.arrayContaining([
        context.userId,
        'server_storage:root-1:README',
        'root-1',
        null,
        'README',
        'README',
        'application/octet-stream',
        null,
        12,
        'checksum',
        'external',
      ]),
    );
    expect(database.query.mock.calls.some(([sql]) => String(sql).includes('INSERT INTO file_identity_mappings'))).toBe(false);
    expect(database.query.mock.calls.some(([sql]) => String(sql).includes('SET metadata = metadata ||'))).toBe(false);
  });

  it('detects checksum mismatches before storing uploaded chunks', async () => {
    const database = createDatabase({
      sessions: [{ ...session, received_chunks: 1, expected_chunks: 1, checksum: 'expected-checksum' }],
      payloadChunks: [{ payload: Buffer.from('different') }],
    });
    const { service, objectStorage } = createService(database);

    await expect(service.completeUploadSession('session-1', context)).resolves.toMatchObject({
      ok: false,
      reason: 'checksum_mismatch',
      actualChecksum: expect.any(String),
    });

    expect(objectStorage.writeObjectFromChunks).not.toHaveBeenCalled();
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'failed'"),
      expect.arrayContaining([context.userId, 'session-1', expect.stringContaining('checksum mismatch')]),
    );
  });

  it('creates download sessions from storage metadata and reads object-storage ranges', async () => {
    const database = createDatabase({
      sessions: [
        {
          ...session,
          id: 'download-1',
          direction: 'download',
          storage_object_id: 'storage-1',
          chunk_size: 4,
        },
      ],
      storageLookup: [
        {
          provider_key: 'server_storage',
          object_key: 'object-1',
          display_name: 'report.md',
          size_bytes: '12',
          chunk_size: 4,
          checksum: 'checksum',
          metadata: { storagePath: 'object-1' },
        },
      ],
      insertedSessions: [
        {
          sessionId: 'download-1',
          resumeToken: 'resume-download',
          status: 'open',
          chunkSize: 4,
          totalBytes: 12,
          expectedChunks: 3,
          checksum: 'checksum',
          storageObjectId: 'storage-1',
        },
      ],
    });
    const { service, objectStorage } = createService(database);

    await expect(
      service.createDownloadSession({ storageObjectId: 'storage-1', metadata: { target: 'mobile' } }, context),
    ).resolves.toEqual({
      downloadSession: {
        sessionId: 'download-1',
        resumeToken: 'resume-download',
        status: 'open',
        chunkSize: 4,
        totalBytes: 12,
        expectedChunks: 3,
        checksum: 'checksum',
        storageObjectId: 'storage-1',
      },
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_transfer_sessions'),
      expect.arrayContaining([context.userId, 'server_storage', 'report.md', null, null, 'object-1', 'storage-1', 12, 4, 3, 'checksum']),
    );

    database.query.mockClear();
    await expect(
      service.downloadRange(
        'download-1',
        { start: '2', end: '6' },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      sessionId: 'download-1',
      range: { start: 2, end: 12 },
      note: 'local filesystem object storage range',
      chunks: [
        {
          chunkIndex: 0,
          startByte: 2,
          endByte: 12,
          sizeBytes: 11,
          payloadBase64: Buffer.from('range-bytes').toString('base64'),
        },
      ],
    });
    expect(objectStorage.readRange).toHaveBeenCalledWith('object-1', 2, 6);
  });

  it('serves shared server path download ranges and handles missing sources', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'flowplan-files-'));
    const filePath = join(tempDir, 'shared.txt');
    await writeFile(filePath, 'abcdef');
    try {
      const database = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            chunk_size: 3,
            metadata: {
              rootId: 'root-1',
              sourcePath: filePath,
            },
          },
        ],
        rootLookup: [{ rootUri: tempDir }],
      });
      const { service } = createService(database);

      await expect(
        service.downloadRange('download-1', { start: '1', end: '3' }, context),
      ).resolves.toMatchObject({
        ok: true,
        sessionId: 'download-1',
        range: { start: 1, end: 3 },
        note: 'shared server folder file range',
        chunks: [
          {
            chunkIndex: 0,
            startByte: 1,
            endByte: 3,
            sizeBytes: 3,
            payloadBase64: Buffer.from('bcd').toString('base64'),
          },
        ],
      });

      const missingRoot = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            metadata: { rootId: 'root-1', sourcePath: filePath },
          },
        ],
        rootLookup: [],
      });
      await expect(createService(missingRoot).service.downloadRange('download-1', {}, context)).resolves.toEqual({
        ok: false,
        reason: 'download_source_missing',
      });

      const missingRootId = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            metadata: { sourcePath: filePath },
          },
        ],
      });
      await expect(createService(missingRootId).service.downloadRange('download-1', {}, context)).resolves.toEqual({
        ok: false,
        reason: 'download_source_missing',
      });

      const missingSourcePath = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            metadata: { rootId: 'root-1' },
          },
        ],
      });
      await expect(createService(missingSourcePath).service.downloadRange('download-1', {}, context)).resolves.toEqual({
        ok: false,
        reason: 'download_source_missing',
      });

      const outsideRoot = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            metadata: { rootId: 'root-1', sourcePath: filePath },
          },
        ],
        rootLookup: [{ rootUri: join(tempDir, 'other-root') }],
      });
      await expect(createService(outsideRoot).service.downloadRange('download-1', {}, context)).resolves.toEqual({
        ok: false,
        reason: 'download_source_missing',
      });
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  });

  it('handles shared path read failures, empty ranges, and database chunk fallback downloads', async () => {
    const tempDir = await mkdtemp(join(tmpdir(), 'flowplan-files-'));
    const filePath = join(tempDir, 'shared.txt');
    await writeFile(filePath, 'abc');
    try {
      const emptyRangeDb = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            chunk_size: 3,
            metadata: { rootId: 'root-1', sourcePath: filePath },
          },
        ],
        rootLookup: [{ rootUri: tempDir }],
      });
      await expect(emptyRangeDb && createService(emptyRangeDb).service.downloadRange('download-1', { start: '9', end: '12' }, context))
        .resolves.toMatchObject({
          ok: true,
          range: { start: 9, end: 8 },
          chunks: [{ sizeBytes: 0, payloadBase64: '' }],
        });

      const failedReadDb = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: null,
            metadata: { rootId: 'root-1', sourcePath: join(tempDir, 'missing.txt') },
          },
        ],
        rootLookup: [{ rootUri: tempDir }],
      });
      await expect(createService(failedReadDb).service.downloadRange('download-1', {}, context))
        .resolves.toMatchObject({ ok: false, reason: 'shared_source_read_failed' });

      const chunkDb = createDatabase({
        sessions: [
          {
            ...session,
            direction: 'download',
            storage_object_id: 'storage-1',
            chunk_size: 4,
          },
        ],
        storageLookup: [{ metadata: {} }],
        chunks: [{ chunkIndex: 0, startByte: 0, endByte: 3, payloadBase64: 'YQ==' }],
      });
      await expect(createService(chunkDb).service.downloadRange('download-1', { start: '0', end: '3' }, context))
        .resolves.toEqual({
          ok: true,
          sessionId: 'download-1',
          range: { start: 0, end: 3 },
          chunks: [{ chunkIndex: 0, startByte: 0, endByte: 3, payloadBase64: 'YQ==' }],
          note: 'P10 returns resumable chunk payloads as base64 JSON; production storage can map this to HTTP Range.',
        });
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  });

  it('downloads registered storage objects and records the range operation', async () => {
    const database = createDatabase({
      storageLookup: [
        {
          id: 'storage-1',
          displayName: 'report.md',
          sizeBytes: '128',
          checksum: 'checksum',
          metadata: { storagePath: 'object-1' },
        },
      ],
    });
    const { service, objectStorage } = createService(database);

    await expect(service.downloadStorageObject('storage-1', { start: '2', limit: '5' }, context)).resolves.toEqual({
      ok: true,
      storageObjectId: 'storage-1',
      fileName: 'report.md',
      totalBytes: 128,
      checksum: 'checksum',
      range: { start: 2, end: 12 },
      sizeBytes: 11,
      payloadBase64: Buffer.from('range-bytes').toString('base64'),
    });

    expect(objectStorage.readRange).toHaveBeenCalledWith('object-1', 2, 6);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_operation_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'file.storage.download_range']),
    );

    await expect(createService(createDatabase({ storageLookup: [] })).service.downloadStorageObject('missing', {}, context))
      .resolves.toEqual({ ok: false, reason: 'storage_object_not_found' });
    await expect(createService(createDatabase({ storageLookup: [{ id: 'storage-2', metadata: {} }] })).service.downloadStorageObject('storage-2', {}, context))
      .resolves.toEqual({ ok: false, reason: 'storage_path_missing' });
  });

  it('lists transfer sessions and calculates transfer progress metrics', async () => {
    const progressCreated = new Date('2026-06-08T09:00:00.000Z');
    const progressUpdated = new Date('2026-06-08T09:02:00.000Z');
    const database = createDatabase({
      sessions: [
        {
          sessionId: 'session-1',
          providerKey: 'server_storage',
          direction: 'upload',
          fileName: 'report.txt',
          storageObjectId: 'storage-1',
          totalBytes: '100',
          chunkSize: 25,
          expectedChunks: 4,
          receivedChunks: 2,
          receivedBytes: '50',
          checksum: 'checksum',
          status: 'open',
          resumeToken: 'resume',
          errorMessage: null,
          createdAt: progressCreated,
          updatedAt: progressUpdated,
          firstChunkAt: progressCreated,
          lastChunkAt: progressUpdated,
        },
      ],
    });
    const { service } = createService(database);

    await expect(service.transfers({ direction: ' upload ', status: ' open ', limit: '1', offset: '2' }, context))
      .resolves.toEqual({
        limit: 1,
        offset: 2,
        hasMore: true,
        transfers: [
          {
            sessionId: 'session-1',
            providerKey: 'server_storage',
            direction: 'upload',
            fileName: 'report.txt',
            storageObjectId: 'storage-1',
            totalBytes: '100',
            chunkSize: 25,
            expectedChunks: 4,
            receivedChunks: 2,
            receivedBytes: '50',
            checksum: 'checksum',
            status: 'open',
            resumeToken: 'resume',
            errorMessage: null,
            createdAt: progressCreated,
            updatedAt: progressUpdated,
            firstChunkAt: progressCreated,
            lastChunkAt: progressUpdated,
          },
        ],
      });

    await expect(service.transferProgress('session-1', context)).resolves.toMatchObject({
      ok: true,
      session: {
        sessionId: 'session-1',
        totalBytes: 100,
        receivedBytes: 50,
        progress: 0.5,
        percent: 50,
        bytesPerSecond: expect.closeTo(0.416, 2),
      },
    });
    await expect(createService(createDatabase({ sessions: [] })).service.transferProgress('missing', context))
      .resolves.toEqual({ ok: false, reason: 'transfer_not_found', sessionId: 'missing' });

    const zeroCreated = new Date('2026-06-08T10:00:00.000Z');
    const zeroUpdated = new Date('2026-06-08T10:00:30.000Z');
    const zeroDb = createDatabase({
      sessions: [
        {
          sessionId: 'session-zero',
          providerKey: 'server_storage',
          direction: 'upload',
          fileName: 'empty.bin',
          storageObjectId: null,
          totalBytes: '0',
          chunkSize: 25,
          expectedChunks: 0,
          receivedChunks: 0,
          receivedBytes: '0',
          checksum: null,
          status: 'open',
          resumeToken: 'resume-zero',
          errorMessage: null,
          createdAt: zeroCreated,
          updatedAt: zeroUpdated,
          firstChunkAt: null,
          lastChunkAt: null,
        },
      ],
    });
    await expect(createService(zeroDb).service.transferProgress('session-zero', context)).resolves.toMatchObject({
      ok: true,
      session: {
        sessionId: 'session-zero',
        totalBytes: 0,
        receivedBytes: 0,
        progress: 0,
        percent: 0,
        bytesPerSecond: 0,
      },
    });
  });

  it('lists, creates, and deletes server drive roots safely', async () => {
    const rootRow = {
      id: 'root-1',
      rootUid: 'server-root:C:\\Data',
      name: 'Data',
      rootUri: 'C:\\Data',
      rootDisplayPath: 'C:\\Data',
      nodeCount: '3',
      fileCount: '2',
      folderCount: '1',
      totalBytes: '1000',
      storageObjectCount: '2',
      storageTotalBytes: '800',
    };
    const database = createDatabase({
      rootLookup: [rootRow],
      roots: [{ id: 'root-2', rootUid: 'server-root:C:\\New', name: 'New', rootUri: 'C:\\New', scanStatus: 'idle' }],
    });
    const { service } = createService(database);

    await expect(service.roots({ q: 'Data' }, context)).resolves.toEqual({ roots: [rootRow] });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM file_roots r'), [
      context.userId,
      '%Data%',
    ]);

    await expect(
      service.upsertRoot(
        {
          providerType: 'server_storage',
          rootUri: 'C:\\New',
          name: 'New',
          rootDisplayPath: 'Drive New',
          isManaged: true,
          syncPolicy: 'full',
          metadata: { owner: 'ops' },
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      root: { id: 'root-2', rootUid: 'server-root:C:\\New', name: 'New', rootUri: 'C:\\New', scanStatus: 'idle' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_roots'),
      [
        context.userId,
        'server-root:C:\\New',
        'New',
        'server_storage',
        'C:\\New',
        'Drive New',
        context.deviceId,
        true,
        'full',
        '{"owner":"ops"}',
      ],
    );

    await expect(service.deleteDriveRoot('root-1', context)).resolves.toEqual({
      ok: true,
      deletedRoot: {
        id: 'root-1',
        rootUid: 'server-root:C:\\Data',
        name: 'Data',
        rootUri: 'C:\\Data',
        rootDisplayPath: 'C:\\Data',
      },
      deletedCounts: { nodes: 3, files: 2, folders: 1, totalBytes: 1000 },
      storageObjectsRetained: true,
      physicalFilesDeleted: false,
    });
    await expect(createService(createDatabase({ rootLookup: [] })).service.deleteDriveRoot('missing', context))
      .resolves.toEqual({ ok: false, reason: 'root_not_found' });
  });

  it('creates server roots from localPath with default root fields', async () => {
    const database = createDatabase({
      roots: [{ id: 'root-default', rootUid: 'server-root:C:\\Default', name: 'Default', rootUri: 'C:\\Default', scanStatus: 'idle' }],
    });
    const { service } = createService(database);

    await expect(
      service.upsertRoot({ localPath: ' C:\\Default ', metadata: { source: 'localPath' } }, context),
    ).resolves.toEqual({
      ok: true,
      root: { id: 'root-default', rootUid: 'server-root:C:\\Default', name: 'Default', rootUri: 'C:\\Default', scanStatus: 'idle' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_roots'),
      [
        context.userId,
        'server-root:C:\\Default',
        'Default',
        'server_storage',
        'C:\\Default',
        'C:\\Default',
        context.deviceId,
        false,
        'metadata_only',
        '{"source":"localPath"}',
      ],
    );
  });

  it('lists canonical file nodes and drive roots with normalized filters', async () => {
    const node = {
      id: 'node-1',
      nodeUid: 'node-uid',
      rootId: 'root-1',
      parentId: 'parent-1',
      nodeType: 'file',
      name: 'report.md',
      relativePath: 'docs/report.md',
    };
    const root = { id: 'root-1', name: 'Workspace' };
    const database = createDatabase({ nodes: [node], rootLookup: [root] });
    const { service } = createService(database);

    await expect(service.fileNodes({ rootId: 'root-1', parentId: 'parent-1', q: 'report', limit: '1', offset: '3' }, context))
      .resolves.toEqual({
        limit: 1,
        offset: 3,
        hasMore: true,
        nodes: [node],
      });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM file_nodes n'),
      [context.userId, 'root-1', 'parent-1', '%report%', 1, 3],
    );

    await expect(service.driveRoots({ q: 'Work' }, context)).resolves.toEqual({
      roots: [root],
      model: 'logical_cloud_drive',
      canonicalTree: 'file_nodes',
    });
  });

  it('lists and loads drive nodes with storage, device and identity summaries', async () => {
    const database = createDatabase({ nodes: [driveNodeRow()] });
    const { service } = createService(database);

    await expect(
      service.driveNodes({ rootId: 'root-1', q: 'report', limit: '1', offset: '2' }, context),
    ).resolves.toMatchObject({
      limit: 1,
      offset: 2,
      hasMore: true,
      nodes: [
        {
          id: 'node-1',
          name: 'report.md',
          displayName: 'report.md',
          sizeBytes: 128,
          availability: 'local',
          storage: {
            storageObjectId: 'storage-1',
            providerKey: 'server_storage',
            status: 'available',
            checksum: 'hash-1',
            sourceType: 'storage_object',
          },
          currentDevice: {
            locationId: 'location-1',
            localPath: 'C:/workspace/report.md',
            availability: 'available',
          },
          identity: {
            hashSha256: 'hash-1',
            storageChecksum: 'hash-1',
            providerFileId: 'provider-file-1',
            contentHash: 'hash-1',
          },
        },
      ],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM file_nodes n'),
      [context.userId, 'root-1', null, '%report%', 1, 2, context.deviceId],
    );

    await expect(service.driveNode('node-1', context)).resolves.toMatchObject({
      node: {
        id: 'node-1',
        root: { id: 'root-1', name: 'Workspace' },
        knownDeviceLocationCount: 1,
      },
    });
  });

  it('maps drive node availability and default storage/device identity fields', async () => {
    const database = createDatabase({
      nodes: [
        driveNodeRow({
          id: 'missing-node',
          isMissing: true,
          localPath: null,
          storageObjectId: null,
          deviceLocalPath: null,
          deviceAvailability: null,
        }),
        driveNodeRow({
          id: 'shared-node',
          localPath: 'C:/server/docs/report.md',
          storageObjectId: null,
          storageProviderKey: null,
          storageStatus: null,
          storageChecksum: null,
          deviceLocalPath: null,
          deviceAvailability: 'cached',
        }),
        driveNodeRow({
          id: 'metadata-node',
          localPath: null,
          storageObjectId: null,
          storageChecksum: null,
          deviceLocalPath: null,
          deviceAvailability: null,
          knownDeviceLocationCount: null,
          hashSha256: null,
          metadata: { sha256: 'metadata-hash' },
        }),
        driveNodeRow({
          id: 'default-device-node',
          deviceLocalPath: 'C:/workspace/default.md',
          deviceAvailability: null,
        }),
      ],
    });
    const { service } = createService(database);

    await expect(service.driveNodes({}, context)).resolves.toMatchObject({
      nodes: [
        {
          id: 'missing-node',
          availability: 'missing',
          storage: null,
          currentDevice: null,
        },
        {
          id: 'shared-node',
          availability: 'remote_only',
          storage: {
            storageObjectId: null,
            providerKey: 'server_shared_folder',
            status: 'available',
            sourceType: 'shared_server_path',
          },
          currentDevice: {
            localPath: null,
            availability: 'cached',
          },
        },
        {
          id: 'metadata-node',
          availability: 'metadata_only',
          storage: null,
          currentDevice: null,
          knownDeviceLocationCount: 0,
          identity: {
            contentHash: 'metadata-hash',
          },
        },
        {
          id: 'default-device-node',
          currentDevice: {
            localPath: 'C:/workspace/default.md',
            availability: 'available',
          },
        },
      ],
    });
  });

  it('plans drive node opening based on verified local identity or remote sources', async () => {
    const openLocalDb = createDatabase({ nodes: [driveNodeRow()] });
    await expect(
      createService(openLocalDb).service.driveOpenPlan(
        'node-1',
        { localIdentity: { localPath: 'C:/workspace/report.md', hashSha256: 'hash-1' } },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      action: 'open_local',
      requiresConfirmation: false,
      identity: { matched: true, confidence: 'hash' },
    });

    const cachedLocalDb = createDatabase({
      nodes: [driveNodeRow({ deviceAvailability: 'cached' })],
    });
    await expect(
      createService(cachedLocalDb).service.driveOpenPlan(
        'node-1',
        { localIdentity: { localPath: 'C:/workspace/report.md', hashSha256: 'hash-1' } },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      action: 'open_local',
      requiresConfirmation: false,
    });

    const conflictDb = createDatabase({ nodes: [driveNodeRow()] });
    await expect(
      createService(conflictDb).service.driveOpenPlan(
        'node-1',
        { localIdentity: { localPath: 'C:/workspace/report.md', hashSha256: 'other-hash' } },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      action: 'conflict_or_download_required',
      requiresConfirmation: true,
      identity: { matched: false, confidence: 'hash' },
    });

    const remoteDb = createDatabase({
      nodes: [
        driveNodeRow({
          deviceLocationId: null,
          deviceLocalPath: null,
          deviceAvailability: null,
        }),
      ],
    });
    await expect(
      createService(remoteDb).service.driveOpenPlan('node-1', { localIdentity: {} }, context),
    ).resolves.toMatchObject({
      ok: true,
      action: 'download_then_open',
      requiresConfirmation: true,
    });

    await expect(
      createService(createDatabase({ nodes: [] })).service.driveOpenPlan('missing', {}, context),
    ).resolves.toEqual({ ok: false, reason: 'node_not_found' });
  });

  it('upserts drive device locations and relinks local files to nodes', async () => {
    const database = createDatabase({
      updatedNodes: [{ id: 'node-1', nodeUid: 'node-uid', name: 'report.md' }],
    });
    const { service } = createService(database);

    await expect(
      service.upsertDriveDeviceLocation(
        'node-1',
        { localPath: ' C:/workspace/report.md ', availability: ' cached ', metadata: { source: 'manual' } },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      location: {
        id: 'location-1',
        nodeId: 'node-1',
        localPath: 'C:/workspace/report.md',
        availability: 'cached',
      },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_node_device_locations'),
      [context.userId, 'node-1', context.deviceId, 'C:/workspace/report.md', 'cached', '{"source":"manual"}'],
    );

    const defaultLocationDb = createDatabase();
    await expect(
      createService(defaultLocationDb).service.upsertDriveDeviceLocation(
        'node-1',
        { localPath: 'C:/workspace/default.md' },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      location: {
        id: 'location-1',
        nodeId: 'node-1',
        localPath: 'C:/workspace/default.md',
        availability: 'available',
      },
    });
    expect(defaultLocationDb.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_node_device_locations'),
      [context.userId, 'node-1', context.deviceId, 'C:/workspace/default.md', 'available', '{}'],
    );

    await expect(service.relinkDriveNode('node-1', { localPath: '   ' }, context)).resolves.toEqual({
      ok: false,
      reason: 'localPath_required',
    });

    await expect(
      service.relinkDriveNode(
        'node-1',
        { localPath: 'C:/workspace/report.md', reason: 'Moved', identity: { hashSha256: 'hash-1' } },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      node: { id: 'node-1', nodeUid: 'node-uid', name: 'report.md' },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE file_nodes'),
      expect.arrayContaining([context.userId, 'node-1', 'C:/workspace/report.md']),
    );
    expect(database.query.mock.calls.some(([, params]) =>
      Array.isArray(params) &&
      params.includes(context.userId) &&
      params.includes(context.deviceId) &&
      params.includes('file.drive.node.relink'),
    )).toBe(true);

    const missingRelinkDb = createDatabase({ updatedNodes: [] });
    await expect(
      createService(missingRelinkDb).service.relinkDriveNode(
        'missing-node',
        { localPath: 'C:/workspace/missing.md' },
        context,
      ),
    ).resolves.toEqual({ ok: false, node: null });
  });

  it('logs node operations and lists context links and recommendations', async () => {
    const database = createDatabase({
      links: [{ id: 'link-1', entityType: 'task', entityId: 'task-1', nodeName: 'report.md' }],
      recommendations: [{ id: 'rec-1', entityType: 'task', entityId: 'task-1', score: 0.9 }],
    });
    const { service } = createService(database);

    await expect(
      service.logNodeOperation(
        'node-1',
        {
          operation: ' file.preview ',
          sourcePath: ' C:/source.md ',
          targetPath: ' C:/target.md ',
          status: ' failed ',
          errorMessage: ' locked ',
          metadata: { viewer: 'markdown' },
        },
        context,
      ),
    ).resolves.toEqual({ ok: true });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_operation_logs'),
      [
        context.userId,
        context.deviceId,
        'file.preview',
        'node-1',
        'C:/source.md',
        'C:/target.md',
        'failed',
        'locked',
        '{"sourcePath":"C:/source.md","targetPath":"C:/target.md","status":"failed","errorMessage":"locked","metadata":{"viewer":"markdown"}}',
      ],
    );

    await expect(service.contextLinks({ entityType: ' task ', entityId: ' task-1 ' }, context)).resolves.toEqual({
      links: [{ id: 'link-1', entityType: 'task', entityId: 'task-1', nodeName: 'report.md' }],
    });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM file_context_links l'), [
      context.userId,
      'task',
      'task-1',
    ]);

    await expect(service.recommendations({ entityType: ' task ', entityId: ' task-1 ' }, context)).resolves.toEqual({
      recommendations: [{ id: 'rec-1', entityType: 'task', entityId: 'task-1', score: 0.9 }],
    });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM file_recommendations r'), [
      context.userId,
      'task',
      'task-1',
    ]);
  });

  it('uses operation defaults and returns empty link and recommendation lists without filters', async () => {
    const database = createDatabase({ links: [], recommendations: [] });
    const { service } = createService(database);

    await expect(service.logNodeOperation('node-1', {}, context)).resolves.toEqual({ ok: true });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_operation_logs'),
      [
        context.userId,
        context.deviceId,
        'file.open',
        'node-1',
        null,
        null,
        'success',
        null,
        '{"sourcePath":null,"targetPath":null,"status":"success","errorMessage":null,"metadata":{}}',
      ],
    );

    await expect(service.contextLinks({}, context)).resolves.toEqual({ links: [] });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM file_context_links l'), [
      context.userId,
      null,
      null,
    ]);
    await expect(service.recommendations({}, context)).resolves.toEqual({ recommendations: [] });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM file_recommendations r'), [
      context.userId,
      null,
      null,
    ]);
  });

  it('compares provider identity and size/mtime when planning drive opens', async () => {
    await expect(
      createService(createDatabase({
        nodes: [
          driveNodeRow({
            hashSha256: null,
            storageChecksum: null,
            metadata: {},
          }),
        ],
      })).service.driveOpenPlan(
        'node-1',
        { localIdentity: { localPath: 'C:/workspace/report.md', providerFileId: 'provider-file-1' } },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      action: 'open_local',
      identity: { matched: true, confidence: 'provider_id' },
    });

    await expect(
      createService(createDatabase({
        nodes: [
          driveNodeRow({
            hashSha256: null,
            storageChecksum: null,
            providerFileId: null,
            metadata: {},
            mtime: '2026-06-08T00:00:00.000Z',
          }),
        ],
      })).service.driveOpenPlan(
        'node-1',
        { localIdentity: { localPath: 'C:/workspace/report.md', sizeBytes: 128, modifiedAt: '2026-06-08T00:00:00.000Z' } },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      action: 'conflict_or_download_required',
      identity: { matched: true, confidence: 'size_mtime' },
    });
  });

  it('returns identity mismatch and unavailable reasons for drive open plans', async () => {
    await expect(
      createService(createDatabase({
        nodes: [
          driveNodeRow({
            hashSha256: null,
            storageChecksum: null,
            metadata: {},
          }),
        ],
      })).service.driveOpenPlan(
        'node-1',
        { localIdentity: { localPath: 'C:/workspace/report.md', providerFileId: 'other-provider-file' } },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      action: 'conflict_or_download_required',
      identity: {
        matched: false,
        confidence: 'provider_id',
        reason: 'provider file id differs',
      },
    });

    await expect(
      createService(createDatabase({
        nodes: [
          driveNodeRow({
            hashSha256: null,
            storageChecksum: null,
            providerFileId: null,
            sizeBytes: '0',
            localPath: null,
            storageObjectId: null,
            deviceLocationId: null,
            deviceLocalPath: null,
            deviceAvailability: null,
            metadata: {},
          }),
        ],
      })).service.driveOpenPlan('node-1', { localIdentity: {} }, context),
    ).resolves.toMatchObject({
      ok: true,
      action: 'needs_upload_or_relink',
      identity: {
        matched: false,
        confidence: 'none',
        reason: 'no comparable identity fields',
      },
    });
  });

  it('creates drive download requests only for downloadable file nodes', async () => {
    const database = createDatabase({
      nodes: [driveNodeRow()],
      storageLookup: [
        {
          provider_key: 'server_storage',
          object_key: 'object-1',
          display_name: 'report.md',
          size_bytes: '128',
          chunk_size: 64,
          checksum: 'hash-1',
          metadata: { storagePath: 'object-1' },
        },
      ],
      insertedSessions: [
        {
          sessionId: 'download-1',
          resumeToken: 'resume-download',
          status: 'open',
          chunkSize: 64,
          totalBytes: 128,
          expectedChunks: 2,
          checksum: 'hash-1',
          storageObjectId: 'storage-1',
        },
      ],
    });
    const { service } = createService(database);

    await expect(
      service.createDriveDownloadRequest('node-1', { targetPath: 'C:/downloads/report.md' }, context),
    ).resolves.toMatchObject({
      ok: true,
      node: { id: 'node-1', name: 'report.md' },
      downloadSession: {
        sessionId: 'download-1',
        storageObjectId: 'storage-1',
      },
    });

    await expect(
      createService(createDatabase({ nodes: [] })).service.createDriveDownloadRequest('missing', {}, context),
    ).resolves.toEqual({ ok: false, reason: 'node_not_found' });
    await expect(
      createService(createDatabase({ nodes: [driveNodeRow({ nodeType: 'folder' })] })).service.createDriveDownloadRequest('folder', {}, context),
    ).resolves.toMatchObject({ ok: false, reason: 'node_is_not_file' });
    await expect(
      createService(createDatabase({
        nodes: [
          driveNodeRow({
            storageObjectId: null,
            localPath: null,
            storageChecksum: null,
            deviceLocalPath: null,
            deviceAvailability: null,
          }),
        ],
      })).service.createDriveDownloadRequest('node-1', {}, context),
    ).resolves.toMatchObject({ ok: false, reason: 'download_source_missing' });

    const sharedPathDb = createDatabase({
      nodes: [
        driveNodeRow({
          storageObjectId: null,
          storageChecksum: null,
          localPath: 'C:/server/docs/report.md',
          deviceLocalPath: null,
          deviceAvailability: null,
        }),
      ],
      insertedSessions: [
        {
          sessionId: 'shared-download',
          resumeToken: 'resume-shared',
          status: 'open',
          chunkSize: 64,
          totalBytes: 128,
          expectedChunks: 2,
          checksum: 'hash-1',
          storageObjectId: null,
        },
      ],
    });
    await expect(
      createService(sharedPathDb).service.createDriveDownloadRequest(
        'node-1',
        { targetPath: 'C:/downloads/shared.md' },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      downloadSession: {
        sessionId: 'shared-download',
        checksum: 'hash-1',
        storageObjectId: null,
      },
    });
    const sharedSessionParams = sharedPathDb.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO file_transfer_sessions'),
    )?.[1] as unknown[];
    expect(sharedSessionParams[10]).toBe('hash-1');
    expect(JSON.parse(String(sharedSessionParams[11]))).toMatchObject({
      nodeId: 'node-1',
      sourcePath: 'C:/server/docs/report.md',
      sourceType: 'shared_server_path',
      targetPath: 'C:/downloads/shared.md',
    });
  });

  it('normalizes server root URIs and maps common preview MIME types', async () => {
    const { service } = createService();
    const internals = service as unknown as {
      normalizeServerRootUri(path: string | null): string | null;
      guessMimeType(path: string): string | null;
    };

    expect(internals.normalizeServerRootUri(null)).toBeNull();
    expect(internals.normalizeServerRootUri('/srv/data/../data')).toBe('/srv/data');
    expect(internals.normalizeServerRootUri('C:\\Data\\..\\Data')).toBe('C:\\Data');
    expect(internals.normalizeServerRootUri('relative/path')).toBeNull();
    expect(internals.normalizeServerRootUri('/client/mobile/root')).toBe('/client/mobile/root');

    expect(internals.guessMimeType('note.txt')).toBe('text/plain');
    expect(internals.guessMimeType('data.json')).toBe('application/json');
    expect(internals.guessMimeType('sheet.csv')).toBe('text/csv');
    expect(internals.guessMimeType('config.yaml')).toBe('text/yaml');
    expect(internals.guessMimeType('config.yml')).toBe('text/yaml');
    expect(internals.guessMimeType('app.log')).toBe('text/plain');
    expect(internals.guessMimeType('image.png')).toBe('image/png');
    expect(internals.guessMimeType('photo.jpg')).toBe('image/jpeg');
    expect(internals.guessMimeType('photo.jpeg')).toBe('image/jpeg');
    expect(internals.guessMimeType('anim.gif')).toBe('image/gif');
    expect(internals.guessMimeType('bitmap.bmp')).toBe('image/bmp');
    expect(internals.guessMimeType('modern.webp')).toBe('image/webp');
    expect(internals.guessMimeType('paper.pdf')).toBe('application/pdf');
    expect(internals.guessMimeType('binary.bin')).toBeNull();
  });

  it('delegates file conflict endpoints to FileVersionService', async () => {
    const { service } = createService();

    await expect(service.conflicts(context)).resolves.toEqual({
      method: 'conflicts',
      args: [context],
    });
    await expect(service.createConflict({ fileUid: 'file-1', versionA: { etag: 'a' } }, context)).resolves.toEqual({
      method: 'createConflict',
      args: [{ fileUid: 'file-1', versionA: { etag: 'a' } }, context],
    });
    await expect(service.resolveConflict('conflict-1', { resolution: { chosen: 'server' } }, context)).resolves.toEqual({
      method: 'resolveConflict',
      args: ['conflict-1', { resolution: { chosen: 'server' } }, context],
    });
  });

  it('validates server drive roots before writing to the database', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(service.upsertRoot({ providerType: 'local', rootUri: 'C:\\Users\\me' }, context)).resolves.toMatchObject({
      ok: false,
      reason: 'client_local_root_not_allowed',
    });
    await expect(service.upsertRoot({ providerType: 'server_storage', rootUri: 'relative/path' }, context)).resolves.toMatchObject({
      ok: false,
      reason: 'absolute_server_root_required',
    });
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('links nodes to entities and validates required link fields', async () => {
    const database = createDatabase({ links: [{ id: 'link-1', linkUid: 'custom-link' }] });
    const { service } = createService(database);

    await expect(service.linkNodeToEntity({ nodeId: 'node-1', entityType: 'task' }, context)).resolves.toEqual({
      ok: false,
      error: 'nodeId, entityType and entityId are required',
    });
    await expect(
      service.linkNodeToEntity(
        { nodeId: 'node-1', entityType: 'task', entityId: 'task-1', linkUid: 'custom-link', confidence: 2 },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      link: { id: 'link-1', linkUid: 'custom-link' },
    });

    const defaultLinkDb = createDatabase({
      links: [{ id: 'link-default', linkUid: 'file-link:task:task-1:node-1' }],
    });
    await expect(
      createService(defaultLinkDb).service.linkNodeToEntity(
        { nodeId: 'node-1', entityType: 'task', entityId: 'task-1' },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      link: { id: 'link-default', linkUid: 'file-link:task:task-1:node-1' },
    });
    expect(defaultLinkDb.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_context_links'),
      [
        context.userId,
        'file-link:task:task-1:node-1',
        'task',
        'task-1',
        'node-1',
        'manual',
        1,
        null,
        'confirmed',
      ],
    );
  });

  it('reviews accepted recommendations by creating context links', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(service.reviewRecommendation('rec-1', { status: 'accepted' }, context)).resolves.toEqual({
      ok: true,
      recommendation: {
        id: 'rec-1',
        entityType: 'task',
        entityId: 'task-1',
        nodeId: 'node-1',
        status: 'accepted',
      },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_context_links'),
      [context.userId, 'file-rec:rec-1', 'task', 'task-1', 'node-1'],
    );
  });

  it('handles missing and non-accepted recommendation reviews without creating links', async () => {
    const missingDb = createDatabase({ reviewedRecommendations: [] });
    await expect(createService(missingDb).service.reviewRecommendation('missing-rec', {}, context))
      .resolves.toEqual({ ok: false, recommendation: null });
    expect(missingDb.query.mock.calls.some(([sql]) => String(sql).includes('INSERT INTO file_context_links'))).toBe(false);
    expect(missingDb.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO file_operation_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'file.recommendation.review', null]),
    );

    const dismissedDb = createDatabase({
      reviewedRecommendations: [
        {
          id: 'rec-2',
          entityType: 'task',
          entityId: 'task-2',
          nodeId: 'node-2',
          status: 'dismissed',
        },
      ],
    });
    await expect(createService(dismissedDb).service.reviewRecommendation('rec-2', { status: 'dismissed' }, context))
      .resolves.toEqual({
        ok: true,
        recommendation: {
          id: 'rec-2',
          entityType: 'task',
          entityId: 'task-2',
          nodeId: 'node-2',
          status: 'dismissed',
        },
      });
    expect(dismissedDb.query.mock.calls.some(([sql]) => String(sql).includes('INSERT INTO file_context_links'))).toBe(false);
  });

  it('delegates tree, transfer, storage, and version helper endpoints', async () => {
    const { service, fileTree, fileTransfer, fileVersion } = createService();

    await expect(service.versions('file-1', context)).resolves.toEqual({
      method: 'versions',
      args: ['file-1', context],
    });
    await expect(service.createVersionDownloadRequest('version-1', { targetPath: '/tmp' }, context)).resolves.toEqual({
      method: 'createVersionDownloadRequest',
      args: ['version-1', { targetPath: '/tmp' }, context],
    });
    await expect(service.storageObjects({ limit: '5' }, context)).resolves.toEqual({
      method: 'storageObjects',
      args: [{ limit: '5' }, context],
    });
    await expect(service.storageStatus()).resolves.toEqual({ ok: true });
    await expect(service.registerStorageObject({ localPath: '/tmp/a.txt' }, context)).resolves.toEqual({
      method: 'registerStorageObject',
      args: [{ localPath: '/tmp/a.txt' }, context],
    });
    await expect(service.createKopiaSnapshot({ fileId: 'file-1' }, context)).resolves.toEqual({
      method: 'createKopiaSnapshot',
      args: [{ fileId: 'file-1' }, context],
    });
    await expect(service.refreshKopiaVersions({ fileId: 'file-1' }, context)).resolves.toEqual({
      method: 'refreshKopiaVersions',
      args: [{ fileId: 'file-1' }, context],
    });
    await expect(service.downloadVersionCopy('version-1', { targetPath: '/tmp/copy' }, context)).resolves.toEqual({
      method: 'downloadVersionCopy',
      args: ['version-1', { targetPath: '/tmp/copy' }, context],
    });
    await expect(service.prepareVersionRestore('version-1', { mode: 'preview' }, context)).resolves.toEqual({
      method: 'prepareVersionRestore',
      args: ['version-1', { mode: 'preview' }, context],
    });
    await expect(service.applyNodeSnapshot({ rootId: 'root-1' }, context)).resolves.toEqual({
      method: 'applyNodeSnapshot',
      args: [{ rootId: 'root-1' }, context],
    });
    await expect(service.scanDriveRoot('root-1', { maxNodes: 1 }, context)).resolves.toEqual({
      method: 'scanDriveRoot',
      args: ['root-1', { maxNodes: 1 }, context],
    });
    await expect(service.upsertNetworkPresence({ localIp: '127.0.0.1' }, context)).resolves.toEqual({
      method: 'upsertNetworkPresence',
      args: [{ localIp: '127.0.0.1' }, context],
    });
    await expect(service.networkPresence(context)).resolves.toEqual({
      method: 'networkPresence',
      args: [context],
    });
    await expect(service.transferCandidates('session-1', context)).resolves.toEqual({
      method: 'transferCandidates',
      args: ['session-1', context],
    });
    await expect(service.upsertTransferCandidate('session-1', { protocol: 'lan' }, context)).resolves.toEqual({
      method: 'upsertTransferCandidate',
      args: ['session-1', { protocol: 'lan' }, context],
    });
    await expect(service.appendTransferEvent('session-1', { eventType: 'note' }, context)).resolves.toEqual({
      method: 'appendTransferEvent',
      args: ['session-1', { eventType: 'note' }, context],
    });
    expect(fileVersion.versions).toHaveBeenCalledOnce();
    expect(fileTransfer.storageObjects).toHaveBeenCalledOnce();
    expect(fileTree.applyNodeSnapshot).toHaveBeenCalledOnce();
  });
});
