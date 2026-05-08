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

// ---- AES-256-GCM encryption (shared with AiService / ReportsService) ----

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
