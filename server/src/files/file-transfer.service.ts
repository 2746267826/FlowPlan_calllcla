import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import type { FilesQuery } from './files.service';
import { clean, asRecord, readLimit, readOffset, readInt, toNumber, basename, readNullableNumber } from '../common/utils';
import { LocalObjectStorageService } from './local-object-storage.service';

@Injectable()
export class FileTransferService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly objectStorage: LocalObjectStorageService,
  ) {}

  async storageStatus() {
    return this.objectStorage.status();
  }

  async storageObjects(query: FilesQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 1000);
    const offset = readOffset(query.offset);
    const localPath = clean(query.localPath);
    const nodeId = clean(query.nodeId);
    const result = await this.database.query(
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
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM file_storage_objects
      WHERE user_id = $1
        AND (
          $2::text IS NULL
          OR metadata->>'sourcePath' = $2
          OR metadata->>'localPath' = $2
        )
        AND (
          $3::text IS NULL
          OR metadata->>'fileNodeId' = $3
          OR id::text IN (
            SELECT storage_object_id::text
            FROM file_identity_mappings
            WHERE user_id = $1 AND node_id::text = $3 AND storage_object_id IS NOT NULL
          )
        )
      ORDER BY updated_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, localPath, nodeId, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, storageObjects: result.rows };
  }

  async registerStorageObject(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const sourcePath = clean(body.localPath);
    const fileNodeId = clean(body.fileNodeId) ?? clean(asRecord(body.metadata).fileNodeId);
    if (!sourcePath) {
      return { ok: false, reason: 'localPath_required' };
    }
    const fileName = clean(body.fileName) ?? basename(sourcePath);
    const objectKey = clean(body.objectKey) ?? randomUUID();
    const copied = await this.objectStorage.copyLocalFile(userId, sourcePath, objectKey);
    const result = await this.database.transaction(async (client) => {
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
        ) VALUES ($1, 'server_storage', $2, $3, $4, $5, $6, 1, 'available', $7::jsonb)
        ON CONFLICT (user_id, provider_key, object_key) DO UPDATE SET
          display_name = EXCLUDED.display_name,
          size_bytes = EXCLUDED.size_bytes,
          checksum = EXCLUDED.checksum,
          chunk_size = EXCLUDED.chunk_size,
          chunk_count = EXCLUDED.chunk_count,
          status = 'available',
          metadata = EXCLUDED.metadata,
          updated_at = now()
        RETURNING id::text AS "storageObjectId", object_key AS "objectKey", display_name AS "displayName", size_bytes AS "sizeBytes", checksum
        `,
        [
          userId,
          objectKey,
          fileName,
          copied.sizeBytes,
          copied.checksum,
          copied.sizeBytes,
          JSON.stringify({
            sourcePath,
            storageType: 'local_filesystem',
            storageRoot: this.objectStorage.root(),
            storagePath: copied.relativePath,
            absoluteStoragePath: copied.storagePath,
            ...asRecord(body.metadata),
          }),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'files.storage.register', {
        storageObjectId: storage.rows[0]?.storageObjectId,
        objectKey,
        sourcePath,
        storagePath: copied.relativePath,
      });
      if (fileNodeId) {
        await client.query(
          `
          UPDATE file_nodes
          SET
            hash_sha256 = COALESCE(hash_sha256, $3),
            size_bytes = COALESCE(size_bytes, $4),
            metadata = metadata || $5::jsonb,
            updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [
            userId,
            fileNodeId,
            copied.checksum,
            copied.sizeBytes,
            JSON.stringify({
              storageObjectId: storage.rows[0]?.storageObjectId,
              storageProviderKey: 'server_storage',
              storageRegisteredAt: new Date().toISOString(),
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
            fileNodeId,
            deviceId,
            sourcePath,
            JSON.stringify({ hashSha256: copied.checksum, source: 'storage_register' }),
          ],
        );
        await client.query(
          `
          INSERT INTO file_identity_mappings (
            user_id,
            node_id,
            provider_key,
            storage_object_id,
            device_id,
            local_path,
            hash_sha256,
            size_bytes,
            confidence,
            metadata
          ) VALUES ($1, $2, 'server_storage', $3, $4, $5, $6, $7, 'hash', $8::jsonb)
          ON CONFLICT (user_id, node_id, provider_key, device_id, local_path) DO UPDATE SET
            storage_object_id = EXCLUDED.storage_object_id,
            hash_sha256 = EXCLUDED.hash_sha256,
            size_bytes = EXCLUDED.size_bytes,
            confidence = 'hash',
            status = 'active',
            metadata = file_identity_mappings.metadata || EXCLUDED.metadata,
            updated_at = now()
          `,
          [
            userId,
            fileNodeId,
            storage.rows[0]?.storageObjectId,
            deviceId,
            sourcePath,
            copied.checksum,
            copied.sizeBytes,
            JSON.stringify({ objectKey, storagePath: copied.relativePath }),
          ],
        );
      }
      return storage.rows[0];
    });
    return { ok: true, storageObject: result };
  }

  async upsertNetworkPresence(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.query<QueryResultRow>(
      `
      INSERT INTO device_network_presence (
        user_id,
        device_id,
        network_type,
        wifi_ssid_hash,
        local_ip,
        local_port,
        public_ip_hash,
        nat_type,
        capabilities,
        last_seen_at,
        expires_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, now(), now() + ($10::text || ' minutes')::interval)
      ON CONFLICT (user_id, device_id) DO UPDATE SET
        network_type = EXCLUDED.network_type,
        wifi_ssid_hash = EXCLUDED.wifi_ssid_hash,
        local_ip = EXCLUDED.local_ip,
        local_port = EXCLUDED.local_port,
        public_ip_hash = EXCLUDED.public_ip_hash,
        nat_type = EXCLUDED.nat_type,
        capabilities = EXCLUDED.capabilities,
        last_seen_at = now(),
        expires_at = EXCLUDED.expires_at
      RETURNING id::text AS id, device_id::text AS "deviceId", network_type AS "networkType", local_ip AS "localIp", local_port AS "localPort", expires_at AS "expiresAt"
      `,
      [
        userId,
        deviceId,
        clean(body.networkType) ?? 'unknown',
        clean(body.wifiSsidHash),
        clean(body.localIp),
        readNullableNumber(body.localPort),
        clean(body.publicIpHash),
        clean(body.natType) ?? 'unknown',
        JSON.stringify(asRecord(body.capabilities)),
        String(readInt(body.ttlMinutes, 10)),
      ],
    );
    return { ok: true, presence: result.rows[0] };
  }

  async networkPresence(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        p.id::text AS id,
        p.device_id::text AS "deviceId",
        d.device_name AS "deviceName",
        p.network_type AS "networkType",
        p.local_ip AS "localIp",
        p.local_port AS "localPort",
        p.nat_type AS "natType",
        p.capabilities,
        p.last_seen_at AS "lastSeenAt",
        p.expires_at AS "expiresAt",
        CASE WHEN p.expires_at > now() THEN 'available' ELSE 'expired' END AS status
      FROM device_network_presence p
      LEFT JOIN devices d ON d.user_id = p.user_id AND d.id = p.device_id
      WHERE p.user_id = $1
      ORDER BY p.last_seen_at DESC
      `,
      [userId],
    );
    return { devices: result.rows };
  }

  async transferCandidates(sessionId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureServerRelayCandidate(userId, sessionId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        session_id::text AS "sessionId",
        candidate_type AS "candidateType",
        source_address AS "sourceAddress",
        source_port AS "sourcePort",
        target_address AS "targetAddress",
        target_port AS "targetPort",
        protocol,
        priority,
        status,
        latency_ms AS "latencyMs",
        bandwidth_estimate AS "bandwidthEstimate",
        failure_reason AS "failureReason",
        updated_at AS "updatedAt"
      FROM file_transfer_candidates
      WHERE user_id = $1 AND session_id = $2
      ORDER BY priority ASC, updated_at DESC
      `,
      [userId, sessionId],
    );
    return { candidates: result.rows };
  }

  async upsertTransferCandidate(
    sessionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const row = await client.query<QueryResultRow>(
        `
        INSERT INTO file_transfer_candidates (
          user_id,
          session_id,
          candidate_type,
          source_address,
          source_port,
          target_address,
          target_port,
          protocol,
          priority,
          status,
          latency_ms,
          bandwidth_estimate,
          failure_reason
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        RETURNING id::text AS id, candidate_type AS "candidateType", protocol, status
        `,
        [
          userId,
          sessionId,
          clean(body.candidateType) ?? 'lan_hint',
          clean(body.sourceAddress),
          readNullableNumber(body.sourcePort),
          clean(body.targetAddress),
          readNullableNumber(body.targetPort),
          clean(body.protocol) ?? 'server_api',
          readInt(body.priority, 100),
          clean(body.status) ?? 'pending',
          readNullableNumber(body.latencyMs),
          readNullableNumber(body.bandwidthEstimate),
          clean(body.failureReason),
        ],
      );
      await this.appendTransferEventWithClient(client, userId, sessionId, 'candidate.added', {
        candidateId: row.rows[0]?.id,
        deviceId,
      });
      return row.rows[0];
    });
    return { ok: true, candidate: result };
  }

  async appendTransferEvent(
    sessionId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.devicesService.ensureDevice(context);
    await this.appendTransferEventWithClient(
      this.database,
      userId,
      sessionId,
      clean(body.eventType) ?? 'transfer.note',
      {
        message: clean(body.message),
        ...asRecord(body.payload),
      },
    );
    return { ok: true };
  }

  private async ensureServerRelayCandidate(userId: string, sessionId: string) {
    await this.database.query(
      `
      INSERT INTO file_transfer_candidates (
        user_id,
        session_id,
        candidate_type,
        protocol,
        priority,
        status
      )
      SELECT $1, $2, 'server_relay', 'server_api', 10, 'available'
      WHERE NOT EXISTS (
        SELECT 1
        FROM file_transfer_candidates
        WHERE user_id = $1 AND session_id = $2 AND candidate_type = 'server_relay'
      )
      `,
      [userId, sessionId],
    );
  }

  private async appendTransferEventWithClient(
    client: Pick<DatabaseService | TransactionClient, 'query'>,
    userId: string,
    sessionId: string,
    eventType: string,
    payload: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO file_transfer_events (
        user_id,
        session_id,
        event_type,
        message,
        payload_json
      ) VALUES ($1, $2, $3, $4, $5::jsonb)
      `,
      [
        userId,
        sessionId,
        eventType,
        clean(payload.message),
        JSON.stringify(payload),
      ],
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
