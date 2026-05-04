import { Injectable } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { open, stat } from 'node:fs/promises';
import { posix, win32 } from 'node:path';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { FileTreeService } from './file-tree.service';
import { FileTransferService } from './file-transfer.service';
import { FileVersionService } from './file-version.service';
import { LocalObjectStorageService } from './local-object-storage.service';

export interface FilesQuery {
  providerKey?: string;
  parentRemoteId?: string;
  q?: string;
  status?: string;
  direction?: string;
  start?: string;
  end?: string;
  rootId?: string;
  parentId?: string;
  entityType?: string;
  entityId?: string;
  limit?: string;
  offset?: string;
  localPath?: string;
  deviceId?: string;
  nodeId?: string;
}

type SessionRow = QueryResultRow & {
  id: string;
  provider_key: string;
  direction: string;
  file_name: string;
  object_key: string | null;
  storage_object_id: string | null;
  total_bytes: string | number;
  chunk_size: number;
  expected_chunks: number;
  received_chunks: number;
  received_bytes: string | number;
  checksum: string | null;
  status: string;
  metadata: Record<string, unknown>;
};

@Injectable()
export class FilesService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly objectStorage: LocalObjectStorageService,
    private readonly fileTreeService: FileTreeService,
    private readonly fileTransferService: FileTransferService,
    private readonly fileVersionService: FileVersionService,
  ) {}

  async providers(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultProviders(userId);
    const result = await this.database.query(
      `
      SELECT
        id::text AS id,
        provider_key AS "providerKey",
        provider_type AS "providerType",
        display_name AS "displayName",
        priority,
        status,
        root_remote_id AS "rootRemoteId",
        local_mirror_path AS "localMirrorPath",
        mobile_download_root AS "mobileDownloadRoot",
        sync_mode AS "syncMode",
        capabilities,
        config,
        last_tree_sync_at AS "lastTreeSyncAt",
        last_error AS "lastError",
        updated_at AS "updatedAt"
      FROM file_providers
      WHERE user_id = $1
      ORDER BY priority ASC, provider_key ASC
      `,
      [userId],
    );
    return { providers: result.rows };
  }

  async dashboard(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultProviders(userId);
    const [
      providers,
      treeSummary,
      storageObjects,
      versionRecords,
      transfers,
      conflicts,
      versionRequests,
      storageStatus,
    ] =
      await Promise.all([
        this.providers(context),
        this.database.query(
          `
          SELECT
            provider_key AS "providerKey",
            availability,
            item_type AS "itemType",
            COUNT(*)::int AS count,
            COALESCE(SUM(size_bytes), 0)::bigint AS "totalBytes",
            MAX(last_seen_at) AS "lastSeenAt"
          FROM cloud_file_tree_nodes
          WHERE user_id = $1
          GROUP BY provider_key, availability, item_type
          ORDER BY provider_key ASC, availability ASC, item_type ASC
          `,
          [userId],
        ),
        this.database.query(
          `
          SELECT
            id::text AS "storageObjectId",
            provider_key AS "providerKey",
            object_key AS "objectKey",
            display_name AS "displayName",
            size_bytes AS "sizeBytes",
            checksum,
            status,
            metadata,
            updated_at AS "updatedAt"
          FROM file_storage_objects
          WHERE user_id = $1
          ORDER BY updated_at DESC
          LIMIT 20
          `,
          [userId],
        ),
        this.database.query(
          `
          SELECT
            id::text AS id,
            file_id AS "fileId",
            provider,
            version_ref AS "versionRef",
            display_name AS "displayName",
            size_bytes AS "sizeBytes",
            modified_at AS "modifiedAt",
            source_backend AS "sourceBackend",
            created_at AS "createdAt"
          FROM file_version_records
          WHERE user_id = $1
          ORDER BY created_at DESC
          LIMIT 20
          `,
          [userId],
        ),
        this.database.query(
          `
          SELECT
            id::text AS "sessionId",
            provider_key AS "providerKey",
            direction,
            file_name AS "fileName",
            total_bytes AS "totalBytes",
            received_bytes AS "receivedBytes",
            expected_chunks AS "expectedChunks",
            received_chunks AS "receivedChunks",
            status,
            updated_at AS "updatedAt"
          FROM file_transfer_sessions
          WHERE user_id = $1
          ORDER BY updated_at DESC
          LIMIT 20
          `,
          [userId],
        ),
        this.database.query(
          `
          SELECT
            id::text AS id,
            path,
            provider_a AS "providerA",
            provider_b AS "providerB",
            reason,
            status,
            created_at AS "createdAt"
          FROM file_conflict_candidates
          WHERE user_id = $1
          ORDER BY created_at DESC
          LIMIT 20
          `,
          [userId],
        ),
        this.database.query(
          `
          SELECT
            id::text AS id,
            file_id AS "fileId",
            provider,
            version_ref AS "versionRef",
            target_mode AS "targetMode",
            target_path AS "targetPath",
            status,
            created_at AS "createdAt"
          FROM file_version_download_requests
          WHERE user_id = $1
          ORDER BY created_at DESC
          LIMIT 20
          `,
          [userId],
        ),
        this.objectStorage.status(),
      ]);

    return {
      storageStatus,
      providers: providers.providers,
      treeSummary: treeSummary.rows,
      transfers: transfers.rows,
      storageObjects: storageObjects.rows,
      versionRecords: versionRecords.rows,
      conflicts: conflicts.rows,
      versionDownloadRequests: versionRequests.rows,
    };
  }

  async upsertProvider(
    providerKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const provider = await client.query(
        `
        INSERT INTO file_providers (
          user_id,
          provider_key,
          provider_type,
          display_name,
          priority,
          status,
          root_remote_id,
          local_mirror_path,
          mobile_download_root,
          sync_mode,
          capabilities,
          config,
          last_error
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, $12::jsonb, $13)
        ON CONFLICT (user_id, provider_key) DO UPDATE SET
          provider_type = EXCLUDED.provider_type,
          display_name = EXCLUDED.display_name,
          priority = EXCLUDED.priority,
          status = EXCLUDED.status,
          root_remote_id = EXCLUDED.root_remote_id,
          local_mirror_path = EXCLUDED.local_mirror_path,
          mobile_download_root = EXCLUDED.mobile_download_root,
          sync_mode = EXCLUDED.sync_mode,
          capabilities = EXCLUDED.capabilities,
          config = EXCLUDED.config,
          last_error = EXCLUDED.last_error,
          updated_at = now()
        RETURNING id::text, provider_key AS "providerKey", status, updated_at AS "updatedAt"
        `,
        [
          userId,
          providerKey,
          this.clean(body.providerType) ?? providerKey,
          this.clean(body.displayName) ?? providerKey,
          this.readNumber(body.priority, 100),
          this.clean(body.status) ?? 'enabled',
          this.clean(body.rootRemoteId),
          this.clean(body.localMirrorPath),
          this.clean(body.mobileDownloadRoot),
          this.clean(body.syncMode) ?? 'manual',
          JSON.stringify(this.asRecord(body.capabilities)),
          JSON.stringify(this.asRecord(body.config)),
          this.clean(body.lastError),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'files.provider.upsert', {
        providerKey,
      });
      return provider.rows[0];
    });
    return { ok: true, provider: result };
  }

  async applyTreeSnapshot(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const providerKey = this.clean(body.providerKey) ?? 'onedrive';
    const treeRevision = this.clean(body.treeRevision) ?? randomUUID();
    const nodes = Array.isArray(body.nodes) ? body.nodes : [];
    const markMissing = body.markMissing === true;

    let accepted = 0;
    await this.database.transaction(async (client) => {
      await this.ensureProvider(client, userId, providerKey);
      for (const nodeValue of nodes) {
        const node = this.asRecord(nodeValue);
        const remoteId = this.clean(node.remoteId);
        const path = this.clean(node.path);
        if (!remoteId || !path) {
          continue;
        }
        await client.query(
          `
          INSERT INTO cloud_file_tree_nodes (
            user_id,
            provider_key,
            remote_id,
            parent_remote_id,
            path,
            display_name,
            item_type,
            mime_type,
            size_bytes,
            etag,
            ctag,
            checksum,
            local_path,
            availability,
            modified_at,
            metadata,
            tree_revision,
            last_seen_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16::jsonb, $17, now())
          ON CONFLICT (user_id, provider_key, remote_id) DO UPDATE SET
            parent_remote_id = EXCLUDED.parent_remote_id,
            path = EXCLUDED.path,
            display_name = EXCLUDED.display_name,
            item_type = EXCLUDED.item_type,
            mime_type = EXCLUDED.mime_type,
            size_bytes = EXCLUDED.size_bytes,
            etag = EXCLUDED.etag,
            ctag = EXCLUDED.ctag,
            checksum = EXCLUDED.checksum,
            local_path = EXCLUDED.local_path,
            availability = EXCLUDED.availability,
            modified_at = EXCLUDED.modified_at,
            metadata = EXCLUDED.metadata,
            tree_revision = EXCLUDED.tree_revision,
            last_seen_at = now(),
            updated_at = now()
          `,
          [
            userId,
            providerKey,
            remoteId,
            this.clean(node.parentRemoteId),
            path,
            this.clean(node.displayName) ?? this.basename(path),
            this.clean(node.itemType) ?? 'file',
            this.clean(node.mimeType),
            this.readNullableNumber(node.sizeBytes),
            this.clean(node.etag),
            this.clean(node.ctag),
            this.clean(node.checksum),
            this.clean(node.localPath),
            this.clean(node.availability) ?? 'remote_only',
            this.readDate(node.modifiedAt),
            JSON.stringify(this.asRecord(node.metadata)),
            treeRevision,
          ],
        );
        accepted += 1;
      }

      if (markMissing) {
        await client.query(
          `
          UPDATE cloud_file_tree_nodes
          SET availability = 'missing', updated_at = now()
          WHERE user_id = $1
            AND provider_key = $2
            AND tree_revision IS DISTINCT FROM $3
          `,
          [userId, providerKey, treeRevision],
        );
      }

      await client.query(
        `
        UPDATE file_providers
        SET last_tree_sync_at = now(), last_error = NULL, updated_at = now()
        WHERE user_id = $1 AND provider_key = $2
        `,
        [userId, providerKey],
      );
      await this.recordAudit(client, userId, deviceId, 'files.tree.snapshot', {
        providerKey,
        treeRevision,
        accepted,
        markMissing,
      });
    });
    return { ok: true, providerKey, treeRevision, accepted };
  }

  async tree(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 300);
    const offset = this.readOffset(query.offset);
    const providerKey = this.clean(query.providerKey);
    const parentRemoteId = this.clean(query.parentRemoteId);
    const search = this.search(query.q);
    const result = await this.database.query(
      `
      SELECT
        id::text AS id,
        provider_key AS "providerKey",
        remote_id AS "remoteId",
        parent_remote_id AS "parentRemoteId",
        path,
        display_name AS "displayName",
        item_type AS "itemType",
        mime_type AS "mimeType",
        size_bytes AS "sizeBytes",
        etag,
        checksum,
        local_path AS "localPath",
        availability,
        modified_at AS "modifiedAt",
        tree_revision AS "treeRevision",
        last_seen_at AS "lastSeenAt",
        updated_at AS "updatedAt"
      FROM cloud_file_tree_nodes
      WHERE user_id = $1
        AND ($2::text IS NULL OR provider_key = $2)
        AND ($3::text IS NULL OR parent_remote_id = $3)
        AND ($4::text IS NULL OR path ILIKE $4 OR display_name ILIKE $4)
      ORDER BY provider_key ASC, item_type ASC, path ASC
      LIMIT $5 OFFSET $6
      `,
      [userId, providerKey, parentRemoteId, search, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async createUploadSession(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const providerKey = this.clean(body.providerKey) ?? 'server_storage';
    const fileName = this.clean(body.fileName) ?? 'unnamed';
    const totalBytes = this.readNumber(body.totalBytes, 0);
    const chunkSize = this.readNumber(body.chunkSize, 5 * 1024 * 1024);
    const expectedChunks =
      totalBytes <= 0 ? 0 : Math.ceil(totalBytes / Math.max(chunkSize, 1));
    const objectKey = this.clean(body.objectKey) ?? randomUUID();
    await this.ensureDefaultProviders(userId);
    const uploadSession = await this.database.transaction(async (client) => {
      const result = await client.query(
        `
        INSERT INTO file_transfer_sessions (
          user_id,
          provider_key,
          direction,
          file_name,
          remote_id,
          local_path,
          object_key,
          total_bytes,
          chunk_size,
          expected_chunks,
          checksum,
          metadata,
          expires_at
        ) VALUES ($1, $2, 'upload', $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, now() + interval '7 days')
        RETURNING
          id::text AS "sessionId",
          resume_token AS "resumeToken",
          provider_key AS "providerKey",
          object_key AS "objectKey",
          chunk_size AS "chunkSize",
          expected_chunks AS "expectedChunks",
          status
        `,
        [
          userId,
          providerKey,
          fileName,
          this.clean(body.remoteId),
          this.clean(body.localPath),
          objectKey,
          totalBytes,
          chunkSize,
          expectedChunks,
          this.clean(body.checksum),
          JSON.stringify(this.asRecord(body.metadata)),
        ],
      );
      const session = result.rows[0];
      await this.recordAudit(client, userId, deviceId, 'files.upload.create_session', {
        sessionId: session.sessionId,
        providerKey,
        fileName,
        totalBytes,
        chunkSize,
        expectedChunks,
      });
      return session;
    });
    return { uploadSession };
  }

  async uploadChunk(
    sessionId: string,
    chunkIndex: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const index = this.readNumber(chunkIndex, -1);
    const payloadBase64 = this.clean(body.payloadBase64);
    if (index < 0 || !payloadBase64) {
      return { ok: false, reason: 'chunkIndex and payloadBase64 are required' };
    }
    const sizeBytes = Buffer.from(payloadBase64, 'base64').length;
    const startByte = this.readNumber(body.startByte, 0);
    const endByte = this.readNumber(body.endByte, startByte + sizeBytes - 1);
    const checksum = this.clean(body.checksum) ?? this.sha256(Buffer.from(payloadBase64, 'base64'));

    const result = await this.database.transaction(async (client) => {
      const session = await this.findSession(client, userId, sessionId, 'upload');
      if (!session || session.status === 'completed') {
        return null;
      }
      await client.query(
        `
        INSERT INTO file_transfer_chunks (
          user_id,
          session_id,
          chunk_index,
          start_byte,
          end_byte,
          size_bytes,
          checksum,
          payload,
          status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, decode($8, 'base64'), 'received')
        ON CONFLICT (user_id, session_id, chunk_index) DO UPDATE SET
          start_byte = EXCLUDED.start_byte,
          end_byte = EXCLUDED.end_byte,
          size_bytes = EXCLUDED.size_bytes,
          checksum = EXCLUDED.checksum,
          payload = EXCLUDED.payload,
          status = 'received',
          created_at = now()
        `,
        [userId, sessionId, index, startByte, endByte, sizeBytes, checksum, payloadBase64],
      );
      await this.refreshSessionProgress(client, userId, sessionId);
      const updated = await this.findSession(client, userId, sessionId, 'upload');
      return updated;
    });
    return { ok: !!result, session: this.sessionDto(result) };
  }

  async missingUploadChunks(
    sessionId: string,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const session = await this.findSession(this.database, userId, sessionId, 'upload');
    if (!session) {
      return { ok: false, reason: 'session_not_found' };
    }
    const received = await this.database.query<QueryResultRow & { chunk_index: number }>(
      `
      SELECT chunk_index
      FROM file_transfer_chunks
      WHERE user_id = $1
        AND session_id = $2
        AND status = 'received'
      ORDER BY chunk_index ASC
      `,
      [userId, sessionId],
    );
    const receivedSet = new Set(
      received.rows.map((row) => Number(row.chunk_index)),
    );
    const missingChunks: number[] = [];
    for (let index = 0; index < session.expected_chunks; index += 1) {
      if (!receivedSet.has(index)) {
        missingChunks.push(index);
      }
    }
    return {
      ok: true,
      session: this.sessionDto(session),
      missingChunks,
      receivedChunks: receivedSet.size,
      expectedChunks: session.expected_chunks,
    };
  }

  async completeUploadSession(
    sessionId: string,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const session = await this.findSession(client, userId, sessionId, 'upload');
      if (!session) {
        return { ok: false, reason: 'session_not_found' };
      }
      if (session.expected_chunks > 0 && session.received_chunks < session.expected_chunks) {
        return { ok: false, reason: 'missing_chunks', session: this.sessionDto(session) };
      }
      const chunks = await client.query<QueryResultRow & { payload: Buffer }>(
        `
        SELECT payload
        FROM file_transfer_chunks
        WHERE user_id = $1 AND session_id = $2
        ORDER BY chunk_index ASC
        `,
        [userId, sessionId],
      );
      const hash = createHash('sha256');
      for (const chunk of chunks.rows) {
        hash.update(chunk.payload);
      }
      const actualChecksum = hash.digest('hex');
      if (session.checksum && session.checksum !== actualChecksum) {
        await client.query(
          `
          UPDATE file_transfer_sessions
          SET status = 'failed', error_message = $3, updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, sessionId, `checksum mismatch: ${actualChecksum}`],
        );
        return { ok: false, reason: 'checksum_mismatch', actualChecksum };
      }
      const objectKey = session.object_key ?? randomUUID();
      const storedObject = await this.objectStorage.writeObjectFromChunks(
        userId,
        objectKey,
        chunks.rows.map((chunk) => chunk.payload),
      );

      const storage = await client.query(
        `
        INSERT INTO file_storage_objects (
          user_id,
          provider_key,
          object_key,
          display_name,
          size_bytes,
          checksum,
          chunk_size,
          chunk_count,
          status,
          metadata
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'available', $9::jsonb)
        ON CONFLICT (user_id, provider_key, object_key) DO UPDATE SET
          display_name = EXCLUDED.display_name,
          size_bytes = EXCLUDED.size_bytes,
          checksum = EXCLUDED.checksum,
          chunk_size = EXCLUDED.chunk_size,
          chunk_count = EXCLUDED.chunk_count,
          status = 'available',
          metadata = EXCLUDED.metadata,
          updated_at = now()
        RETURNING id::text AS "storageObjectId", object_key AS "objectKey"
        `,
        [
          userId,
          session.provider_key,
          objectKey,
          session.file_name,
          storedObject.sizeBytes,
          storedObject.checksum,
          session.chunk_size,
          session.received_chunks,
          JSON.stringify({
            uploadSessionId: sessionId,
            storageType: 'local_filesystem',
            storageRoot: this.objectStorage.root(),
            storagePath: storedObject.relativePath,
            absoluteStoragePath: storedObject.storagePath,
            localPath: session.local_path,
            ...session.metadata,
          }),
        ],
      );
      const storageObjectId = storage.rows[0]?.storageObjectId as string | undefined;
      let fileNodeId: string | undefined;
      const sessionMetadata = this.asRecord(session.metadata);
      const rootId = this.clean(sessionMetadata.rootId);
      if (rootId) {
        const parentId = this.clean(sessionMetadata.parentId);
        const parent = parentId
          ? await client.query<QueryResultRow>(
              `
              SELECT relative_path
              FROM file_nodes
              WHERE user_id = $1 AND id = $2 AND root_id = $3
              LIMIT 1
              `,
              [userId, parentId, rootId],
            )
          : null;
        const parentPath = this.clean(parent?.rows[0]?.relative_path) ?? '';
        const fileName = this.clean(sessionMetadata.nodeName) ?? session.file_name;
        const relativePath = this.clean(sessionMetadata.relativePath) ??
          [parentPath, fileName].filter(Boolean).join('/');
        const extension = fileName.includes('.') ? fileName.split('.').pop()?.toLowerCase() : null;
        const mimeType =
          this.clean(sessionMetadata.mimeType) ?? this.guessMimeType(fileName) ?? 'application/octet-stream';
        const node = await client.query<QueryResultRow>(
          `
          INSERT INTO file_nodes (
            user_id,
            node_uid,
            root_id,
            parent_id,
            node_type,
            name,
            relative_path,
            display_path,
            mime_type,
            extension,
            size_bytes,
            mtime,
            hash_sha256,
            preview_status,
            metadata
          ) VALUES ($1, $2, $3, $4, 'file', $5, $6, $6, $7, $8, $9, now(), $10, $11, $12::jsonb)
          ON CONFLICT (user_id, node_uid) DO UPDATE SET
            parent_id = EXCLUDED.parent_id,
            name = EXCLUDED.name,
            relative_path = EXCLUDED.relative_path,
            display_path = EXCLUDED.display_path,
            mime_type = EXCLUDED.mime_type,
            extension = EXCLUDED.extension,
            size_bytes = EXCLUDED.size_bytes,
            mtime = now(),
            hash_sha256 = EXCLUDED.hash_sha256,
            preview_status = EXCLUDED.preview_status,
            is_deleted = false,
            is_missing = false,
            metadata = file_nodes.metadata || EXCLUDED.metadata,
            updated_at = now()
          RETURNING id::text AS id
          `,
          [
            userId,
            `server_storage:${rootId}:${relativePath}`,
            rootId,
            parentId,
            fileName,
            relativePath,
            mimeType,
            extension,
            storedObject.sizeBytes,
            storedObject.checksum,
            mimeType.startsWith('text/') || mimeType.startsWith('image/') ? 'ready' : 'external',
            JSON.stringify({
              ...sessionMetadata,
              storageObjectId,
              uploadSessionId: sessionId,
              providerKey: session.provider_key,
            }),
          ],
        );
        fileNodeId = node.rows[0]?.id as string | undefined;
        if (fileNodeId && storageObjectId) {
          await client.query(
            `
            UPDATE file_storage_objects
            SET metadata = metadata || $3::jsonb,
                updated_at = now()
            WHERE user_id = $1 AND id = $2
            `,
            [userId, storageObjectId, JSON.stringify({ fileNodeId, rootId, relativePath })],
          );
          await client.query(
            `
            INSERT INTO file_identity_mappings (
              user_id,
              node_id,
              provider_key,
              provider_file_id,
              storage_object_id,
              hash_sha256,
              size_bytes,
              confidence,
              metadata
            ) VALUES ($1, $2, 'server_storage', $3, $4, $5, $6, 'high', $7::jsonb)
            ON CONFLICT (user_id, provider_key, provider_file_id) DO UPDATE SET
              node_id = EXCLUDED.node_id,
              storage_object_id = EXCLUDED.storage_object_id,
              hash_sha256 = EXCLUDED.hash_sha256,
              size_bytes = EXCLUDED.size_bytes,
              confidence = EXCLUDED.confidence,
              metadata = file_identity_mappings.metadata || EXCLUDED.metadata,
              updated_at = now()
            `,
            [
              userId,
              fileNodeId,
              objectKey,
              storageObjectId,
              storedObject.checksum,
              storedObject.sizeBytes,
              JSON.stringify({ source: 'web_upload', uploadSessionId: sessionId }),
            ],
          );
        }
      }
      await client.query(
        `
        UPDATE file_transfer_sessions
        SET status = 'completed',
            storage_object_id = $3,
            checksum = $4,
            updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, sessionId, storageObjectId, actualChecksum],
      );
      await this.recordAudit(client, userId, deviceId, 'files.upload.complete', {
        sessionId,
        storageObjectId,
        fileNodeId,
        checksum: storedObject.checksum,
        storagePath: storedObject.relativePath,
      });
      return { ok: true, storageObject: storage.rows[0], fileNodeId, checksum: storedObject.checksum };
    });
    return result;
  }

  async createDownloadSession(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const storageObjectId = this.clean(body.storageObjectId);
    const storage = storageObjectId
      ? await this.database.query<QueryResultRow>(
          `
          SELECT *
          FROM file_storage_objects
          WHERE user_id = $1 AND id = $2
          LIMIT 1
          `,
          [userId, storageObjectId],
        )
      : null;
    const storageRow = storage?.rows[0];
    const fileName = this.clean(body.fileName) ?? String(storageRow?.display_name ?? 'download');
    const totalBytes = this.readNumber(body.totalBytes, this.toNumber(storageRow?.size_bytes));
    const chunkSize = this.readNumber(body.chunkSize, this.toNumber(storageRow?.chunk_size) || 5 * 1024 * 1024);
    const expectedChunks =
      totalBytes <= 0 ? 0 : Math.ceil(totalBytes / Math.max(chunkSize, 1));
    const downloadSession = await this.database.transaction(async (client) => {
      const result = await client.query(
        `
        INSERT INTO file_transfer_sessions (
          user_id,
          provider_key,
          direction,
          file_name,
          remote_id,
          local_path,
          object_key,
          storage_object_id,
          total_bytes,
          chunk_size,
          expected_chunks,
          checksum,
          status,
          metadata,
          expires_at
        ) VALUES ($1, $2, 'download', $3, $4, $5, $6, $7, $8, $9, $10, $11, 'open', $12::jsonb, now() + interval '7 days')
        RETURNING
          id::text AS "sessionId",
          resume_token AS "resumeToken",
          status,
          chunk_size AS "chunkSize",
          total_bytes AS "totalBytes",
          expected_chunks AS "expectedChunks",
          checksum,
          storage_object_id::text AS "storageObjectId"
        `,
        [
          userId,
          this.clean(body.providerKey) ?? String(storageRow?.provider_key ?? 'server_storage'),
          fileName,
          this.clean(body.remoteId),
          this.clean(body.localPath),
          this.clean(body.objectKey) ?? String(storageRow?.object_key ?? ''),
          storageObjectId,
          totalBytes,
          chunkSize,
          expectedChunks,
          this.clean(body.checksum) ?? (storageRow?.checksum as string | undefined) ?? null,
          JSON.stringify(this.asRecord(body.metadata)),
        ],
      );
      const session = result.rows[0];
      await this.recordAudit(client, userId, deviceId, 'files.download.create_session', {
        sessionId: session.sessionId,
        storageObjectId,
        fileName,
        totalBytes,
        chunkSize,
        expectedChunks,
      });
      return session;
    });
    return { downloadSession };
  }

  async downloadRange(
    sessionId: string,
    query: FilesQuery,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const session = await this.findSession(this.database, userId, sessionId, 'download');
    if (!session) {
      return { ok: false, reason: 'download_session_missing' };
    }
    const start = this.readNumber(query.start, 0);
    const end = this.readNumber(query.end, Math.max(start, start + session.chunk_size - 1));
    if (!session.storage_object_id) {
      const sharedPath = await this.resolveSharedDownloadPath(userId, session);
      if (!sharedPath) {
        return { ok: false, reason: 'download_source_missing' };
      }
      try {
        const payload = await this.readLocalFileRange(sharedPath, start, end);
        return {
          ok: true,
          sessionId,
          range: { start, end: start + payload.length - 1 },
          chunks: [
            {
              chunkIndex: Math.floor(start / Math.max(session.chunk_size, 1)),
              startByte: start,
              endByte: start + payload.length - 1,
              sizeBytes: payload.length,
              checksum: this.sha256(payload),
              payloadBase64: payload.toString('base64'),
            },
          ],
          note: 'shared server folder file range',
        };
      } catch (error) {
        return {
          ok: false,
          reason: 'shared_source_read_failed',
          error: this.errorMessage(error),
        };
      }
    }
    const storage = await this.database.query<QueryResultRow>(
      `
      SELECT metadata
      FROM file_storage_objects
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, session.storage_object_id],
    );
    const storageMetadata = this.asRecord(storage.rows[0]?.metadata);
    const storedPath = this.clean(storageMetadata.storagePath);
    if (storedPath) {
      const payload = await this.objectStorage.readRange(storedPath, start, end);
      return {
        ok: true,
        sessionId,
        range: { start, end: start + payload.length - 1 },
        chunks: [
          {
            chunkIndex: Math.floor(start / Math.max(session.chunk_size, 1)),
            startByte: start,
            endByte: start + payload.length - 1,
            sizeBytes: payload.length,
            checksum: this.sha256(payload),
            payloadBase64: payload.toString('base64'),
          },
        ],
        note: 'local filesystem object storage range',
      };
    }
    const chunks = await this.database.query<QueryResultRow>(
      `
      SELECT
        c.chunk_index AS "chunkIndex",
        c.start_byte AS "startByte",
        c.end_byte AS "endByte",
        c.size_bytes AS "sizeBytes",
        c.checksum,
        encode(c.payload, 'base64') AS "payloadBase64"
      FROM file_transfer_chunks c
      INNER JOIN file_transfer_sessions s ON s.id = c.session_id
      WHERE c.user_id = $1
        AND s.storage_object_id = $2
        AND c.end_byte >= $3
        AND c.start_byte <= $4
      ORDER BY c.chunk_index ASC
      `,
      [userId, session.storage_object_id, start, end],
    );
    return {
      ok: true,
      sessionId,
      range: { start, end },
      chunks: chunks.rows,
      note: 'P10 returns resumable chunk payloads as base64 JSON; production storage can map this to HTTP Range.',
    };
  }

  async downloadStorageObject(
    objectId: string,
    query: FilesQuery,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const storage = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        display_name AS "displayName",
        size_bytes AS "sizeBytes",
        checksum,
        metadata
      FROM file_storage_objects
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, objectId],
    );
    const row = storage.rows[0];
    if (!row) {
      return { ok: false, reason: 'storage_object_not_found' };
    }
    const metadata = this.asRecord(row.metadata);
    const storedPath = this.clean(metadata.storagePath);
    if (!storedPath) {
      return { ok: false, reason: 'storage_path_missing' };
    }
    const start = this.readNumber(query.start, 0);
    const defaultEnd = Math.max(start, start + this.readNumber(query.limit, 5 * 1024 * 1024) - 1);
    const end = this.readNumber(query.end, defaultEnd);
    const payload = await this.objectStorage.readRange(storedPath, start, end);
    await this.recordFileOperation(this.database, userId, deviceId, 'file.storage.download_range', null, {
      storageObjectId: objectId,
      start,
      end: start + payload.length - 1,
      sizeBytes: payload.length,
    });
    return {
      ok: true,
      storageObjectId: objectId,
      fileName: row.displayName,
      totalBytes: this.toNumber(row.sizeBytes),
      checksum: row.checksum,
      range: { start, end: start + payload.length - 1 },
      sizeBytes: payload.length,
      payloadBase64: payload.toString('base64'),
    };
  }

  async transfers(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 100);
    const offset = this.readOffset(query.offset);
    const result = await this.database.query(
      `
      SELECT
        id::text AS "sessionId",
        provider_key AS "providerKey",
        direction,
        file_name AS "fileName",
        storage_object_id::text AS "storageObjectId",
        total_bytes AS "totalBytes",
        chunk_size AS "chunkSize",
        expected_chunks AS "expectedChunks",
        received_chunks AS "receivedChunks",
        received_bytes AS "receivedBytes",
        checksum,
        status,
        resume_token AS "resumeToken",
        error_message AS "errorMessage",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM file_transfer_sessions
      WHERE user_id = $1
        AND ($2::text IS NULL OR direction = $2)
        AND ($3::text IS NULL OR status = $3)
      ORDER BY updated_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, this.clean(query.direction), this.clean(query.status), limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, transfers: result.rows };
  }

  async transferProgress(sessionId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<
      QueryResultRow & {
        sessionId: string;
        providerKey: string;
        direction: string;
        fileName: string;
        storageObjectId: string | null;
        totalBytes: string | number;
        chunkSize: number;
        expectedChunks: number;
        receivedChunks: number;
        receivedBytes: string | number;
        checksum: string | null;
        status: string;
        resumeToken: string | null;
        errorMessage: string | null;
        createdAt: Date;
        updatedAt: Date;
        firstChunkAt: Date | null;
        lastChunkAt: Date | null;
      }
    >(
      `
      SELECT
        s.id::text AS "sessionId",
        s.provider_key AS "providerKey",
        s.direction,
        s.file_name AS "fileName",
        s.storage_object_id::text AS "storageObjectId",
        s.total_bytes AS "totalBytes",
        s.chunk_size AS "chunkSize",
        s.expected_chunks AS "expectedChunks",
        s.received_chunks AS "receivedChunks",
        s.received_bytes AS "receivedBytes",
        s.checksum,
        s.status,
        s.resume_token AS "resumeToken",
        s.error_message AS "errorMessage",
        s.created_at AS "createdAt",
        s.updated_at AS "updatedAt",
        MIN(c.created_at) AS "firstChunkAt",
        MAX(c.created_at) AS "lastChunkAt"
      FROM file_transfer_sessions s
      LEFT JOIN file_transfer_chunks c
        ON c.user_id = s.user_id AND c.session_id = s.id
      WHERE s.user_id = $1 AND s.id = $2
      GROUP BY s.id
      LIMIT 1
      `,
      [userId, sessionId],
    );
    const row = result.rows[0];
    if (!row) {
      return { ok: false, reason: 'transfer_not_found', sessionId };
    }

    const totalBytes = this.toNumber(row.totalBytes);
    const receivedBytes = this.toNumber(row.receivedBytes);
    const progress =
      totalBytes > 0 ? Math.max(0, Math.min(1, receivedBytes / totalBytes)) : 0;
    const startedAt = row.firstChunkAt ?? row.createdAt;
    const elapsedSeconds = Math.max(
      1,
      (new Date(row.updatedAt).getTime() - new Date(startedAt).getTime()) / 1000,
    );
    const bytesPerSecond = receivedBytes > 0 ? receivedBytes / elapsedSeconds : 0;

    return {
      ok: true,
      session: {
        sessionId: row.sessionId,
        providerKey: row.providerKey,
        direction: row.direction,
        fileName: row.fileName,
        storageObjectId: row.storageObjectId,
        totalBytes,
        chunkSize: row.chunkSize,
        expectedChunks: row.expectedChunks,
        receivedChunks: row.receivedChunks,
        receivedBytes,
        progress,
        percent: Math.round(progress * 10000) / 100,
        bytesPerSecond,
        checksum: row.checksum,
        status: row.status,
        resumeToken: row.resumeToken,
        errorMessage: row.errorMessage,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        firstChunkAt: row.firstChunkAt,
        lastChunkAt: row.lastChunkAt,
      },
    };
  }

  async versions(fileId: string, context: FlowPlanV2RequestContext) {
    return this.fileVersionService.versions(fileId, context);
  }

  async createVersionDownloadRequest(
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.createVersionDownloadRequest(
      versionId,
      body,
      context,
    );
  }

  async storageStatus() {
    return this.fileTransferService.storageStatus();
  }

  async storageObjects(query: FilesQuery, context: FlowPlanV2RequestContext) {
    return this.fileTransferService.storageObjects(query, context);
  }

  async registerStorageObject(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileTransferService.registerStorageObject(body, context);
  }

  async createKopiaSnapshot(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.createKopiaSnapshot(body, context);
  }

  async refreshKopiaVersions(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.refreshKopiaVersions(body, context);
  }

  async downloadVersionCopy(
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.downloadVersionCopy(versionId, body, context);
  }

  async prepareVersionRestore(
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.prepareVersionRestore(
      versionId,
      body,
      context,
    );
  }

  async conflicts(context: FlowPlanV2RequestContext) {
    return this.fileVersionService.conflicts(context);
  }

  async createConflict(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.createConflict(body, context);
  }

  async resolveConflict(
    conflictId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileVersionService.resolveConflict(conflictId, body, context);
  }

  async roots(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const search = this.search(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        r.id::text AS id,
        r.root_uid AS "rootUid",
        r.name,
        r.provider_type AS "providerType",
        r.root_uri AS "rootUri",
        r.root_display_path AS "rootDisplayPath",
        r.is_managed AS "isManaged",
        r.scan_status AS "scanStatus",
        r.last_scan_at AS "lastScanAt",
        r.last_error AS "lastError",
        r.sync_policy AS "syncPolicy",
        r.metadata,
        COALESCE(node_summary.node_count, 0)::int AS "nodeCount",
        COALESCE(node_summary.file_count, 0)::int AS "fileCount",
        COALESCE(node_summary.folder_count, 0)::int AS "folderCount",
        COALESCE(node_summary.total_bytes, 0)::bigint AS "totalBytes",
        node_summary.last_node_update_at AS "lastNodeUpdateAt",
        COALESCE(storage_summary.storage_object_count, 0)::int AS "storageObjectCount",
        COALESCE(storage_summary.storage_total_bytes, 0)::bigint AS "storageTotalBytes",
        last_operation.operation AS "lastOperation",
        last_operation.status AS "lastOperationStatus",
        last_operation.error_message AS "lastOperationError",
        last_operation.created_at AS "lastOperationAt",
        r.updated_at AS "updatedAt"
      FROM file_roots r
      LEFT JOIN LATERAL (
        SELECT
          COUNT(*)::int AS node_count,
          COUNT(*) FILTER (WHERE n.node_type = 'file')::int AS file_count,
          COUNT(*) FILTER (WHERE n.node_type = 'folder')::int AS folder_count,
          COALESCE(SUM(n.size_bytes) FILTER (WHERE n.node_type = 'file'), 0)::bigint AS total_bytes,
          MAX(n.updated_at) AS last_node_update_at
        FROM file_nodes n
        WHERE n.user_id = r.user_id
          AND n.root_id = r.id
          AND n.is_deleted = false
      ) node_summary ON true
      LEFT JOIN LATERAL (
        SELECT
          COUNT(*)::int AS storage_object_count,
          COALESCE(SUM(so.size_bytes), 0)::bigint AS storage_total_bytes
        FROM file_storage_objects so
        WHERE so.user_id = r.user_id
          AND so.metadata->>'rootId' = r.id::text
      ) storage_summary ON true
      LEFT JOIN LATERAL (
        SELECT
          op.operation,
          op.status,
          op.error_message,
          op.created_at
        FROM file_operation_logs op
        WHERE op.user_id = r.user_id
          AND op.metadata->>'rootId' = r.id::text
        ORDER BY op.created_at DESC
        LIMIT 1
      ) last_operation ON true
      WHERE r.user_id = $1
        AND ($2::text IS NULL OR r.name ILIKE $2 OR r.root_uri ILIKE $2 OR r.root_display_path ILIKE $2)
      ORDER BY r.updated_at DESC, r.name ASC
      `,
      [userId, search],
    );
    return { roots: result.rows };
  }

  async upsertRoot(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const providerType = this.clean(body.providerType) ?? 'server_storage';
    const providerTypeKey = providerType.toLowerCase();
    if (providerTypeKey === 'local' || providerTypeKey === 'client_local') {
      return {
        ok: false,
        reason: 'client_local_root_not_allowed',
        message:
          'file_roots are server-accessible cloud roots. Client local folders must be registered as device locations/bindings.',
      };
    }
    const requestedRootUri =
      this.clean(body.rootUri) ?? this.clean(body.localPath);
    const normalizedRootUri = this.normalizeServerRootUri(requestedRootUri);
    if (!normalizedRootUri) {
      return {
        ok: false,
        reason: 'absolute_server_root_required',
        message: 'Drive roots must use an absolute server filesystem path.',
      };
    }
    const rootUid =
      this.clean(body.rootUid) ?? `server-root:${normalizedRootUri}`;
    const result = await this.database.transaction(async (client) => {
      const row = await client.query<QueryResultRow>(
        `
        INSERT INTO file_roots (
          user_id,
          root_uid,
          name,
          provider_type,
          root_uri,
          root_display_path,
          device_id,
          is_managed,
          sync_policy,
          metadata
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)
        ON CONFLICT (user_id, root_uid) DO UPDATE SET
          name = EXCLUDED.name,
          provider_type = EXCLUDED.provider_type,
          root_uri = EXCLUDED.root_uri,
          root_display_path = EXCLUDED.root_display_path,
          device_id = EXCLUDED.device_id,
          is_managed = EXCLUDED.is_managed,
          sync_policy = EXCLUDED.sync_policy,
          metadata = file_roots.metadata || EXCLUDED.metadata,
          updated_at = now()
        RETURNING id::text AS id, root_uid AS "rootUid", name, root_uri AS "rootUri", scan_status AS "scanStatus"
        `,
        [
          userId,
          rootUid,
          this.clean(body.name) ?? this.basename(String(body.rootUri ?? rootUid)),
          providerType,
          normalizedRootUri,
          this.clean(body.rootDisplayPath) ?? normalizedRootUri,
          deviceId,
          Boolean(body.isManaged),
          this.clean(body.syncPolicy) ?? 'metadata_only',
          JSON.stringify(this.asRecord(body.metadata)),
        ],
      );
      await this.recordFileOperation(client, userId, deviceId, 'file.root.upsert', null, {
        rootUid,
        rootId: row.rows[0]?.id,
      });
      return row.rows[0];
    });
    return { ok: true, root: result };
  }

  async deleteDriveRoot(rootId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const deleted = await this.database.transaction(async (client) => {
      const rootResult = await client.query<QueryResultRow>(
        `
        SELECT
          r.id::text AS id,
          r.root_uid AS "rootUid",
          r.name,
          r.provider_type AS "providerType",
          r.root_uri AS "rootUri",
          r.root_display_path AS "rootDisplayPath",
          r.scan_status AS "scanStatus",
          r.last_scan_at AS "lastScanAt",
          r.last_error AS "lastError",
          COALESCE(node_summary.node_count, 0)::int AS "nodeCount",
          COALESCE(node_summary.file_count, 0)::int AS "fileCount",
          COALESCE(node_summary.folder_count, 0)::int AS "folderCount",
          COALESCE(node_summary.total_bytes, 0)::bigint AS "totalBytes",
          COALESCE(storage_summary.storage_object_count, 0)::int AS "storageObjectCount",
          COALESCE(storage_summary.storage_total_bytes, 0)::bigint AS "storageTotalBytes"
        FROM file_roots r
        LEFT JOIN LATERAL (
          SELECT
            COUNT(*)::int AS node_count,
            COUNT(*) FILTER (WHERE n.node_type = 'file')::int AS file_count,
            COUNT(*) FILTER (WHERE n.node_type = 'folder')::int AS folder_count,
            COALESCE(SUM(n.size_bytes) FILTER (WHERE n.node_type = 'file'), 0)::bigint AS total_bytes
          FROM file_nodes n
          WHERE n.user_id = r.user_id
            AND n.root_id = r.id
            AND n.is_deleted = false
        ) node_summary ON true
        LEFT JOIN LATERAL (
          SELECT
            COUNT(*)::int AS storage_object_count,
            COALESCE(SUM(so.size_bytes), 0)::bigint AS storage_total_bytes
          FROM file_storage_objects so
          WHERE so.user_id = r.user_id
            AND so.metadata->>'rootId' = r.id::text
        ) storage_summary ON true
        WHERE r.user_id = $1 AND r.id = $2
        LIMIT 1
        `,
        [userId, rootId],
      );
      const root = rootResult.rows[0];
      if (!root) {
        return null;
      }
      await client.query(
        `
        DELETE FROM file_roots
        WHERE user_id = $1 AND id = $2
        `,
        [userId, rootId],
      );
      const deletedCounts = {
        nodes: this.toNumber(root.nodeCount),
        files: this.toNumber(root.fileCount),
        folders: this.toNumber(root.folderCount),
        totalBytes: this.toNumber(root.totalBytes),
      };
      await this.recordFileOperation(client, userId, deviceId, 'file.drive.root.delete', null, {
        rootId,
        rootUid: root.rootUid,
        rootName: root.name,
        rootUri: root.rootUri,
        rootDisplayPath: root.rootDisplayPath,
        deletedCounts,
        storageObjectCount: this.toNumber(root.storageObjectCount),
        storageTotalBytes: this.toNumber(root.storageTotalBytes),
        storageObjectsRetained: true,
        physicalFilesDeleted: false,
        status: 'success',
      });
      return { root, deletedCounts };
    });
    if (!deleted) {
      return { ok: false, reason: 'root_not_found' };
    }
    return {
      ok: true,
      deletedRoot: {
        id: deleted.root.id,
        rootUid: deleted.root.rootUid,
        name: deleted.root.name,
        rootUri: deleted.root.rootUri,
        rootDisplayPath: deleted.root.rootDisplayPath,
      },
      deletedCounts: deleted.deletedCounts,
      storageObjectsRetained: true,
      physicalFilesDeleted: false,
    };
  }

  async fileNodes(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 300);
    const offset = this.readOffset(query.offset);
    const search = this.search(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        n.id::text AS id,
        n.node_uid AS "nodeUid",
        n.root_id::text AS "rootId",
        n.parent_id::text AS "parentId",
        n.node_type AS "nodeType",
        n.name,
        n.relative_path AS "relativePath",
        n.display_path AS "displayPath",
        n.local_path AS "localPath",
        n.mime_type AS "mimeType",
        n.extension,
        n.size_bytes AS "sizeBytes",
        n.mtime,
        n.hash_sha256 AS "hashSha256",
        n.preview_status AS "previewStatus",
        n.index_status AS "indexStatus",
        n.is_deleted AS "isDeleted",
        n.is_missing AS "isMissing",
        r.name AS "rootName",
        n.metadata,
        n.updated_at AS "updatedAt"
      FROM file_nodes n
      LEFT JOIN file_roots r ON r.user_id = n.user_id AND r.id = n.root_id
      WHERE n.user_id = $1
        AND ($2::uuid IS NULL OR n.root_id = $2)
        AND ($3::uuid IS NULL OR n.parent_id IS NOT DISTINCT FROM $3)
        AND ($4::text IS NULL OR n.name ILIKE $4 OR n.relative_path ILIKE $4 OR n.display_path ILIKE $4)
      ORDER BY n.node_type ASC, n.name ASC
      LIMIT $5 OFFSET $6
      `,
      [
        userId,
        this.clean(query.rootId),
        this.clean(query.parentId),
        search,
        limit,
        offset,
      ],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, nodes: result.rows };
  }

  async driveRoots(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const roots = await this.roots(query, context);
    return {
      ...roots,
      model: 'logical_cloud_drive',
      canonicalTree: 'file_nodes',
    };
  }

  async driveNodes(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const limit = this.readLimit(query.limit, 300);
    const offset = this.readOffset(query.offset);
    const search = this.search(query.q);
    const rootId = this.clean(query.rootId);
    const parentId = this.clean(query.parentId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        n.id::text AS id,
        n.node_uid AS "nodeUid",
        n.root_id::text AS "rootId",
        n.parent_id::text AS "parentId",
        n.node_type AS "nodeType",
        n.name,
        n.relative_path AS "relativePath",
        COALESCE(n.display_path, n.relative_path, n.name) AS "displayPath",
        n.local_path AS "localPath",
        n.provider_file_id AS "providerFileId",
        n.mime_type AS "mimeType",
        n.extension,
        n.size_bytes AS "sizeBytes",
        n.mtime,
        n.hash_sha256 AS "hashSha256",
        n.preview_status AS "previewStatus",
        n.index_status AS "indexStatus",
        n.is_deleted AS "isDeleted",
        n.is_missing AS "isMissing",
        r.name AS "rootName",
        r.provider_type AS "rootProviderType",
        r.root_uri AS "rootUri",
        r.root_display_path AS "rootDisplayPath",
        so.id::text AS "storageObjectId",
        so.provider_key AS "storageProviderKey",
        so.status AS "storageStatus",
        so.checksum AS "storageChecksum",
        dl.id::text AS "deviceLocationId",
        dl.local_path AS "deviceLocalPath",
        dl.availability AS "deviceAvailability",
        dl.last_seen_at AS "deviceLastSeenAt",
        COALESCE(loc.count, 0)::int AS "knownDeviceLocationCount",
        n.metadata,
        n.updated_at AS "updatedAt"
      FROM file_nodes n
      LEFT JOIN file_roots r ON r.user_id = n.user_id AND r.id = n.root_id
      LEFT JOIN file_storage_objects so
        ON so.user_id = n.user_id
       AND (
          so.id::text = n.metadata->>'storageObjectId'
          OR so.metadata->>'fileNodeId' = n.id::text
          OR (n.hash_sha256 IS NOT NULL AND so.checksum = n.hash_sha256)
       )
      LEFT JOIN file_node_device_locations dl
        ON dl.user_id = n.user_id
       AND dl.node_id = n.id
       AND dl.device_id = $7
      LEFT JOIN (
        SELECT user_id, node_id, COUNT(*) AS count
        FROM file_node_device_locations
        WHERE availability IN ('available', 'local', 'cached')
        GROUP BY user_id, node_id
      ) loc ON loc.user_id = n.user_id AND loc.node_id = n.id
      WHERE n.user_id = $1
        AND n.is_deleted = false
        AND ($2::uuid IS NULL OR n.root_id = $2)
        AND (
          ($4::text IS NOT NULL AND $3::uuid IS NULL)
          OR (
            $2::uuid IS NOT NULL
            AND $3::uuid IS NULL
            AND n.parent_id = (
              SELECT root_node.id
              FROM file_nodes root_node
              WHERE root_node.user_id = $1
                AND root_node.root_id = $2
                AND root_node.parent_id IS NULL
                AND root_node.relative_path = ''
                AND root_node.is_deleted = false
              LIMIT 1
            )
          )
          OR ($2::uuid IS NULL AND $3::uuid IS NULL AND n.parent_id IS NULL)
          OR n.parent_id IS NOT DISTINCT FROM $3
        )
        AND ($4::text IS NULL OR n.name ILIKE $4 OR n.relative_path ILIKE $4 OR n.display_path ILIKE $4)
      ORDER BY CASE n.node_type WHEN 'folder' THEN 0 ELSE 1 END, n.name ASC
      LIMIT $5 OFFSET $6
      `,
      [userId, rootId, parentId, search, limit, offset, deviceId],
    );
    return {
      limit,
      offset,
      hasMore: result.rows.length >= limit,
      nodes: result.rows.map((row) => this.driveNodeDto(row)),
    };
  }

  async driveNode(nodeId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        n.id::text AS id,
        n.node_uid AS "nodeUid",
        n.root_id::text AS "rootId",
        n.parent_id::text AS "parentId",
        n.node_type AS "nodeType",
        n.name,
        n.relative_path AS "relativePath",
        COALESCE(n.display_path, n.relative_path, n.name) AS "displayPath",
        n.local_path AS "localPath",
        n.provider_file_id AS "providerFileId",
        n.mime_type AS "mimeType",
        n.extension,
        n.size_bytes AS "sizeBytes",
        n.mtime,
        n.hash_sha256 AS "hashSha256",
        n.preview_status AS "previewStatus",
        n.index_status AS "indexStatus",
        n.is_deleted AS "isDeleted",
        n.is_missing AS "isMissing",
        r.name AS "rootName",
        r.provider_type AS "rootProviderType",
        r.root_uri AS "rootUri",
        r.root_display_path AS "rootDisplayPath",
        so.id::text AS "storageObjectId",
        so.provider_key AS "storageProviderKey",
        so.status AS "storageStatus",
        so.checksum AS "storageChecksum",
        dl.id::text AS "deviceLocationId",
        dl.local_path AS "deviceLocalPath",
        dl.availability AS "deviceAvailability",
        dl.last_seen_at AS "deviceLastSeenAt",
        COALESCE(loc.count, 0)::int AS "knownDeviceLocationCount",
        n.metadata,
        n.updated_at AS "updatedAt"
      FROM file_nodes n
      LEFT JOIN file_roots r ON r.user_id = n.user_id AND r.id = n.root_id
      LEFT JOIN file_storage_objects so
        ON so.user_id = n.user_id
       AND (
          so.id::text = n.metadata->>'storageObjectId'
          OR so.metadata->>'fileNodeId' = n.id::text
          OR (n.hash_sha256 IS NOT NULL AND so.checksum = n.hash_sha256)
       )
      LEFT JOIN file_node_device_locations dl
        ON dl.user_id = n.user_id
       AND dl.node_id = n.id
       AND dl.device_id = $3
      LEFT JOIN (
        SELECT user_id, node_id, COUNT(*) AS count
        FROM file_node_device_locations
        WHERE availability IN ('available', 'local', 'cached')
        GROUP BY user_id, node_id
      ) loc ON loc.user_id = n.user_id AND loc.node_id = n.id
      WHERE n.user_id = $1 AND n.id = $2
      LIMIT 1
      `,
      [userId, nodeId, deviceId],
    );
    return { node: result.rows[0] ? this.driveNodeDto(result.rows[0]) : null };
  }

  async driveOpenPlan(
    nodeId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const nodeResult = await this.driveNode(nodeId, context);
    const node = nodeResult.node;
    if (!node) {
      return { ok: false, reason: 'node_not_found' };
    }
    const localIdentity = this.asRecord(body.localIdentity);
    const sameContent = this.compareIdentity(node, localIdentity);
    const verifiedLocalPath =
      this.clean(localIdentity.localPath) ?? this.clean(node.currentDevice?.localPath);
    const verifiedIdentity =
      sameContent.matched &&
      (sameContent.confidence === 'hash' || sameContent.confidence === 'provider_id');
    const canOpenLocal =
      Boolean(verifiedLocalPath) &&
      (node.currentDevice?.availability === 'available' || Boolean(localIdentity.localPath)) &&
      verifiedIdentity;
    const comparableLocalCopy =
      Boolean(verifiedLocalPath) && sameContent.confidence !== 'none';
    const action = canOpenLocal
      ? 'open_local'
      : comparableLocalCopy
        ? 'conflict_or_download_required'
      : node.storage?.storageObjectId || this.clean(node.serverPath)
        ? 'download_then_open'
        : 'needs_upload_or_relink';
    await this.recordFileOperation(this.database, userId, deviceId, 'file.drive.open_plan', nodeId, {
      action,
      identity: sameContent,
      localPath: verifiedLocalPath,
      storageObjectId: node.storage?.storageObjectId,
    });
    return {
      ok: true,
      action,
      node,
      identity: sameContent,
      requiresConfirmation: action !== 'open_local',
    };
  }

  async upsertDriveDeviceLocation(
    nodeId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const localPath = this.clean(body.localPath);
    const availability = this.clean(body.availability) ?? 'available';
    const result = await this.database.transaction(async (client) => {
      const row = await client.query<QueryResultRow>(
        `
        INSERT INTO file_node_device_locations (
          user_id,
          node_id,
          device_id,
          local_path,
          availability,
          metadata,
          last_seen_at
        ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, now())
        ON CONFLICT (user_id, node_id, device_id) DO UPDATE SET
          local_path = EXCLUDED.local_path,
          availability = EXCLUDED.availability,
          metadata = file_node_device_locations.metadata || EXCLUDED.metadata,
          last_seen_at = now()
        RETURNING id::text AS id, node_id::text AS "nodeId", local_path AS "localPath", availability
        `,
        [
          userId,
          nodeId,
          deviceId,
          localPath,
          availability,
          JSON.stringify(this.asRecord(body.metadata)),
        ],
      );
      await this.recordFileOperation(client, userId, deviceId, 'file.drive.device_location.upsert', nodeId, {
        localPath,
        availability,
      });
      return row.rows[0];
    });
    return { ok: true, location: result };
  }

  async createDriveDownloadRequest(
    nodeId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.devicesService.ensureDevice(context);
    const node = (await this.driveNode(nodeId, context)).node;
    if (!node) {
      return { ok: false, reason: 'node_not_found' };
    }
    if (node.nodeType !== 'file') {
      return { ok: false, reason: 'node_is_not_file', node };
    }
    const serverPath = this.clean(node.serverPath);
    if (!node.storage?.storageObjectId && !serverPath) {
      return { ok: false, reason: 'download_source_missing', node };
    }
    const session = await this.createDownloadSession(
      {
        storageObjectId: node.storage?.storageObjectId,
        fileName: node.name,
        totalBytes: node.sizeBytes,
        checksum: node.storage?.checksum ?? node.hashSha256,
        metadata: {
          nodeId,
          rootId: node.rootId,
          sourcePath: serverPath,
          sourceType: node.storage?.storageObjectId
            ? 'storage_object'
            : 'shared_server_path',
          targetPath: this.clean(body.targetPath),
          requestSource: 'drive_download_request',
        },
      },
      context,
    );
    return { ok: true, node, ...session };
  }

  async scanDriveRoot(
    rootId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileTreeService.scanDriveRoot(rootId, body, context);
  }

  async relinkDriveNode(
    nodeId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const localPath = this.clean(body.localPath);
    if (!localPath) {
      return { ok: false, reason: 'localPath_required' };
    }
    const result = await this.database.transaction(async (client) => {
      const node = await client.query<QueryResultRow>(
        `
        UPDATE file_nodes
        SET
          local_path = $3,
          is_missing = false,
          metadata = metadata || $4::jsonb,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, node_uid AS "nodeUid", name
        `,
        [
          userId,
          nodeId,
          localPath,
          JSON.stringify({
            relinkedAt: new Date().toISOString(),
            relinkReason: this.clean(body.reason),
          }),
        ],
      );
      await client.query(
        `
        INSERT INTO file_node_device_locations (
          user_id, node_id, device_id, local_path, availability, metadata, last_seen_at
        ) VALUES ($1, $2, $3, $4, 'available', $5::jsonb, now())
        ON CONFLICT (user_id, node_id, device_id) DO UPDATE SET
          local_path = EXCLUDED.local_path,
          availability = 'available',
          metadata = file_node_device_locations.metadata || EXCLUDED.metadata,
          last_seen_at = now()
        `,
        [
          userId,
          nodeId,
          deviceId,
          localPath,
          JSON.stringify(this.asRecord(body.identity)),
        ],
      );
      await this.recordFileOperation(client, userId, deviceId, 'file.drive.node.relink', nodeId, {
        localPath,
        identity: this.asRecord(body.identity),
      });
      return node.rows[0] ?? null;
    });
    return { ok: Boolean(result), node: result };
  }

  async applyNodeSnapshot(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.fileTreeService.applyNodeSnapshot(body, context);
  }

  async logNodeOperation(
    nodeId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.recordFileOperation(this.database, userId, deviceId, this.clean(body.operation) ?? 'file.open', nodeId, {
      sourcePath: this.clean(body.sourcePath),
      targetPath: this.clean(body.targetPath),
      status: this.clean(body.status) ?? 'success',
      errorMessage: this.clean(body.errorMessage),
      metadata: this.asRecord(body.metadata),
    });
    return { ok: true };
  }

  async linkNodeToEntity(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const nodeId = this.clean(body.nodeId);
    const entityType = this.clean(body.entityType);
    const entityId = this.clean(body.entityId);
    if (!nodeId || !entityType || !entityId) {
      return { ok: false, error: 'nodeId, entityType and entityId are required' };
    }
    const result = await this.database.transaction(async (client) => {
      const link = await client.query<QueryResultRow>(
        `
        INSERT INTO file_context_links (
          user_id,
          link_uid,
          entity_type,
          entity_id,
          target_type,
          target_id,
          relation_type,
          confidence,
          reason,
          status,
          confirmed_at
        ) VALUES ($1, $2, $3, $4, 'file_node', $5, $6, $7, $8, $9, now())
        ON CONFLICT (user_id, link_uid) DO UPDATE SET
          relation_type = EXCLUDED.relation_type,
          confidence = EXCLUDED.confidence,
          reason = EXCLUDED.reason,
          status = EXCLUDED.status,
          confirmed_at = now(),
          updated_at = now()
        RETURNING id::text AS id, link_uid AS "linkUid"
        `,
        [
          userId,
          this.clean(body.linkUid) ?? `file-link:${entityType}:${entityId}:${nodeId}`,
          entityType,
          entityId,
          nodeId,
          this.clean(body.relationType) ?? 'manual',
          this.readNumber(body.confidence, 1),
          this.clean(body.reason),
          this.clean(body.status) ?? 'confirmed',
        ],
      );
      await this.recordFileOperation(client, userId, deviceId, 'file.context.link', nodeId, {
        entityType,
        entityId,
        linkId: link.rows[0]?.id,
      });
      return link.rows[0];
    });
    return { ok: true, link: result };
  }

  async contextLinks(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        l.id::text AS id,
        l.link_uid AS "linkUid",
        l.entity_type AS "entityType",
        l.entity_id AS "entityId",
        l.target_type AS "targetType",
        l.target_id AS "targetId",
        l.relation_type AS "relationType",
        l.confidence,
        l.reason,
        l.status,
        n.name AS "nodeName",
        n.display_path AS "displayPath",
        n.local_path AS "localPath",
        l.updated_at AS "updatedAt"
      FROM file_context_links l
      LEFT JOIN file_nodes n ON n.user_id = l.user_id AND n.id::text = l.target_id
      WHERE l.user_id = $1
        AND ($2::text IS NULL OR l.entity_type = $2)
        AND ($3::text IS NULL OR l.entity_id = $3)
      ORDER BY l.updated_at DESC
      LIMIT 200
      `,
      [userId, this.clean(query.entityType), this.clean(query.entityId)],
    );
    return { links: result.rows };
  }

  async recommendations(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        r.id::text AS id,
        r.entity_type AS "entityType",
        r.entity_id AS "entityId",
        r.node_id::text AS "nodeId",
        n.name AS "nodeName",
        n.display_path AS "displayPath",
        r.reason,
        r.score,
        r.status,
        r.created_at AS "createdAt",
        r.updated_at AS "updatedAt"
      FROM file_recommendations r
      LEFT JOIN file_nodes n ON n.user_id = r.user_id AND n.id = r.node_id
      WHERE r.user_id = $1
        AND ($2::text IS NULL OR r.entity_type = $2)
        AND ($3::text IS NULL OR r.entity_id = $3)
      ORDER BY r.score DESC, r.updated_at DESC
      LIMIT 100
      `,
      [userId, this.clean(query.entityType), this.clean(query.entityId)],
    );
    return { recommendations: result.rows };
  }

  async reviewRecommendation(
    recommendationId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const status = this.clean(body.status) ?? 'accepted';
    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE file_recommendations
        SET status = $3, updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, entity_type AS "entityType", entity_id AS "entityId", node_id::text AS "nodeId", status
        `,
        [userId, recommendationId, status],
      );
      const row = updated.rows[0];
      if (row && status === 'accepted') {
        await client.query(
          `
          INSERT INTO file_context_links (
            user_id, link_uid, entity_type, entity_id, target_type, target_id, relation_type, confidence, reason, status, confirmed_at
          ) VALUES ($1, $2, $3, $4, 'file_node', $5, 'recommendation', 0.75, 'accepted recommendation', 'confirmed', now())
          ON CONFLICT (user_id, link_uid) DO NOTHING
          `,
          [
            userId,
            `file-rec:${recommendationId}`,
            row.entityType,
            row.entityId,
            row.nodeId,
          ],
        );
      }
      await this.recordFileOperation(client, userId, deviceId, 'file.recommendation.review', row?.nodeId ?? null, {
        recommendationId,
        status,
      });
      return row ?? null;
    });
    return { ok: Boolean(result), recommendation: result };
  }

  async upsertNetworkPresence(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.fileTransferService.upsertNetworkPresence(body, context);
  }

  async networkPresence(context: FlowPlanV2RequestContext) {
    return this.fileTransferService.networkPresence(context);
  }

  async transferCandidates(sessionId: string, context: FlowPlanV2RequestContext) {
    return this.fileTransferService.transferCandidates(sessionId, context);
  }

  async upsertTransferCandidate(
    sessionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileTransferService.upsertTransferCandidate(sessionId, body, context);
  }

  async appendTransferEvent(
    sessionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    return this.fileTransferService.appendTransferEvent(sessionId, body, context);
  }

  private driveNodeDto(row: QueryResultRow) {
    const deviceLocalPath = this.clean(row.deviceLocalPath);
    const deviceAvailability = this.clean(row.deviceAvailability);
    const storageObjectId = this.clean(row.storageObjectId);
    const serverPath = this.clean(row.localPath);
    const metadata = this.asRecord(row.metadata);
    const availability = row.isMissing
      ? 'missing'
      : deviceAvailability === 'available' || deviceAvailability === 'local'
        ? 'local'
        : storageObjectId || serverPath
          ? 'remote_only'
          : 'metadata_only';
    return {
      id: row.id,
      nodeUid: row.nodeUid,
      rootId: row.rootId,
      parentId: row.parentId,
      nodeType: row.nodeType,
      name: row.name,
      displayName: row.name,
      relativePath: row.relativePath,
      displayPath: row.displayPath,
      localPath: deviceLocalPath,
      serverPath,
      providerFileId: row.providerFileId,
      mimeType: row.mimeType,
      extension: row.extension,
      sizeBytes: this.toNumber(row.sizeBytes),
      mtime: row.mtime,
      hashSha256: row.hashSha256,
      previewStatus: row.previewStatus,
      indexStatus: row.indexStatus,
      isDeleted: row.isDeleted,
      isMissing: row.isMissing,
      availability,
      root: {
        id: row.rootId,
        name: row.rootName,
        providerType: row.rootProviderType,
        rootUri: row.rootUri,
        rootDisplayPath: row.rootDisplayPath,
      },
      storage: storageObjectId || serverPath
        ? {
            storageObjectId: storageObjectId ?? null,
            providerKey: row.storageProviderKey ?? 'server_shared_folder',
            status: row.storageStatus ?? 'available',
            checksum: row.storageChecksum,
            sourceType: storageObjectId ? 'storage_object' : 'shared_server_path',
          }
        : null,
      currentDevice: deviceLocalPath || deviceAvailability
        ? {
            locationId: row.deviceLocationId,
            localPath: deviceLocalPath,
            availability: deviceAvailability ?? 'available',
            lastSeenAt: row.deviceLastSeenAt,
          }
        : null,
      knownDeviceLocationCount: this.toNumber(row.knownDeviceLocationCount),
      identity: {
        hashSha256: row.hashSha256,
        storageChecksum: row.storageChecksum,
        providerFileId: row.providerFileId,
        contentHash: metadata.contentHash ?? metadata.sha256 ?? null,
      },
      metadata,
      updatedAt: row.updatedAt,
    };
  }

  private compareIdentity(
    node: Record<string, unknown>,
    localIdentity: Record<string, unknown>,
  ) {
    const identity = this.asRecord(node.identity);
    const nodeHash =
      this.clean(identity.hashSha256) ??
      this.clean(identity.storageChecksum) ??
      this.clean(identity.contentHash);
    const localHash =
      this.clean(localIdentity.hashSha256) ??
      this.clean(localIdentity.checksum) ??
      this.clean(localIdentity.contentHash);
    if (nodeHash && localHash) {
      return {
        matched: nodeHash === localHash,
        confidence: 'hash',
        reason: nodeHash === localHash ? 'sha256/content hash matches' : 'hash differs',
      };
    }
    const providerId = this.clean(identity.providerFileId);
    const localProviderId = this.clean(localIdentity.providerFileId);
    if (providerId && localProviderId) {
      return {
        matched: providerId === localProviderId,
        confidence: 'provider_id',
        reason: providerId === localProviderId ? 'provider file id matches' : 'provider file id differs',
      };
    }
    const nodeSize = this.toNumber(node.sizeBytes);
    const localSize = this.toNumber(localIdentity.sizeBytes);
    const nodeMtime = this.clean(node.mtime);
    const localMtime = this.clean(localIdentity.modifiedAt) ?? this.clean(localIdentity.mtime);
    if (nodeSize > 0 && localSize > 0 && nodeSize === localSize) {
      return {
        matched: !nodeMtime || !localMtime || nodeMtime === localMtime,
        confidence: 'size_mtime',
        reason: 'matched by size and optional modified time; verify hash when possible',
      };
    }
    return {
      matched: false,
      confidence: 'none',
      reason: 'no comparable identity fields',
    };
  }

  private async resolveSharedDownloadPath(
    userId: string,
    session: SessionRow,
  ): Promise<string | null> {
    const metadata = this.asRecord(session.metadata);
    const sourcePath = this.clean(metadata.sourcePath);
    if (!sourcePath) {
      return null;
    }
    const rootId = this.clean(metadata.rootId);
    if (!rootId) {
      return null;
    }
    const rootResult = await this.database.query<QueryResultRow>(
      `
      SELECT root_uri AS "rootUri"
      FROM file_roots
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, rootId],
    );
    const rootUri = this.clean(rootResult.rows[0]?.rootUri);
    if (!rootUri) {
      return null;
    }
    const normalizedRoot = rootUri.replace(/\\/g, '/').replace(/\/$/, '');
    const normalizedSource = sourcePath.replace(/\\/g, '/');
    if (
      !normalizedSource.startsWith(normalizedRoot + '/') &&
      normalizedSource !== normalizedRoot
    ) {
      return null;
    }
    return sourcePath;
  }

  private async readLocalFileRange(
    filePath: string,
    start: number,
    endInclusive: number,
  ): Promise<Buffer> {
    const fileStat = await stat(filePath);
    const safeStart = Math.max(0, Math.min(start, fileStat.size));
    const safeEnd = Math.max(safeStart - 1, Math.min(endInclusive, fileStat.size - 1));
    if (safeEnd < safeStart) {
      return Buffer.alloc(0);
    }
    const handle = await open(filePath, 'r');
    try {
      const buffer = Buffer.alloc(safeEnd - safeStart + 1);
      await handle.read(buffer, 0, buffer.length, safeStart);
      return buffer;
    } finally {
      await handle.close();
    }
  }

  private guessMimeType(path: string) {
    const lower = path.toLowerCase();
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'text/yaml';
    if (lower.endsWith('.log')) return 'text/plain';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return null;
  }

  private async ensureDefaultProviders(userId: string) {
    await this.database.query(
      `
      INSERT INTO file_providers (
        user_id,
        provider_key,
        provider_type,
        display_name,
        priority,
        status,
        sync_mode,
        capabilities
      ) VALUES
        ($1, 'server_storage', 'server_storage', '服务端存储', 10, 'enabled', 'primary', '{"upload":true,"download":true,"range":true,"chunks":true}'::jsonb),
        ($1, 'onedrive', 'onedrive', 'OneDrive', 20, 'available', 'mirror', '{"tree":true,"upload":false,"download":false,"externalAuth":true}'::jsonb),
        ($1, 'local', 'local', '本地缓存', 30, 'enabled', 'cache', '{"openLocal":true,"mirror":true}'::jsonb)
      ON CONFLICT (user_id, provider_key) DO NOTHING
      `,
      [userId],
    );
  }

  private async ensureProvider(
    client: TransactionClient,
    userId: string,
    providerKey: string,
  ) {
    await client.query(
      `
      INSERT INTO file_providers (
        user_id,
        provider_key,
        provider_type,
        display_name,
        status,
        sync_mode
      ) VALUES ($1, $2, $2, $2, 'available', 'manual')
      ON CONFLICT (user_id, provider_key) DO NOTHING
      `,
      [userId, providerKey],
    );
  }

  private async findSession(
    client: Pick<DatabaseService | TransactionClient, 'query'>,
    userId: string,
    sessionId: string,
    direction: 'upload' | 'download',
  ) {
    const result = await client.query<SessionRow>(
      `
      SELECT *
      FROM file_transfer_sessions
      WHERE user_id = $1 AND id = $2 AND direction = $3
      LIMIT 1
      `,
      [userId, sessionId, direction],
    );
    return result.rows[0] ?? null;
  }

  private async refreshSessionProgress(
    client: TransactionClient,
    userId: string,
    sessionId: string,
  ) {
    await client.query(
      `
      UPDATE file_transfer_sessions s
      SET
        received_chunks = progress.received_chunks,
        received_bytes = progress.received_bytes,
        status = 'open',
        updated_at = now()
      FROM (
        SELECT
          COUNT(*)::int AS received_chunks,
          COALESCE(SUM(size_bytes), 0)::bigint AS received_bytes
        FROM file_transfer_chunks
        WHERE user_id = $1 AND session_id = $2 AND status = 'received'
      ) progress
      WHERE s.user_id = $1 AND s.id = $2
      `,
      [userId, sessionId],
    );
  }

  private async recordFileOperation(
    client: Pick<DatabaseService | TransactionClient, 'query'>,
    userId: string,
    deviceId: string,
    operation: string,
    nodeId: string | null,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO file_operation_logs (
        user_id,
        device_id,
        operation,
        node_id,
        source_path,
        target_path,
        status,
        error_message,
        metadata
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
      `,
      [
        userId,
        deviceId,
        operation,
        nodeId,
        this.clean(details.sourcePath),
        this.clean(details.targetPath),
        this.clean(details.status) ?? 'success',
        this.clean(details.errorMessage),
        JSON.stringify(details),
      ],
    );
    await this.recordAudit(client, userId, deviceId, operation, {
      ...details,
      nodeId,
    });
  }

  private sessionDto(session: SessionRow | null) {
    if (!session) {
      return null;
    }
    return {
      sessionId: session.id,
      providerKey: session.provider_key,
      direction: session.direction,
      fileName: session.file_name,
      storageObjectId: session.storage_object_id,
      totalBytes: this.toNumber(session.total_bytes),
      chunkSize: session.chunk_size,
      expectedChunks: session.expected_chunks,
      receivedChunks: session.received_chunks,
      receivedBytes: this.toNumber(session.received_bytes),
      status: session.status,
      checksum: session.checksum,
    };
  }

  private async recordAudit(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    action: string,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id,
        device_id,
        actor,
        action,
        entity_type,
        entity_id,
        summary,
        metadata
      ) VALUES ($1, $2, 'server', $3, 'file', $4, $3, $5::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        details.rootId ??
          details.nodeId ??
          details.sessionId ??
          details.providerKey ??
          details.conflictId ??
          null,
        JSON.stringify(details),
      ],
    );
  }

  private basename(path: string) {
    const normalized = path.replace(/\\/g, '/');
    return normalized.split('/').filter(Boolean).pop() ?? path;
  }

  private normalizeServerRootUri(path: string | null) {
    if (!path) {
      return null;
    }
    if (path.startsWith('/')) {
      return posix.normalize(path);
    }
    if (win32.isAbsolute(path)) {
      return win32.normalize(path);
    }
    if (posix.isAbsolute(path)) {
      return posix.normalize(path);
    }
    return null;
  }

  private sha256(buffer: Buffer) {
    return createHash('sha256').update(buffer).digest('hex');
  }

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }

  private search(value: string | undefined) {
    const cleaned = this.clean(value);
    return cleaned ? `%${cleaned}%` : null;
  }

  private clean(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : null;
  }

  private asRecord(value: unknown): Record<string, unknown> {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
    return {};
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.max(1, Math.min(1000, Math.trunc(parsed)));
  }

  private readOffset(value: string | undefined) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    return Math.max(0, Math.trunc(parsed));
  }

  private readNumber(value: unknown, fallback: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.max(0, Math.trunc(parsed));
  }

  private readNullableNumber(value: unknown) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : null;
  }

  private readDate(value: unknown) {
    if (typeof value !== 'string' || value.trim().length === 0) {
      return null;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  private toNumber(value: unknown) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
