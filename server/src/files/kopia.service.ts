import { Injectable } from '@nestjs/common';
import { execFile } from 'node:child_process';
import { stat } from 'node:fs/promises';
import * as path from 'node:path';

export interface KopiaSnapshotVersion {
  snapshotId: string;
  versionRef: string;
  displayName: string;
  modifiedAt: string | null;
  sizeBytes: number | null;
  checksum: string | null;
  metadata: Record<string, unknown>;
}

@Injectable()
export class KopiaService {
  private readonly executable = process.env.KOPIA_EXE ?? 'kopia';
  private readonly timeoutMs = Number(process.env.KOPIA_TIMEOUT_MS ?? 120000);

  async createSnapshot(rootPath: string) {
    await this.ensureExistingPath(rootPath);
    const result = await this.run(['snapshot', 'create', rootPath, '--json']);
    const parsed = this.parseKopiaJson(result.stdout);
    return {
      rootPath,
      raw: parsed,
      stderr: result.stderr,
      snapshots: this.normalizeSnapshots(parsed, rootPath),
    };
  }

  async listSnapshots(targetPath: string) {
    await this.ensureExistingPath(targetPath);
    const result = await this.run(['snapshot', 'list', targetPath, '--json']);
    const parsed = this.parseKopiaJson(result.stdout);
    return {
      targetPath,
      raw: parsed,
      stderr: result.stderr,
      snapshots: this.normalizeSnapshots(parsed, targetPath),
    };
  }

  async downloadVersionCopy(
    versionRef: string,
    objectPath: string | null,
    targetPath: string,
  ) {
    try {
      await stat(targetPath);
      throw new Error('target_already_exists');
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
        throw error;
      }
    }
    const sourceRef = objectPath
      ? `${versionRef}/${this.normalizeSnapshotPath(objectPath)}`
      : versionRef;
    const result = await this.run(['snapshot', 'restore', sourceRef, targetPath]);
    return {
      sourceRef,
      targetPath,
      stderr: result.stderr,
      stdout: result.stdout,
    };
  }

  async prepareRestore(versionRef: string, objectPath: string | null, targetPath: string | null) {
    return {
      executable: this.executable,
      command: [
        this.executable,
        'snapshot',
        'restore',
        objectPath ? `${versionRef}/${this.normalizeSnapshotPath(objectPath)}` : versionRef,
        targetPath ?? '<target-path>',
      ],
      executableStep: false,
      reason: 'restore_prepare_only_requires_second_confirmation',
    };
  }

  private run(args: string[]) {
    return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
      execFile(
        this.executable,
        args,
        {
          timeout: this.timeoutMs,
          maxBuffer: 20 * 1024 * 1024,
          windowsHide: true,
        },
        (error, stdout, stderr) => {
          if (error) {
            const wrapped = new Error(
              `kopia_cli_failed: ${error.message}${stderr ? `; ${stderr}` : ''}`,
            );
            reject(wrapped);
            return;
          }
          resolve({ stdout, stderr });
        },
      );
    });
  }

  private async ensureExistingPath(targetPath: string) {
    await stat(targetPath);
  }

  private parseKopiaJson(stdout: string): unknown {
    const text = stdout.trim();
    if (!text) {
      return null;
    }
    try {
      return JSON.parse(text);
    } catch {
      const startObject = text.indexOf('{');
      const startArray = text.indexOf('[');
      const start =
        startArray >= 0 && (startArray < startObject || startObject < 0)
          ? startArray
          : startObject;
      const end = Math.max(text.lastIndexOf('}'), text.lastIndexOf(']'));
      if (start >= 0 && end > start) {
        return JSON.parse(text.slice(start, end + 1));
      }
      throw new Error('kopia_json_parse_failed');
    }
  }

  private normalizeSnapshots(value: unknown, targetPath: string): KopiaSnapshotVersion[] {
    const objects = this.collectObjects(value).filter((item) => this.snapshotId(item));
    return objects.map((item) => {
      const snapshotId = this.snapshotId(item) ?? '';
      const modifiedAt = this.firstString(
        item,
        ['endTime', 'startTime', 'snapshotTime', 'modTime', 'mtime', 'createdAt'],
      );
      const sizeBytes = this.firstNumber(item, [
        'size',
        'sizeBytes',
        'totalSize',
        'rootEntry.summ.size',
        'rootEntry.size',
      ]);
      const checksum = this.firstString(item, [
        'checksum',
        'hash',
        'rootEntry.hash',
        'rootEntry.contentID',
      ]);
      return {
        snapshotId,
        versionRef: snapshotId,
        displayName: `${path.basename(targetPath)} @ ${modifiedAt ?? snapshotId.slice(0, 12)}`,
        modifiedAt,
        sizeBytes,
        checksum,
        metadata: {
          kopiaExecutable: this.executable,
          targetPath,
          snapshot: item,
        },
      };
    });
  }

  private collectObjects(value: unknown): Record<string, unknown>[] {
    if (Array.isArray(value)) {
      return value.flatMap((item) => this.collectObjects(item));
    }
    if (!value || typeof value !== 'object') {
      return [];
    }
    const item = value as Record<string, unknown>;
    const nestedKeys = ['snapshots', 'items', 'entries', 'results'];
    const nested = nestedKeys.flatMap((key) => this.collectObjects(item[key]));
    return [item, ...nested];
  }

  private snapshotId(item: Record<string, unknown>) {
    return this.firstString(item, [
      'id',
      'snapshotId',
      'snapshotID',
      'manifestId',
      'manifestID',
      'rootEntry.obj',
    ]);
  }

  private firstString(item: Record<string, unknown>, paths: string[]) {
    for (const itemPath of paths) {
      const value = this.readPath(item, itemPath);
      if (typeof value === 'string' && value.trim()) {
        return value.trim();
      }
    }
    return null;
  }

  private firstNumber(item: Record<string, unknown>, paths: string[]) {
    for (const itemPath of paths) {
      const value = this.readPath(item, itemPath);
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
      if (typeof value === 'string') {
        const parsed = Number(value);
        if (Number.isFinite(parsed)) {
          return parsed;
        }
      }
    }
    return null;
  }

  private readPath(item: Record<string, unknown>, itemPath: string) {
    return itemPath.split('.').reduce<unknown>((current, segment) => {
      if (!current || typeof current !== 'object') {
        return undefined;
      }
      return (current as Record<string, unknown>)[segment];
    }, item);
  }

  private normalizeSnapshotPath(value: string) {
    return value.replace(/^[a-zA-Z]:/, '').replace(/\\/g, '/').replace(/^\/+/, '');
  }
}
