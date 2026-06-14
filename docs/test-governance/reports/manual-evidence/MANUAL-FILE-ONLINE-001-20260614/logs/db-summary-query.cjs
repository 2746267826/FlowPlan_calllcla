const path = require('node:path');
const { createRequire } = require('node:module');
const [root, databaseUrl, userId, sessionId, storageObjectId] = process.argv.slice(2);
const requireFromServer = createRequire(path.join(root, 'server', 'package.json'));
const { Client } = requireFromServer('pg');
(async () => {
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  try {
    const session = await client.query(`
      SELECT id::text AS "sessionId", status, storage_object_id::text AS "storageObjectId", received_chunks AS "receivedChunks", expected_chunks AS "expectedChunks", checksum
      FROM file_transfer_sessions
      WHERE user_id = $1 AND id = $2
      LIMIT 1
    `, [userId, sessionId]);
    const storage = await client.query(`
      SELECT id::text AS "storageObjectId", display_name AS "displayName", size_bytes AS "sizeBytes", checksum, metadata
      FROM file_storage_objects
      WHERE user_id = $1 AND id = $2
      LIMIT 1
    `, [userId, storageObjectId]);
    const audit = await client.query(`
      SELECT id::text AS id, action, actor, entity_type AS "entityType", entity_id AS "entityId", metadata
      FROM audit_logs
      WHERE user_id = $1 AND action IN ('files.upload.create_session', 'files.upload.complete', 'files.download.create_session', 'file.storage.download_range')
        AND (metadata->>'sessionId' = $2 OR metadata->>'storageObjectId' = $3)
      ORDER BY occurred_at ASC
    `, [userId, sessionId, storageObjectId]);
    process.stdout.write(JSON.stringify({ session: session.rows[0] ?? null, storage: storage.rows[0] ?? null, audit: audit.rows }, null, 2));
  } finally {
    await client.end();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
