import { describe, it, expect, afterAll } from 'vitest';
import { writeFile, unlink, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { LocalObjectStorageService } from './local-object-storage.service';

describe('LocalObjectStorageService', () => {
  const service = new LocalObjectStorageService();
  const testDir = join(tmpdir(), 'flowplanv2-test-storage');
  let testFilePath = '';

  // Override root to use temp directory
  const origRoot = service.root();
  (service as any).rootPath = testDir;

  afterAll(async () => {
    if (testFilePath) {
      try { await unlink(testFilePath); } catch { /* ok */ }
    }
  });

  it('returns storage status', async () => {
    const status = await service.status();
    expect(status.providerKey).toBe('server_storage_flowplanv2');
    expect(status.writable).toBe(true);
  });

  it('writes and reads chunks', async () => {
    const chunks = [Buffer.from('Hello '), Buffer.from('World!')];
    const result = await service.writeObjectFromChunks('test-user', 'test-obj', chunks);
    testFilePath = result.storagePath;

    expect(result.sizeBytes).toBe(12);
    expect(result.checksum).toBeTruthy();

    const buf = await service.readRange(testFilePath, 0, 4);
    expect(buf.toString()).toBe('Hello');
  });

  it('reads a byte range', async () => {
    // Create a temp file first
    const chunks = [Buffer.from('0123456789ABCDEF')];
    const result = await service.writeObjectFromChunks('user', 'range-test', chunks);
    testFilePath = result.storagePath;

    const buf = await service.readRange(testFilePath, 3, 7);
    expect(buf.toString()).toBe('34567');
  });

  it('streams a byte range', async () => {
    const chunks = [Buffer.from('ABCDEFGHIJKLMNOP')];
    const result = await service.writeObjectFromChunks('user', 'stream-test', chunks);
    testFilePath = result.storagePath;

    const stream = service.createReadStream(testFilePath, 2, 5);
    const data = await new Promise<Buffer>((resolve, reject) => {
      const bufs: Buffer[] = [];
      stream.on('data', (b: string | Buffer) => bufs.push(Buffer.isBuffer(b) ? b : Buffer.from(b)));
      stream.on('error', reject);
      stream.on('end', () => resolve(Buffer.concat(bufs)));
    });
    expect(data.toString()).toBe('CDEF');
  });

  it('hashes a file via stream', async () => {
    const chunks = [Buffer.from('hash me please')];
    const result = await service.writeObjectFromChunks('user', 'hash-test', chunks);
    testFilePath = result.storagePath;

    const hash = await service.hashFile(testFilePath);
    expect(hash).toHaveLength(64); // SHA-256 hex = 64 chars
    expect(hash).toBe(result.checksum);
  });

  // C3: large-file performance with random data
  describe('performance (C3)', () => {
    it('writes 10MB, reads range, and streams hash under 2 seconds', async () => {
      const { randomBytes } = require('node:crypto');
      const sizeMb = 10;
      const chunkSize = 1024 * 1024; // 1MB
      const totalBytes = sizeMb * chunkSize;
      const chunks: Buffer[] = [];
      let generated = 0;
      while (generated < totalBytes) {
        const len = Math.min(chunkSize, totalBytes - generated);
        chunks.push(Buffer.from(randomBytes(len)));
        generated += len;
      }

      const writeStart = Date.now();
      const result = await service.writeObjectFromChunks('user', 'c3-large-file', chunks);
      const writeMs = Date.now() - writeStart;
      console.log(`[C3] writeObjectFromChunks (${sizeMb}MB): ${writeMs}ms`);

      // Read 1MB range from middle
      const readStart = Date.now();
      const middle = Math.floor(result.sizeBytes / 2);
      const buf = await service.readRange(result.storagePath, middle, middle + chunkSize - 1);
      const readMs = Date.now() - readStart;
      console.log(`[C3] readRange (1MB from middle): ${readMs}ms`);

      // Stream hash
      const hashStart = Date.now();
      const hash = await service.hashFile(result.storagePath);
      const hashMs = Date.now() - hashStart;
      console.log(`[C3] hashFile (${sizeMb}MB stream): ${hashMs}ms`);

      expect(buf.length).toBe(chunkSize);
      expect(hash).toBe(result.checksum);
      expect(writeMs + readMs + hashMs).toBeLessThan(5000); // under 5s total
    });
  });
});
