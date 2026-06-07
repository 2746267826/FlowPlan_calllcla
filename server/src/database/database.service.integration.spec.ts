import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { DatabaseService } from './database.service';
import { cleanDatabase, createTestUser, createTestDevice } from '../common/test/test-utils';

describe('DatabaseService', () => {
  let db: DatabaseService;

  beforeAll(async () => {
    db = new DatabaseService();
    await db.onModuleInit();
  });

  afterAll(async () => {
    await db.onModuleDestroy();
  });

  beforeEach(async () => {
    await cleanDatabase(db);
  });

  describe('connectivity', () => {
    it('SELECT 1 returns a result', async () => {
      const result = await db.query('SELECT 1 AS ok');
      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].ok).toBe(1);
    });
  });

  describe('query', () => {
    it('inserts and reads a user row', async () => {
      await db.query(
        `INSERT INTO users (id, display_name) VALUES ($1, $2)
         ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name`,
        ['00000000-0000-0000-0000-000000000001', 'alice'],
      );
      const result = await db.query('SELECT * FROM users WHERE id = $1', [
        '00000000-0000-0000-0000-000000000001',
      ]);
      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].display_name).toBe('alice');
    });

    it('returns an empty rows array when nothing matches', async () => {
      const result = await db.query(
        'SELECT * FROM users WHERE id = $1',
        ['00000000-0000-0000-0000-000000000099'],
      );
      expect(result.rows).toHaveLength(0);
    });

    it('supports parameterised queries with multiple types', async () => {
      const id = '00000000-0000-0000-0000-000000000002';
      await db.query(
        `INSERT INTO users (id, display_name) VALUES ($1, $2)
         ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name`,
        [id, 'bob'],
      );
      const result = await db.query(
        `SELECT id, display_name, created_at FROM users WHERE display_name = $1`,
        ['bob'],
      );
      expect(result.rows[0].id).toBe(id);
      expect(result.rows[0].created_at).toBeInstanceOf(Date);
    });
  });

  describe('transaction', () => {
    it('commits on success', async () => {
      const id = '00000000-0000-0000-0000-000000000003';
      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO users (id, display_name) VALUES ($1, $2)`,
          [id, 'charlie'],
        );
      });
      const result = await db.query('SELECT * FROM users WHERE id = $1', [id]);
      expect(result.rows).toHaveLength(1);
    });

    it('rolls back on error and does not persist changes', async () => {
      const id = '00000000-0000-0000-0000-000000000004';

      const txError = await db
        .transaction(async (client) => {
          await client.query(
            `INSERT INTO users (id, display_name) VALUES ($1, $2)`,
            [id, 'dave'],
          );
          throw new Error('simulated failure');
        })
        .catch((err: Error) => err);

      expect(txError).toBeInstanceOf(Error);
      expect(txError.message).toBe('simulated failure');

      const result = await db.query('SELECT * FROM users WHERE id = $1', [id]);
      expect(result.rows).toHaveLength(0);
    });

    it('supports multiple queries within a single transaction', async () => {
      const uid = '00000000-0000-0000-0000-000000000005';
      const did = '00000000-0000-0000-0000-000000000006';

      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO users (id, display_name) VALUES ($1, $2)`,
          [uid, 'multi'],
        );
        await client.query(
          `INSERT INTO devices (id, user_id, device_name, platform, client_device_id, connection_status)
           VALUES ($1, $2, $3, $4, $5, 'online')`,
          [did, uid, 'multi-device', 'android', 'multi-client-id'],
        );
      });

      const userResult = await db.query('SELECT id FROM users WHERE id = $1', [
        uid,
      ]);
      const devResult = await db.query(
        'SELECT id FROM devices WHERE id = $1',
        [did],
      );
      expect(userResult.rows).toHaveLength(1);
      expect(devResult.rows).toHaveLength(1);
    });
  });

  describe('error handling', () => {
    it('throws on invalid SQL', async () => {
      await expect(
        db.query('SELECTT 1'),
      ).rejects.toThrow();
    });

    it('throws on foreign key violation', async () => {
      await expect(
        db.query(
          `INSERT INTO devices (id, user_id, device_name, platform, client_device_id, connection_status)
           VALUES ($1, $2, $3, $4, $5, 'online')`,
          ['00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000099', 'bad', 'windows', 'bad-client'],
        ),
      ).rejects.toMatchObject({
        code: '23503',
        constraint: 'devices_user_id_fkey',
      });
    });
  });

  describe('integration with test helpers', () => {
    it('createTestUser inserts a user', async () => {
      const user = await createTestUser(db, {
        id: '00000000-0000-0000-0000-000000000011',
        displayName: 'HelperUser',
      });
      expect(user.id).toBe('00000000-0000-0000-0000-000000000011');
      expect(user.displayName).toBe('HelperUser');

      const result = await db.query('SELECT * FROM users WHERE id = $1', [
        user.id,
      ]);
      expect(result.rows).toHaveLength(1);
    });

    it('createTestDevice links to a user', async () => {
      const user = await createTestUser(db);
      const device = await createTestDevice(db, user.id, {
        deviceName: 'HelperDevice',
        platform: 'android',
      });

      const result = await db.query('SELECT * FROM devices WHERE id = $1', [
        device.id,
      ]);
      expect(result.rows[0].device_name).toBe('HelperDevice');
      expect(result.rows[0].platform).toBe('android');
    });

    it('cleanDatabase removes all rows', async () => {
      const user = await createTestUser(db);
      await createTestDevice(db, user.id);

      let result = await db.query('SELECT COUNT(*)::int AS cnt FROM users');
      expect(result.rows[0].cnt).toBeGreaterThan(0);

      await cleanDatabase(db);

      result = await db.query('SELECT COUNT(*)::int AS cnt FROM users');
      expect(result.rows[0].cnt).toBe(0);

      result = await db.query('SELECT COUNT(*)::int AS cnt FROM devices');
      expect(result.rows[0].cnt).toBe(0);
    });
  });
});
