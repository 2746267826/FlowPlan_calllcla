import { describe, expect, it, vi } from 'vitest';
import { FileTransferService } from './file-transfer.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

type Rows = Record<string, unknown>[];

interface DatabaseRows {
  storageObjects?: Rows;
  insertedStorage?: Rows;
  insertedPresence?: Rows;
  networkPresence?: Rows;
  transferCandidates?: Rows;
  insertedCandidate?: Rows;
}

function createDatabase(rows: DatabaseRows = {}) {
  const query = vi.fn(async (sql: string, params: unknown[] = []) => {
    if (sql.includes('FROM file_storage_objects')) {
      return { rows: rows.storageObjects ?? [] };
    }
    if (sql.includes('INSERT INTO file_storage_objects')) {
      return {
        rows: rows.insertedStorage ?? [
          {
            storageObjectId: 'storage-1',
            objectKey: params[1],
            displayName: params[2],
            sizeBytes: params[3],
            checksum: params[4],
          },
        ],
      };
    }
    if (sql.includes('INSERT INTO device_network_presence')) {
      return {
        rows: rows.insertedPresence ?? [
          {
            id: 'presence-1',
            deviceId: params[1],
            networkType: params[2],
            localIp: params[4],
            localPort: params[5],
            expiresAt: '2026-06-08T00:10:00.000Z',
          },
        ],
      };
    }
    if (sql.includes('FROM device_network_presence')) {
      return { rows: rows.networkPresence ?? [] };
    }
    if (sql.includes('INSERT INTO file_transfer_candidates') && sql.includes('RETURNING id::text AS id')) {
      return {
        rows: rows.insertedCandidate ?? [
          {
            id: 'candidate-1',
            candidateType: params[2],
            protocol: params[7],
            status: params[9],
          },
        ],
      };
    }
    if (sql.includes('FROM file_transfer_candidates')) {
      return { rows: rows.transferCandidates ?? [] };
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
    status: vi.fn(async () => ({
      providerKey: 'server_storage_flowplanv2',
      storageType: 'local_filesystem',
      rootPath: 'C:/flowplan/storage',
      writable: true,
    })),
    root: vi.fn(() => 'C:/flowplan/storage'),
    copyLocalFile: vi.fn(async () => ({
      storagePath: 'C:/flowplan/storage/user/object-1',
      relativePath: 'user/object-1',
      sizeBytes: 128,
      checksum: 'sha256-1',
    })),
  };
  return {
    service: new FileTransferService(database as never, devices as never, objectStorage as never),
    database,
    devices,
    objectStorage,
  };
}

function findQuery(database: ReturnType<typeof createDatabase>, snippet: string) {
  const call = database.query.mock.calls.find(([sql]) => sql.includes(snippet));
  expect(call).toBeDefined();
  return call as [string, unknown[]];
}

function findQueries(database: ReturnType<typeof createDatabase>, snippet: string) {
  return database.query.mock.calls.filter(([sql]) => sql.includes(snippet));
}

function parseJsonParam(params: unknown[], index: number) {
  expect(typeof params[index]).toBe('string');
  return JSON.parse(params[index] as string) as Record<string, unknown>;
}

describe('FileTransferService', () => {
  it('returns local object storage status without touching the database', async () => {
    const { service, database, objectStorage } = createService();

    await expect(service.storageStatus()).resolves.toEqual({
      providerKey: 'server_storage_flowplanv2',
      storageType: 'local_filesystem',
      rootPath: 'C:/flowplan/storage',
      writable: true,
    });

    expect(objectStorage.status).toHaveBeenCalledOnce();
    expect(database.query).not.toHaveBeenCalled();
  });

  it('lists storage objects with default pagination and no filters', async () => {
    const database = createDatabase({
      storageObjects: [{ storageObjectId: 'storage-1', displayName: 'report.md' }],
    });
    const { service } = createService(database);

    await expect(service.storageObjects({}, context)).resolves.toEqual({
      limit: 100,
      offset: 0,
      hasMore: false,
      storageObjects: [{ storageObjectId: 'storage-1', displayName: 'report.md' }],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM file_storage_objects'),
      [context.userId, null, null, 100, 0],
    );
  });

  it('lists storage objects with cleaned filters and reports hasMore when the page is full', async () => {
    const database = createDatabase({
      storageObjects: [
        { storageObjectId: 'storage-1' },
        { storageObjectId: 'storage-2' },
      ],
    });
    const { service } = createService(database);

    await expect(
      service.storageObjects(
        { localPath: '  C:/data/report.md  ', nodeId: ' node-1 ', limit: '2', offset: '3' },
        context,
      ),
    ).resolves.toEqual({
      limit: 2,
      offset: 3,
      hasMore: true,
      storageObjects: [{ storageObjectId: 'storage-1' }, { storageObjectId: 'storage-2' }],
    });
    expect(database.query).toHaveBeenLastCalledWith(
      expect.stringContaining('FROM file_storage_objects'),
      [context.userId, 'C:/data/report.md', 'node-1', 2, 3],
    );
  });

  it('rejects storage object registration without a local path before copying files', async () => {
    const database = createDatabase();
    const { service, objectStorage } = createService(database);

    await expect(service.registerStorageObject({ localPath: '   ' }, context)).resolves.toEqual({
      ok: false,
      reason: 'localPath_required',
    });
    expect(objectStorage.copyLocalFile).not.toHaveBeenCalled();
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('registers a copied storage object and records an audit entry without node mapping', async () => {
    const database = createDatabase();
    const { service, objectStorage } = createService(database);

    await expect(
      service.registerStorageObject(
        {
          localPath: ' C:/data/report.md ',
          fileName: ' Quarterly Report.md ',
          objectKey: ' object-1 ',
          metadata: { projectId: 'project-1' },
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      storageObject: {
        storageObjectId: 'storage-1',
        objectKey: 'object-1',
        displayName: 'Quarterly Report.md',
        sizeBytes: 128,
        checksum: 'sha256-1',
      },
    });

    expect(objectStorage.copyLocalFile).toHaveBeenCalledWith(context.userId, 'C:/data/report.md', 'object-1');
    const [, storageParams] = findQuery(database, 'INSERT INTO file_storage_objects');
    expect(storageParams.slice(0, 7)).toEqual([
      context.userId,
      'object-1',
      'Quarterly Report.md',
      128,
      'sha256-1',
      128,
      expect.any(String),
    ]);
    expect(parseJsonParam(storageParams, 6)).toEqual({
      sourcePath: 'C:/data/report.md',
      storageType: 'local_filesystem',
      storageRoot: 'C:/flowplan/storage',
      storagePath: 'user/object-1',
      absoluteStoragePath: 'C:/flowplan/storage/user/object-1',
      projectId: 'project-1',
    });

    const [, auditParams] = findQuery(database, 'INSERT INTO audit_logs');
    expect(auditParams.slice(0, 4)).toEqual([
      context.userId,
      context.deviceId,
      'files.storage.register',
      null,
    ]);
    expect(parseJsonParam(auditParams, 4)).toMatchObject({
      storageObjectId: 'storage-1',
      objectKey: 'object-1',
      sourcePath: 'C:/data/report.md',
      storagePath: 'user/object-1',
    });
    expect(findQueries(database, 'UPDATE file_nodes')).toHaveLength(0);
    expect(findQueries(database, 'INSERT INTO file_node_device_locations')).toHaveLength(0);
    expect(findQueries(database, 'INSERT INTO file_identity_mappings')).toHaveLength(0);
  });

  it('registers node-linked storage using metadata fileNodeId, basename defaults and a generated object key', async () => {
    const database = createDatabase({
      insertedStorage: [
        {
          storageObjectId: 'storage-2',
          objectKey: 'stored-generated-key',
          displayName: 'diagram.png',
          sizeBytes: 256,
          checksum: 'sha256-2',
        },
      ],
    });
    const { service, objectStorage } = createService(database);
    objectStorage.copyLocalFile.mockResolvedValueOnce({
      storagePath: 'C:/flowplan/storage/user/generated-key',
      relativePath: 'user/generated-key',
      sizeBytes: 256,
      checksum: 'sha256-2',
    });

    await expect(
      service.registerStorageObject(
        {
          localPath: 'C:\\Users\\me\\diagram.png',
          metadata: { fileNodeId: ' node-77 ', source: 'desktop' },
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      storageObject: {
        storageObjectId: 'storage-2',
        objectKey: 'stored-generated-key',
        displayName: 'diagram.png',
        sizeBytes: 256,
        checksum: 'sha256-2',
      },
    });

    const generatedKey = objectStorage.copyLocalFile.mock.calls[0][2];
    expect(generatedKey).toEqual(expect.any(String));
    expect(generatedKey).not.toHaveLength(0);
    const [, storageParams] = findQuery(database, 'INSERT INTO file_storage_objects');
    expect(storageParams.slice(0, 6)).toEqual([
      context.userId,
      generatedKey,
      'diagram.png',
      256,
      'sha256-2',
      256,
    ]);

    const [, nodeParams] = findQuery(database, 'UPDATE file_nodes');
    expect(nodeParams.slice(0, 5)).toEqual([
      context.userId,
      'node-77',
      'sha256-2',
      256,
      expect.any(String),
    ]);
    expect(parseJsonParam(nodeParams, 4)).toEqual({
      storageObjectId: 'storage-2',
      storageProviderKey: 'server_storage',
      storageRegisteredAt: expect.any(String),
    });

    const [, locationParams] = findQuery(database, 'INSERT INTO file_node_device_locations');
    expect(locationParams).toEqual([
      context.userId,
      'node-77',
      context.deviceId,
      'C:\\Users\\me\\diagram.png',
      expect.any(String),
    ]);
    expect(parseJsonParam(locationParams, 4)).toEqual({
      hashSha256: 'sha256-2',
      source: 'storage_register',
    });

    const [, mappingParams] = findQuery(database, 'INSERT INTO file_identity_mappings');
    expect(mappingParams.slice(0, 8)).toEqual([
      context.userId,
      'node-77',
      'storage-2',
      context.deviceId,
      'C:\\Users\\me\\diagram.png',
      'sha256-2',
      256,
      expect.any(String),
    ]);
    expect(parseJsonParam(mappingParams, 7)).toEqual({
      objectKey: generatedKey,
      storagePath: 'user/generated-key',
    });
  });

  it('upserts network presence with cleaned custom values', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(
      service.upsertNetworkPresence(
        {
          networkType: ' wifi ',
          wifiSsidHash: ' ssid-hash ',
          localIp: ' 192.168.1.10 ',
          localPort: '6881',
          publicIpHash: ' public-hash ',
          natType: ' cone ',
          capabilities: { relay: true },
          ttlMinutes: '45',
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      presence: {
        id: 'presence-1',
        deviceId: context.deviceId,
        networkType: 'wifi',
        localIp: '192.168.1.10',
        localPort: 6881,
        expiresAt: '2026-06-08T00:10:00.000Z',
      },
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO device_network_presence'),
      [
        context.userId,
        context.deviceId,
        'wifi',
        'ssid-hash',
        '192.168.1.10',
        6881,
        'public-hash',
        'cone',
        '{"relay":true}',
        '45',
      ],
    );
  });

  it('upserts network presence with safe defaults for blank and invalid values', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(
      service.upsertNetworkPresence(
        { networkType: ' ', localPort: 'not-a-port', natType: '', capabilities: ['relay'], ttlMinutes: 'bad' },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      presence: { networkType: 'unknown', localPort: null },
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO device_network_presence'),
      [
        context.userId,
        context.deviceId,
        'unknown',
        null,
        null,
        null,
        null,
        'unknown',
        '{}',
        '10',
      ],
    );
  });

  it('lists network presence rows for the ensured user', async () => {
    const database = createDatabase({
      networkPresence: [
        { id: 'presence-1', deviceId: 'device-1', status: 'available' },
        { id: 'presence-2', deviceId: 'device-2', status: 'expired' },
      ],
    });
    const { service } = createService(database);

    await expect(service.networkPresence(context)).resolves.toEqual({
      devices: [
        { id: 'presence-1', deviceId: 'device-1', status: 'available' },
        { id: 'presence-2', deviceId: 'device-2', status: 'expired' },
      ],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM device_network_presence'),
      [context.userId],
    );
  });

  it('ensures the server relay candidate before listing transfer candidates', async () => {
    const database = createDatabase({
      transferCandidates: [{ id: 'candidate-server', candidateType: 'server_relay', status: 'available' }],
    });
    const { service } = createService(database);

    await expect(service.transferCandidates('session-1', context)).resolves.toEqual({
      candidates: [{ id: 'candidate-server', candidateType: 'server_relay', status: 'available' }],
    });

    expect(database.query.mock.calls[0]).toEqual([
      expect.stringContaining('INSERT INTO file_transfer_candidates'),
      [context.userId, 'session-1'],
    ]);
    expect(database.query.mock.calls[1]).toEqual([
      expect.stringContaining('FROM file_transfer_candidates'),
      [context.userId, 'session-1'],
    ]);
  });

  it('upserts a default transfer candidate and appends a candidate event in the same transaction', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(service.upsertTransferCandidate('session-1', {}, context)).resolves.toEqual({
      ok: true,
      candidate: {
        id: 'candidate-1',
        candidateType: 'lan_hint',
        protocol: 'server_api',
        status: 'pending',
      },
    });

    expect(database.transaction).toHaveBeenCalledOnce();
    const [, candidateParams] = findQuery(database, 'RETURNING id::text AS id, candidate_type');
    expect(candidateParams).toEqual([
      context.userId,
      'session-1',
      'lan_hint',
      null,
      null,
      null,
      null,
      'server_api',
      100,
      'pending',
      null,
      null,
      null,
    ]);
    const [, eventParams] = findQuery(database, 'INSERT INTO file_transfer_events');
    expect(eventParams.slice(0, 4)).toEqual([
      context.userId,
      'session-1',
      'candidate.added',
      null,
    ]);
    expect(parseJsonParam(eventParams, 4)).toEqual({
      candidateId: 'candidate-1',
      deviceId: context.deviceId,
    });
  });

  it('upserts a custom transfer candidate with numeric fields and failure diagnostics', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(
      service.upsertTransferCandidate(
        'session-2',
        {
          candidateType: ' direct ',
          sourceAddress: ' 10.0.0.2 ',
          sourcePort: '5000',
          targetAddress: ' 10.0.0.9 ',
          targetPort: 6000.9,
          protocol: ' webrtc ',
          priority: '7',
          status: 'failed',
          latencyMs: '19.8',
          bandwidthEstimate: '2048',
          failureReason: ' timeout ',
        },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      candidate: {
        id: 'candidate-1',
        candidateType: 'direct',
        protocol: 'webrtc',
        status: 'failed',
      },
    });

    const [, candidateParams] = findQuery(database, 'RETURNING id::text AS id, candidate_type');
    expect(candidateParams).toEqual([
      context.userId,
      'session-2',
      'direct',
      '10.0.0.2',
      5000,
      '10.0.0.9',
      6000,
      'webrtc',
      7,
      'failed',
      19,
      2048,
      'timeout',
    ]);
  });

  it('appends transfer events with custom payloads or default note events', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await expect(
      service.appendTransferEvent(
        'session-1',
        { eventType: ' transfer.progress ', message: ' half way ', payload: { chunkIndex: 2 } },
        context,
      ),
    ).resolves.toEqual({ ok: true });
    await expect(service.appendTransferEvent('session-2', { payload: 'ignored' }, context)).resolves.toEqual({
      ok: true,
    });

    const eventCalls = findQueries(database, 'INSERT INTO file_transfer_events');
    expect(eventCalls).toHaveLength(2);
    expect(eventCalls[0][1].slice(0, 4)).toEqual([
      context.userId,
      'session-1',
      'transfer.progress',
      'half way',
    ]);
    expect(parseJsonParam(eventCalls[0][1], 4)).toEqual({
      message: 'half way',
      chunkIndex: 2,
    });
    expect(eventCalls[1][1].slice(0, 4)).toEqual([
      context.userId,
      'session-2',
      'transfer.note',
      null,
    ]);
    expect(parseJsonParam(eventCalls[1][1], 4)).toEqual({ message: null });
  });
});
