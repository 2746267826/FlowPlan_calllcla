import { Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { basename } from 'node:path';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { KopiaService, type KopiaSnapshotVersion } from './kopia.service';
import { clean, asRecord, readDate, sha256, errorMessage, toNumber, readInt } from '../common/utils';

@Injectable()
export class FileVersionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly kopiaService: KopiaService,
  ) {}

  async versions(fileId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        id::text AS id,
        version_uid AS "versionUid",
        file_id AS "fileId",
        provider,
        version_ref AS "versionRef",
        display_name AS "displayName",
        size_bytes AS "sizeBytes",
        modified_at AS "modifiedAt",
        checksum,
        source_device AS "sourceDevice",
        source_backend AS "sourceBackend",
        note,
        metadata,
        created_at AS "createdAt"
      FROM file_version_records
      WHERE user_id = $1 AND file_id = $2
      ORDER BY modified_at DESC NULLS LAST, created_at DESC
      `,
      [userId, fileId],
    );
    return { versions: result.rows };
  }

  async createVersionDownloadRequest(
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const version = await client.query<QueryResultRow>(
        `
        SELECT id, file_id, provider, version_ref
        FROM file_version_records
        WHERE user_id = $1 AND id = $2
        LIMIT 1
        `,
        [userId, versionId],
      );
      const row = version.rows[0];
      if (!row) {
        return null;
      }
      const targetMode = clean(body.targetMode) ?? 'download_copy';
      const request = await client.query(
        `
        INSERT INTO file_version_download_requests (
          user_id,
          version_record_id,
          file_id,
          provider,
          version_ref,
          target_mode,
          target_path,
          audit_note
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id::text AS id, status, target_mode AS "targetMode", target_path AS "targetPath"
        `,
        [
          userId,
          versionId,
          row.file_id,
          row.provider,
          row.version_ref,
          targetMode,
          clean(body.targetPath),
          clean(body.auditNote),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'files.version.download_request', {
        versionId,
        targetMode,
      });
      return request.rows[0];
    });
    return { ok: !!result, request: result };
  }

  async createKopiaSnapshot(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const rootPath = clean(body.rootPath);
    if (!rootPath) {
      return { ok: false, reason: 'rootPath_required' };
    }
    try {
      const snapshot = await this.kopiaService.createSnapshot(rootPath);
      await this.database.transaction(async (client) => {
        await this.recordAudit(client, userId, deviceId, 'files.kopia.snapshot.create', {
          rootPath,
          rootId: clean(body.rootId),
          snapshotCount: snapshot.snapshots.length,
        });
      });
      return { ok: true, ...snapshot };
    } catch (error) {
      await this.database.transaction(async (client) => {
        await this.recordAudit(client, userId, deviceId, 'files.kopia.snapshot.failed', {
          rootPath,
          error: errorMessage(error),
        });
      });
      return { ok: false, reason: errorMessage(error) };
    }
  }

  async refreshKopiaVersions(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const fileId = clean(body.fileId);
    const filePath = clean(body.filePath);
    if (!fileId || !filePath) {
      return { ok: false, reason: 'fileId_and_filePath_required' };
    }
    try {
      const listed = await this.kopiaService.listSnapshots(filePath);
      const displayName = clean(body.displayName) ?? basename(filePath);
      const versions = await this.database.transaction(async (client) => {
        const saved: QueryResultRow[] = [];
        for (const snapshot of listed.snapshots) {
          const metadata = this.buildKopiaVersionMetadata(
            snapshot,
            filePath,
            displayName,
            context,
            clean(body.rootId),
          );
          const versionUid = this.buildKopiaVersionUid(
            fileId,
            snapshot.snapshotId,
            filePath,
          );
          const result = await client.query(
            `
            INSERT INTO file_version_records (
              user_id,
              version_uid,
              file_id,
              provider,
              version_ref,
              display_name,
              size_bytes,
              modified_at,
              checksum,
              source_device,
              source_backend,
              note,
              metadata
            ) VALUES ($1, $2, $3, 'kopia', $4, $5, $6, $7, $8, $9, 'kopia', $10, $11::jsonb)
            ON CONFLICT (user_id, version_uid) DO UPDATE SET
              version_ref = EXCLUDED.version_ref,
              display_name = EXCLUDED.display_name,
              size_bytes = EXCLUDED.size_bytes,
              modified_at = EXCLUDED.modified_at,
              checksum = EXCLUDED.checksum,
              source_device = EXCLUDED.source_device,
              source_backend = EXCLUDED.source_backend,
              note = EXCLUDED.note,
              metadata = EXCLUDED.metadata
            RETURNING
              id::text AS id,
              version_uid AS "versionUid",
              file_id AS "fileId",
              provider,
              version_ref AS "versionRef",
              display_name AS "displayName",
              size_bytes AS "sizeBytes",
              modified_at AS "modifiedAt",
              checksum,
              source_backend AS "sourceBackend",
              note,
              metadata,
              created_at AS "createdAt"
            `,
            [
              userId,
              versionUid,
              fileId,
              snapshot.versionRef,
              snapshot.displayName,
              snapshot.sizeBytes,
              readDate(snapshot.modifiedAt),
              snapshot.checksum,
              context.deviceId,
              `Kopia snapshot ${snapshot.snapshotId}`,
              JSON.stringify(metadata),
            ],
          );
          saved.push(result.rows[0]);
        }
        await this.recordAudit(client, userId, deviceId, 'files.kopia.versions.refresh', {
          fileId,
          filePath,
          versionCount: saved.length,
        });
        return saved;
      });
      return { ok: true, versions };
    } catch (error) {
      await this.database.transaction(async (client) => {
        await this.recordAudit(client, userId, deviceId, 'files.kopia.versions.failed', {
          fileId,
          filePath,
          error: errorMessage(error),
        });
      });
      return { ok: false, reason: errorMessage(error), versions: [] };
    }
  }

  async downloadVersionCopy(
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const targetPath = clean(body.targetPath);
    if (!targetPath) {
      return { ok: false, reason: 'targetPath_required' };
    }
    const result = await this.database.transaction(async (client) => {
      const version = await client.query<QueryResultRow>(
        `
        SELECT id, file_id, provider, version_ref, display_name, metadata
        FROM file_version_records
        WHERE user_id = $1 AND id = $2
        LIMIT 1
        `,
        [userId, versionId],
      );
      const row = version.rows[0];
      if (!row) {
        return { ok: false, reason: 'version_not_found' };
      }
      const metadata = asRecord(row.metadata);
      const objectPath = this.resolveKopiaRestoreObjectPath(metadata);
      const request = await client.query(
        `
        INSERT INTO file_version_download_requests (
          user_id,
          version_record_id,
          file_id,
          provider,
          version_ref,
          target_mode,
          target_path,
          status,
          audit_note,
          confirmed_at
        ) VALUES ($1, $2, $3, $4, $5, 'download_copy', $6, 'running', $7, now())
        RETURNING id::text AS id
        `,
        [
          userId,
          versionId,
          row.file_id,
          row.provider,
          row.version_ref,
          targetPath,
          clean(body.auditNote),
        ],
      );
      try {
        const download = await this.kopiaService.downloadVersionCopy(
          String(row.version_ref),
          objectPath,
          targetPath,
        );
        await client.query(
          `
          UPDATE file_version_download_requests
          SET status = 'completed', updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, request.rows[0].id],
        );
        await this.recordAudit(client, userId, deviceId, 'files.kopia.version.download_copy', {
          versionId,
          requestId: request.rows[0].id,
          targetPath,
          sourceRef: download.sourceRef,
        });
        return { ok: true, request: request.rows[0], download };
      } catch (error) {
        await client.query(
          `
          UPDATE file_version_download_requests
          SET status = 'failed', updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, request.rows[0].id],
        );
        await this.recordAudit(client, userId, deviceId, 'files.kopia.version.download_failed', {
          versionId,
          requestId: request.rows[0].id,
          targetPath,
          error: errorMessage(error),
        });
        return { ok: false, reason: errorMessage(error), request: request.rows[0] };
      }
    });
    return result;
  }

  async prepareVersionRestore(
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const version = await this.database.query<QueryResultRow>(
      `
      SELECT id, version_ref, metadata
      FROM file_version_records
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, versionId],
    );
    const row = version.rows[0];
    if (!row) {
      return { ok: false, reason: 'version_not_found' };
    }
    const metadata = asRecord(row.metadata);
    const prepare = await this.kopiaService.prepareRestore(
      String(row.version_ref),
      this.resolveKopiaRestoreObjectPath(metadata),
      clean(body.targetPath),
    );
    await this.database.transaction(async (client) => {
      await this.recordAudit(client, userId, deviceId, 'files.kopia.restore.prepare', {
        versionId,
        targetPath: clean(body.targetPath),
      });
    });
    return { ok: true, prepare };
  }

  async conflicts(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        id::text AS id,
        file_uid AS "fileUid",
        path,
        provider_a AS "providerA",
        provider_b AS "providerB",
        version_a AS "versionA",
        version_b AS "versionB",
        reason,
        status,
        resolution,
        resolved_at AS "resolvedAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM file_conflict_candidates
      WHERE user_id = $1
      ORDER BY created_at DESC
      LIMIT 200
      `,
      [userId],
    );
    return { conflicts: result.rows };
  }

  async createConflict(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      INSERT INTO file_conflict_candidates (
        user_id,
        file_uid,
        path,
        provider_a,
        provider_b,
        version_a,
        version_b,
        reason
      ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8)
      RETURNING id::text AS id, status, created_at AS "createdAt"
      `,
      [
        userId,
        clean(body.fileUid),
        clean(body.path) ?? '/',
        clean(body.providerA) ?? 'server_storage',
        clean(body.providerB) ?? 'onedrive',
        JSON.stringify(asRecord(body.versionA)),
        JSON.stringify(asRecord(body.versionB)),
        clean(body.reason) ?? 'provider_version_mismatch',
      ],
    );
    return { ok: true, conflict: result.rows[0] };
  }

  async resolveConflict(
    conflictId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const resolved = await client.query(
        `
        UPDATE file_conflict_candidates
        SET status = 'resolved',
            resolution = $3::jsonb,
            resolved_at = now(),
            updated_at = now()
        WHERE user_id = $1 AND id = $2 AND status = 'open'
        RETURNING id::text AS id, status, resolution
        `,
        [userId, conflictId, JSON.stringify(asRecord(body.resolution ?? body))],
      );
      await this.recordAudit(client, userId, deviceId, 'files.conflict.resolve', {
        conflictId,
        resolution: asRecord(body.resolution ?? body),
      });
      return resolved.rows[0] ?? null;
    });
    return { ok: !!result, conflict: result };
  }

  private buildKopiaVersionUid(
    fileId: string,
    snapshotId: string,
    sourcePath: string,
  ) {
    const normalizedPath = sourcePath.replace(/\\/g, '/');
    const sourceHash = sha256(Buffer.from(normalizedPath)).slice(0, 16);
    return ['kopia', fileId, snapshotId, sourceHash].join(':');
  }

  private buildKopiaVersionMetadata(
    snapshot: KopiaSnapshotVersion,
    filePath: string,
    displayName: string,
    context: FlowPlanV2RequestContext,
    rootId?: string | null,
  ) {
    return {
      ...snapshot.metadata,
      displayName,
      sourcePath: filePath,
      sourceBackend: 'kopia',
      sourceDevice: context.deviceId,
      sourceRootId: rootId ?? null,
      kopiaSnapshotId: snapshot.snapshotId,
      kopiaVersionRef: snapshot.versionRef,
      linkedAt: new Date().toISOString(),
    };
  }

  private resolveKopiaRestoreObjectPath(metadata: Record<string, unknown>) {
    return (
      clean(metadata.objectPath) ??
      clean(metadata.targetPath) ??
      clean(metadata.sourcePath) ??
      clean(metadata.filePath) ??
      clean(metadata.relativePath)
    );
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
        details.sessionId ?? details.providerKey ?? details.conflictId ?? null,
        JSON.stringify(details),
      ],
    );
  }

}
