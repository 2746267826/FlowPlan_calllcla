import { describe, expect, it, vi } from 'vitest';
import { FilesController } from './files.controller';

const headers = {
  'x-flowplanv2-user-id': ' 11111111-1111-4111-8111-111111111111 ',
  'x-flowplanv2-device-id': '22222222-2222-4222-8222-222222222222',
};

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

const defaultContext = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

const providerBody = { enabled: true, displayName: 'Local drive' };
const treeSnapshotBody = { providerKey: 'local', nodes: [{ nodeId: 'node-1' }] };
const query = { providerKey: 'local', parentId: 'root-1', limit: '25' };
const rootBody = { providerKey: 'local', rootPath: 'C:/data' };
const nodeSnapshotBody = { nodeId: 'node-1', path: 'C:/data/a.txt' };
const operationBody = { action: 'open', localPath: 'C:/data/a.txt' };
const linkBody = { nodeId: 'node-1', entityType: 'task', entityId: 'task-1' };
const recommendationBody = { decision: 'accepted' };
const uploadBody = { fileName: 'a.txt', totalChunks: 2 };
const chunkBody = { payloadBase64: 'YQ==' };
const downloadBody = { nodeId: 'node-1', byteRange: { start: 0, end: 10 } };
const scanBody = { recursive: true };
const presenceBody = { deviceName: 'desktop', address: '192.168.0.2' };
const candidateBody = { deviceId: 'device-remote', score: 10 };
const eventBody = { eventType: 'started', at: '2026-06-08T00:00:00.000Z' };
const storageBody = { objectId: 'object-1', sizeBytes: 12 };
const kopiaBody = { rootPath: 'C:/data', snapshotId: 'snap-1' };
const versionBody = { targetPath: 'C:/restore/a.txt' };
const conflictBody = { conflictType: 'name', resolution: { winner: 'local' } };

function createController() {
  const service = new Proxy(
    {},
    {
      get(target, prop: string) {
        if (!(prop in target)) {
          (target as Record<string, unknown>)[prop] = vi.fn(async (...args: unknown[]) => ({
            method: prop,
            args,
          }));
        }
        return (target as Record<string, unknown>)[prop];
      },
    },
  ) as Record<string, ReturnType<typeof vi.fn>>;
  return { controller: new FilesController(service as never), service };
}

