import { Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { copyFile, mkdir, open, stat } from 'node:fs/promises';
import * as path from 'node:path';

export interface StoredObjectResult {
  storagePath: string;
  relativePath: string;
  sizeBytes: number;
  checksum: string;
}

@Injectable()
export class LocalObjectStorageService {
  private readonly rootPath = path.resolve(
    process.env.FLOWPLANV2_SERVER_STORAGE_DIR ??
      path.join(process.cwd(), 'server_storage_flowplanv2'),
  );

  root() {
    return this.rootPath;
  }

  async status() {
    await this.ensureRoot();
    return {
      providerKey: 'server_storage_flowplanv2',
      storageType: 'local_filesystem',
      rootPath: this.rootPath,
      writable: true,
    };
  }

  async writeObjectFromChunks(
    userId: string,
    objectKey: string,
    chunks: Buffer[],
  ): Promise<StoredObjectResult> {
    await this.ensureRoot();
    const targetPath = this.objectPath(userId, objectKey);
    await mkdir(path.dirname(targetPath), { recursive: true });
    const hash = createHash('sha256');
    let sizeBytes = 0;
    const handle = await open(targetPath, 'w');
    try {
      for (const chunk of chunks) {
        hash.update(chunk);
        sizeBytes += chunk.length;
        await handle.write(chunk);
      }
    } finally {
      await handle.close();
    }
    return {
      storagePath: targetPath,
      relativePath: this.toRelativeStoragePath(targetPath),
      sizeBytes,
      checksum: hash.digest('hex'),
    };
  }

  async copyLocalFile(
    userId: string,
    sourcePath: string,
    objectKey: string,
  ): Promise<StoredObjectResult> {
    const sourceStat = await stat(sourcePath);
    if (!sourceStat.isFile()) {
      throw new Error('source_path_is_not_file');
    }
    await this.ensureRoot();
    const targetPath = this.objectPath(userId, objectKey);
    await mkdir(path.dirname(targetPath), { recursive: true });
    await copyFile(sourcePath, targetPath);
    return {
      storagePath: targetPath,
      relativePath: this.toRelativeStoragePath(targetPath),
      sizeBytes: sourceStat.size,
      checksum: await this.sha256File(targetPath),
    };
  }

  async readRange(
    storedPath: string,
    start: number,
    endInclusive: number,
  ): Promise<Buffer> {
    const { safeStart, safeEnd } = await this.computeRange(storedPath, start, endInclusive);
    if (safeEnd < safeStart) {
      return Buffer.alloc(0);
    }
    const handle = await open(storedPath, 'r');
    try {
      const buffer = Buffer.alloc(safeEnd - safeStart + 1);
      await handle.read(buffer, 0, buffer.length, safeStart);
      return buffer;
    } finally {
      await handle.close();
    }
  }

  /**
   * Create a readable stream for a byte range of a stored file.
   * Much more memory-efficient than readRange() for large files.
   */
  createReadStream(
    storedPath: string,
    start: number,
    endInclusive: number,
  ) {
    const resolved = this.resolveStoredPath(storedPath);
    return createReadStream(resolved, { start, end: endInclusive });
  }

  /**
   * Stream-based SHA-256 hash of a stored file (or byte range).
   * O(1) memory regardless of file size.
   */
  async hashFile(storedPath: string, start?: number, end?: number): Promise<string> {
    const resolved = this.resolveStoredPath(storedPath);
    return new Promise<string>((resolve, reject) => {
      const hash = createHash('sha256');
      const stream = createReadStream(resolved, start != null && end != null ? { start, end } : {});
      stream.on('data', (chunk: string | Buffer) => hash.update(chunk));
      stream.on('error', reject);
      stream.on('end', () => resolve(hash.digest('hex')));
    });
  }

  private async computeRange(
    storedPath: string, start: number, endInclusive: number,
  ) {
    const resolved = this.resolveStoredPath(storedPath);
    const fileStat = await stat(resolved);
    const safeStart = Math.max(0, Math.min(start, fileStat.size));
    const safeEnd = Math.max(safeStart - 1, Math.min(endInclusive, fileStat.size - 1));
    return { safeStart, safeEnd };
  }

  resolveStoredPath(storedPath: string) {
    const resolved = path.isAbsolute(storedPath)
      ? path.resolve(storedPath)
      : path.resolve(this.rootPath, storedPath);
    const relative = path.relative(this.rootPath, resolved);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
      throw new Error('storage_path_outside_root');
    }
    return resolved;
  }

  private async ensureRoot() {
    await mkdir(this.rootPath, { recursive: true });
  }

  private objectPath(userId: string, objectKey: string) {
    return path.join(this.rootPath, this.safeSegment(userId), this.safeSegment(objectKey));
  }

  private toRelativeStoragePath(storagePath: string) {
    return path.relative(this.rootPath, storagePath).replace(/\\/g, '/');
  }

  private safeSegment(value: string) {
    return value.replace(/[^a-zA-Z0-9._-]/g, '_');
  }

  private sha256File(filePath: string) {
    return new Promise<string>((resolve, reject) => {
      const hash = createHash('sha256');
      const input = createReadStream(filePath);
      input.on('data', (chunk: string | Buffer) => hash.update(chunk));
      input.on('error', reject);
      input.on('end', () => resolve(hash.digest('hex')));
    });
  }
}
