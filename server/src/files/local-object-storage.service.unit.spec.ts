import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { LocalObjectStorageService } from './local-object-storage.service';

function sha256(value: Buffer | string) {
  return createHash('sha256').update(value).digest('hex');
}

async function readStream(stream: NodeJS.ReadableStream) {
  const chunks: Buffer[] = [];
  return new Promise<Buffer>((resolve, reject) => {
    stream.on('data', (chunk: string | Buffer) => chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
    stream.on('error', reject);
    stream.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

describe('LocalObjectStorageService unit', () => {
  let tempRoot: string;
  let service: LocalObjectStorageService;

  beforeEach(async () => {
    tempRoot = await mkdtemp(join(tmpdir(), 'flowplan-local-storage-unit-'));
    service = new LocalObjectStorageService();
    (service as never as { rootPath: string }).rootPath = tempRoot;
  });

  afterEach(async () => {
    await rm(tempRoot, { recursive: true, force: true });
  });

  it('reports local storage status for the configured root', async () => {
    await expect(service.status()).resolves.toEqual({
      providerKey: 'server_storage_flowplanv2',
      storageType: 'local_filesystem',
      rootPath: tempRoot,
      writable: true,
    });
    expect(service.root()).toBe(tempRoot);
  });

  it('falls back to the default storage root when the storage env var is blank', () => {
    const previousStorageDir = process.env.FLOWPLANV2_SERVER_STORAGE_DIR;
    process.env.FLOWPLANV2_SERVER_STORAGE_DIR = '';

    try {
      const blankEnvService = new LocalObjectStorageService();

      expect(blankEnvService.root()).toBe(join(process.cwd(), 'server_storage_flowplanv2'));
    } finally {
      if (previousStorageDir === undefined) {
        delete process.env.FLOWPLANV2_SERVER_STORAGE_DIR;
      } else {
        process.env.FLOWPLANV2_SERVER_STORAGE_DIR = previousStorageDir;
      }
    }
  });

  it('writes chunked objects with sanitized storage segments and hashes the content', async () => {
    const result = await service.writeObjectFromChunks('user/id', 'folder:name?.txt', [
      Buffer.from('hello '),
      Buffer.from('world'),
    ]);

    expect(result.relativePath).toBe('user_id/folder_name_.txt');
    expect(result.sizeBytes).toBe(11);
    expect(result.checksum).toBe(sha256('hello world'));
    await expect(service.readRange(result.storagePath, -5, 4)).resolves.toEqual(Buffer.from('hello'));
  });

  it('copies local files, rejects directories, and computes copied-file checksums', async () => {
    const sourcePath = join(tempRoot, 'source.txt');
    const directoryPath = join(tempRoot, 'source-dir');
    await writeFile(sourcePath, 'copied content');
    await mkdir(directoryPath);

    await expect(service.copyLocalFile('user', directoryPath, 'dir-copy')).rejects.toThrow('source_path_is_not_file');
    const result = await service.copyLocalFile('user', sourcePath, 'copied.txt');

    expect(result.relativePath).toBe('user/copied.txt');
    expect(result.sizeBytes).toBe(14);
    expect(result.checksum).toBe(sha256('copied content'));
    await expect(stat(result.storagePath)).resolves.toMatchObject({ size: 14 });
  });

  it('clamps read ranges, returns empty buffers past EOF, and streams byte ranges', async () => {
    const result = await service.writeObjectFromChunks('user', 'ranges.txt', [Buffer.from('0123456789')]);

    await expect(service.readRange(result.storagePath, 4, 99)).resolves.toEqual(Buffer.from('456789'));
    await expect(service.readRange(result.relativePath, 2, 5)).resolves.toEqual(Buffer.from('2345'));
    await expect(service.readRange(result.storagePath, 99, 120)).resolves.toEqual(Buffer.alloc(0));
    await expect(readStream(service.createReadStream(result.relativePath, 2, 5))).resolves.toEqual(Buffer.from('2345'));
  });

  it('hashes full files and byte ranges through public streams', async () => {
    const result = await service.writeObjectFromChunks('user', 'hash.txt', [Buffer.from('abcdefghij')]);

    await expect(service.hashFile(result.relativePath)).resolves.toBe(sha256('abcdefghij'));
    await expect(service.hashFile(result.relativePath, 2, 5)).resolves.toBe(sha256('cdef'));
  });

  it('rejects stored paths outside the configured root', async () => {
    expect(() => service.resolveStoredPath(join(tempRoot, '..', 'outside.txt'))).toThrow('storage_path_outside_root');
  });

  it('surfaces stream errors from the internal copied-file hasher', async () => {
    await expect((service as never as { sha256File: (path: string) => Promise<string> }).sha256File(join(tempRoot, 'missing.txt'))).rejects.toMatchObject({
      code: 'ENOENT',
    });
  });
});
