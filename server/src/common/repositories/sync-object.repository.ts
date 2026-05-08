import { Injectable } from '@nestjs/common';
import { QueryResultRow } from 'pg';
import { DatabaseService, TransactionClient } from '../../database/database.service';

export interface SyncObjectRow {
  id: string;
  objectType: string;
  uid: string | null;
  payload: Record<string, unknown>;
  deletedAt: Date | null;
  serverVersion: number;
  updatedAt: Date;
}

@Injectable()
export class SyncObjectRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Find a single non-deleted object by type and uid. */
  async findByUid(
    userId: string,
    objectType: string,
    uid: string,
    client?: DatabaseService | TransactionClient,
  ): Promise<SyncObjectRow | null> {
    const conn = client ?? this.db;
    const result = await conn.query<SyncObjectRow>(
      `SELECT id::text, object_type AS "objectType", uid, payload,
              deleted_at AS "deletedAt", server_version AS "serverVersion",
              updated_at AS "updatedAt"
       FROM sync_objects
       WHERE user_id = $1 AND object_type = $2 AND uid = $3 AND deleted_at IS NULL
       LIMIT 1`,
      [userId, objectType, uid],
    );
    return result.rows[0] ?? null;
  }

  /** Find a single non-deleted object by server id. */
  async findById(
    userId: string,
    id: string,
    client?: DatabaseService | TransactionClient,
  ): Promise<SyncObjectRow | null> {
    const conn = client ?? this.db;
    const result = await conn.query<SyncObjectRow>(
      `SELECT id::text, object_type AS "objectType", uid, payload,
              deleted_at AS "deletedAt", server_version AS "serverVersion",
              updated_at AS "updatedAt"
       FROM sync_objects
       WHERE user_id = $1 AND id = $2
       LIMIT 1`,
      [userId, id],
    );
    return result.rows[0] ?? null;
  }

  /** List objects by type, ordered by updated_at DESC. */
  async listByType(
    userId: string,
    objectTypes: string[],
    limit = 200,
    offset = 0,
  ): Promise<SyncObjectRow[]> {
    const result = await this.db.query<SyncObjectRow>(
      `SELECT id::text, object_type AS "objectType", uid, payload,
              deleted_at AS "deletedAt", server_version AS "serverVersion",
              updated_at AS "updatedAt"
       FROM sync_objects
       WHERE user_id = $1
         AND deleted_at IS NULL
         AND object_type = ANY($2::text[])
       ORDER BY updated_at DESC
       LIMIT $3 OFFSET $4`,
      [userId, objectTypes, limit, offset],
    );
    return result.rows;
  }

  /** Write a sync_changes row recording an upsert or delete. */
  async recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    serverObjectId: string,
    objectType: string,
    action: 'upsert' | 'delete' | 'create' | 'update',
    serverVersion: number,
    payload: Record<string, unknown>,
  ) {
    await client.query(
      `INSERT INTO sync_changes (
         user_id, device_id, server_object_id, object_type, action, server_version, payload
       ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)`,
      [
        userId,
        deviceId,
        serverObjectId,
        objectType,
        action,
        serverVersion,
        JSON.stringify(payload ?? {}),
      ],
    );
  }

  /** Count objects by type (non-deleted). */
  async countByType(userId: string, objectTypes: string[]): Promise<number> {
    const result = await this.db.query<{ count: string }>(
      `SELECT COUNT(*)::int AS count
       FROM sync_objects
       WHERE user_id = $1 AND deleted_at IS NULL AND object_type = ANY($2::text[])`,
      [userId, objectTypes],
    );
    return Number(result.rows[0]?.count ?? 0);
  }
}
