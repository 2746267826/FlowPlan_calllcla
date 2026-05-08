/**
 * Cryptographic utilities used across services.
 * Replaces the per-service `private sha256()`, `private hashJson()`, etc.
 */

import { createHash, randomUUID } from 'node:crypto';
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from 'node:crypto';

// ---- Hashing ----

/** SHA-256 digest of a Buffer, returned as hex. */
export function sha256(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex');
}

/** SHA-256 hex digest of a JSON-serializable value. */
export function hashJson(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

// ---- UUID ----

/** Generate a random UUID v4 string. */
export function randomUid(): string {
  return randomUUID();
}

// ---- Unified encryption key ----

/**
 * Derive the AES-256-GCM encryption key from the configured secret.
 *
 * Priority order:
 *   1. FLOWPLANV2_ENCRYPTION_KEY (dedicated env var — PREFERRED)
 *   2. OUTLOOK_CONFIG_SECRET (Outlook token encryption)
 *   3. AI_CONFIG_SECRET (AI provider key encryption)
 *   4. FLOWPLANV2_DATABASE_URL / DATABASE_URL (legacy fallback)
 *   5. Hardcoded dev-only fallback (prints warning)
 *
 * All AI / Outlook / models services MUST use this function via
 * `encrypt(value, encryptionKey())` instead of maintaining their own
 * `private secretKey()`.
 */
export function encryptionKey(): Buffer {
  const secret =
    process.env.FLOWPLANV2_ENCRYPTION_KEY ??
    process.env.OUTLOOK_CONFIG_SECRET ??
    process.env.AI_CONFIG_SECRET ??
    process.env.FLOWPLANV2_DATABASE_URL ??
    process.env.DATABASE_URL ??
    'flowplanv2-local-fallback-key-for-dev-only';

  if (!process.env.FLOWPLANV2_ENCRYPTION_KEY && !process.env.OUTLOOK_CONFIG_SECRET && !process.env.AI_CONFIG_SECRET) {
    // Only warn in non-test environments
    if (!process.env.DATABASE_URL?.includes('flowplantest')) {
      console.warn('[FlowPlanV2] WARNING: Encryption key is derived from DATABASE_URL. Set FLOWPLANV2_ENCRYPTION_KEY for production.');
    }
  }

  return createHash('sha256').update(secret).digest();
}

/**
 * Validate that the encryption key is properly configured for production.
 * Returns true if FLOWPLANV2_ENCRYPTION_KEY or a dedicated service key is set.
 */
export function isEncryptionKeySecure(): boolean {
  return !!(process.env.FLOWPLANV2_ENCRYPTION_KEY ?? process.env.OUTLOOK_CONFIG_SECRET ?? process.env.AI_CONFIG_SECRET);
}

// ---- AES-256-GCM encryption ----

function deriveKey(secret: string | Buffer): Buffer {
  if (Buffer.isBuffer(secret)) return secret;
  return createHash('sha256').update(secret).digest();
}

/** Encrypt a plaintext string. Returns "iv.tag.ciphertext" (all base64). */
export function encrypt(value: string, secret: string | Buffer): string {
  const key = deriveKey(secret);
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, encrypted].map((part) => part.toString('base64')).join('.');
}

/** Decrypt a string produced by encrypt(). */
export function decrypt(value: string, secret: string | Buffer): string {
  const [ivRaw, tagRaw, encryptedRaw] = value.split('.');
  if (!ivRaw || !tagRaw || !encryptedRaw) {
    throw new Error('Invalid encrypted format.');
  }
  const key = deriveKey(secret);
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(ivRaw, 'base64'));
  decipher.setAuthTag(Buffer.from(tagRaw, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedRaw, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}
