import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import pg from 'pg';

const { Pool } = pg;

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error('DATABASE_URL is required.');
}

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const schemaPath = join(root, 'src', 'database', 'p1_schema.sql');
const schema = await readFile(schemaPath, 'utf8');
const pool = new Pool({ connectionString: databaseUrl });

try {
  await pool.query(schema);
  console.log('FlowPlan P1 schema applied.');
} finally {
  await pool.end();
}
