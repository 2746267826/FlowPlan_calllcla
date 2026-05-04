import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { readdir, stat } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

type DriveScanProgress = {
  scanned: number;
  maxNodes: number;
  currentPath: string;
  queuedFolders: number;
  phase: 'reading' | 'collected';
};

@Injectable()
export class FileTreeService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async scanDriveRoot(
    rootId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const rootResult = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, root_uri AS "rootUri", root_display_path AS "rootDisplayPath", name
      FROM file_roots
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, rootId],
    );
    const root = rootResult.rows[0];
    const requestedRootPath = this.clean(body.rootPath);
    const rootPath = this.clean(root?.rootUri);
    if (!root || !rootPath) {
      return { ok: false, reason: 'root_not_found_or_path_missing', applied: 0 };
    }
    if (requestedRootPath && requestedRootPath !== rootPath) {
      await this.recordFileOperation(this.database, userId, deviceId, 'file.drive.root.scan_path_override_ignored', null, {
        rootId,
        requestedRootPath,
        serverRootPath: rootPath,
      });
    }
    const startedAt = new Date();
    const maxNodes = this.readNumber(body.maxNodes, 5000);
    const logPrefix = `[drive-scan:${rootId}]`;
    console.log(
      `${logPrefix} start name="${String(root.name ?? '')}" rootPath="${rootPath}" maxNodes=${maxNodes}`,
    );
    await this.database.query(
      `
      UPDATE file_roots
      SET
        scan_status = 'scanning',
        last_error = NULL,
        metadata = metadata || $3::jsonb,
        updated_at = now()
      WHERE user_id = $1 AND id = $2
      `,
      [
        userId,
        rootId,
        JSON.stringify({
          lastScan: {
            status: 'scanning',
            startedAt: startedAt.toISOString(),
            maxNodes,
            rootPath,
          },
        }),
      ],
    );
    const nodes: Record<string, unknown>[] = [];
    let lastProgressAt = 0;
    let lastProgressCount = 0;
    const publishProgress = async (progress: DriveScanProgress) => {
      const now = Date.now();
      const shouldPublish =
        progress.scanned === 0 ||
        progress.scanned >= maxNodes ||
        progress.scanned - lastProgressCount >= 100 ||
        now - lastProgressAt >= 2000;
      if (!shouldPublish) {
        return;
      }
      lastProgressAt = now;
      lastProgressCount = progress.scanned;
      const durationMs = now - startedAt.getTime();
      const progressMessage = `${progress.phase}: ${progress.scanned}/${maxNodes} nodes, current=${progress.currentPath}`;
      console.log(
        `${logPrefix} ${progressMessage}, queuedFolders=${progress.queuedFolders}, durationMs=${durationMs}`,
      );
      await this.database.query(
        `
        UPDATE file_roots
        SET
          metadata = metadata || $3::jsonb,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [
          userId,
          rootId,
          JSON.stringify({
            lastScan: {
              status: 'scanning',
              startedAt: startedAt.toISOString(),
              lastProgressAt: new Date(now).toISOString(),
              durationMs,
              maxNodes,
              rootPath,
              scanned: progress.scanned,
              currentPath: progress.currentPath,
              queuedFolders: progress.queuedFolders,
              phase: progress.phase,
              progressMessage,
              reachedMaxNodes: progress.scanned >= maxNodes,
            },
          }),
        ],
      );
    };
    try {
      await this.collectLocalNodesForRoot(
        userId,
        rootId,
        rootPath,
        maxNodes,
        nodes,
        publishProgress,
      );
    } catch (error) {
      const failedAt = new Date();
      const errorMessage = this.errorMessage(error);
      console.log(
        `${logPrefix} failed scanned=${nodes.length}/${maxNodes} durationMs=${failedAt.getTime() - startedAt.getTime()} error="${errorMessage}"`,
      );
      await this.database.query(
        `
        UPDATE file_roots
        SET
          scan_status = 'failed',
          last_error = $3,
          metadata = metadata || $4::jsonb,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [
          userId,
          rootId,
          errorMessage,
          JSON.stringify({
            lastScan: {
              status: 'failed',
              startedAt: startedAt.toISOString(),
              finishedAt: failedAt.toISOString(),
              durationMs: failedAt.getTime() - startedAt.getTime(),
              maxNodes,
              rootPath,
              scanned: nodes.length,
              currentPath: nodes.length > 0 ? this.clean(nodes[nodes.length - 1]?.localPath) : rootPath,
              progressMessage: `failed after ${nodes.length}/${maxNodes} nodes: ${errorMessage}`,
              error: errorMessage,
            },
          }),
        ],
      );
      await this.recordFileOperation(this.database, userId, deviceId, 'file.drive.root.scan', null, {
        rootId,
        rootPath,
        status: 'failed',
        errorMessage,
        scanned: nodes.length,
        durationMs: failedAt.getTime() - startedAt.getTime(),
      });
      return { ok: false, reason: 'scan_failed', error: errorMessage, applied: 0 };
    }
    const applied = await this.applyNodeSnapshot(
      {
        rootId,
        nodes,
        scanStatus: 'completed',
        scanDiagnostic: {
          status: 'completed',
          startedAt: startedAt.toISOString(),
          maxNodes,
          rootPath,
          scanned: nodes.length,
          reachedMaxNodes: nodes.length >= maxNodes,
          progressMessage: `collected ${nodes.length}/${maxNodes} nodes; applying snapshot`,
        },
      },
      context,
    );
    const completedAt = new Date();
    console.log(
      `${logPrefix} completed scanned=${nodes.length}/${maxNodes} applied=${applied.applied} durationMs=${completedAt.getTime() - startedAt.getTime()}`,
    );
    await this.recordFileOperation(this.database, userId, deviceId, 'file.drive.root.scan', null, {
      rootId,
      rootPath,
      status: 'success',
      scanned: nodes.length,
      applied: applied.applied,
      durationMs: completedAt.getTime() - startedAt.getTime(),
    });
    return { ...applied, ok: true, rootId, scanned: nodes.length };
  }

  async applyNodeSnapshot(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const rootId = this.clean(body.rootId);
    const nodes = Array.isArray(body.nodes) ? body.nodes : [];
    if (!rootId) {
      return { ok: false, error: 'rootId is required', applied: 0 };
    }
    const result = await this.database.transaction(async (client) => {
      let applied = 0;
      for (const item of nodes) {
        const node = this.asRecord(item);
        const nodeUid =
          this.clean(node.nodeUid) ??
          `node:${rootId}:${this.clean(node.relativePath) ?? randomUUID()}`;
        const parentUid = this.clean(node.parentNodeUid) ?? this.clean(node.parentUid);
        await client.query(
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
            provider_file_id,
            local_path,
            mime_type,
            extension,
            size_bytes,
            mtime,
            ctime,
            hash_sha256,
            thumbnail_status,
            preview_status,
            index_status,
            is_deleted,
            is_missing,
            metadata
          ) VALUES (
            $1, $2, $3,
            (SELECT id FROM file_nodes WHERE user_id = $1 AND node_uid = $4 LIMIT 1),
            $5, $6, $7, $8, $9, $10, $11, $12, $13,
            $14::timestamptz, $15::timestamptz, $16, $17, $18, $19, $20, $21, $22::jsonb
          )
          ON CONFLICT (user_id, node_uid) DO UPDATE SET
            root_id = EXCLUDED.root_id,
            parent_id = EXCLUDED.parent_id,
            node_type = EXCLUDED.node_type,
            name = EXCLUDED.name,
            relative_path = EXCLUDED.relative_path,
            display_path = EXCLUDED.display_path,
            provider_file_id = EXCLUDED.provider_file_id,
            local_path = EXCLUDED.local_path,
            mime_type = EXCLUDED.mime_type,
            extension = EXCLUDED.extension,
            size_bytes = EXCLUDED.size_bytes,
            mtime = EXCLUDED.mtime,
            ctime = EXCLUDED.ctime,
            hash_sha256 = EXCLUDED.hash_sha256,
            thumbnail_status = EXCLUDED.thumbnail_status,
            preview_status = EXCLUDED.preview_status,
            index_status = EXCLUDED.index_status,
            is_deleted = EXCLUDED.is_deleted,
            is_missing = EXCLUDED.is_missing,
            metadata = file_nodes.metadata || EXCLUDED.metadata,
            updated_at = now()
          `,
          [
            userId,
            nodeUid,
            rootId,
            parentUid,
            this.clean(node.nodeType) ?? this.clean(node.type) ?? 'file',
            this.clean(node.name) ?? this.basename(String(node.localPath ?? node.relativePath ?? nodeUid)),
            this.clean(node.relativePath) ?? '',
            this.clean(node.displayPath),
            this.clean(node.providerFileId),
            this.clean(node.localPath),
            this.clean(node.mimeType),
            this.clean(node.extension),
            this.readNullableNumber(node.sizeBytes),
            this.readDate(node.mtime),
            this.readDate(node.ctime),
            this.clean(node.hashSha256),
            this.clean(node.thumbnailStatus) ?? 'none',
            this.clean(node.previewStatus) ?? 'none',
            this.clean(node.indexStatus) ?? 'none',
            Boolean(node.isDeleted),
            Boolean(node.isMissing),
            JSON.stringify(this.asRecord(node.metadata)),
          ],
        );
        const savedNode = await client.query<QueryResultRow>(
          `
          SELECT id::text AS id
          FROM file_nodes
          WHERE user_id = $1 AND node_uid = $2
          LIMIT 1
          `,
          [userId, nodeUid],
        );
        const savedNodeId = savedNode.rows[0]?.id as string | undefined;
        const localPath = this.clean(node.localPath);
        const hashSha256 = this.clean(node.hashSha256);
        if (savedNodeId && localPath) {
          await client.query(
            `
            INSERT INTO file_node_device_locations (
              user_id, node_id, device_id, local_path, availability, metadata, last_seen_at
            ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, now())
            ON CONFLICT (user_id, node_id, device_id) DO UPDATE SET
              local_path = EXCLUDED.local_path,
              availability = EXCLUDED.availability,
              metadata = file_node_device_locations.metadata || EXCLUDED.metadata,
              last_seen_at = now()
            `,
            [
              userId,
              savedNodeId,
              deviceId,
              localPath,
              this.clean(node.availability) ?? 'available',
              JSON.stringify({
                source: 'node_snapshot',
                hashSha256,
                sizeBytes: this.readNullableNumber(node.sizeBytes),
              }),
            ],
          );
        }
        if (savedNodeId && (hashSha256 || this.clean(node.providerFileId) || localPath)) {
          await client.query(
            `
            INSERT INTO file_identity_mappings (
              user_id,
              node_id,
              provider_key,
              provider_file_id,
              device_id,
              local_path,
              hash_sha256,
              size_bytes,
              modified_at,
              confidence,
              metadata
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::timestamptz, $10, $11::jsonb)
            ON CONFLICT (user_id, node_id, provider_key, device_id, local_path) DO UPDATE SET
              provider_file_id = EXCLUDED.provider_file_id,
              hash_sha256 = EXCLUDED.hash_sha256,
              size_bytes = EXCLUDED.size_bytes,
              modified_at = EXCLUDED.modified_at,
              confidence = EXCLUDED.confidence,
              status = 'active',
              metadata = file_identity_mappings.metadata || EXCLUDED.metadata,
              updated_at = now()
            `,
            [
              userId,
              savedNodeId,
              this.clean(node.providerKey) ?? 'local',
              this.clean(node.providerFileId),
              deviceId,
              localPath,
              hashSha256,
              this.readNullableNumber(node.sizeBytes),
              this.readDate(node.mtime),
              hashSha256 ? 'hash' : this.clean(node.providerFileId) ? 'provider_id' : 'path_size_mtime',
              JSON.stringify({ source: 'node_snapshot' }),
            ],
          );
        }
        applied += 1;
      }
      const scanStatus = this.clean(body.scanStatus) ?? 'completed';
      const scanDiagnostic = this.asRecord(body.scanDiagnostic);
      const finishedAt = new Date();
      const startedAt = this.clean(scanDiagnostic.startedAt);
      const startedTime = startedAt ? new Date(startedAt).getTime() : NaN;
      const rootMetadataPatch =
        Object.keys(scanDiagnostic).length > 0
          ? {
              lastScan: {
              ...scanDiagnostic,
              status: scanStatus,
              applied,
              finishedAt: finishedAt.toISOString(),
              progressMessage: `${scanStatus}: applied ${applied} nodes`,
              durationMs: Number.isFinite(startedTime)
                ? finishedAt.getTime() - startedTime
                : undefined,
              },
            }
          : {};
      await client.query(
        `
        UPDATE file_roots
        SET
          scan_status = $3,
          last_scan_at = now(),
          last_error = NULL,
          metadata = metadata || $4::jsonb,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, rootId, scanStatus, JSON.stringify(rootMetadataPatch)],
      );
      await this.recordFileOperation(client, userId, deviceId, 'file.nodes.snapshot', null, {
        rootId,
        applied,
      });
      return applied;
    });
    return { ok: true, rootId, applied: result };
  }

  private async collectLocalNodesForRoot(
    userId: string,
    rootId: string,
    rootPath: string,
    maxNodes: number,
    nodes: Record<string, unknown>[],
    onProgress?: (progress: DriveScanProgress) => Promise<void>,
  ) {
    const rootStat = await stat(rootPath);
    nodes.push(this.createScannedRootNode(rootPath, rootStat.mtime.toISOString()));
    const queue: Array<{ path: string; parentUid: string }> = [
      { path: rootPath, parentUid: `root:${rootPath}` },
    ];
    while (queue.length > 0 && nodes.length < maxNodes) {
      const current = queue.shift();
      if (!current) {
        continue;
      }
      const entries = await readdir(current.path, { withFileTypes: true });
      entries.sort((left, right) => left.name.localeCompare(right.name));
      for (const entry of entries) {
        if (nodes.length >= maxNodes) {
          break;
        }
        if (!entry.isFile() && !entry.isDirectory()) {
          continue;
        }
        const fullPath = join(current.path, entry.name);
        await onProgress?.({
          scanned: nodes.length,
          maxNodes,
          currentPath: fullPath,
          queuedFolders: queue.length,
          phase: 'reading',
        });
        const entryStat = await stat(fullPath);
        const relativePath = relative(rootPath, fullPath).replace(/\\/g, '/');
        const isFolder = entry.isDirectory();
        const node = await this.createScannedNode({
          userId,
          rootId,
          rootPath,
          parentUid: current.parentUid,
          fullPath,
          relativePath,
          name: entry.name,
          isFolder,
          sizeBytes: entryStat.size,
          mtime: entryStat.mtime.toISOString(),
          ctime: entryStat.ctime.toISOString(),
        });
        nodes.push(node);
        await onProgress?.({
          scanned: nodes.length,
          maxNodes,
          currentPath: fullPath,
          queuedFolders: queue.length,
          phase: 'collected',
        });
        if (isFolder) {
          queue.push({ path: fullPath, parentUid: node.nodeUid });
        }
      }
    }
  }

  private createScannedRootNode(rootPath: string, mtime: string) {
    return {
      nodeUid: `root:${rootPath}`,
      nodeType: 'folder',
      name: this.basename(rootPath),
      relativePath: '',
      displayPath: rootPath,
      localPath: rootPath,
      mtime,
      metadata: { source: 'server_scan' },
    };
  }

  private async createScannedNode(input: {
    userId: string;
    rootId: string;
    rootPath: string;
    parentUid: string;
    fullPath: string;
    relativePath: string;
    name: string;
    isFolder: boolean;
    sizeBytes: number;
    mtime: string;
    ctime: string;
  }) {
    const nodeUid = `node:${input.rootPath}:${input.relativePath}`;
    if (input.isFolder) {
      return {
        nodeUid,
        parentNodeUid: input.parentUid,
        nodeType: 'folder',
        name: input.name,
        relativePath: input.relativePath,
        displayPath: input.fullPath,
        localPath: input.fullPath,
        mimeType: null,
        extension: null,
        sizeBytes: null,
        mtime: input.mtime,
        ctime: input.ctime,
        hashSha256: null,
        providerKey: 'server_storage',
        metadata: { source: 'server_scan' },
      };
    }
    return {
      nodeUid,
      parentNodeUid: input.parentUid,
      nodeType: 'file',
      name: input.name,
      relativePath: input.relativePath,
      displayPath: input.fullPath,
      localPath: input.fullPath,
      mimeType: this.guessMimeType(input.name),
      extension: extname(input.name).replace(/^\./, ''),
      sizeBytes: input.sizeBytes,
      mtime: input.mtime,
      ctime: input.ctime,
      hashSha256: null,
      providerKey: 'server_storage',
      metadata: {
        source: 'server_shared_root',
        rootId: input.rootId,
        relativePath: input.relativePath,
        originalServerPath: input.fullPath,
        storageMode: 'shared_server_path',
      },
    };
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

  private async recordAudit(
    client: Pick<DatabaseService | TransactionClient, 'query'>,
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

  private basename(path: string) {
    const normalized = path.replace(/\\/g, '/');
    return normalized.split('/').filter(Boolean).pop() ?? path;
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

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
