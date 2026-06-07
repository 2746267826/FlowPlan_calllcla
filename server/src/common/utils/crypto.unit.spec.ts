import { createHash } from 'node:crypto';
import { afterEach, describe, expect, it } from 'vitest';
import {
  decrypt,
  encrypt,
  encryptionKey,
  hashJson,
  isEncryptionKeySecure,
  randomUid,
  sha256,
} from './crypto';

const ENV_KEYS = [
  'FLOWPLANV2_ENCRYPTION_KEY',
  'OUTLOOK_CONFIG_SECRET',
  'AI_CONFIG_SECRET',
  'FLOWPLANV2_DATABASE_URL',
  'DATABASE_URL',
] as const;

const originalEnv = Object.fromEntries(
  ENV_KEYS.map((key) => [key, process.env[key]]),
);

function digest(secret: string): Buffer {
  return createHash('sha256').update(secret).digest();
}

describe('crypto utilities', () => {
  afterEach(() => {
    for (const key of ENV_KEYS) {
      const value = originalEnv[key];
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it('hashes buffers and JSON payloads with SHA-256 hex output', () => {
    expect(sha256(Buffer.from('flowplan'))).toBe(
      createHash('sha256').update('flowplan').digest('hex'),
    );
    expect(hashJson({ a: 1, b: 'two' })).toBe(
      createHash('sha256').update(JSON.stringify({ a: 1, b: 'two' })).digest('hex'),
    );
  });

  it('encrypts values that can be decrypted with the same secret only', () => {
    const encrypted = encrypt('private value', 'test-secret');

    expect(encrypted.split('.')).toHaveLength(3);
    expect(decrypt(encrypted, 'test-secret')).toBe('private value');
    expect(() => decrypt(encrypted, 'wrong-secret')).toThrow();
  });

  it('rejects encrypted payloads without iv tag and ciphertext parts', () => {
    expect(() => decrypt('not-enough-parts', 'test-secret')).toThrow(
      'Invalid encrypted format.',
    );
  });

  it('uses the dedicated encryption secret before database fallbacks', () => {
    process.env.FLOWPLANV2_ENCRYPTION_KEY = 'dedicated-secret';
    process.env.OUTLOOK_CONFIG_SECRET = 'outlook-secret';
    process.env.AI_CONFIG_SECRET = 'ai-secret';
    process.env.FLOWPLANV2_DATABASE_URL = 'postgres://db-secret';

    expect(encryptionKey()).toEqual(digest('dedicated-secret'));
    expect(isEncryptionKeySecure()).toBe(true);
  });

  it('treats database-derived keys as insecure fallback material', () => {
    delete process.env.FLOWPLANV2_ENCRYPTION_KEY;
    delete process.env.OUTLOOK_CONFIG_SECRET;
    delete process.env.AI_CONFIG_SECRET;
    process.env.DATABASE_URL = 'postgres://localhost/flowplantest';

    expect(encryptionKey()).toEqual(digest('postgres://localhost/flowplantest'));
    expect(isEncryptionKeySecure()).toBe(false);
  });

  it('generates UUID-shaped identifiers', () => {
    expect(randomUid()).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
  });
});
