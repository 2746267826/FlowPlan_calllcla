import { Injectable } from '@nestjs/common';
import { DatabaseService, TransactionClient } from '../../database/database.service';

export interface AuditEntry {
  userId: string;
  deviceId: string;
  actor: string;
  action: string;
  entityType: string;
  entityId?: string | null;
  summary?: string | null;
  metadata?: Record<string, unknown>;
}

/**
 * Unified audit-log writer.
 *
 * Every service that previously had its own `private recordAudit()` should
 * inject (or call) this service instead.  It keeps the same INSERT shape
 * that every service already used, but removes the per-service duplication.
 */
@Injectable()
export class AuditService {
  constructor(private readonly database: DatabaseService) {}

  /** Write a single audit row inside an existing transaction. */
  async write(client: TransactionClient, entry: AuditEntry): Promise<void> {
    await client.query(
      `INSERT INTO audit_logs (
         user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)`,
      [
        entry.userId,
        entry.deviceId,
        entry.actor,
        entry.action,
        entry.entityType,
        entry.entityId ?? null,
        entry.summary ?? entry.action,
        JSON.stringify(entry.metadata ?? {}),
      ],
    );
  }

  /** Convenience wrapper that opens its own connection (for non-transactional use). */
  async writeStandalone(entry: AuditEntry): Promise<void> {
    await this.database.query(
      `INSERT INTO audit_logs (
         user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)`,
      [
        entry.userId,
        entry.deviceId,
        entry.actor,
        entry.action,
        entry.entityType,
        entry.entityId ?? null,
        entry.summary ?? entry.action,
        JSON.stringify(entry.metadata ?? {}),
      ],
    );
  }
}
