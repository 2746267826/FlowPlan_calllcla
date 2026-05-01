import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import pg from 'pg';

const { Pool } = pg;

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is required to apply the FlowPlan schema.');
  console.error('Expected format: postgres://USER:PASSWORD@HOST:5432/DATABASE');
  console.error('Set it in flowplan.local.env or in the current shell, then run: npm run db:schema');
  process.exit(1);
}

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const schemaPath = join(root, 'src', 'database', 'p1_schema.sql');
let pool;

try {
  pool = new Pool({ connectionString: databaseUrl });
  const schema = await readFile(schemaPath, 'utf8');
  await pool.query(schema);
  console.log('FlowPlan P1 schema applied.');
  console.log(`Schema file: ${schemaPath}`);
} catch (error) {
  console.error('FlowPlan schema apply failed.');
  console.error(`Schema file: ${schemaPath}`);
  console.error(error instanceof Error ? error.message : String(error));
  console.error('Check DATABASE_URL, PostgreSQL permissions, and the SQL statement reported by PostgreSQL above.');
  process.exitCode = 1;
} finally {
  await pool?.end();
}