const cases = [
  {
    controllerMethod: 'providers',
    serviceMethod: 'providers',
    invoke: (controller: FilesController) => controller.providers(headers),
    expectedArgs: [context],
  },
  {
    controllerMethod: 'dashboard',
    serviceMethod: 'dashboard',
    invoke: (controller: FilesController) => controller.dashboard(headers),
    expectedArgs: [context],
  },
  {
    controllerMethod: 'upsertProvider',
    serviceMethod: 'upsertProvider',
    invoke: (controller: FilesController) => controller.upsertProvider('local', providerBody, headers),
    expectedArgs: ['local', providerBody, context],
  },
  {
    controllerMethod: 'applyTreeSnapshot',
    serviceMethod: 'applyTreeSnapshot',
    invoke: (controller: FilesController) => controller.applyTreeSnapshot(treeSnapshotBody, headers),
    expectedArgs: [treeSnapshotBody, context],
  },
  {
    controllerMethod: 'tree',
    serviceMethod: 'tree',
    invoke: (controller: FilesController) => controller.tree(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'roots',
    serviceMethod: 'roots',
    invoke: (controller: FilesController) => controller.roots(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'driveRoots',
    serviceMethod: 'driveRoots',
    invoke: (controller: FilesController) => controller.driveRoots(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'upsertRoot',
    serviceMethod: 'upsertRoot',
    invoke: (controller: FilesController) => controller.upsertRoot(rootBody, headers),
    expectedArgs: [rootBody, context],
  },
  {
    controllerMethod: 'fileNodes',
    serviceMethod: 'fileNodes',
    invoke: (controller: FilesController) => controller.fileNodes(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'driveNodes',
    serviceMethod: 'driveNodes',
    invoke: (controller: FilesController) => controller.driveNodes(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'driveNode',
    serviceMethod: 'driveNode',
    invoke: (controller: FilesController) => controller.driveNode('node-1', headers),
    expectedArgs: ['node-1', context],
  },
  {
    controllerMethod: 'driveOpenPlan',
    serviceMethod: 'driveOpenPlan',
    invoke: (controller: FilesController) => controller.driveOpenPlan('node-1', operationBody, headers),
    expectedArgs: ['node-1', operationBody, context],
  },
  {
    controllerMethod: 'upsertDriveDeviceLocation',
    serviceMethod: 'upsertDriveDeviceLocation',
    invoke: (controller: FilesController) => controller.upsertDriveDeviceLocation('node-1', operationBody, headers),
    expectedArgs: ['node-1', operationBody, context],
  },
  {
    controllerMethod: 'createDriveDownloadRequest',
    serviceMethod: 'createDriveDownloadRequest',
    invoke: (controller: FilesController) => controller.createDriveDownloadRequest('node-1', downloadBody, headers),
    expectedArgs: ['node-1', downloadBody, context],
  },
  {
    controllerMethod: 'scanDriveRoot',
    serviceMethod: 'scanDriveRoot',
    invoke: (controller: FilesController) => controller.scanDriveRoot('root-1', scanBody, headers),
    expectedArgs: ['root-1', scanBody, context],
  },
  {
    controllerMethod: 'deleteDriveRoot',
    serviceMethod: 'deleteDriveRoot',
    invoke: (controller: FilesController) => controller.deleteDriveRoot('root-1', headers),
    expectedArgs: ['root-1', context],
  },
  {
    controllerMethod: 'relinkDriveNode',
    serviceMethod: 'relinkDriveNode',
    invoke: (controller: FilesController) => controller.relinkDriveNode('node-1', operationBody, headers),
    expectedArgs: ['node-1', operationBody, context],
  },
  {
    controllerMethod: 'applyNodeSnapshot',
    serviceMethod: 'applyNodeSnapshot',
    invoke: (controller: FilesController) => controller.applyNodeSnapshot(nodeSnapshotBody, headers),
    expectedArgs: [nodeSnapshotBody, context],
  },
  {
    controllerMethod: 'logNodeOperation',
    serviceMethod: 'logNodeOperation',
    invoke: (controller: FilesController) => controller.logNodeOperation('node-1', operationBody, headers),
    expectedArgs: ['node-1', operationBody, context],
  },
  {
    controllerMethod: 'linkNodeToEntity',
    serviceMethod: 'linkNodeToEntity',
    invoke: (controller: FilesController) => controller.linkNodeToEntity(linkBody, headers),
    expectedArgs: [linkBody, context],
  },
  {
    controllerMethod: 'contextLinks',
    serviceMethod: 'contextLinks',
    invoke: (controller: FilesController) => controller.contextLinks(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'recommendations',
    serviceMethod: 'recommendations',
    invoke: (controller: FilesController) => controller.recommendations(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'reviewRecommendation',
    serviceMethod: 'reviewRecommendation',
    invoke: (controller: FilesController) =>
      controller.reviewRecommendation('recommendation-1', recommendationBody, headers),
    expectedArgs: ['recommendation-1', recommendationBody, context],
  },
  {
    controllerMethod: 'createUploadSession',
    serviceMethod: 'createUploadSession',
    invoke: (controller: FilesController) => controller.createUploadSession(uploadBody, headers),
    expectedArgs: [uploadBody, context],
  },
  {
    controllerMethod: 'createUploadTransferSession',
    serviceMethod: 'createUploadSession',
    invoke: (controller: FilesController) => controller.createUploadTransferSession(uploadBody, headers),
    expectedArgs: [uploadBody, context],
  },
  {
    controllerMethod: 'uploadChunk',
    serviceMethod: 'uploadChunk',
    invoke: (controller: FilesController) => controller.uploadChunk('session-1', '2', chunkBody, headers),
    expectedArgs: ['session-1', '2', chunkBody, context],
  },
  {
    controllerMethod: 'uploadTransferChunk',
    serviceMethod: 'uploadChunk',
    invoke: (controller: FilesController) => controller.uploadTransferChunk('session-1', '2', chunkBody, headers),
    expectedArgs: ['session-1', '2', chunkBody, context],
  },
  {
    controllerMethod: 'missingUploadChunks',
    serviceMethod: 'missingUploadChunks',
    invoke: (controller: FilesController) => controller.missingUploadChunks('session-1', headers),
    expectedArgs: ['session-1', context],
  },
  {
    controllerMethod: 'missingTransferUploadChunks',
    serviceMethod: 'missingUploadChunks',
    invoke: (controller: FilesController) => controller.missingTransferUploadChunks('session-1', headers),
    expectedArgs: ['session-1', context],
  },
  {
    controllerMethod: 'completeUploadSession',
    serviceMethod: 'completeUploadSession',
    invoke: (controller: FilesController) => controller.completeUploadSession('session-1', headers),
    expectedArgs: ['session-1', context],
  },
  {
    controllerMethod: 'completeUploadTransferSession',
    serviceMethod: 'completeUploadSession',
    invoke: (controller: FilesController) => controller.completeUploadTransferSession('session-1', headers),
    expectedArgs: ['session-1', context],
  },
  {
    controllerMethod: 'createDownloadSession',
    serviceMethod: 'createDownloadSession',
    invoke: (controller: FilesController) => controller.createDownloadSession(downloadBody, headers),
    expectedArgs: [downloadBody, context],
  },
  {
    controllerMethod: 'downloadRange',
    serviceMethod: 'downloadRange',
    invoke: (controller: FilesController) => controller.downloadRange('session-1', query, headers),
    expectedArgs: ['session-1', query, context],
  },
  {
    controllerMethod: 'downloadStorageObject',
    serviceMethod: 'downloadStorageObject',
    invoke: (controller: FilesController) => controller.downloadStorageObject('object-1', query, headers),
    expectedArgs: ['object-1', query, context],
  },
  {
    controllerMethod: 'transfers',
    serviceMethod: 'transfers',
    invoke: (controller: FilesController) => controller.transfers(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'transferProgress',
    serviceMethod: 'transferProgress',
    invoke: (controller: FilesController) => controller.transferProgress('session-1', headers),
    expectedArgs: ['session-1', context],
  },
  {
    controllerMethod: 'upsertNetworkPresence',
    serviceMethod: 'upsertNetworkPresence',
    invoke: (controller: FilesController) => controller.upsertNetworkPresence(presenceBody, headers),
    expectedArgs: [presenceBody, context],
  },
  {
    controllerMethod: 'networkPresence',
    serviceMethod: 'networkPresence',
    invoke: (controller: FilesController) => controller.networkPresence(headers),
    expectedArgs: [context],
  },
  {
    controllerMethod: 'transferCandidates',
    serviceMethod: 'transferCandidates',
    invoke: (controller: FilesController) => controller.transferCandidates('session-1', headers),
    expectedArgs: ['session-1', context],
  },
  {
    controllerMethod: 'upsertTransferCandidate',
    serviceMethod: 'upsertTransferCandidate',
    invoke: (controller: FilesController) => controller.upsertTransferCandidate('session-1', candidateBody, headers),
    expectedArgs: ['session-1', candidateBody, context],
  },
  {
    controllerMethod: 'appendTransferEvent',
    serviceMethod: 'appendTransferEvent',
    invoke: (controller: FilesController) => controller.appendTransferEvent('session-1', eventBody, headers),
    expectedArgs: ['session-1', eventBody, context],
  },
  {
    controllerMethod: 'storageStatus',
    serviceMethod: 'storageStatus',
    invoke: (controller: FilesController) => controller.storageStatus(),
    expectedArgs: [],
  },
  {
    controllerMethod: 'storageObjects',
    serviceMethod: 'storageObjects',
    invoke: (controller: FilesController) => controller.storageObjects(query, headers),
    expectedArgs: [query, context],
  },
  {
    controllerMethod: 'registerStorageObject',
    serviceMethod: 'registerStorageObject',
    invoke: (controller: FilesController) => controller.registerStorageObject(storageBody, headers),
    expectedArgs: [storageBody, context],
  },
  {
    controllerMethod: 'createKopiaSnapshot',
    serviceMethod: 'createKopiaSnapshot',
    invoke: (controller: FilesController) => controller.createKopiaSnapshot(kopiaBody, headers),
    expectedArgs: [kopiaBody, context],
  },
  {
    controllerMethod: 'refreshKopiaVersions',
    serviceMethod: 'refreshKopiaVersions',
    invoke: (controller: FilesController) => controller.refreshKopiaVersions(kopiaBody, headers),
    expectedArgs: [kopiaBody, context],
  },
  {
    controllerMethod: 'versions',
    serviceMethod: 'versions',
    invoke: (controller: FilesController) => controller.versions('file-1', headers),
    expectedArgs: ['file-1', context],
  },
  {
    controllerMethod: 'createVersionDownloadRequest',
    serviceMethod: 'createVersionDownloadRequest',
    invoke: (controller: FilesController) => controller.createVersionDownloadRequest('version-1', versionBody, headers),
    expectedArgs: ['version-1', versionBody, context],
  },
  {
    controllerMethod: 'downloadVersionCopy',
    serviceMethod: 'downloadVersionCopy',
    invoke: (controller: FilesController) => controller.downloadVersionCopy('version-1', versionBody, headers),
    expectedArgs: ['version-1', versionBody, context],
  },
  {
    controllerMethod: 'prepareVersionRestore',
    serviceMethod: 'prepareVersionRestore',
    invoke: (controller: FilesController) => controller.prepareVersionRestore('version-1', versionBody, headers),
    expectedArgs: ['version-1', versionBody, context],
  },
  {
    controllerMethod: 'conflicts',
    serviceMethod: 'conflicts',
    invoke: (controller: FilesController) => controller.conflicts(headers),
    expectedArgs: [context],
  },
  {
    controllerMethod: 'createConflict',
    serviceMethod: 'createConflict',
    invoke: (controller: FilesController) => controller.createConflict(conflictBody, headers),
    expectedArgs: [conflictBody, context],
  },
  {
    controllerMethod: 'resolveConflict',
    serviceMethod: 'resolveConflict',
    invoke: (controller: FilesController) => controller.resolveConflict('conflict-1', conflictBody, headers),
    expectedArgs: ['conflict-1', conflictBody, context],
  },
];

describe('FilesController', () => {
  it('has a delegation case for every public route method', () => {
    const publicMethods = Object.getOwnPropertyNames(FilesController.prototype)
      .filter((name) => name !== 'constructor')
      .sort();

    expect(cases.map((testCase) => testCase.controllerMethod).sort()).toEqual(publicMethods);
  });

  it.each(cases)('forwards $controllerMethod to $serviceMethod with parsed request context', async (testCase) => {
    const { controller, service } = createController();

    await expect(testCase.invoke(controller)).resolves.toEqual({
      method: testCase.serviceMethod,
      args: testCase.expectedArgs,
    });
    expect(service[testCase.serviceMethod]).toHaveBeenCalledWith(...testCase.expectedArgs);
  });

  it('falls back to default request context for invalid headers', async () => {
    const { controller } = createController();

    await expect(controller.dashboard({ 'x-flowplanv2-user-id': 'bad' })).resolves.toEqual({
      method: 'dashboard',
      args: [defaultContext],
    });
  });

  it('maps transfer upload aliases to uploadChunk while preserving raw route params and DTO identity', async () => {
    const service = {
      uploadChunk: vi.fn(async () => ({ stored: true, sessionId: 'session-1', chunkIndex: '02' })),
    };
    const controller = new FilesController(service as never);
    const body = { payloadBase64: 'YQ==', checksum: 'sha256:abc' };

    await expect(
      controller.uploadTransferChunk('session-1', '02', body, headers),
    ).resolves.toEqual({ stored: true, sessionId: 'session-1', chunkIndex: '02' });
    expect(service.uploadChunk).toHaveBeenCalledTimes(1);
    expect(service.uploadChunk.mock.calls[0][0]).toBe('session-1');
    expect(service.uploadChunk.mock.calls[0][1]).toBe('02');
    expect(service.uploadChunk.mock.calls[0][2]).toBe(body);
    expect(service.uploadChunk.mock.calls[0][3]).toEqual(context);
  });

  it('leaves storage status public by not synthesizing request context', async () => {
    const service = {
      storageStatus: vi.fn(async () => ({ ok: true, backend: 'local' })),
    };
    const controller = new FilesController(service as never);

    await expect(controller.storageStatus()).resolves.toEqual({ ok: true, backend: 'local' });
    expect(service.storageStatus).toHaveBeenCalledWith();
  });

  it('passes service errors through without wrapping them', async () => {
    const { controller, service } = createController();
    const error = new Error('conflict create failed');
    service.createConflict.mockRejectedValueOnce(error);

    await expect(controller.createConflict(conflictBody, headers)).rejects.toBe(error);
  });
});
