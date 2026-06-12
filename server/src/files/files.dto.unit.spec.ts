import 'reflect-metadata';
import { describe, expect, it } from 'vitest';
import { validate } from 'class-validator';
import { CreateDownloadSessionDto, SharedDownloadDto, UploadChunkDto } from './files.dto';

describe('files DTO validation', () => {
  it('accepts upload chunk payloads with optional checksum', async () => {
    const dto = Object.assign(new UploadChunkDto(), {
      sessionId: 'session-1',
      chunkIndex: 0,
      payloadBase64: 'YQ==',
      checksum: 'sha256',
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('rejects upload chunks with missing session ids or non-numeric indexes', async () => {
    const dto = Object.assign(new UploadChunkDto(), {
      chunkIndex: '0',
      payloadBase64: 123,
    });

    const errors = await validate(dto);

    expect(errors.map((error) => error.property).sort()).toEqual(['chunkIndex', 'payloadBase64', 'sessionId']);
  });

  it('validates download session dto required and optional string fields', async () => {
    await expect(
      validate(Object.assign(new CreateDownloadSessionDto(), { fileId: 'file-1', format: 'pdf' })),
    ).resolves.toHaveLength(0);

    const errors = await validate(Object.assign(new CreateDownloadSessionDto(), { format: 42 }));

    expect(errors.map((error) => error.property).sort()).toEqual(['fileId', 'format']);
  });

  it('validates shared download path and numeric range boundaries', async () => {
    await expect(
      validate(Object.assign(new SharedDownloadDto(), { path: '/data/a.txt', start: 0, end: 10 })),
    ).resolves.toHaveLength(0);

    const errors = await validate(Object.assign(new SharedDownloadDto(), { path: 123, start: '0', end: '10' }));

    expect(errors.map((error) => error.property).sort()).toEqual(['end', 'path', 'start']);
  });
});
