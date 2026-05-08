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
});
