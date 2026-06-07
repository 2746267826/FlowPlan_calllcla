import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../../database/database.service';
import { resetTestDatabase } from './db-test-harness';

export interface TestUser {
  id: string;
  displayName: string;
}

export interface TestDevice {
  id: string;
  deviceName: string;
  platform: string;
  clientDeviceId: string;
}

export async function createTestUser(
  db: DatabaseService,
  overrides: Partial<TestUser> = {},
): Promise<TestUser> {
  const id = overrides.id ?? randomUUID();
  const displayName = overrides.displayName ?? 'Test User';
  await db.query(
    `INSERT INTO users (id, display_name)
     VALUES ($1, $2)
     ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name`,
    [id, displayName],
  );
  return { id, displayName };
}

export async function createTestDevice(
  db: DatabaseService,
  userId: string,
  overrides: Partial<TestDevice> = {},
): Promise<TestDevice> {
  const id = overrides.id ?? randomUUID();
  const deviceName = overrides.deviceName ?? 'Test Device';
  const platform = overrides.platform ?? 'windows';
  const clientDeviceId = overrides.clientDeviceId ?? randomUUID();
  await db.query(
    `INSERT INTO devices (id, user_id, device_name, platform, client_device_id, connection_status)
     VALUES ($1, $2, $3, $4, $5, 'online')
     ON CONFLICT (user_id, client_device_id) DO UPDATE
       SET device_name = EXCLUDED.device_name,
           connection_status = 'online'`,
    [id, userId, deviceName, platform, clientDeviceId],
  );
  return { id, deviceName, platform, clientDeviceId };
}

export async function cleanDatabase(db: DatabaseService): Promise<void> {
  await resetTestDatabase(db);
}
