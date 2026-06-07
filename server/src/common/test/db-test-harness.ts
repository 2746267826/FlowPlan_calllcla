import { DatabaseService } from '../../database/database.service';

export function assertTestDatabaseUrl(
  url = process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL ?? '',
): void {
  if (!/flowplantest|test/i.test(url)) {
    throw new Error(`Refusing to use non-test database: ${url}`);
  }
}

export async function assertActiveTestDatabase(
  db: DatabaseService,
): Promise<void> {
  const result = await db.query<{ name: string }>(
    'SELECT current_database() AS name',
  );
  const name = String(result.rows[0]?.name ?? '');

  if (!/flowplantest|test/i.test(name)) {
    throw new Error(`Refusing to clean non-test database: ${name}`);
  }
}

export async function resetTestDatabase(db: DatabaseService): Promise<void> {
  assertTestDatabaseUrl();
  await assertActiveTestDatabase(db);
  await db.query('TRUNCATE TABLE users RESTART IDENTITY CASCADE');
}
