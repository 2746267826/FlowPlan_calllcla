import { existsSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { config as loadDotenv } from 'dotenv';

export interface EnvFileDiscoveryOptions {
  cwd?: string;
  sourceDir?: string;
  explicitPath?: string;
  exists?: (path: string) => boolean;
}

export interface EnvFileDiscoveryResult {
  selectedPath?: string;
  candidates: string[];
  explicit: boolean;
}

export interface EnvFileLoadResult extends EnvFileDiscoveryResult {
  loadedVarCount: number;
}

function unique(paths: string[]): string[] {
  return Array.from(new Set(paths.map((path) => resolve(path))));
}

export function buildEnvFileCandidates(
  options: EnvFileDiscoveryOptions = {},
): string[] {
  const cwd = resolve(options.cwd ?? process.cwd());
  const sourceDir = resolve(options.sourceDir ?? (options.cwd ? cwd : __dirname));
  const roots = unique([
    cwd,
    resolve(cwd, 'server'),
    resolve(sourceDir, '..', '..', '..'),
    resolve(sourceDir, '..', '..', '..', '..'),
    resolve(sourceDir, '..', '..', '..', '..', '..'),
  ]);
  const serverDirs = unique([
    ...roots.filter((root) => basename(root).toLowerCase() === 'server'),
    ...roots.map((root) => resolve(root, 'server')),
  ]);
  const repoDirs = unique([
    ...serverDirs.map((serverDir) => resolve(serverDir, '..')),
    ...roots.filter((root) => basename(root).toLowerCase() !== 'dist'),
  ]);

  return unique([
    ...serverDirs.flatMap((serverDir) => [
      resolve(serverDir, '.env'),
      resolve(serverDir, 'flowplanv2.local.env'),
    ]),
    ...repoDirs.flatMap((repoDir) => [
      resolve(repoDir, 'flowplanv2.local.env'),
      resolve(repoDir, '.env'),
    ]),
  ]);
}

export function resolveEnvFile(
  options: EnvFileDiscoveryOptions = {},
): EnvFileDiscoveryResult {
  const exists = options.exists ?? existsSync;
  const explicitValue =
    options.explicitPath ?? process.env.FLOWPLANV2_ENV_FILE;
  const explicitPath = explicitValue?.trim();

  if (explicitPath) {
    const selectedPath = resolve(explicitPath);
    if (!exists(selectedPath)) {
      throw new Error(
        `FLOWPLANV2_ENV_FILE points to a missing file: ${selectedPath}`,
      );
    }
    return { selectedPath, candidates: [selectedPath], explicit: true };
  }

  const candidates = buildEnvFileCandidates(options);
  return {
    selectedPath: candidates.find((candidate) => exists(candidate)),
    candidates,
    explicit: false,
  };
}

export function loadEnvFile(
  options: EnvFileDiscoveryOptions = {},
): EnvFileLoadResult {
  const discovery = resolveEnvFile(options);
  if (!discovery.selectedPath) {
    return { ...discovery, loadedVarCount: 0 };
  }

  const result = loadDotenv({
    path: discovery.selectedPath,
    override: false,
  });
  if (result.error) {
    throw result.error;
  }

  return {
    ...discovery,
    loadedVarCount: Object.keys(result.parsed ?? {}).length,
  };
}

export function formatEnvLoadMessage(result: EnvFileLoadResult): string {
  if (result.selectedPath) {
    return `[Env] Loaded ${result.loadedVarCount} vars from ${result.selectedPath}`;
  }
  return `[Env] .env not found. Searched: ${result.candidates.join(', ')}. Using system environment variables only.`;
}
